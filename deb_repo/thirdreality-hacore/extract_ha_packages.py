#!/usr/bin/env python3
"""
Home Assistant Package Extractor

This script analyzes log files to extract Home Assistant package installations
from lines containing "homeassistant.util.package" and "Attempting install of".

Usage:
    python3 extract_ha_packages.py <log_file> [options]

Options:
    --output FILE    Save results to file (default: print to stdout)
    --format FORMAT  Output format: list, json, requirements (default: list)
    --unique         Remove duplicate packages (default: False)
    --version-only   Extract only package names without versions (default: False)
"""

import re
import sys
import argparse
import json
from pathlib import Path
from typing import List, Set, Dict, Optional


def extract_packages_from_log(log_file: str, unique: bool = False, version_only: bool = False) -> List[str]:
    """
    Extract Home Assistant package installations from log file.
    
    Args:
        log_file: Path to the log file
        unique: If True, return only unique packages
        version_only: If True, return only package names without versions
        
    Returns:
        List of package specifications (e.g., "package==1.0.0")
    """
    packages = []
    seen = set() if unique else None
    
    # Pattern to match Home Assistant package installation lines
    pattern = r'homeassistant\.util\.package.*Attempting install of ([^\s]+)'
    
    try:
        with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
            for line_num, line in enumerate(f, 1):
                match = re.search(pattern, line)
                if match:
                    package_spec = match.group(1)
                    
                    # Extract version if version_only is True
                    if version_only:
                        package_name = package_spec.split('==')[0]
                        package_spec = package_name
                    
                    # Check for uniqueness if requested
                    if unique and package_spec in seen:
                        continue
                    
                    if unique:
                        seen.add(package_spec)
                    
                    packages.append(package_spec)
                    
    except FileNotFoundError:
        print(f"Error: Log file '{log_file}' not found.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error reading log file: {e}", file=sys.stderr)
        sys.exit(1)
    
    return packages


def format_output(packages: List[str], format_type: str) -> str:
    """
    Format the extracted packages according to the specified format.
    
    Args:
        packages: List of package specifications
        format_type: Output format ('list', 'json', 'requirements')
        
    Returns:
        Formatted string
    """
    if format_type == 'json':
        return json.dumps(packages, indent=2)
    elif format_type == 'requirements':
        return '\n'.join(packages)
    else:  # list format
        return '\n'.join(packages)


def main():
    parser = argparse.ArgumentParser(
        description='Extract Home Assistant package installations from log files',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python3 extract_ha_packages.py /var/log/homeassistant.log
  python3 extract_ha_packages.py 1.log --unique --format requirements
  python3 extract_ha_packages.py 1.log --output packages.txt --format json
  python3 extract_ha_packages.py 1.log --version-only --unique
        """
    )
    
    parser.add_argument('log_file', help='Path to the log file to analyze')
    parser.add_argument('--output', '-o', help='Output file (default: stdout)')
    parser.add_argument('--format', '-f', choices=['list', 'json', 'requirements'], 
                       default='list', help='Output format (default: list)')
    parser.add_argument('--unique', '-u', action='store_true', 
                       help='Remove duplicate packages')
    parser.add_argument('--version-only', '-v', action='store_true',
                       help='Extract only package names without versions')
    
    args = parser.parse_args()
    
    # Check if log file exists
    if not Path(args.log_file).exists():
        print(f"Error: Log file '{args.log_file}' does not exist.", file=sys.stderr)
        sys.exit(1)
    
    # Extract packages
    packages = extract_packages_from_log(
        args.log_file, 
        unique=args.unique, 
        version_only=args.version_only
    )
    
    if not packages:
        print("No Home Assistant package installations found in the log file.", file=sys.stderr)
        sys.exit(1)
    
    # Format output
    output = format_output(packages, args.format)
    
    # Write output
    if args.output:
        try:
            with open(args.output, 'w', encoding='utf-8') as f:
                f.write(output)
            print(f"Extracted {len(packages)} packages to '{args.output}'")
        except Exception as e:
            print(f"Error writing to output file: {e}", file=sys.stderr)
            sys.exit(1)
    else:
        print(output)


if __name__ == '__main__':
    main()
