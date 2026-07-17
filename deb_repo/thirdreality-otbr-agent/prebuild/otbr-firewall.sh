#!/bin/bash
# =============================================================================
# otbr-firewall.sh —— 建/拆 OpenThread 的 ip6tables/ipset/NAT64 规则
#
# 由 otbr-agent.service 的 ExecStartPre(setup) / ExecStopPost(teardown) 调用，
# 保证每次启停成对建/拆，避免规则残留或叠加（旧版用 init.d 只建不拆，会累积）。
# 逻辑对齐 HA addon openthread_border_router 的 s6 run/finish。
#
# 开关与接口从 /etc/default/otbr-agent 读取：
#   OTBR_THREAD_IF   (默认 wpan0)
#   OTBR_BACKBONE_IF (默认 wlan0)
#   OTBR_FIREWALL    (默认 1)
#   OTBR_NAT64       (默认 1)
# =============================================================================
set -u

[ -r /etc/default/otbr-agent ] && . /etc/default/otbr-agent

THREAD_IF="${OTBR_THREAD_IF:-wpan0}"
BACKBONE_IF="${OTBR_BACKBONE_IF:-wlan0}"
FIREWALL="${OTBR_FIREWALL:-1}"
NAT64="${OTBR_NAT64:-1}"

INGRESS_CHAIN="OTBR_FORWARD_INGRESS"
EGRESS_CHAIN="OTBR_FORWARD_EGRESS"
NAT64_CHAIN="OTBR_FORWARD_NAT64"
FW_MARK="0x1001"

log() { echo "[otbr-firewall] $1"; }

teardown() {
    # --- ip6tables ingress/egress 链 ---
    while ip6tables -C FORWARD -o "${THREAD_IF}" -j "${INGRESS_CHAIN}" 2>/dev/null; do
        ip6tables -D FORWARD -o "${THREAD_IF}" -j "${INGRESS_CHAIN}"
    done
    if ip6tables -L "${INGRESS_CHAIN}" -n >/dev/null 2>&1; then
        ip6tables -w -F "${INGRESS_CHAIN}" 2>/dev/null || true
        ip6tables -w -X "${INGRESS_CHAIN}" 2>/dev/null || true
    fi

    while ip6tables -C FORWARD -i "${THREAD_IF}" -j "${EGRESS_CHAIN}" 2>/dev/null; do
        ip6tables -D FORWARD -i "${THREAD_IF}" -j "${EGRESS_CHAIN}"
    done
    if ip6tables -L "${EGRESS_CHAIN}" -n >/dev/null 2>&1; then
        ip6tables -w -F "${EGRESS_CHAIN}" 2>/dev/null || true
        ip6tables -w -X "${EGRESS_CHAIN}" 2>/dev/null || true
    fi

    # --- ipset（内核会短暂占用，循环重试销毁）---
    for s in otbr-ingress-deny-src otbr-ingress-deny-src-swap \
             otbr-ingress-allow-dst otbr-ingress-allow-dst-swap; do
        while ipset list -n "$s" >/dev/null 2>&1; do
            ipset destroy "$s" 2>/dev/null || break
        done
    done

    # --- NAT64 (iptables v4) ---
    while iptables -C FORWARD -j "${NAT64_CHAIN}" 2>/dev/null; do
        iptables -D FORWARD -j "${NAT64_CHAIN}"
    done
    if iptables -L "${NAT64_CHAIN}" -n >/dev/null 2>&1; then
        iptables -w -F "${NAT64_CHAIN}" 2>/dev/null || true
        iptables -w -X "${NAT64_CHAIN}" 2>/dev/null || true
    fi
    while iptables -t mangle -C PREROUTING -i "${THREAD_IF}" -j MARK --set-mark "${FW_MARK}" 2>/dev/null; do
        iptables -t mangle -D PREROUTING -i "${THREAD_IF}" -j MARK --set-mark "${FW_MARK}"
    done
    while iptables -t nat -C POSTROUTING -m mark --mark "${FW_MARK}" -j MASQUERADE 2>/dev/null; do
        iptables -t nat -D POSTROUTING -m mark --mark "${FW_MARK}" -j MASQUERADE
    done

    log "teardown done"
}

setup() {
    # 先拆一遍保证幂等（防止上次未拆干净导致规则叠加）
    teardown >/dev/null 2>&1 || true

    # otbr-agent 编了 firewall 支持，启动会去更新这些 ipset，必须先建好
    ipset create -exist otbr-ingress-deny-src       hash:net family inet6
    ipset create -exist otbr-ingress-deny-src-swap  hash:net family inet6
    ipset create -exist otbr-ingress-allow-dst      hash:net family inet6
    ipset create -exist otbr-ingress-allow-dst-swap hash:net family inet6

    ip6tables -N "${INGRESS_CHAIN}" 2>/dev/null || true
    ip6tables -I FORWARD 1 -o "${THREAD_IF}" -j "${INGRESS_CHAIN}"
    ip6tables -N "${EGRESS_CHAIN}" 2>/dev/null || true
    ip6tables -I FORWARD 2 -i "${THREAD_IF}" -j "${EGRESS_CHAIN}"

    if [ "${FIREWALL}" = "1" ]; then
        log "firewall enabled"
        ip6tables -A "${INGRESS_CHAIN}" -m pkttype --pkt-type unicast -i "${THREAD_IF}" -j DROP
        ip6tables -A "${INGRESS_CHAIN}" -m set --match-set otbr-ingress-deny-src src -j DROP
        ip6tables -A "${INGRESS_CHAIN}" -m set --match-set otbr-ingress-allow-dst dst -j ACCEPT
        ip6tables -A "${INGRESS_CHAIN}" -m pkttype --pkt-type unicast -j DROP
        ip6tables -A "${INGRESS_CHAIN}" -j ACCEPT
        ip6tables -A "${EGRESS_CHAIN}" -j ACCEPT
    else
        log "firewall disabled (accept all)"
        ip6tables -A "${INGRESS_CHAIN}" -j ACCEPT
        ip6tables -A "${EGRESS_CHAIN}" -j ACCEPT
    fi

    if [ "${NAT64}" = "1" ]; then
        log "nat64 enabled (backbone=${BACKBONE_IF})"
        # 标记 Thread 侧入向流量
        iptables -t mangle -A PREROUTING -i "${THREAD_IF}" -j MARK --set-mark "${FW_MARK}"
        # 对标记流量做 MASQUERADE
        iptables -t nat -A POSTROUTING -m mark --mark "${FW_MARK}" -j MASQUERADE
        # NAT64 forward 链
        iptables -N "${NAT64_CHAIN}" 2>/dev/null || true
        iptables -I FORWARD 1 -j "${NAT64_CHAIN}"
        iptables -A "${NAT64_CHAIN}" -m mark --mark "${FW_MARK}" -o "${BACKBONE_IF}" -j ACCEPT
        iptables -A "${NAT64_CHAIN}" -m conntrack --ctstate ESTABLISHED,RELATED \
                 -i "${BACKBONE_IF}" -o "${THREAD_IF}" -j ACCEPT
    fi

    log "setup done (thread=${THREAD_IF})"
}

case "${1:-}" in
    setup)    setup ;;
    teardown) teardown ;;
    *) echo "usage: $0 {setup|teardown}" >&2; exit 2 ;;
esac

exit 0
