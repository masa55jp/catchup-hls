#!/bin/bash
# watch-recordings.sh - Monitor for new TS files and start HLS generation

RECORD_DIR="/record"
HLS_DIR="/hls"
PID_DIR="/tmp/hls-pids"
API_URL="http://localhost/api"

mkdir -p "$PID_DIR"

echo "Starting TS file watcher on ${RECORD_DIR}..."

# Get recording ID from EPGStation by filename
get_recording_id() {
    local filename="$1"
    # Query EPGStation for currently recording items and find matching filename
    local result=$(curl -s "${API_URL}/recording?isHalfWidth=false" 2>/dev/null | \
        jq -r --arg fn "$filename" '.records[] | select(.videoFiles[].filename == $fn) | .id' 2>/dev/null | head -1)
    echo "$result"
}

# Start HLS generation for a file
start_hls_generation() {
    local filepath="$1"
    local basename=$(basename "$filepath" .m2ts)
    local pid_file="${PID_DIR}/${basename}.pid"

    # Check if already processing
    if [ -f "$pid_file" ] && kill -0 $(cat "$pid_file") 2>/dev/null; then
        echo "Already processing: $basename"
        return
    fi

    # Get recording ID from EPGStation
    local filename=$(basename "$filepath")
    local recording_id=$(get_recording_id "$filename")

    if [ -n "$recording_id" ]; then
        echo "Found recording ID: $recording_id for $basename"
    else
        echo "Warning: Could not find recording ID for $basename"
    fi

    # Start HLS generation in background
    echo "Starting HLS generation for: $basename"
    /usr/local/bin/generate-hls.sh "$filepath" "$recording_id" &
    echo $! > "$pid_file"
}

# Cleanup function
cleanup_process() {
    local ts_file="$1"
    local basename=$(basename "$ts_file" .m2ts)
    local pid_file="${PID_DIR}/${basename}.pid"

    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping HLS generation for: $basename (PID: $pid)"
            kill "$pid" 2>/dev/null || true
            # Wait a moment then force kill if needed
            sleep 2
            kill -9 "$pid" 2>/dev/null || true
        fi
        rm -f "$pid_file"
    fi
}

# Check for existing recordings on startup
echo "Checking for existing active recordings..."
sleep 5  # Wait for nginx/api to be ready

# Query EPGStation for currently recording items
curl -s "${API_URL}/recording?isHalfWidth=false" 2>/dev/null | \
    jq -r '.records[] | "\(.id) \(.videoFiles[0].filename)"' 2>/dev/null | \
    while read id filename; do
        if [ -n "$filename" ] && [ -f "${RECORD_DIR}/${filename}" ]; then
            echo "Found existing recording: $filename (ID: $id)"
            start_hls_generation "${RECORD_DIR}/${filename}"
        fi
    done

echo "Starting file system watcher..."

# Watch for new .m2ts files
inotifywait -m -e create -e close_write --format '%w%f %e' "$RECORD_DIR" 2>/dev/null | while read filepath event; do
    # Only process .m2ts files
    if [[ "$filepath" == *.m2ts ]]; then
        basename=$(basename "$filepath" .m2ts)

        case "$event" in
            *CREATE*)
                echo "New recording detected: $basename"

                # Wait a moment for file to be properly created and EPGStation to register it
                sleep 5

                start_hls_generation "$filepath"
                ;;

            *CLOSE_WRITE*)
                echo "Recording finished: $basename"
                # Give ffmpeg time to process remaining data
                sleep 10
                cleanup_process "$filepath"

                # Finalize the m3u8 playlist
                hls_dir="${HLS_DIR}/${basename}"
                if [ -f "${hls_dir}/index.m3u8" ]; then
                    echo "Finalizing playlist for: $basename"
                    # Add EXT-X-ENDLIST if not present
                    if ! grep -q "EXT-X-ENDLIST" "${hls_dir}/index.m3u8"; then
                        echo "#EXT-X-ENDLIST" >> "${hls_dir}/index.m3u8"
                    fi
                fi
                ;;
        esac
    fi
done
