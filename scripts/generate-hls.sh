#!/bin/bash
# generate-hls.sh - Generate HLS from a growing TS file using Intel QSV

TS_FILE="$1"
RECORDING_ID="$2"  # Optional: EPGStation recording ID for symlink
BASENAME=$(basename "$TS_FILE" .m2ts)
HLS_DIR="/hls/${BASENAME}"

# Get settings from environment
VIDEO_BITRATE="${HLS_VIDEO_BITRATE:-600k}"
AUDIO_BITRATE="${HLS_AUDIO_BITRATE:-128k}"
RESOLUTION="${HLS_RESOLUTION:-854x480}"
SEGMENT_TIME="${HLS_SEGMENT_TIME:-4}"

# Parse resolution
WIDTH=$(echo "$RESOLUTION" | cut -d'x' -f1)
HEIGHT=$(echo "$RESOLUTION" | cut -d'x' -f2)

echo "==================================="
echo "HLS Generation Started"
echo "Input: $TS_FILE"
echo "Output: $HLS_DIR"
echo "Recording ID: ${RECORDING_ID:-none}"
echo "Resolution: ${WIDTH}x${HEIGHT}"
echo "Video: ${VIDEO_BITRATE}, Audio: ${AUDIO_BITRATE}"
echo "==================================="

# Create output directory with proper permissions
mkdir -p "$HLS_DIR"
chmod 755 "$HLS_DIR"

# Create symlink if recording ID is provided
if [ -n "$RECORDING_ID" ]; then
    ln -sf "$HLS_DIR" "/hls/${RECORDING_ID}"
    echo "Created symlink: /hls/${RECORDING_ID} -> $HLS_DIR"
fi

# Check if QSV is available
USE_QSV=false
if [ -e /dev/dri/renderD128 ]; then
    # Test QSV availability
    if ffmpeg -hide_banner -init_hw_device vaapi=va:/dev/dri/renderD128 -f lavfi -i testsrc=duration=1:size=64x64 -vf 'format=nv12,hwupload' -c:v h264_vaapi -f null - 2>/dev/null; then
        USE_QSV=true
        echo "Using Intel VA-API hardware encoding"
    else
        echo "VA-API test failed, using software encoding"
    fi
else
    echo "No GPU device, using software encoding"
fi

# Wait for file to have some content
sleep 3

# HLS output options
# append_list: keep adding to playlist without rewriting
# omit_endlist: don't add #EXT-X-ENDLIST (keeps playlist "live")
# hls_list_size 0: keep all segments in playlist for seeking from beginning
HLS_OPTS="-f hls -hls_time ${SEGMENT_TIME} -hls_list_size 0 -hls_flags append_list+omit_endlist"
HLS_OPTS="${HLS_OPTS} -hls_segment_filename ${HLS_DIR}/segment%05d.ts"

# Use tail -f to follow growing file and pipe to ffmpeg
# This allows continuous processing as the TS file grows
echo "Starting continuous HLS generation (following growing file)..."

if [ "$USE_QSV" = true ]; then
    # Intel VA-API hardware encoding
    # No -re flag: process as fast as possible to catch up, then wait for more data from tail -f
    tail -c +0 -f "$TS_FILE" 2>/dev/null | \
    ffmpeg \
        -fflags +genpts+discardcorrupt -analyzeduration 10M -probesize 10M \
        -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 -hwaccel_output_format vaapi \
        -i pipe:0 \
        -vf "format=nv12|vaapi,hwupload,scale_vaapi=w=${WIDTH}:h=${HEIGHT}" \
        -c:v h264_vaapi -b:v "$VIDEO_BITRATE" -maxrate "$VIDEO_BITRATE" -bufsize "${VIDEO_BITRATE%k}0k" \
        -g $((SEGMENT_TIME * 30)) -keyint_min $((SEGMENT_TIME * 30)) \
        -c:a aac -b:a "$AUDIO_BITRATE" -ar 48000 -ac 2 \
        -map 0:v:0 -map 0:a:0 \
        $HLS_OPTS \
        "${HLS_DIR}/index.m3u8" \
        2>&1 | while read line; do echo "[ffmpeg] $line"; done
else
    # Software encoding (fallback)
    # No -re flag: process as fast as possible to catch up, then wait for more data from tail -f
    tail -c +0 -f "$TS_FILE" 2>/dev/null | \
    ffmpeg \
        -fflags +genpts+discardcorrupt -analyzeduration 10M -probesize 10M \
        -i pipe:0 \
        -vf "yadif,scale=${WIDTH}:${HEIGHT}" \
        -c:v libx264 -preset veryfast -b:v "$VIDEO_BITRATE" -maxrate "$VIDEO_BITRATE" -bufsize "${VIDEO_BITRATE%k}0k" \
        -g $((SEGMENT_TIME * 30)) -keyint_min $((SEGMENT_TIME * 30)) \
        -c:a aac -b:a "$AUDIO_BITRATE" -ar 48000 -ac 2 \
        -map 0:v:0 -map 0:a:0 \
        $HLS_OPTS \
        "${HLS_DIR}/index.m3u8" \
        2>&1 | while read line; do echo "[ffmpeg] $line"; done
fi

echo "HLS generation ended for: $BASENAME"
