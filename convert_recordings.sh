#!/bin/bash
#
# FreePBX Post Call Recording Script
# Converts WAV to MP3 and updates CDR database
#

FREEPBX_CONF="/etc/freepbx.conf"

if [[ ! -f "$FREEPBX_CONF" ]]; then
    echo "Error: $FREEPBX_CONF not found"
    exit 1
fi

# Parse credentials - handle both " and ' quotes
parse_conf() {
    grep "$1" "$FREEPBX_CONF" | sed -E 's/.*=\s*["'"'"']([^"'"'"']*)["'"'"'].*/\1/'
}

DB_USER=$(parse_conf 'AMPDBUSER')
DB_PASS=$(parse_conf 'AMPDBPASS')
DB_HOST=$(parse_conf 'AMPDBHOST')
DB_PORT=$(parse_conf 'AMPDBPORT')

# CDR database
CDR_DB="asteriskcdrdb"
CDR_TABLE="cdr"

# Recording base path
RECORDING_PATH="/var/spool/asterisk/monitor"

# MP3 quality (0-9, lower = better)
MP3_QUALITY=2

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

mysql_query() {
    mysql -h"$DB_HOST" -P"$DB_PORT" -u"$DB_USER" -p"$DB_PASS" "$CDR_DB" -sN -e "$1" 2>/dev/null
}

convert_and_update() {
    local input_file="$1"
    
    # If relative path, prepend base path
    if [[ "$input_file" != /* ]]; then
        input_file="${RECORDING_PATH}/${input_file}"
    fi
    
    # Check if file exists
    if [[ ! -f "$input_file" ]]; then
        log "ERROR: File not found: $input_file"
        return 1
    fi
    
    # Check if already mp3
    if [[ "$input_file" == *.mp3 ]]; then
        log "SKIP: Already MP3: $input_file"
        return 0
    fi
    
    # Check if wav
    if [[ "$input_file" != *.wav ]]; then
        log "SKIP: Not a WAV file: $input_file"
        return 0
    fi
    
    local wav_file="$input_file"
    local mp3_file="${wav_file%.wav}.mp3"
    local wav_basename=$(basename "$wav_file")
    local mp3_basename=$(basename "$mp3_file")
    
    log "Converting: $wav_file"
    
    # Get file size before
    local size_before=$(stat -c%s "$wav_file" 2>/dev/null)
    
    # Convert to MP3
    if ! lame -V $MP3_QUALITY --quiet "$wav_file" "$mp3_file" 2>&1; then
        log "ERROR: lame conversion failed"
        return 1
    fi
    
    # Verify MP3 created and not empty
    if [[ ! -f "$mp3_file" ]] || [[ ! -s "$mp3_file" ]]; then
        log "ERROR: MP3 file not created or empty"
        return 1
    fi
    
    local size_after=$(stat -c%s "$mp3_file" 2>/dev/null)
    
    # Remove original WAV
    rm -f "$wav_file"
    log "OK: $wav_basename -> $mp3_basename (${size_before} -> ${size_after} bytes)"
    
    # Update CDR database
    local updated=$(mysql_query "UPDATE $CDR_TABLE SET recordingfile = REPLACE(recordingfile, '.wav', '.mp3') WHERE recordingfile LIKE '%${wav_basename}%'; SELECT ROW_COUNT();")
    
    if [[ "$updated" -gt 0 ]]; then
        log "CDR: Updated $updated record(s)"
    else
        log "CDR: No matching records (OK for new recordings)"
    fi
    
    return 0
}

# Check lame installed
if ! command -v lame &>/dev/null; then
    log "ERROR: lame not installed. Run: apt install lame"
    exit 1
fi

# Debug: show parsed credentials
# echo "DB: $DB_USER@$DB_HOST:$DB_PORT"

# Check mysql access
if ! mysql_query "SELECT 1;" >/dev/null; then
    log "ERROR: Cannot connect to MySQL (user=$DB_USER, host=$DB_HOST)"
    exit 1
fi

if [[ -n "$1" ]]; then
    # Single file mode
    convert_and_update "$1"
else
    # Batch mode
    log "=== Batch mode: scanning $RECORDING_PATH ==="
    
    count=0
    while IFS= read -r wav_file; do
        convert_and_update "$wav_file"
        ((count++))
    done < <(find "$RECORDING_PATH" -name "*.wav" -type f 2>/dev/null)
    
    if [[ $count -eq 0 ]]; then
        log "No WAV files found"
    else
        log "=== Processed $count file(s) ==="
    fi
fi
