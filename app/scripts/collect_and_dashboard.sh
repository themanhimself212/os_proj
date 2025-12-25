#!/bin/bash

# Script to collect metrics and generate HTML dashboard

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

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

