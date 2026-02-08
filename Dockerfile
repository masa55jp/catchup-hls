# catchup-hls - Live Recording HLS Generator with Intel QSV
# For UGREEN NAS (Intel N100) and other Intel-based systems
# Build: 2026-02-08

FROM debian:bookworm-slim

LABEL maintainer="asakusatv"
LABEL description="Auto-generate HLS from growing TS files with Intel QSV hardware encoding"
LABEL org.opencontainers.image.source="https://github.com/masa55jp/catchup-hls"

# Install dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    # FFmpeg and VA-API for Intel QSV
    ffmpeg \
    intel-media-va-driver \
    libva-drm2 \
    libva2 \
    vainfo \
    # File monitoring
    inotify-tools \
    # Web server
    nginx \
    # Process management
    supervisor \
    # Utilities
    curl \
    jq \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Create directories
RUN mkdir -p /record /hls /var/log/supervisor /run/nginx

# Copy scripts
COPY scripts/entrypoint.sh /usr/local/bin/
COPY scripts/watch-recordings.sh /usr/local/bin/
COPY scripts/generate-hls.sh /usr/local/bin/
COPY scripts/cleanup-hls.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/*.sh

# Copy nginx config
COPY nginx/default.conf.template /etc/nginx/sites-available/default

# Copy web UI
COPY web/ /var/www/html/

# Copy supervisor config
COPY supervisor/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Environment variables
ENV EPGSTATION_URL=http://localhost:8888
ENV HLS_VIDEO_BITRATE=600k
ENV HLS_AUDIO_BITRATE=128k
ENV HLS_RESOLUTION=854x480
ENV HLS_SEGMENT_TIME=4
ENV HLS_CLEANUP_HOURS=24
ENV TZ=Asia/Tokyo

EXPOSE 80

VOLUME ["/record", "/hls"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
