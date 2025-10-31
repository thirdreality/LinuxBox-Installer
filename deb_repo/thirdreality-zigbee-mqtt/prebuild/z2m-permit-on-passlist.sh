#!/bin/bash

MQTT_HOST="localhost"
TIMEOUT="254"

# Only check this config file
CONFIG_FILE="/opt/zigbee2mqtt/data/configuration.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "Zigbee2MQTT configuration.yaml not found. Skipping permit_join."
  exit 0
fi

# YAML parsing (handles block list and inline list) without yq dependency
count_passlist_with_awk() {
  awk '
    BEGIN {count=0; in_pass=0; indent=-1}
    {
      line=$0
      # inline list: passlist: [a, b]
      if (match(line, /^\s*passlist:\s*\[/)) {
        inl=line
        gsub(/^[^\[]*\[/, "", inl)
        gsub(/\].*$/, "", inl)
        n=gsub(/,/, "&", inl) + (length(inl)>0 ? 1:0)
        count+=n
        in_pass=0
        next
      }
      # block list start: passlist:
      if (match(line, /^\s*passlist:\s*$/)) {
        in_pass=1
        indent=index(line, "p")-1
        next
      }
      if (in_pass==1) {
        # stop when indentation decreases or a new key appears at same indent
        if (match(line, /^\S/) || (indent>=0 && match(line, "^" sprintf("%%-%ds", indent) "[^ ]")) ) {
          in_pass=0
        } else if (match(line, /^\s*-\s*[^#].*/)) {
          count++
        }
      }
    }
    END {print count}
  ' "$CONFIG_FILE"
}

get_passlist_count() {
  count_passlist_with_awk
}

PASSLIST_COUNT=$(get_passlist_count)

if [ -n "$PASSLIST_COUNT" ] && [ "$PASSLIST_COUNT" -gt 1 ]; then
  echo "Detected passlist with $PASSLIST_COUNT items in $CONFIG_FILE. Waiting for Zigbee2MQTT online..."
  # Wait for bridge to be online (up to 90s)
  if mosquitto_sub -h "$MQTT_HOST" -u "thirdreality" -P "thirdreality" -t "zigbee2mqtt/bridge/state" -C 1 -W 90 2>/dev/null | grep -qi "online"; then
    echo "Zigbee2MQTT online. Sending permit_join..."
    mosquitto_pub -h "$MQTT_HOST" \
      -u "thirdreality" \
      -P "thirdreality" \
      -t "zigbee2mqtt/bridge/request/permit_join" \
      -m "{\"value\": true, \"time\": $TIMEOUT}"
    # 同步LED：开始配对
    /usr/local/bin/supervisor led sys_device_pairing || true
    # 超时后自动结束LED配对指示
    ( sleep "$TIMEOUT"; /usr/local/bin/supervisor led sys_device_paired || true ) &
  else
    echo "Zigbee2MQTT did not come online within timeout. Skipping permit_join."
  fi
else
  echo "passlist not present or items <= 1. No permit_join."
fi
