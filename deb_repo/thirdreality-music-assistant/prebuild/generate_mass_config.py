#!/srv/music-assistant/bin/python3
import json
import uuid
import sys
import shutil
from pathlib import Path

# 用法: python3 generate_mass_config.py template.json output_dir
if len(sys.argv) != 3:
    print(f"Usage: {sys.argv[0]} TEMPLATE_JSON OUTPUT_DIR")
    sys.exit(1)

template_path = Path(sys.argv[1])
output_dir = Path(sys.argv[2])

if not template_path.is_file():
    print(f"Template file {template_path} does not exist.")
    sys.exit(1)

output_dir.mkdir(parents=True, exist_ok=True)

# 读取模板
with template_path.open("r", encoding="utf-8") as f:
    config = json.load(f)

# 生成新的 server_id
new_server_id = uuid.uuid4().hex
config["server_id"] = new_server_id

# 清理 players 的 player_id、name 和 last_error
for player_key, player in config.get("players", {}).items():
    player["player_id"] = ""
    player["name"] = None
    player["available"] = True
    player["default_name"] = ""
    player["values"] = {}
    player["last_error"] = None

# 清理 providers 的 last_error
for provider in config.get("providers", {}).values():
    provider["last_error"] = None

# 输出到目标目录
output_file = output_dir / "settings.json"
with output_file.open("w", encoding="utf-8") as f:
    json.dump(config, f, indent=2, ensure_ascii=False)

print(f"Generated new Music Assistant config with server_id={new_server_id}")
print(f"Output path: {output_file}")

