#!/bin/bash
# cleanup-hls.sh - Remove HLS directories older than specified hours

HLS_DIR="/hls"
CLEANUP_HOURS="${HLS_CLEANUP_HOURS:-24}"
CHECK_INTERVAL=3600  # Check every hour

echo "HLS cleanup service started"
echo "Cleanup threshold: ${CLEANUP_HOURS} hours"
echo "Check interval: ${CHECK_INTERVAL} seconds"

while true; do
    echo "Running cleanup check..."

    # Find and remove directories older than CLEANUP_HOURS
    find "$HLS_DIR" -mindepth 1 -maxdepth 1 -type d -mmin +$((CLEANUP_HOURS * 60)) | while read dir; do
        dirname=$(basename "$dir")
        echo "Removing old HLS directory: $dirname"
        rm -rf "$dir"
    done

    # Also cleanup empty directories
    find "$HLS_DIR" -mindepth 1 -maxdepth 1 -type d -empty | while read dir; do
        dirname=$(basename "$dir")
        echo "Removing empty HLS directory: $dirname"
        rm -rf "$dir"
    done

    # Report current status
    count=$(find "$HLS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
    echo "Current HLS directories: $count"

    sleep $CHECK_INTERVAL
done
