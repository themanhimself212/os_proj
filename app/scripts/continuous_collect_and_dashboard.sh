#!/bin/bash

# Script to continuously collect metrics and generate HTML dashboard

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
INTERVAL=${MONITOR_INTERVAL:-5}

echo "Starting continuous collection and dashboard generation (Interval: ${INTERVAL}s)"
echo "Press Ctrl+C to stop."

# Trap SIGINT for graceful shutdown
trap 'echo "Stopped by user"; exit 0' INT

while true; do
    # Collect metrics
    echo "Collecting system metrics..."
    "$SCRIPT_DIR/monitor.sh" -o
    
    # Generate HTML dashboard
    if [ -f "$PROJECT_ROOT/generate_html_dashboard.py" ]; then
        echo "Generating HTML dashboard..."
        python3 "$PROJECT_ROOT/generate_html_dashboard.py"
    else
        echo "Warning: generate_html_dashboard.py not found"
    fi
    
    echo "Waiting ${INTERVAL} seconds before next collection..."
    sleep "$INTERVAL"
done

