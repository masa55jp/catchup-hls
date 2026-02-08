#!/bin/bash
# generate-hls.sh - Generate HLS from a growing TS file using Intel QSV

TS_FILE="$1"
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
echo "Resolution: ${WIDTH}x${HEIGHT}"
echo "Video: ${VIDEO_BITRATE}, Audio: ${AUDIO_BITRATE}"
echo "==================================="

# Create output directory
mkdir -p "$HLS_DIR"

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

# Common FFmpeg options for reading growing file
INPUT_OPTS="-re -fflags +genpts+discardcorrupt -analyzeduration 10M -probesize 10M"

# HLS output options
HLS_OPTS="-f hls -hls_time ${SEGMENT_TIME} -hls_list_size 0 -hls_flags append_list+delete_segments+omit_endlist"
HLS_OPTS="${HLS_OPTS} -hls_segment_filename ${HLS_DIR}/segment%05d.ts"

if [ "$USE_QSV" = true ]; then
    # Intel VA-API hardware encoding
    ffmpeg $INPUT_OPTS \
        -hwaccel vaapi -hwaccel_device /dev/dri/renderD128 -hwaccel_output_format vaapi \
        -i "$TS_FILE" \
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
    ffmpeg $INPUT_OPTS \
        -i "$TS_FILE" \
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
