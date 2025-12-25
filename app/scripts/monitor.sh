#!/bin/bash

# Main System Monitoring Script
# Orchestrates the collection and reporting of system metrics

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Source the metrics collection script
if ! source "$SCRIPT_DIR/collect_metrics.sh"; then
    echo "ERROR: Failed to source collect_metrics.sh" >&2
    exit 1
fi

# Verify that required functions are available
if ! type collect_all_metrics >/dev/null 2>&1; then
    echo "ERROR: collect_all_metrics function not found. The script may not have sourced correctly." >&2
    exit 1
fi

# Configuration
INTERVAL=${MONITOR_INTERVAL:-5}  # Default 5 seconds
CONTINUOUS=${CONTINUOUS_MODE:-false}
ALERT_THRESHOLD_CPU=${ALERT_CPU:-80}
ALERT_THRESHOLD_MEM=${ALERT_MEM:-85}
ALERT_THRESHOLD_DISK=${ALERT_DISK:-90}

# Alert function
check_alerts() {
    local metrics_file="$1"
    
    if [ ! -f "$metrics_file" ]; then
        log_message "WARNING" "Metrics file not found for alert checking"
        return
    fi
    
    # Check if jq is available for JSON parsing
    if ! command -v jq &> /dev/null; then
        log_message "WARNING" "jq not available, skipping alert checks"
        return
    fi
    
    # Check CPU usage
    local cpu_usage=$(jq -r '.cpu.cpu_usage_percent' "$metrics_file" 2>/dev/null)
    if [ -n "$cpu_usage" ] && command -v bc &> /dev/null; then
        if (( $(echo "$cpu_usage > $ALERT_THRESHOLD_CPU" | bc -l) )); then
            log_message "WARNING" "CPU usage is high: ${cpu_usage}% (threshold: ${ALERT_THRESHOLD_CPU}%)"
        fi
    fi
    
    # Check memory usage
    local mem_usage=$(jq -r '.memory.memory_usage_percent' "$metrics_file" 2>/dev/null)
    if [ -n "$mem_usage" ] && command -v bc &> /dev/null; then
        if (( $(echo "$mem_usage > $ALERT_THRESHOLD_MEM" | bc -l) )); then
            log_message "WARNING" "Memory usage is high: ${mem_usage}% (threshold: ${ALERT_THRESHOLD_MEM}%)"
        fi
    fi
    
    # Check disk usage
    local disk_usage=$(jq -r '.disk[0].use_percent' "$metrics_file" 2>/dev/null)
    if [ -n "$disk_usage" ] && command -v bc &> /dev/null; then
        if (( $(echo "$disk_usage > $ALERT_THRESHOLD_DISK" | bc -l) )); then
            log_message "WARNING" "Disk usage is high: ${disk_usage}% (threshold: ${ALERT_THRESHOLD_DISK}%)"
        fi
    fi
}

# Display usage information
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Options:
    -i, --interval SECONDS    Set collection interval in seconds (default: 5)
    -c, --continuous          Run in continuous mode
    -o, --once                Collect metrics once and exit (default)
    -a, --alert CPU,MEM,DISK  Set alert thresholds (default: 80,85,90)
    -h, --help                Show this help message

Examples:
    $0 -o                    # Collect once
    $0 -c -i 10             # Continuous mode, 10 second interval
    $0 -c -a 90,90,95       # Custom alert thresholds

EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--interval)
                INTERVAL="$2"
                shift 2
                ;;
            -c|--continuous)
                CONTINUOUS=true
                shift
                ;;
            -o|--once)
                CONTINUOUS=false
                shift
                ;;
            -a|--alert)
                IFS=',' read -r ALERT_THRESHOLD_CPU ALERT_THRESHOLD_MEM ALERT_THRESHOLD_DISK <<< "$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done
}

# Main monitoring loop
main() {
    parse_args "$@"
    
    log_message "INFO" "Starting system monitor (Interval: ${INTERVAL}s, Continuous: ${CONTINUOUS})"
    
    if [ "$CONTINUOUS" = true ]; then
        log_message "INFO" "Running in continuous mode. Press Ctrl+C to stop."
        
        # Trap SIGINT for graceful shutdown
        trap 'log_message "INFO" "Monitoring stopped by user"; exit 0' INT
        
        while true; do
            collect_all_metrics > /dev/null  # JSON goes to file, suppress stdout
            check_alerts "$METRICS_FILE"
            sleep "$INTERVAL"
        done
    else
        collect_all_metrics > /dev/null  # JSON goes to file, suppress stdout
        check_alerts "$METRICS_FILE"
        log_message "INFO" "Metrics collection completed"
    fi
}

# Run main function
main "$@"

