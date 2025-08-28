#!/bin/bash

VENV_PATHS=(
    "/usr/local/thirdreality/zigpy_tools"
    "/srv/homeassistant"
)

DEVICE="/dev/ttyAML3"

for venv_path in "${VENV_PATHS[@]}"; do
    if [ -f "${venv_path}/bin/activate" ]; then
        cd "${venv_path}"
        source "${venv_path}/bin/activate"
        output=$(zigpy radio --baudrate 2000000 blz $DEVICE reset 2>&1)
        ret=$?
        deactivate
        if [ $ret -eq 0 ]; then
            echo "$output"
            echo "blz reset success"
            exit 0
        fi
        # 输出每次失败的详细信息
        echo "[$venv_path] reset failed (exit code: $ret):"
        echo "$output"
        echo "---"
    fi

done

echo "Error: blz reset failed in all venvs"
exit 1
