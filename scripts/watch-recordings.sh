#!/bin/bash
# watch-recordings.sh - Monitor for new TS files and start HLS generation

RECORD_DIR="/record"
HLS_DIR="/hls"
PID_DIR="/tmp/hls-pids"

mkdir -p "$PID_DIR"

echo "Starting TS file watcher on ${RECORD_DIR}..."

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

# Watch for new .m2ts files
inotifywait -m -e create -e close_write --format '%w%f %e' "$RECORD_DIR" 2>/dev/null | while read filepath event; do
    # Only process .m2ts files
    if [[ "$filepath" == *.m2ts ]]; then
        basename=$(basename "$filepath" .m2ts)

        case "$event" in
            *CREATE*)
                echo "New recording detected: $basename"

                # Wait a moment for file to be properly created
                sleep 2

                # Check if already processing
                pid_file="${PID_DIR}/${basename}.pid"
                if [ -f "$pid_file" ] && kill -0 $(cat "$pid_file") 2>/dev/null; then
                    echo "Already processing: $basename"
                    continue
                fi

                # Start HLS generation in background
                echo "Starting HLS generation for: $basename"
                /usr/local/bin/generate-hls.sh "$filepath" &
                echo $! > "$pid_file"
                ;;

            *CLOSE_WRITE*)
                echo "Recording finished: $basename"
                # Give ffmpeg time to process remaining data
                sleep 5
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
