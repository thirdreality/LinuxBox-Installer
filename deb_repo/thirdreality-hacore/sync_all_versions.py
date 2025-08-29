#!/usr/bin/env python3
"""
Home Assistant 完整版本同步脚本
从 requirements.txt、requirements_all.txt、Dockerfile 同步所有版本号
"""

import requests
import re
import json
from datetime import datetime
import os
import time

class HomeAssistantVersionSyncer:
    def __init__(self, build_script_path="build.sh"):
        self.build_script_path = build_script_path
        self.backup_path = f"{build_script_path}.backup.{datetime.now().strftime('%Y%m%d_%H%M%S')}"
        
        # 需要从不同源获取的包配置
        self.package_sources = {
            # 主要版本 - 从 GitHub API 获取
            "home_assistant": {
                "type": "github_release",
                "repo": "home-assistant/core",
                "pattern": r'export HOME_ASSISTANT_VERSION="([^"]*)"'
            },
            "matter_server": {
                "type": "github_release",
                "repo": "home-assistant-libs/python-matter-server", 
                "pattern": r'export MATTER_SERVER_VERSION="([^"]*)"'
            },
            
            # 从 requirements.txt 获取的包
            "requirements_packages": {
                "type": "requirements_file",
                "file": "requirements.txt",
                "packages": [
                    # 这些包实际在 requirements.txt 中有版本定义
                ]
            },
            
            # 从 requirements_all.txt 获取的包
            "requirements_all_packages": {
                "type": "requirements_file",
                "file": "requirements_all.txt", 
                "packages": [
                    "home-assistant-frontend",
                    "universal-silabs-flasher",
                    "ha-silabs-firmware-client",
                    "psutil-home-assistant",
                    "python-otbr-api",
                    "python-matter-server",
                    "pyroute2", 
                    "zha"
                ]
            }
        }
        
    def get_latest_home_assistant_version(self):
        """获取最新的 Home Assistant Core 版本"""
        try:
            url = "https://api.github.com/repos/home-assistant/core/releases/latest"
            response = requests.get(url, timeout=10)
            response.raise_for_status()
            
            data = response.json()
            version = data['tag_name'].lstrip('v')
            
            print(f"✅ 获取到最新 Home Assistant Core 版本: {version}")
            return version
        except Exception as e:
            print(f"❌ 获取 Home Assistant Core 版本失败: {e}")
            return None
    
    def get_github_latest_version(self, repo):
        """从 GitHub API 获取指定仓库的最新版本"""
        try:
            url = f"https://api.github.com/repos/{repo}/releases/latest"
            response = requests.get(url, timeout=10)
            response.raise_for_status()
            
            data = response.json()
            version = data['tag_name'].lstrip('v')
            
            return version
        except Exception as e:
            print(f"❌ 获取 {repo} 版本失败: {e}")
            return None
    
    def get_matter_ota_provider_version(self, matter_server_version):
        """根据 matter-server 版本获取对应的 ota-provider 版本"""
        try:
            dockerfile_url = f"https://raw.githubusercontent.com/home-assistant-libs/python-matter-server/{matter_server_version}/Dockerfile"
            response = requests.get(dockerfile_url, timeout=10)
            response.raise_for_status()
            dockerfile_content = response.text
            # 直接匹配 releases/download/<tag>
            match = re.search(r"matter-linux-ota-provider/releases/download/([^\s\"']+)", dockerfile_content)
            if match:
                ota_version = match.group(1)
                print(f"✅ 从 matter-server Dockerfile 获取到 ota-provider 版本: {ota_version}")
                return ota_version
            # 兜底：取 ota-provider 最新 release
            releases_url = "https://api.github.com/repos/home-assistant-libs/matter-linux-ota-provider/releases/latest"
            response = requests.get(releases_url, timeout=10)
            response.raise_for_status()
            data = response.json()
            ota_version = data.get('tag_name', '').lstrip('v') or data.get('name', '')
            if ota_version:
                print(f"✅ 获取到最新 ota-provider 版本: {ota_version}")
                return ota_version
            return None
        except Exception as e:
            print(f"❌ 获取 ota-provider 版本失败: {e}")
            return None

    def get_file_content(self, version, file_path):
        """获取指定版本的文件内容"""
        try:
            url = f"https://raw.githubusercontent.com/home-assistant/core/{version}/{file_path}"
            response = requests.get(url, timeout=10)
            response.raise_for_status()
            
            print(f"✅ 获取到 {version} 版本的 {file_path}")
            return response.text
        except Exception as e:
            print(f"❌ 获取 {file_path} 失败: {e}")
            return None
    
    def parse_requirements_file(self, content, target_packages):
        """解析 requirements 文件中的包版本"""
        packages = {}
        
        for line in content.split('\n'):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            
            # 匹配包名和版本号
            match = re.match(r'^([^=<>!~]+)(?:==|>=|<=|!=|~=)(.+)$', line)
            if match:
                package_name = match.group(1).strip()
                version = match.group(2).strip()
                
                if package_name in target_packages:
                    packages[package_name] = version
        
        return packages

    def extract_dockerfile_package_section(self, dockerfile_content):
        """从 Dockerfile 中提取整个包安装段"""
        try:
            pattern = r'(uv pip install[\s\S]*?)\n\n|\Z'
            match = re.search(pattern, dockerfile_content)
            if match:
                package_section = match.group(1)
                print("✅ 成功提取 Dockerfile 包安装段")
                return package_section
            print("❌ 无法从 Dockerfile 中提取包安装段")
            return None
        except Exception as e:
            print(f"❌ 提取 Dockerfile 包安装段失败: {e}")
            return None

    def parse_packages_from_docker_section(self, dockerfile_section):
        """解析 uv pip install 段中的逐个包版本，返回 dict(name->version)"""
        packages = {}
        if not dockerfile_section:
            return packages
        for line in dockerfile_section.split('\n'):
            line = line.strip().rstrip('\\').strip()
            if not line or line.startswith('uv pip install'):
                continue
            if line.startswith(('--no-build', '--no-cache', '-c ', '-r ')):
                continue
            m = re.match(r'^([A-Za-z0-9_.\-]+)==([^\s]+)$', line)
            if m:
                packages[m.group(1)] = m.group(2)
        return packages

    def get_all_versions(self, target_version):
        """获取所有需要的版本号"""
        all_versions = {}
        print(f" 正在获取 {target_version} 版本的所有依赖信息...")
        # 1. 获取主要版本
        for package_name, package_info in self.package_sources.items():
            if package_info["type"] == "github_release":
                if package_name == "home_assistant":
                    all_versions[package_name] = target_version
                else:
                    version = self.get_github_latest_version(package_info["repo"])
                    if version:
                        all_versions[package_name] = version
        # 2. requirements.txt
        requirements_content = self.get_file_content(target_version, "requirements.txt")
        if requirements_content:
            req_packages = self.package_sources["requirements_packages"]["packages"]
            req_versions = self.parse_requirements_file(requirements_content, req_packages)
            all_versions.update(req_versions)
        # 3. requirements_all.txt
        requirements_all_content = self.get_file_content(target_version, "requirements_all.txt")
        if requirements_all_content:
            req_all_packages = self.package_sources["requirements_all_packages"]["packages"]
            req_all_versions = self.parse_requirements_file(requirements_all_content, req_all_packages)
            all_versions.update(req_all_versions)
        # 4. Dockerfile 段与逐包
        dockerfile_content = self.get_file_content(target_version, "script/hassfest/docker/Dockerfile")
        if dockerfile_content:
            dockerfile_package_section = self.extract_dockerfile_package_section(dockerfile_content)
            if dockerfile_package_section:
                all_versions["dockerfile_package_section"] = dockerfile_package_section
                all_versions["dockerfile_packages"] = self.parse_packages_from_docker_section(dockerfile_package_section)
        # 5. OTA provider
        if "matter_server" in all_versions:
            ota_version = self.get_matter_ota_provider_version(all_versions["matter_server"])
            if ota_version:
                all_versions["ota_provider"] = ota_version
        return all_versions
    
    def backup_original_file(self):
        """备份原始文件"""
        try:
            if os.path.exists(self.build_script_path):
                import shutil
                shutil.copy2(self.build_script_path, self.backup_path)
                print(f"✅ 已备份原始文件到: {self.backup_path}")
                return True
        except Exception as e:
            print(f"❌ 备份文件失败: {e}")
            return False
    
    def update_control_file_version(self, ha_version):
        """更新 DEBIAN/control 文件中的版本号"""
        try:
            control_file = "DEBIAN/control"
            if not os.path.exists(control_file):
                print(f"⚠️ DEBIAN/control 文件不存在，跳过更新")
                return False
            
            with open(control_file, 'r', encoding='utf-8') as f:
                content = f.read()
            
            # 更新版本号
            pattern = r'Version:\s*([^\n]+)'
            match = re.search(pattern, content)
            if match:
                current_version = match.group(1).strip()
                if current_version != ha_version:
                    updated_content = re.sub(pattern, f'Version: {ha_version}', content)
                    
                    with open(control_file, 'w', encoding='utf-8') as f:
                        f.write(updated_content)
                    
                    print(f"✅ 已更新 DEBIAN/control 版本: {current_version} -> {ha_version}")
                    return True
                else:
                    print(f"ℹ️ DEBIAN/control 版本已是最新: {ha_version}")
                    return False
            else:
                print("❌ 无法在 DEBIAN/control 中找到版本号")
                return False
                
        except Exception as e:
            print(f"❌ 更新 DEBIAN/control 失败: {e}")
            return False

    def update_versions_in_build_script(self, versions):
        """更新 build.sh 中的所有版本号"""
        try:
            with open(self.build_script_path, 'r', encoding='utf-8') as f:
                content = f.read()
            
            updated_content = content
            updated_count = 0
            
            # 更新主要版本号
            for package_name, version in versions.items():
                if package_name in ["home_assistant", "matter_server"]:
                    pattern = rf'export {package_name.upper()}_VERSION="([^"]*)"'
                    if re.search(pattern, updated_content):
                        updated_content = re.sub(
                            pattern,
                            f'export {package_name.upper()}_VERSION="{version}"',
                            updated_content
                        )
                        updated_count += 1
                        print(f"✅ 已更新 {package_name.upper()}_VERSION: {version}")
                elif package_name == "home-assistant-frontend":
                    # 特殊处理 frontend 版本
                    pattern = r'export FRONTEND_VERSION="([^"]*)"'
                    if re.search(pattern, updated_content):
                        updated_content = re.sub(
                            pattern,
                            f'export FRONTEND_VERSION="{version}"',
                            updated_content
                        )
                        updated_count += 1
                        print(f"✅ 已更新 FRONTEND_VERSION: {version}")
            
            # 更新 chip_example_url
            if "ota_provider" in versions:
                ota_version = versions["ota_provider"]
                pattern = r'chip_example_url="([^"]*)"'
                if re.search(pattern, updated_content):
                    new_url = f'chip_example_url="https://github.com/home-assistant-libs/matter-linux-ota-provider/releases/download/{ota_version}"'
                    updated_content = re.sub(pattern, new_url, updated_content)
                    updated_count += 1
                    print(f"✅ 已更新 chip_example_url: {ota_version}")
            
            # 更新 pip install 中的包版本
            for package_name, version in versions.items():
                if package_name not in ["home_assistant", "home-assistant-frontend", "matter_server", "ota_provider", "dockerfile_package_section", "dockerfile_packages"]:
                    # 处理带连字符的包名
                    pip_package_name = package_name.replace('_', '-')
                    pattern = rf'{pip_package_name}==([^\s]+)'
                    
                    if re.search(pattern, updated_content):
                        updated_content = re.sub(
                            pattern,
                            f'{pip_package_name}=={version}',
                            updated_content
                        )
                        updated_count += 1
                        print(f"✅ 已更新 {pip_package_name}: {version}")
            
            # 更新 Dockerfile 包安装段（替换整个段）
            if "dockerfile_package_section" in versions:
                dockerfile_section = versions["dockerfile_package_section"]
                
                # 将 uv pip install 段转换为 python3 -m pip install 段
                # 提取包列表部分
                package_lines = []
                for line in dockerfile_section.split('\n'):
                    line = line.strip()
                    if line and not line.startswith('uv pip install') and not line.startswith('--no-build') and not line.startswith('--no-cache') and not line.startswith('-c') and not line.startswith('-r') and not line.startswith('\\'):
                        # 这是包行，格式如: stdlib-list==0.10.0
                        if '==' in line:
                            package_lines.append(f"        {line}")
                
                if package_lines:
                    # 构建新的包安装段
                    new_package_section = f"""    python3 -m pip install \\
{chr(10).join(package_lines)}"""
                    
                    # 查找并替换现有的包安装部分
                    pattern = r'(    python3 -m pip install \\\n(?:        [^\n]+\n)+)'
                    
                    if re.search(pattern, updated_content):
                        updated_content = re.sub(pattern, new_package_section, updated_content)
                        updated_count += 1
                        print(f"✅ 已更新 Dockerfile 包安装段，共 {len(package_lines)} 个包")
            
            if updated_content != content:
                with open(self.build_script_path, 'w', encoding='utf-8') as f:
                    f.write(updated_content)
                print(f"\n✅ 文件已更新，共更新了 {updated_count} 个版本号/段")
                return True
            else:
                print("\nℹ️ 没有版本号需要更新")
                return False
                
        except Exception as e:
            print(f"❌ 更新文件失败: {e}")
            return False
    
    def restore_from_backup(self):
        """从备份恢复文件"""
        try:
            if os.path.exists(self.backup_path):
                import shutil
                shutil.copy2(self.backup_path, self.build_script_path)
                print(f"✅ 已从备份恢复文件: {self.build_script_path}")
                return True
        except Exception as e:
            print(f"❌ 恢复备份失败: {e}")
            return False
    
    def show_version_summary(self, versions):
        """显示版本更新摘要"""
        print("\n📋 版本更新摘要:")
        # 主要版本
        print("  🏠 主要版本:")
        for key in ["home_assistant", "matter_server"]:
            if key in versions:
                print(f"    {key.upper()}: {versions[key]}")
        # Frontend 版本（从 requirements.txt 获取）
        if "home-assistant-frontend" in versions:
            print(f"    FRONTEND: {versions['home-assistant-frontend']}")
        # OTA Provider 版本
        if "ota_provider" in versions:
            print("  📡 OTA Provider:")
            print(f"    ota_provider: {versions['ota_provider']}")
        # requirements 指定包
        print("  📦 requirements 版本:")
        for name in self.package_sources["requirements_packages"]["packages"]:
            if name in versions:
                print(f"    {name}: {versions[name]}")
        # requirements_all 指定包
        print("  📦 requirements_all 版本:")
        for name in self.package_sources["requirements_all_packages"]["packages"]:
            if name in versions:
                print(f"    {name}: {versions[name]}")
        # Dockerfile 段与逐包
        if "dockerfile_packages" in versions and versions["dockerfile_packages"]:
            print("  🐳 Dockerfile 包列表:")
            for pkg, ver in versions["dockerfile_packages"].items():
                print(f"    {pkg}: {ver}")
        if "dockerfile_package_section" in versions:
            print("  🐳 Dockerfile 原始段: 已提取")
    
    def run_sync(self, target_version=None, dry_run=False):
        """运行完整版本同步"""
        print("🚀 开始 Home Assistant 完整版本同步...")
        print(f"📁 目标文件: {self.build_script_path}")
        
        if dry_run:
            print("🔍 模拟运行模式 - 不会实际修改文件")
        
        # 获取目标版本
        if not target_version:
            target_version = self.get_latest_home_assistant_version()
            if not target_version:
                return False
        
        print(f"🎯 目标版本: {target_version}")
        
        # 获取所有版本
        versions = self.get_all_versions(target_version)
        if not versions:
            print("❌ 无法获取版本信息")
            return False
        
        # 显示版本摘要
        self.show_version_summary(versions)
        
        if dry_run:
            print("\n🔍 模拟运行完成，文件未修改")
            return True
        
        # 备份原文件
        if not self.backup_original_file():
            return False
        
        # 更新版本
        try:
            build_success = self.update_versions_in_build_script(versions)
            control_success = False
            
            # 更新 DEBIAN/control 文件版本
            if "home_assistant" in versions:
                control_success = self.update_control_file_version(versions["home_assistant"])
            
            if build_success or control_success:
                print("\n🎉 完整版本同步完成!")
                print(f"💾 原始文件已备份到: {self.backup_path}")
                return True
            else:
                print("\n⚠️ 版本同步未完成")
                return False
        except Exception as e:
            print(f"\n❌ 同步过程中出错: {e}")
            print("🔄 正在恢复备份...")
            self.restore_from_backup()
            return False

def main():
    """主函数"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Home Assistant 完整版本同步")
    parser.add_argument("--version", help="指定 Home Assistant 版本 (默认: 最新版本)")
    parser.add_argument("--dry-run", action="store_true", help="模拟运行，不实际修改文件")
    parser.add_argument("--file", default="build.sh", help="要更新的文件路径 (默认: build.sh)")
    parser.add_argument("--restore", action="store_true", help="从备份恢复文件")
    
    args = parser.parse_args()
    
    syncer = HomeAssistantVersionSyncer(args.file)
    
    if args.restore:
        if syncer.restore_from_backup():
            print("✅ 恢复完成")
        else:
            print("❌ 恢复失败")
        return
    
    # 运行同步
    success = syncer.run_sync(target_version=args.version, dry_run=args.dry_run)
    
    if success:
        print("\n✨ 操作完成!")
    else:
        print("\n💥 操作失败!")

if __name__ == "__main__":
    main()
