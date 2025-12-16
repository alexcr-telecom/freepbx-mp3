#!/bin/bash
#
# FreePBX Recording Cleanup Script
# Deletes old recordings when disk space < 10%
#
# Crontab: 0 * * * * /usr/local/bin/recording_maintenance.sh >> /var/log/asterisk/recording_maintenance.log 2>&1
#

RECORDING_PATH="/var/spool/asterisk/monitor"
MIN_FREE_PERCENT=10

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

get_free_percent() {
    df "$RECORDING_PATH" | awk 'NR==2 {gsub(/%/,""); print 100-$5}'
}

# ============ MAIN ============
free_percent=$(get_free_percent)

if [[ $free_percent -ge $MIN_FREE_PERCENT ]]; then
    log "Disk OK: ${free_percent}% free"
    exit 0
fi

log "WARNING: Disk low - ${free_percent}% free. Starting cleanup..."

deleted=0
freed=0

# Delete oldest files first until we have enough space
while [[ $(get_free_percent) -lt $MIN_FREE_PERCENT ]]; do
    # Find oldest recording file
    oldest_file=$(find "$RECORDING_PATH" -type f \( -name "*.mp3" -o -name "*.wav" \) -printf '%T+ %p\n' 2>/dev/null | sort | head -1 | cut -d' ' -f2-)
    
    if [[ -z "$oldest_file" ]]; then
        log "No more recordings to delete"
        break
    fi
    
    file_size=$(stat -c%s "$oldest_file" 2>/dev/null)
    
    rm -f "$oldest_file"
    ((deleted++))
    ((freed += file_size))
    
    # Safety limit
    if [[ $deleted -ge 1000 ]]; then
        log "Safety limit reached (1000 files)"
        break
    fi
done

# Cleanup empty directories
find "$RECORDING_PATH" -type d -empty -delete 2>/dev/null

freed_mb=$((freed / 1024 / 1024))
log "Deleted $deleted file(s), freed ${freed_mb}MB. Now $(get_free_percent)% free"
