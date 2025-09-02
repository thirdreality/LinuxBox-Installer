#!/bin/bash

current_dir=$(pwd)
output_dir="${current_dir}/output"

REBUILD=false
CLEAN=false

#Fixed to commit
#commit_sha1="bb4252342d521736c2cdad0058ce90f54b35c75c"
commit_sha1="0700948634b85947e893a65e3d510ed870a5755b"

SCRIPT="R3"
print_info() { echo -e "\e[1;34m[${SCRIPT}] INFO:\e[0m $1"; }
print_error() { echo -e "\e[1;31m[${SCRIPT}] ERROR:\e[0m $1"; }

print_info "Usage: Build.sh [--rebuild] [--clean]"
print_info "Options:"
print_info "  --rebuild: Rebuild the env"
print_info "  --clean: Clean the output directory and remove the env"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --rebuild) REBUILD=true ;;
        --clean) CLEAN=true ;;
        *) print_error "未知参数: $1" >&2; exit 1 ;;
    esac
    shift
done

version=$(grep '^Version:' ${current_dir}/DEBIAN/control | awk '{print $2}')
print_info "Version: $version"

FIREWALL_SERVICE=/etc/init.d/otbr-firewall
NAT44_SERVICE=/etc/init.d/otbr-nat44

SYSCTL_ACCEPT_RA_FILE="/etc/sysctl.d/60-otbr-accept-ra.conf"
SYSCTL_IP_FORWARD_FILE="/etc/sysctl.d/60-otbr-ip-forward.conf"

otbr_uninstall()
{
    echo "Stopping otbr-web/otbr-agent/otbr-firewall services ..."

    /usr/bin/systemctl stop otbr-web || true
    /usr/bin/systemctl stop otbr-agent || true

    /usr/bin/systemctl disable otbr-web || true
    /usr/bin/systemctl disable otbr-agent || true

    killall otbr-web otbr-agent || true

    /usr/bin/systemctl stop otbr-firewall || true
    /usr/bin/systemctl disable otbr-firewall || true

    if [ -f "/usr/sbin/update-rc.d" ]; then
        /usr/sbin/update-rc.d otbr-firewall remove || true
    fi

    test ! -f ${FIREWALL_SERVICE} || rm ${FIREWALL_SERVICE}

    systemctl disable otbr-nat44 || true
    # systemctl disable doesn't remove sym-links
    if [ -f "/usr/sbin/update-rc.d" ]; then
        /usr/sbin/update-rc.d otbr-nat44 remove || true
    fi
    test ! -f $NAT44_SERVICE || rm $NAT44_SERVICE

    /usr/bin/systemctl daemon-reload

    test ! -f ${SYSCTL_ACCEPT_RA_FILE} || rm -v ${SYSCTL_ACCEPT_RA_FILE}
    test ! -f ${SYSCTL_IP_FORWARD_FILE} || rm -v ${SYSCTL_IP_FORWARD_FILE}

    echo "Restoring /etc/iproute2/rt_tables ..."
    sed -i.bak '/88\s\+openthread/d' /etc/iproute2/rt_tables

    echo "Removing file in /usr/lib/ ..."
    rm -rf /usr/lib/libnss_mdns.so.2 || true
    rm -rf /usr/lib/libdns_sd.so || true
    rm -rf /usr/lib/libdns_sd.so.1 || true

    rm -rf /etc/rc2.d/S52mdns 
	rm -rf /etc/rc2.d/S52mdns
	rm -rf /etc/rc3.d/S52mdns
	rm -rf /etc/rc4.d/S52mdns
	rm -rf /etc/rc5.d/S52mdns
	rm -rf /etc/rc0.d/K16mdns
	rm -rf /etc/rc6.d/K16mdns

    echo "Check /etc/sysctl.conf ..."
    sysctl -p /etc/sysctl.conf

    rm -rf /tmp/mDNSResponder*

    echo "Remove success."
}


if [[ "$CLEAN" == true ]]; then
    rm -rf "${output_dir}" > /dev/null 2>&1
    rm -rf ${current_dir}/*.deb > /dev/null 2>&1

    rm -rf "${current_dir}/ot-br-posix"

    otbr_uninstall

    exit 0
fi

if [[ "$REBUILD" == true ]]; then
    print_info "obtr_agent_${version}.deb rebuilding ..."
    rm -rf "${output_dir}" > /dev/null 2>&1
    mkdir -p "${output_dir}"

    rm -rf "${current_dir}/ot-br-posix"

    cp ${current_dir}/DEBIAN ${output_dir}/ -R
fi

print_info "Create output directory ..."
mkdir -p "${output_dir}"

print_info "syncing DEBIAN ..."
rm -rf ${output_dir}/DEBIAN > /dev/null 2>&1
cp ${current_dir}/DEBIAN ${output_dir}/ -R

if [ ! -d "${current_dir}/ot-br-posix" ]; then
    /usr/bin/git --version
    /usr/bin/git clone git@github.com:openthread/ot-br-posix.git

    if [ -n "$commit_sha1" ]; then
        cd "${current_dir}/ot-br-posix"; git checkout "$commit_sha1"
    fi

    # OTBR_VENDOR_NAME="Home Assistant" OTBR_PRODUCT_NAME="OpenThread Border Router"
    cd "${current_dir}/ot-br-posix"; WEB_GUI=0 ./script/bootstrap
    cd "${current_dir}/ot-br-posix"; INFRA_IF_NAME=wlan0 WEB_GUI=0 ./script/setup

    cp ${current_dir}/otbr-agent /etc/default/

    cat /etc/default/otbr-agent
fi

cd ${current_dir}/ot-br-posix
dirty_id=$(/usr/bin/git describe --dirty --always)
print_info "Record dirty-id '$dirty_id'"
echo "dirty-id: $dirty_id" >> ${output_dir}/DEBIAN/control
commit_id=$(git log -1 --format=%H)
print_info "Record commit-id '$commit_id'"
echo "commit: $commit_id" >> ${output_dir}/DEBIAN/control
cd ${current_dir}

# find /usr -type f -newermt $(date +'%Y-%m-%d') ! -newermt $(date -d '1 day' +'%Y-%m-%d')

cp ${current_dir}/otbr-agent /etc/default/otbr-agent

mkdir -p /lib/thirdreality/
mkdir -p /lib/systemd/system/
cp ${current_dir}/hubv3-otbr-agent.sh /lib/thirdreality/hubv3-otbr-agent.sh
cp ${current_dir}/otbr_database /lib/thirdreality/otbr_database

cp ${current_dir}/hubv3-otbr-agent.service /lib/systemd/system/hubv3-otbr-agent.service

chmod +x /lib/thirdreality/hubv3-otbr-agent.sh
chmod +x /lib/thirdreality/otbr_database

print_info "Copy openthread files ..."

mkdir -p ${output_dir}/etc/default/
mkdir -p ${output_dir}/etc/init.d/
mkdir -p ${output_dir}/etc/dbus-1/system.d/
mkdir -p ${output_dir}/etc/sysctl.d/

mkdir -p ${output_dir}/usr/sbin/
mkdir -p ${output_dir}/usr/bin/
mkdir -p ${output_dir}/usr/lib/systemd/system/
mkdir -p ${output_dir}/usr/lib/thirdreality/
mkdir -p ${output_dir}/usr/include/
mkdir -p ${output_dir}/usr/share

if [ -f "/usr/lib/libdns_sd.so.1" ];then 
    cp /usr/lib/libdns_sd.so.1 ${output_dir}/usr/lib/
else
    echo "Error: file /usr/lib/libdns_sd.so.1 is missing!"
fi

cp ${current_dir}/otbr-agent-init.sh ${output_dir}/usr/lib/thirdreality/otbr-agent-init.sh
cp ${current_dir}/hubv3-otbr-agent.sh ${output_dir}/usr/lib/thirdreality/hubv3-otbr-agent.sh
cp ${current_dir}/otbr_database ${output_dir}/usr/lib/thirdreality/otbr_database

chmod +x ${output_dir}/usr/lib/thirdreality/otbr-agent-init.sh
chmod +x ${output_dir}/usr/lib/thirdreality/hubv3-otbr-agent.sh
chmod +x ${output_dir}/usr/lib/thirdreality/otbr_database

cp /usr/lib/systemd/system/otbr-agent.service ${output_dir}/usr/lib/systemd/system/
cp /usr/lib/systemd/system/hubv3-otbr-agent.service ${output_dir}/usr/lib/systemd/system/


# 在otbr-agent.service的ExecStartPre=/usr/sbin/service mdns start之前添加ExecStartPre=/usr/lib/thirdreality/otbr-agent-init.sh
sed -i '/ExecStartPre=\/usr\/sbin\/service mdns start/i ExecStartPre=/usr/lib/thirdreality/otbr-agent-init.sh' ${output_dir}/usr/lib/systemd/system/otbr-agent.service

if [ -d "/usr/share/otbr-web" ];then
    cp /usr/share/otbr-web ${output_dir}/usr/share/otbr-web
fi

if [ -f "/usr/lib/libnss_mdns-0.2.so" ];then 
    cp /usr/lib/libnss_mdns-0.2.so ${output_dir}/usr/lib/
else
    echo "Error: file /usr/lib/libnss_mdns-0.2.so is missing!"
fi

if [ -f "/usr/sbin/ot-ctl" ];then 
    cp /usr/sbin/ot-ctl ${output_dir}/usr/sbin/
else
    echo "Error: file /usr/sbin/ot-ctl is missing!"
    exit 1
fi

# if [ -f "/usr/sbin/mdnsd" ];then 
#     cp /usr/sbin/mdnsd ${output_dir}/usr/sbin/
# else
#     echo "Error: file /usr/sbin/mdnsd is missing!"
#     exit 1
# fi

if [ -f "/usr/sbin/otbr-agent" ];then 
    cp /usr/sbin/otbr-agent ${output_dir}/usr/sbin/
else
    echo "Error: file /usr/sbin/otbr-agent is missing!"
    exit 1
fi



cp /usr/bin/dns-sd ${output_dir}/usr/sbin/
cp /usr/include/dns_sd.h ${output_dir}/usr/include/

cp /etc/dbus-1/system.d/otbr-agent.conf ${output_dir}/etc/dbus-1/system.d/

cp /etc/init.d/otbr-firewall ${output_dir}/etc/init.d/
cp /etc/init.d/otbr-nat44 ${output_dir}/etc/init.d/
cp /etc/init.d/mdns ${output_dir}/etc/init.d/
cp /etc/default/otbr-agent ${output_dir}/etc/default/
cp /etc/sysctl.d/60-otbr-ip-forward.conf ${output_dir}/etc/sysctl.d
cp /etc/sysctl.d/60-otbr-accept-ra.conf ${output_dir}/etc/sysctl.d

cp /etc/nss_mdns.conf ${output_dir}/etc/
#cp /etc/nsswitch.conf.pre-mdns ${output_dir}/etc/
#cp /etc/nsswitch.conf ${output_dir}/etc/
# ---------------------

print_info "Start to build otbr-agent_${version}.deb ..."
dpkg-deb --build ${output_dir} ${current_dir}/otbr-agent_${version}.deb

# rm -rf ${output_dir}/usr > /dev/null 2>&1
# rm -rf ${output_dir}/etc > /dev/null 2>&1
# rm -rf ${output_dir} > /dev/null 2>&1

print_info "Build otbr-agent_${version}.deb finished ..."



