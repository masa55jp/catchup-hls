#!/bin/bash
set -e

echo "==================================="
echo " catchup-hls - Starting up"
echo "==================================="
echo "EPGSTATION_URL: ${EPGSTATION_URL}"
echo "HLS_VIDEO_BITRATE: ${HLS_VIDEO_BITRATE}"
echo "HLS_AUDIO_BITRATE: ${HLS_AUDIO_BITRATE}"
echo "HLS_RESOLUTION: ${HLS_RESOLUTION}"
echo "HLS_SEGMENT_TIME: ${HLS_SEGMENT_TIME}"
echo "HLS_CLEANUP_HOURS: ${HLS_CLEANUP_HOURS}"
echo "==================================="

# Check Intel GPU availability
echo "Checking Intel GPU (VA-API)..."
if [ -e /dev/dri/renderD128 ]; then
    echo "GPU device found: /dev/dri/renderD128"
    vainfo 2>/dev/null || echo "Warning: vainfo failed, QSV may not work"
else
    echo "Warning: /dev/dri/renderD128 not found"
    echo "Hardware encoding will not be available"
    echo "Falling back to software encoding"
fi

# Create HLS directory if needed
mkdir -p /hls

# Generate Nginx config from template
if [ -f /etc/nginx/sites-available/default.template ]; then
    cp /etc/nginx/sites-available/default.template /etc/nginx/sites-available/default
fi

# Update web config with EPGStation URL
sed -i "s|EPGSTATION_URL_PLACEHOLDER|${EPGSTATION_URL}|g" /var/www/html/index.html 2>/dev/null || true

# Verify record directory is accessible
if [ ! -d /record ]; then
    echo "Warning: /record directory not found"
    echo "Make sure to mount the TS recording directory"
fi

echo "Starting services..."
exec "$@"
