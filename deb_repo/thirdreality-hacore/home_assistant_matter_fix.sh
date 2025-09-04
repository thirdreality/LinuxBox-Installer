#!/bin/bash
# Script for homeassistant-core-matter
# Purpose: Fix vendorId 65521 to 5127 in Matter server configuration files
# Version: 1.0.0

set -e

CONFIG_DIR="/var/lib/homeassistant"
MATTER_SERVER_DIR="$CONFIG_DIR/matter_server"
LOG_FILE="/var/log/home_assistant_matter_fix.log"
OLD_VENDOR_ID="65521"
NEW_VENDOR_ID="4939"

# Helper functions
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to backup files before modification
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        cp "$file" "${file}.backup.$(date +%Y%m%d_%H%M%S)"
        log "Created backup for $file"
    fi
}

# Function to fix vendorId in chip.json
fix_chip_json() {
    local chip_file="$MATTER_SERVER_DIR/chip.json"
    
    if [ ! -f "$chip_file" ]; then
        log "WARNING: chip.json not found at $chip_file"
        return 1
    fi
    
    log "Checking chip.json for vendorId issues..."
    
    # Check if the old vendorId exists in the file
    if grep -q "\"vendorId\": $OLD_VENDOR_ID" "$chip_file"; then
        log "Found vendorId $OLD_VENDOR_ID in chip.json, fixing..."
        
        # Create backup
        backup_file "$chip_file"
        
        # Replace vendorId using sed
        sed -i "s/\"vendorId\": $OLD_VENDOR_ID/\"vendorId\": $NEW_VENDOR_ID/g" "$chip_file"
        
        log "Successfully updated vendorId from $OLD_VENDOR_ID to $NEW_VENDOR_ID in chip.json"
        return 0
    else
        log "No vendorId $OLD_VENDOR_ID found in chip.json, no changes needed"
        return 1
    fi
}

# Function to fix vendorId in numbered JSON files
fix_numbered_json_files() {
    local matter_dir="$MATTER_SERVER_DIR"
    local fixed_count=0
    
    if [ ! -d "$matter_dir" ]; then
        log "WARNING: Matter server directory not found at $matter_dir"
        return 1
    fi
    
    log "Searching for numbered JSON files in $matter_dir..."
    
    # Find all numbered JSON files (pattern: digits.json)
    local json_files=$(find "$matter_dir" -maxdepth 1 -name "[0-9]*.json" -type f)
    
    if [ -z "$json_files" ]; then
        log "No numbered JSON files found"
        return 1
    fi
    
    for json_file in $json_files; do
        log "Checking file: $(basename "$json_file")"
        
        # Check if the file contains the old vendorId in the specific pattern
        if grep -q "\"2\": $OLD_VENDOR_ID" "$json_file"; then
            log "Found vendorId $OLD_VENDOR_ID in $(basename "$json_file"), fixing..."
            
            # Create backup
            backup_file "$json_file"
            
            # Replace the specific pattern "2": 65521 with "2": 5127
            sed -i "s/\"2\": $OLD_VENDOR_ID/\"2\": $NEW_VENDOR_ID/g" "$json_file"
            
            log "Successfully updated vendorId in $(basename "$json_file")"
            ((fixed_count++))
        else
            log "No vendorId $OLD_VENDOR_ID found in $(basename "$json_file")"
        fi
    done
    
    if [ $fixed_count -gt 0 ]; then
        log "Fixed vendorId in $fixed_count numbered JSON files"
        return 0
    else
        log "No numbered JSON files required fixing"
        return 1
    fi
}

# Main execution
log "Starting Matter server vendorId fix process..."

if [ ! -d "$MATTER_SERVER_DIR" ]; then
    log "ERROR: Matter server directory not found at $MATTER_SERVER_DIR"
    log "Please ensure Home Assistant Matter integration is installed and configured"
    exit 1
fi

# Fix chip.json
chip_fixed=false
if fix_chip_json; then
    chip_fixed=true
fi

# Fix numbered JSON files
numbered_fixed=false
if fix_numbered_json_files; then
    numbered_fixed=true
fi

# Summary
if [ "$chip_fixed" = true ] || [ "$numbered_fixed" = true ]; then
    log "Matter server vendorId fix completed successfully"
    log "Summary:"
    [ "$chip_fixed" = true ] && log "  - Fixed chip.json"
    [ "$numbered_fixed" = true ] && log "  - Fixed numbered JSON files"
    log "Please restart Home Assistant Matter integration for changes to take effect"
    exit 0
else
    log "No vendorId fixes were needed - all files already have correct vendorId"
    exit 0
fi
