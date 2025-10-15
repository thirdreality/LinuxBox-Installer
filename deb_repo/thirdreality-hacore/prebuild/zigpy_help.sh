#!/bin/bash

VENV_PATHS=(
    "/usr/local/thirdreality/zigpy_tools"
    "/srv/homeassistant"
)

DEVICE="/dev/ttyAML3"
tmp_zigate=$(mktemp)
tmp_blz=$(mktemp)

for venv_path in "${VENV_PATHS[@]}"; do
    if [ -f "${venv_path}/bin/activate" ]; then
        cd "${venv_path}"
        source "${venv_path}/bin/activate"
        # 先试 zigate
        if zigpy radio zigate $DEVICE info > "$tmp_zigate" 2>&1; then
            cat "$tmp_zigate"
            echo "Radio Type: zigate"
            deactivate
            rm -f "$tmp_zigate" "$tmp_blz"
            exit 0
        # 再试 blz
        elif zigpy radio --baudrate 2000000 blz $DEVICE info > "$tmp_blz" 2>&1; then
            cat "$tmp_blz"
            echo "Radio Type: blz"
            deactivate
            rm -f "$tmp_zigate" "$tmp_blz"
            exit 0
        fi
        deactivate
    fi
done

# 如果所有 venv 都失败，输出所有log
echo "Error: Failed to detect any supported radio type"
echo "---- zigate output ----"
cat "$tmp_zigate"
echo "---- blz output ----"
cat "$tmp_blz"
rm -f "$tmp_zigate" "$tmp_blz"
exit 1
