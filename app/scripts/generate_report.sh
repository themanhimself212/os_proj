#!/bin/bash

# Script to generate report from collected metrics

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Generate HTML dashboard
if [ -f "$PROJECT_ROOT/generate_html_dashboard.py" ]; then
    echo "Generating HTML dashboard from existing metrics..."
    python3 "$PROJECT_ROOT/generate_html_dashboard.py"
else
    echo "Error: generate_html_dashboard.py not found"
    exit 1
fi

