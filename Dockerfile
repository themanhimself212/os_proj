# Unified System Monitor Dockerfile
# Combines metrics collection and dashboard generation

FROM alpine:latest

# Install all necessary dependencies
RUN apk add --no-cache \
    bash \
    jq \
    bc \
    coreutils \
    procps \
    util-linux \
    grep \
    sed \
    awk \
    python3 \
    py3-pip \
    && ln -sf python3 /usr/bin/python

# Set working directory
WORKDIR /app

# Copy all scripts
COPY app/scripts/collect_metrics.sh /app/scripts/
COPY app/scripts/monitor.sh /app/scripts/
COPY app/scripts/collect_and_dashboard.sh /app/scripts/
COPY app/scripts/continuous_collect_and_dashboard.sh /app/scripts/
COPY app/scripts/generate_report.sh /app/scripts/

# Copy dashboard generator
COPY app/generate_html_dashboard.py /app/

# Create necessary directories
RUN mkdir -p /app/logs /app/reports

# Make scripts executable
RUN chmod +x /app/scripts/*.sh && \
    chmod +x /app/generate_html_dashboard.py

# Set environment variables
ENV MONITOR_INTERVAL=5
ENV CONTINUOUS_MODE=false
ENV ALERT_CPU=80
ENV ALERT_MEM=85
ENV ALERT_DISK=90
ENV PYTHONUNBUFFERED=1

# Default command - collect metrics and generate dashboard
CMD ["/app/scripts/collect_and_dashboard.sh"]

