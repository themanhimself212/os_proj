#!/bin/bash

# System Metrics Collection Script
# Collects CPU, GPU, Disk, Memory, Network, and System Load metrics

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging function
log_message() {
    local level=$1
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "${LOG_DIR}/monitor.log"
    
    # Always output to stderr to avoid contaminating JSON output
    if [ "$level" = "ERROR" ]; then
        echo -e "${RED}[ERROR]${NC} $message" >&2
    elif [ "$level" = "WARNING" ]; then
        echo -e "${YELLOW}[WARNING]${NC} $message" >&2
    else
        echo -e "${GREEN}[INFO]${NC} $message" >&2
    fi
}

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_message "ERROR" "Command failed at line $line_number with exit code $exit_code"
    return $exit_code
}

# Set error trap (but allow commands to fail gracefully)
set +e  # Don't exit on error, we'll handle errors manually
# Only set ERR trap when executing directly, not when sourcing
# This prevents the trap from interfering with function definitions when sourcing
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    trap 'handle_error $LINENO' ERR
fi

# Initialize variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="${PROJECT_ROOT}/logs"
REPORT_DIR="${PROJECT_ROOT}/reports"
METRICS_FILE="${REPORT_DIR}/metrics.json"
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

# Create necessary directories
mkdir -p "$LOG_DIR" "$REPORT_DIR"

# Check if running as root (needed for some metrics)
check_root() {
    if [ "$EUID" -eq 0 ]; then
        IS_ROOT=true
    else
        IS_ROOT=false
    fi
}

# Detect operating system
detect_os() {
    local os_type=$(uname -s 2>/dev/null || echo "Unknown")
    
    IS_MACOS=false
    IS_WINDOWS=false
    IS_LINUX=false
    
    case "$os_type" in
        Darwin*)
            IS_MACOS=true
            ;;
        Linux*)
            IS_LINUX=true
            ;;
        MINGW*|MSYS*|CYGWIN*)
            IS_WINDOWS=true
            ;;
        *)
            # Try to detect Windows via PowerShell
            if command -v powershell.exe &> /dev/null || command -v pwsh &> /dev/null; then
                # Check if we're on Windows by checking for Windows-specific environment
                if [ -n "$OS" ] && echo "$OS" | grep -qi "windows"; then
                    IS_WINDOWS=true
                elif [ -n "$WINDIR" ] || [ -n "$SYSTEMROOT" ]; then
                    IS_WINDOWS=true
                fi
            fi
            ;;
    esac
    
    # If still not detected, try PowerShell check
    if [ "$IS_WINDOWS" = false ] && [ "$IS_MACOS" = false ] && [ "$IS_LINUX" = false ]; then
        if command -v powershell.exe &> /dev/null || command -v pwsh &> /dev/null; then
            # Try to run a Windows-specific command
            if powershell.exe -Command "Get-WmiObject -Class Win32_OperatingSystem -ErrorAction SilentlyContinue" &> /dev/null 2>&1 || \
               pwsh -Command "Get-WmiObject -Class Win32_OperatingSystem -ErrorAction SilentlyContinue" &> /dev/null 2>&1; then
                IS_WINDOWS=true
            fi
        fi
    fi
}

# Initialize OS detection
detect_os

# Collect CPU metrics
collect_cpu_metrics() {
    log_message "INFO" "Collecting CPU metrics..."
    
    local cpu_usage=0
    local cpu_cores=0
    local cpu_model="Unknown"
    local load_avg="N/A"
    local cpu_temp="N/A"
    
    if [ "$IS_WINDOWS" = true ]; then
        # Windows CPU metrics using PowerShell
        local ps_cmd="powershell.exe"
        if command -v pwsh &> /dev/null; then
            ps_cmd="pwsh"
        fi
        
        # Windows CPU usage
        cpu_usage=$($ps_cmd -Command "Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty CounterSamples | Select-Object -ExpandProperty CookedValue" 2>/dev/null | head -1)
        if [ -z "$cpu_usage" ] || ! [[ "$cpu_usage" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            # Alternative method using WMI
            cpu_usage=$($ps_cmd -Command "(Get-WmiObject Win32_Processor | Measure-Object -property LoadPercentage -Average).Average" 2>/dev/null | head -1)
        fi
        if [ -z "$cpu_usage" ] || ! [[ "$cpu_usage" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            cpu_usage=0
        fi
        
        # Windows CPU cores
        cpu_cores=$($ps_cmd -Command "(Get-WmiObject Win32_ComputerSystem).NumberOfLogicalProcessors" 2>/dev/null | head -1)
        if [ -z "$cpu_cores" ]; then
            cpu_cores=$($ps_cmd -Command "(Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors" 2>/dev/null | head -1)
        fi
        if [ -z "$cpu_cores" ] || ! [[ "$cpu_cores" =~ ^[0-9]+$ ]]; then
            cpu_cores=0
        fi
        
        # Windows CPU model
        cpu_model=$($ps_cmd -Command "(Get-WmiObject Win32_Processor).Name" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$cpu_model" ] || [ "$cpu_model" = "" ]; then
            cpu_model=$($ps_cmd -Command "(Get-CimInstance Win32_Processor).Name" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        fi
        if [ -z "$cpu_model" ] || [ "$cpu_model" = "" ]; then
            cpu_model="Unknown"
        fi
        
        # Windows load average (use CPU usage as approximation)
        load_avg="$cpu_usage 0.00 0.00"
        
        # Windows CPU temperature (requires external tools like OpenHardwareMonitor)
        cpu_temp="N/A"
    elif [ "$IS_MACOS" = true ]; then
        # macOS CPU usage
        cpu_usage=$(top -l 1 -n 0 2>/dev/null | grep "CPU usage" | awk '{print $3}' | sed 's/%//' 2>/dev/null)
        if [ -z "$cpu_usage" ]; then
            cpu_usage=0
        fi
        
        # macOS CPU cores
        cpu_cores=$(sysctl -n hw.ncpu 2>/dev/null)
        if [ -z "$cpu_cores" ]; then
            cpu_cores=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo "0")
        fi
        
        # macOS CPU model
        cpu_model=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
        if [ -z "$cpu_model" ]; then
            cpu_model="Unknown"
        fi
        
        # macOS load average
        load_avg=$(uptime 2>/dev/null | awk -F'load averages:' '{print $2}' | sed 's/^ *//' 2>/dev/null)
        if [ -z "$load_avg" ]; then
            load_avg="N/A"
        fi
        
        # macOS CPU temperature (requires external tools)
        if command -v osx-cpu-temp &> /dev/null; then
            cpu_temp=$(osx-cpu-temp 2>/dev/null || echo "N/A")
        elif command -v istats &> /dev/null; then
            cpu_temp=$(istats cpu temp 2>/dev/null | grep -o '[0-9.]*' | head -1)"°C" || echo "N/A"
        fi
    else
        # Linux CPU usage
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}' 2>/dev/null || echo "0")
        
        # Linux CPU cores
        if command -v nproc &> /dev/null; then
            cpu_cores=$(nproc)
        else
            cpu_cores=$(grep -c processor /proc/cpuinfo 2>/dev/null || echo "0")
        fi
        
        # Linux CPU model
        cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | sed 's/^ *//' || echo "Unknown")
        
        # Linux load average
        load_avg=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^ *//' 2>/dev/null || echo "N/A")
        
        # Linux CPU temperature
        if command -v sensors &> /dev/null; then
            cpu_temp=$(sensors | grep -i "cpu" | grep -i "temp" | head -1 | awk '{print $2}' | sed 's/+//' || echo "N/A")
        elif [ -f /sys/class/thermal/thermal_zone0/temp ]; then
            local temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
            if [ -n "$temp_raw" ] && command -v bc &> /dev/null; then
                cpu_temp=$(echo "scale=1; $temp_raw/1000" | bc)"°C"
            fi
        fi
    fi
    
    # Ensure cpu_usage is a number
    if ! [[ "$cpu_usage" =~ ^[0-9]+\.?[0-9]*$ ]]; then
        cpu_usage=0
    fi
    
    echo "{
        \"cpu_usage_percent\": $cpu_usage,
        \"cpu_cores\": $cpu_cores,
        \"cpu_model\": \"$cpu_model\",
        \"cpu_temperature\": \"$cpu_temp\",
        \"load_average\": \"$load_avg\"
    }"
}

# Collect GPU metrics
collect_gpu_metrics() {
    log_message "INFO" "Collecting GPU metrics..."
    
    local gpu_usage="N/A"
    local gpu_temp="N/A"
    local gpu_memory="N/A"
    
    if [ "$IS_WINDOWS" = true ]; then
        # Windows GPU metrics using PowerShell
        local ps_cmd="powershell.exe"
        if command -v pwsh &> /dev/null; then
            ps_cmd="pwsh"
        fi
        
        # Windows GPU information using WMI
        local gpu_name=$($ps_cmd -Command "Get-WmiObject Win32_VideoController | Select-Object -First 1 -ExpandProperty Name" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$gpu_name" ] || [ "$gpu_name" = "" ]; then
            gpu_name=$($ps_cmd -Command "Get-CimInstance Win32_VideoController | Select-Object -First 1 -ExpandProperty Name" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        fi
        
        # Windows GPU memory
        local gpu_vram=$($ps_cmd -Command "Get-WmiObject Win32_VideoController | Select-Object -First 1 -ExpandProperty AdapterRAM" 2>/dev/null | head -1)
        if [ -n "$gpu_vram" ] && [[ "$gpu_vram" =~ ^[0-9]+$ ]]; then
            # Convert bytes to GB
            if command -v bc &> /dev/null; then
                local gpu_vram_gb=$(echo "scale=2; $gpu_vram / 1073741824" | bc)
                gpu_memory="${gpu_vram_gb} GB"
            else
                gpu_memory="${gpu_vram} bytes"
            fi
        fi
        
        # Windows GPU usage (requires Performance Counters or external tools)
        if [ -n "$gpu_name" ] && [ "$gpu_name" != "" ]; then
            gpu_usage="Available (${gpu_name})"
        else
            gpu_usage="N/A"
        fi
        
        # Windows GPU temperature (requires external tools like GPU-Z, MSI Afterburner, etc.)
        gpu_temp="N/A"
    elif [ "$IS_MACOS" = true ]; then
        # macOS GPU information using system_profiler
        if command -v system_profiler &> /dev/null; then
            local gpu_info=$(system_profiler SPDisplaysDataType 2>/dev/null)
            local gpu_name=$(echo "$gpu_info" | grep "Chipset Model:" | head -1 | cut -d: -f2 | sed 's/^ *//' || echo "N/A")
            
            # Try to get GPU memory
            local gpu_vram=$(echo "$gpu_info" | grep "VRAM" | head -1 | awk '{print $2, $3}' || echo "N/A")
            if [ "$gpu_vram" != "N/A" ]; then
                gpu_memory="$gpu_vram"
            fi
            
            # macOS GPU temperature (requires external tools)
            if command -v istats &> /dev/null; then
                gpu_temp=$(istats gpu temp 2>/dev/null | grep -o '[0-9.]*' | head -1)"°C" || echo "N/A"
            fi
            
            # GPU usage is difficult to get on macOS without external tools
            if [ "$gpu_name" != "N/A" ]; then
                gpu_usage="Available (${gpu_name})"
            fi
        fi
    else
        # Linux GPU detection
        # Check for NVIDIA GPU
        if command -v nvidia-smi &> /dev/null; then
            gpu_usage=$(nvidia-smi --query-gpu=utilization.gpu --format=csv,noheader,nounits | head -1)
            gpu_temp=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader,nounits | head -1)"°C"
            gpu_memory=$(nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader | head -1 | awk '{print $1"/"$3}')
        # Check for AMD GPU
        elif command -v rocm-smi &> /dev/null; then
            gpu_usage=$(rocm-smi --showuse | grep -i "gpu use" | awk '{print $NF}' || echo "N/A")
            gpu_temp=$(rocm-smi --showtemp | grep -i "temp" | head -1 | awk '{print $NF}' || echo "N/A")
        # Check for integrated Intel GPU
        elif [ -d /sys/class/drm ]; then
            if ls /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input &> /dev/null; then
                local temp_file=$(ls /sys/class/drm/card*/device/hwmon/hwmon*/temp1_input | head -1)
                local temp_raw=$(cat "$temp_file" 2>/dev/null)
                if [ -n "$temp_raw" ] && command -v bc &> /dev/null; then
                    gpu_temp=$(echo "scale=1; $temp_raw/1000" | bc)"°C"
                fi
            fi
        fi
    fi
    
    echo "{
        \"gpu_usage_percent\": \"$gpu_usage\",
        \"gpu_temperature\": \"$gpu_temp\",
        \"gpu_memory\": \"$gpu_memory\"
    }"
}

# Collect disk metrics
collect_disk_metrics() {
    log_message "INFO" "Collecting disk metrics..."
    
    local disk_json="["
    local first=true
    
    if [ "$IS_WINDOWS" = true ]; then
        # Windows disk metrics using PowerShell
        local ps_cmd="powershell.exe"
        if command -v pwsh &> /dev/null; then
            ps_cmd="pwsh"
        fi
        
        # Get Windows disk information
        local disk_info=$($ps_cmd -Command "Get-PSDrive -PSProvider FileSystem | Where-Object { \$_.Used -ne \$null } | ForEach-Object { [PSCustomObject]@{ Name=\$_.Name; Used=[math]::Round(\$_.Used/1GB, 2); Free=[math]::Round(\$_.Free/1GB, 2); UsedPercent=[math]::Round((\$_.Used/(\$_.Used+\$_.Free))*100, 2) } } | ConvertTo-Json" 2>/dev/null)
        
        if [ -n "$disk_info" ] && command -v jq &> /dev/null; then
            # Parse JSON output from PowerShell
            local disk_count=$(echo "$disk_info" | jq 'length' 2>/dev/null || echo "0")
            if [ "$disk_count" -gt 0 ]; then
                for i in $(seq 0 $((disk_count - 1))); do
                    if [ "$first" = false ]; then
                        disk_json+=","
                    fi
                    first=false
                    
                    local drive_name=$(echo "$disk_info" | jq -r ".[$i].Name" 2>/dev/null)
                    local used_gb=$(echo "$disk_info" | jq -r ".[$i].Used" 2>/dev/null)
                    local free_gb=$(echo "$disk_info" | jq -r ".[$i].Free" 2>/dev/null)
                    local use_percent=$(echo "$disk_info" | jq -r ".[$i].UsedPercent" 2>/dev/null)
                    
                    # Calculate total size
                    local total_gb=$(echo "$used_gb + $free_gb" | bc 2>/dev/null || echo "0")
                    
                    # Format sizes
                    local size="${total_gb}G"
                    local used="${used_gb}G"
                    local available="${free_gb}G"
                    
                    # Get mount point (drive letter)
                    local mount_point="${drive_name}:\\"
                    
                    disk_json+="{
                        \"filesystem\": \"${drive_name}:\",
                        \"size\": \"$size\",
                        \"used\": \"$used\",
                        \"available\": \"$available\",
                        \"use_percent\": $use_percent,
                        \"mount_point\": \"$mount_point\",
                        \"smart_status\": \"N/A\"
                    }"
                done
            fi
        fi
        
        # Fallback if jq is not available or PowerShell command failed
        if [ "$first" = true ]; then
            # Use df command if available (Git Bash, WSL, Cygwin)
            while IFS= read -r line; do
                if [ "$first" = false ]; then
                    disk_json+=","
                fi
                first=false
                
                local filesystem=$(echo "$line" | awk '{print $1}')
                local size=$(echo "$line" | awk '{print $2}')
                local used=$(echo "$line" | awk '{print $3}')
                local available=$(echo "$line" | awk '{print $4}')
                local use_percent_raw=$(echo "$line" | awk '{print $5}' | sed 's/%//')
                local mount_point=$(echo "$line" | awk '{for(i=6;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')
                
                local use_percent=$(echo "$use_percent_raw" | sed 's/[^0-9.]//g')
                if [ -z "$use_percent" ] || ! [[ "$use_percent" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                    use_percent=0
                fi
                
                disk_json+="{
                    \"filesystem\": \"$filesystem\",
                    \"size\": \"$size\",
                    \"used\": \"$used\",
                    \"available\": \"$available\",
                    \"use_percent\": $use_percent,
                    \"mount_point\": \"$mount_point\",
                    \"smart_status\": \"N/A\"
                }"
            done < <(df -h 2>/dev/null | tail -n +2 || echo "")
        fi
    else
        # Get disk usage for all mounted filesystems (Linux/macOS)
        while IFS= read -r line; do
            if [ "$first" = false ]; then
                disk_json+=","
            fi
            first=false
            
            # Parse df output - handle different formats (Linux vs macOS)
            local filesystem=$(echo "$line" | awk '{print $1}')
            local size=$(echo "$line" | awk '{print $2}')
            local used=$(echo "$line" | awk '{print $3}')
            local available=$(echo "$line" | awk '{print $4}')
            
            # Find use_percent - it might be in column 5 or we need to calculate it
            local use_percent_raw=$(echo "$line" | awk '{print $5}' | sed 's/%//')
            local mount_point=$(echo "$line" | awk '{for(i=6;i<=NF;i++) printf "%s ", $i; print ""}' | sed 's/ $//')
            
            # Clean use_percent - remove any non-numeric characters and ensure it's a number
            local use_percent=$(echo "$use_percent_raw" | sed 's/[^0-9.]//g')
            
            # If use_percent contains non-numeric characters or is empty, try to calculate it
            if [ -z "$use_percent" ] || ! [[ "$use_percent" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                # Try to extract from the line - look for percentage pattern
                use_percent=$(echo "$line" | grep -oE '[0-9]+%' | head -1 | sed 's/%//')
                if [ -z "$use_percent" ] || ! [[ "$use_percent" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                    use_percent=0
                fi
            fi
            
            # Try to get SMART status if available
            local smart_status="N/A"
            if command -v smartctl &> /dev/null && [ "$IS_ROOT" = true ]; then
                local device=$(echo "$filesystem" | sed 's/[0-9]*$//')
                if [ -b "$device" ]; then
                    smart_status=$(smartctl -H "$device" 2>/dev/null | grep -i "SMART overall-health" | awk '{print $6}' || echo "N/A")
                fi
            fi
            
            disk_json+="{
                \"filesystem\": \"$filesystem\",
                \"size\": \"$size\",
                \"used\": \"$used\",
                \"available\": \"$available\",
                \"use_percent\": $use_percent,
                \"mount_point\": \"$mount_point\",
                \"smart_status\": \"$smart_status\"
            }"
        done < <(df -h | tail -n +2)
    fi
    
    disk_json+="]"
    echo "$disk_json"
}

# Collect memory metrics
collect_memory_metrics() {
    log_message "INFO" "Collecting memory metrics..."
    
    local mem_total=0
    local mem_used=0
    local mem_free=0
    local mem_available=0
    local mem_percent=0
    local swap_total=0
    local swap_used=0
    local swap_free=0
    local swap_percent=0
    
    if [ "$IS_WINDOWS" = true ]; then
        # Windows memory using PowerShell
        local ps_cmd="powershell.exe"
        if command -v pwsh &> /dev/null; then
            ps_cmd="pwsh"
        fi
        
        # Windows total memory
        local mem_total_bytes=$($ps_cmd -Command "(Get-WmiObject Win32_ComputerSystem).TotalPhysicalMemory" 2>/dev/null | head -1)
        if [ -z "$mem_total_bytes" ] || ! [[ "$mem_total_bytes" =~ ^[0-9]+$ ]]; then
            mem_total_bytes=$($ps_cmd -Command "(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory" 2>/dev/null | head -1)
        fi
        if [ -n "$mem_total_bytes" ] && [[ "$mem_total_bytes" =~ ^[0-9]+$ ]]; then
            mem_total=$((mem_total_bytes / 1024 / 1024))
        fi
        
        # Windows used memory
        local mem_available_bytes=$($ps_cmd -Command "(Get-WmiObject Win32_OperatingSystem).FreePhysicalMemory" 2>/dev/null | head -1)
        if [ -z "$mem_available_bytes" ] || ! [[ "$mem_available_bytes" =~ ^[0-9]+$ ]]; then
            mem_available_bytes=$($ps_cmd -Command "(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory" 2>/dev/null | head -1)
        fi
        if [ -n "$mem_available_bytes" ] && [[ "$mem_available_bytes" =~ ^[0-9]+$ ]]; then
            # FreePhysicalMemory is in KB, convert to MB
            mem_available=$((mem_available_bytes / 1024))
            mem_used=$((mem_total - mem_available))
            mem_free=$mem_available
        fi
        
        # Windows swap (page file)
        local swap_total_bytes=$($ps_cmd -Command "(Get-WmiObject Win32_PageFileUsage | Measure-Object -Property AllocatedBaseSize -Sum).Sum" 2>/dev/null | head -1)
        if [ -z "$swap_total_bytes" ] || ! [[ "$swap_total_bytes" =~ ^[0-9]+$ ]]; then
            swap_total_bytes=$($ps_cmd -Command "(Get-CimInstance Win32_PageFileUsage | Measure-Object -Property AllocatedBaseSize -Sum).Sum" 2>/dev/null | head -1)
        fi
        if [ -n "$swap_total_bytes" ] && [[ "$swap_total_bytes" =~ ^[0-9]+$ ]]; then
            # AllocatedBaseSize is in MB
            swap_total=$swap_total_bytes
        fi
        
        local swap_used_bytes=$($ps_cmd -Command "(Get-WmiObject Win32_PageFileUsage | Measure-Object -Property CurrentUsage -Sum).Sum" 2>/dev/null | head -1)
        if [ -z "$swap_used_bytes" ] || ! [[ "$swap_used_bytes" =~ ^[0-9]+$ ]]; then
            swap_used_bytes=$($ps_cmd -Command "(Get-CimInstance Win32_PageFileUsage | Measure-Object -Property CurrentUsage -Sum).Sum" 2>/dev/null | head -1)
        fi
        if [ -n "$swap_used_bytes" ] && [[ "$swap_used_bytes" =~ ^[0-9]+$ ]]; then
            # CurrentUsage is in MB
            swap_used=$swap_used_bytes
            swap_free=$((swap_total - swap_used))
        fi
    elif [ "$IS_MACOS" = true ]; then
        # macOS memory using vm_stat and sysctl
        local page_size=$(sysctl -n hw.pagesize 2>/dev/null || echo "4096")
        local mem_total_bytes=$(sysctl -n hw.memsize 2>/dev/null)
        if [ -z "$mem_total_bytes" ] || ! [[ "$mem_total_bytes" =~ ^[0-9]+$ ]]; then
            mem_total_bytes=0
        fi
        
        # Get memory stats from vm_stat
        local vm_stat_output=$(vm_stat 2>/dev/null)
        if [ -n "$vm_stat_output" ]; then
            local pages_free=$(echo "$vm_stat_output" | grep "Pages free" | awk '{print $3}' | sed 's/\.//')
            local pages_active=$(echo "$vm_stat_output" | grep "Pages active" | awk '{print $3}' | sed 's/\.//')
            local pages_inactive=$(echo "$vm_stat_output" | grep "Pages inactive" | awk '{print $3}' | sed 's/\.//')
            local pages_wired=$(echo "$vm_stat_output" | grep "Pages wired down" | awk '{print $4}' | sed 's/\.//')
            
            # Calculate used memory (active + inactive + wired)
            local pages_used=$((pages_active + pages_inactive + pages_wired))
            mem_used=$((pages_used * page_size / 1024 / 1024))
            mem_free=$((pages_free * page_size / 1024 / 1024))
            mem_available=$((mem_free + pages_inactive * page_size / 1024 / 1024))
            
            # If sysctl failed but we have vm_stat data, calculate total from pages
            if [ "$mem_total_bytes" -eq 0 ] && [ -n "$pages_free" ] && [ -n "$pages_active" ]; then
                # Try to get total pages - sum all page types from vm_stat
                local pages_total=0
                local pages_speculative=$(echo "$vm_stat_output" | grep "Pages speculative" | awk '{print $3}' | sed 's/\.//' 2>/dev/null)
                local pages_throttled=$(echo "$vm_stat_output" | grep "Pages throttled" | awk '{print $3}' | sed 's/\.//' 2>/dev/null)
                local pages_occupied=$(echo "$vm_stat_output" | grep "Pages occupied" | awk '{print $3}' | sed 's/\.//' 2>/dev/null)
                
                # Calculate total pages
                pages_total=$((pages_free + pages_active + pages_inactive + pages_wired))
                if [ -n "$pages_speculative" ] && [[ "$pages_speculative" =~ ^[0-9]+$ ]]; then
                    pages_total=$((pages_total + pages_speculative))
                fi
                if [ -n "$pages_throttled" ] && [[ "$pages_throttled" =~ ^[0-9]+$ ]]; then
                    pages_total=$((pages_total + pages_throttled))
                fi
                if [ -n "$pages_occupied" ] && [[ "$pages_occupied" =~ ^[0-9]+$ ]]; then
                    pages_total=$((pages_total + pages_occupied))
                fi
                
                if [ "$pages_total" -gt 0 ]; then
                    mem_total=$((pages_total * page_size / 1024 / 1024))
                fi
            fi
        fi
        
        # Final fallback: if still 0, try to calculate from used + available
        if [ "$mem_total_bytes" -gt 0 ]; then
            mem_total=$((mem_total_bytes / 1024 / 1024))
        elif [ "$mem_total" -eq 0 ] || [ "$mem_total" -lt "$mem_used" ]; then
            # If total is 0 or less than used, estimate from used + available
            if [ "$mem_used" -gt 0 ] && [ "$mem_available" -gt 0 ]; then
                # Estimate total as used + available (rough approximation)
                mem_total=$((mem_used + mem_available))
            elif [ "$mem_used" -gt 0 ]; then
                # If we only have used, estimate total as used * 1.2 (rough estimate)
                mem_total=$((mem_used * 120 / 100))
            fi
        fi
        
        # macOS swap
        local swap_info=$(sysctl vm.swapusage 2>/dev/null)
        if [ -n "$swap_info" ]; then
            local swap_total_str=$(echo "$swap_info" | awk '{print $4}' | sed 's/M//')
            local swap_used_str=$(echo "$swap_info" | awk '{print $7}' | sed 's/M//')
            swap_total=${swap_total_str%.*}
            swap_used=${swap_used_str%.*}
            swap_free=$((swap_total - swap_used))
        fi
    else
        # Linux memory using free
        local mem_info=$(free -m 2>/dev/null || echo "Mem: 0 0 0 0 0 0 0")
        mem_total=$(echo "$mem_info" | grep "Mem:" | awk '{print $2}' || echo "0")
        mem_used=$(echo "$mem_info" | grep "Mem:" | awk '{print $3}' || echo "0")
        mem_free=$(echo "$mem_info" | grep "Mem:" | awk '{print $4}' || echo "0")
        mem_available=$(echo "$mem_info" | grep "Mem:" | awk '{print $7}' || echo "0")
        
        swap_total=$(echo "$mem_info" | grep "Swap:" | awk '{print $2}' || echo "0")
        swap_used=$(echo "$mem_info" | grep "Swap:" | awk '{print $3}' || echo "0")
        swap_free=$(echo "$mem_info" | grep "Swap:" | awk '{print $4}' || echo "0")
    fi
    
    # Calculate percentages
    if [ "$mem_total" -gt 0 ] && command -v bc &> /dev/null; then
        mem_percent=$(echo "scale=2; ($mem_used / $mem_total) * 100" | bc)
    fi
    
    if [ "$swap_total" -gt 0 ] && command -v bc &> /dev/null; then
        swap_percent=$(echo "scale=2; ($swap_used / $swap_total) * 100" | bc)
    fi
    
    echo "{
        \"memory_total_mb\": $mem_total,
        \"memory_used_mb\": $mem_used,
        \"memory_free_mb\": $mem_free,
        \"memory_available_mb\": $mem_available,
        \"memory_usage_percent\": $mem_percent,
        \"swap_total_mb\": $swap_total,
        \"swap_used_mb\": $swap_used,
        \"swap_free_mb\": $swap_free,
        \"swap_usage_percent\": $swap_percent
    }"
}

# Collect network metrics
collect_network_metrics() {
    log_message "INFO" "Collecting network metrics..."
    
    local network_json="["
    local first=true
    
    if [ "$IS_WINDOWS" = true ]; then
        # Windows network metrics using PowerShell
        local ps_cmd="powershell.exe"
        if command -v pwsh &> /dev/null; then
            ps_cmd="pwsh"
        fi
        
        # Get Windows network adapters
        local net_info=$($ps_cmd -Command "Get-NetAdapter | Where-Object { \$_.Status -eq 'Up' } | ForEach-Object { [PSCustomObject]@{ Name=\$_.Name; InterfaceDescription=\$_.InterfaceDescription } } | ConvertTo-Json" 2>/dev/null)
        
        if [ -n "$net_info" ] && command -v jq &> /dev/null; then
            local adapter_count=$(echo "$net_info" | jq 'length' 2>/dev/null || echo "0")
            if [ "$adapter_count" -gt 0 ]; then
                for i in $(seq 0 $((adapter_count - 1))); do
                    if [ "$first" = false ]; then
                        network_json+=","
                    fi
                    first=false
                    
                    local interface=$(echo "$net_info" | jq -r ".[$i].Name" 2>/dev/null)
                    
                    # Get network statistics
                    local stats=$($ps_cmd -Command "Get-NetAdapterStatistics -Name '$interface' | Select-Object ReceivedBytes, SentBytes, ReceivedPackets, SentPackets, ReceivedUnicastPackets, SentUnicastPackets | ConvertTo-Json" 2>/dev/null)
                    
                    local rx_bytes=$(echo "$stats" | jq -r '.ReceivedBytes' 2>/dev/null || echo "0")
                    local tx_bytes=$(echo "$stats" | jq -r '.SentBytes' 2>/dev/null || echo "0")
                    local rx_packets=$(echo "$stats" | jq -r '.ReceivedPackets' 2>/dev/null || echo "0")
                    local tx_packets=$(echo "$stats" | jq -r '.SentPackets' 2>/dev/null || echo "0")
                    
                    # Get IP address
                    local ip_address=$($ps_cmd -Command "(Get-NetIPAddress -InterfaceAlias '$interface' -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress" 2>/dev/null | head -1)
                    if [ -z "$ip_address" ] || [ "$ip_address" = "" ]; then
                        ip_address="N/A"
                    fi
                    
                    # Windows doesn't easily provide error counts, set to 0
                    local rx_errors=0
                    local tx_errors=0
                    
                    network_json+="{
                        \"interface\": \"$interface\",
                        \"ip_address\": \"$ip_address\",
                        \"rx_bytes\": $rx_bytes,
                        \"tx_bytes\": $tx_bytes,
                        \"rx_packets\": $rx_packets,
                        \"tx_packets\": $tx_packets,
                        \"rx_errors\": $rx_errors,
                        \"tx_errors\": $tx_errors
                    }"
                done
            fi
        fi
        
        # Fallback if jq is not available or PowerShell command failed
        if [ "$first" = true ]; then
            # Try using netstat if available (Git Bash, WSL, Cygwin)
            if command -v netstat &> /dev/null; then
                local interfaces=$(netstat -i 2>/dev/null | awk 'NR > 1 {print $1}' | grep -v "^Name$" | grep -v "^lo" | sort -u)
                for interface in $interfaces; do
                    if [ "$first" = false ]; then
                        network_json+=","
                    fi
                    first=false
                    
                    local netstat_line=$(netstat -ib 2>/dev/null | grep "^$interface " | head -1)
                    local rx_bytes=$(echo "$netstat_line" | awk '{print $7}' 2>/dev/null)
                    local tx_bytes=$(echo "$netstat_line" | awk '{print $10}' 2>/dev/null)
                    local rx_packets=$(netstat -i 2>/dev/null | grep "^$interface " | awk '{print $4}' 2>/dev/null)
                    local tx_packets=$(netstat -i 2>/dev/null | grep "^$interface " | awk '{print $8}' 2>/dev/null)
                    local rx_errors=$(netstat -i 2>/dev/null | grep "^$interface " | awk '{print $5}' 2>/dev/null)
                    local tx_errors=$(netstat -i 2>/dev/null | grep "^$interface " | awk '{print $9}' 2>/dev/null)
                    
                    # Validate and default to 0 if empty or not numeric
                    [ -z "$rx_bytes" ] || ! [[ "$rx_bytes" =~ ^[0-9]+$ ]] && rx_bytes=0
                    [ -z "$tx_bytes" ] || ! [[ "$tx_bytes" =~ ^[0-9]+$ ]] && tx_bytes=0
                    [ -z "$rx_packets" ] || ! [[ "$rx_packets" =~ ^[0-9]+$ ]] && rx_packets=0
                    [ -z "$tx_packets" ] || ! [[ "$tx_packets" =~ ^[0-9]+$ ]] && tx_packets=0
                    [ -z "$rx_errors" ] || ! [[ "$rx_errors" =~ ^[0-9]+$ ]] && rx_errors=0
                    [ -z "$tx_errors" ] || ! [[ "$tx_errors" =~ ^[0-9]+$ ]] && tx_errors=0
                    
                    local ip_address="N/A"
                    if command -v ipconfig &> /dev/null; then
                        ip_address=$(ipconfig 2>/dev/null | grep -A 5 "$interface" | grep "IPv4" | awk '{print $NF}' | head -1 || echo "N/A")
                    fi
                    
                    network_json+="{
                        \"interface\": \"$interface\",
                        \"ip_address\": \"$ip_address\",
                        \"rx_bytes\": $rx_bytes,
                        \"tx_bytes\": $tx_bytes,
                        \"rx_packets\": $rx_packets,
                        \"tx_packets\": $tx_packets,
                        \"rx_errors\": $rx_errors,
                        \"tx_errors\": $tx_errors
                    }"
                done
            fi
        fi
    elif [ "$IS_MACOS" = true ]; then
        # macOS network interfaces - try netstat first, fallback to ifconfig
        local interfaces=""
        if command -v netstat &> /dev/null; then
            interfaces=$(netstat -i 2>/dev/null | awk 'NR > 1 {print $1}' | grep -v "^Name$" | grep -v "^lo" | sort -u)
        fi
        
        # Fallback to ifconfig if netstat didn't work
        if [ -z "$interfaces" ] && command -v ifconfig &> /dev/null; then
            interfaces=$(ifconfig -l 2>/dev/null | tr ' ' '\n' | grep -v "^lo" | sort -u)
        fi
        
        for interface in $interfaces; do
            # Skip interfaces with only special characters or empty
            [ -z "$interface" ] && continue
            
            if [ "$first" = false ]; then
                network_json+=","
            fi
            first=false
            
            # Escape special characters in interface name for grep
            local interface_escaped=$(printf '%s\n' "$interface" | sed 's/[[\.*^$()+?{|]/\\&/g')
            
            # Get network stats from netstat
            local netstat_line=$(netstat -ib 2>/dev/null | grep "^$interface_escaped " | head -1)
            local rx_bytes=$(echo "$netstat_line" | awk '{print $7}' 2>/dev/null)
            local tx_bytes=$(echo "$netstat_line" | awk '{print $10}' 2>/dev/null)
            local rx_packets=$(netstat -i 2>/dev/null | grep "^$interface_escaped " | awk '{print $4}' 2>/dev/null)
            local tx_packets=$(netstat -i 2>/dev/null | grep "^$interface_escaped " | awk '{print $8}' 2>/dev/null)
            local rx_errors=$(netstat -i 2>/dev/null | grep "^$interface_escaped " | awk '{print $5}' 2>/dev/null)
            local tx_errors=$(netstat -i 2>/dev/null | grep "^$interface_escaped " | awk '{print $9}' 2>/dev/null)
            
            # If netstat failed, try ifconfig
            if [ -z "$rx_bytes" ] && command -v ifconfig &> /dev/null; then
                local ifconfig_output=$(ifconfig "$interface" 2>/dev/null)
                if [ -n "$ifconfig_output" ]; then
                    # Extract bytes from ifconfig (different format)
                    rx_bytes=$(echo "$ifconfig_output" | grep -i "RX packets" | awk '{print $5}' | sed 's/,//' 2>/dev/null)
                    tx_bytes=$(echo "$ifconfig_output" | grep -i "TX packets" | awk '{print $5}' | sed 's/,//' 2>/dev/null)
                    rx_packets=$(echo "$ifconfig_output" | grep -i "RX packets" | awk '{print $3}' | sed 's/,//' 2>/dev/null)
                    tx_packets=$(echo "$ifconfig_output" | grep -i "TX packets" | awk '{print $3}' | sed 's/,//' 2>/dev/null)
                fi
            fi
            
            # Validate and default to 0 if empty or not numeric
            [ -z "$rx_bytes" ] || ! [[ "$rx_bytes" =~ ^[0-9]+$ ]] && rx_bytes=0
            [ -z "$tx_bytes" ] || ! [[ "$tx_bytes" =~ ^[0-9]+$ ]] && tx_bytes=0
            [ -z "$rx_packets" ] || ! [[ "$rx_packets" =~ ^[0-9]+$ ]] && rx_packets=0
            [ -z "$tx_packets" ] || ! [[ "$tx_packets" =~ ^[0-9]+$ ]] && tx_packets=0
            [ -z "$rx_errors" ] || ! [[ "$rx_errors" =~ ^[0-9]+$ ]] && rx_errors=0
            [ -z "$tx_errors" ] || ! [[ "$tx_errors" =~ ^[0-9]+$ ]] && tx_errors=0
            
            # Get IP address
            local ip_address="N/A"
            if command -v ifconfig &> /dev/null; then
                ip_address=$(ifconfig "$interface" 2>/dev/null | grep "inet " | awk '{print $2}' | head -1)
                [ -z "$ip_address" ] && ip_address="N/A"
            fi
            
            network_json+="{
                \"interface\": \"$interface\",
                \"ip_address\": \"$ip_address\",
                \"rx_bytes\": $rx_bytes,
                \"tx_bytes\": $tx_bytes,
                \"rx_packets\": $rx_packets,
                \"tx_packets\": $tx_packets,
                \"rx_errors\": $rx_errors,
                \"tx_errors\": $tx_errors
            }"
        done
    else
        # Linux network interfaces
        if [ -d /sys/class/net ]; then
            for interface in $(ls /sys/class/net/ | grep -v lo); do
                if [ "$first" = false ]; then
                    network_json+=","
                fi
                first=false
                
                local rx_bytes=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo "0")
                local tx_bytes=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo "0")
                local rx_packets=$(cat /sys/class/net/$interface/statistics/rx_packets 2>/dev/null || echo "0")
                local tx_packets=$(cat /sys/class/net/$interface/statistics/tx_packets 2>/dev/null || echo "0")
                local rx_errors=$(cat /sys/class/net/$interface/statistics/rx_errors 2>/dev/null || echo "0")
                local tx_errors=$(cat /sys/class/net/$interface/statistics/tx_errors 2>/dev/null || echo "0")
                
                # Get IP address if available
                local ip_address="N/A"
                if command -v ip &> /dev/null; then
                    ip_address=$(ip addr show $interface 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1 || echo "N/A")
                elif command -v ifconfig &> /dev/null; then
                    ip_address=$(ifconfig $interface 2>/dev/null | grep "inet " | awk '{print $2}' || echo "N/A")
                fi
                
                network_json+="{
                    \"interface\": \"$interface\",
                    \"ip_address\": \"$ip_address\",
                    \"rx_bytes\": $rx_bytes,
                    \"tx_bytes\": $tx_bytes,
                    \"rx_packets\": $rx_packets,
                    \"tx_packets\": $tx_packets,
                    \"rx_errors\": $rx_errors,
                    \"tx_errors\": $tx_errors
                }"
            done
        fi
    fi
    
    network_json+="]"
    echo "$network_json"
}

# Collect system load metrics
collect_system_load() {
    log_message "INFO" "Collecting system load metrics..."
    
    local load_1min="0.00"
    local load_5min="0.00"
    local load_15min="0.00"
    local uptime_seconds=0
    local uptime_formatted="0d 0h 0m 0s"
    
    if [ "$IS_WINDOWS" = true ]; then
        # Windows doesn't have traditional load average, use CPU usage as approximation
        local ps_cmd="powershell.exe"
        if command -v pwsh &> /dev/null; then
            ps_cmd="pwsh"
        fi
        
        # Get CPU usage as load approximation
        local cpu_usage=$($ps_cmd -Command "Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty CounterSamples | Select-Object -ExpandProperty CookedValue" 2>/dev/null | head -1)
        if [ -z "$cpu_usage" ] || ! [[ "$cpu_usage" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            cpu_usage=$($ps_cmd -Command "(Get-WmiObject Win32_Processor | Measure-Object -property LoadPercentage -Average).Average" 2>/dev/null | head -1)
        fi
        if [ -z "$cpu_usage" ] || ! [[ "$cpu_usage" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            cpu_usage=0
        fi
        
        # Use CPU usage as load (normalize to 0-1 range for single core, multiply by cores)
        local cpu_cores=$($ps_cmd -Command "(Get-WmiObject Win32_ComputerSystem).NumberOfLogicalProcessors" 2>/dev/null | head -1)
        if [ -z "$cpu_cores" ] || ! [[ "$cpu_cores" =~ ^[0-9]+$ ]]; then
            cpu_cores=1
        fi
        
        # Convert CPU percentage to load average approximation
        # Load average represents average system load over time periods
        # For Windows, we approximate using current CPU usage
        if command -v bc &> /dev/null; then
            load_1min=$(echo "scale=2; ($cpu_usage / 100) * $cpu_cores" | bc)
            load_5min=$load_1min
            load_15min=$load_1min
        else
            # Fallback without bc
            load_1min="$cpu_usage"
            load_5min="$cpu_usage"
            load_15min="$cpu_usage"
        fi
        
        # Windows uptime
        local boot_time=$($ps_cmd -Command "(Get-WmiObject Win32_OperatingSystem).LastBootUpTime" 2>/dev/null | head -1)
        if [ -n "$boot_time" ]; then
            # Parse WMI datetime format (YYYYMMDDHHmmss.ffffff+###)
            local boot_timestamp=$($ps_cmd -Command "[System.Management.ManagementDateTimeConverter]::ToDateTime('$boot_time').ToUniversalTime() | ForEach-Object { [DateTimeOffset]::new(\$_).ToUnixTimeSeconds() }" 2>/dev/null | head -1)
            if [ -n "$boot_timestamp" ] && [[ "$boot_timestamp" =~ ^[0-9]+$ ]]; then
                local current_time=$(date +%s 2>/dev/null || echo "0")
                if [ "$current_time" -gt 0 ]; then
                    uptime_seconds=$((current_time - boot_timestamp))
                    uptime_formatted=$(printf '%dd %dh %dm %ds' $((uptime_seconds/86400)) $((uptime_seconds%86400/3600)) $((uptime_seconds%3600/60)) $((uptime_seconds%60)))
                fi
            fi
        fi
        
        # Fallback uptime method
        if [ "$uptime_seconds" -eq 0 ]; then
            # Try using systeminfo if available
            if command -v systeminfo &> /dev/null; then
                local boot_date=$(systeminfo 2>/dev/null | grep "System Boot Time" | cut -d: -f2- | sed 's/^ *//')
                if [ -n "$boot_date" ]; then
                    # This is a simplified approach - full parsing would require date conversion
                    uptime_formatted="N/A (check systeminfo)"
                fi
            fi
        fi
    elif [ "$IS_MACOS" = true ]; then
        # macOS load average
        local uptime_info=$(uptime 2>/dev/null || echo "load averages: 0.00 0.00 0.00")
        load_1min=$(echo "$uptime_info" | awk -F'load averages:' '{print $2}' | awk '{print $1}' | sed 's/,//' 2>/dev/null)
        load_5min=$(echo "$uptime_info" | awk -F'load averages:' '{print $2}' | awk '{print $2}' | sed 's/,//' 2>/dev/null)
        load_15min=$(echo "$uptime_info" | awk -F'load averages:' '{print $2}' | awk '{print $3}' 2>/dev/null)
        
        # Ensure values are not empty
        if [ -z "$load_1min" ] || ! [[ "$load_1min" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            load_1min="0.00"
        fi
        if [ -z "$load_5min" ] || ! [[ "$load_5min" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            load_5min="0.00"
        fi
        if [ -z "$load_15min" ] || ! [[ "$load_15min" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            load_15min="0.00"
        fi
        
        # macOS uptime
        local boot_time=$(sysctl -n kern.boottime 2>/dev/null | awk '{print $4}' | sed 's/,//')
        if [ -n "$boot_time" ] && [[ "$boot_time" =~ ^[0-9]+$ ]]; then
            local current_time=$(date +%s 2>/dev/null)
            if [ -n "$current_time" ] && [ "$current_time" -gt 0 ] && [ "$boot_time" -gt 0 ]; then
                uptime_seconds=$((current_time - boot_time))
                if [ "$uptime_seconds" -gt 0 ]; then
                    uptime_formatted=$(printf '%dd %dh %dm %ds' $((uptime_seconds/86400)) $((uptime_seconds%86400/3600)) $((uptime_seconds%3600/60)) $((uptime_seconds%60)))
                fi
            fi
        fi
    else
        # Linux load average
        local uptime_info=$(uptime 2>/dev/null || echo "load average: 0.00, 0.00, 0.00")
        load_1min=$(echo "$uptime_info" | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//' 2>/dev/null)
        load_5min=$(echo "$uptime_info" | awk -F'load average:' '{print $2}' | awk '{print $2}' | sed 's/,//' 2>/dev/null)
        load_15min=$(echo "$uptime_info" | awk -F'load average:' '{print $2}' | awk '{print $3}' 2>/dev/null)
        
        # Ensure values are not empty
        if [ -z "$load_1min" ] || ! [[ "$load_1min" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            load_1min="0.00"
        fi
        if [ -z "$load_5min" ] || ! [[ "$load_5min" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            load_5min="0.00"
        fi
        if [ -z "$load_15min" ] || ! [[ "$load_15min" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            load_15min="0.00"
        fi
        
        # Linux uptime
        if [ -f /proc/uptime ]; then
            uptime_seconds=$(awk '{print int($1)}' /proc/uptime)
            uptime_formatted=$(printf '%dd %dh %dm %ds' $((uptime_seconds/86400)) $((uptime_seconds%86400/3600)) $((uptime_seconds%3600/60)) $((uptime_seconds%60)))
        fi
    fi
    
    echo "{
        \"load_1min\": $load_1min,
        \"load_5min\": $load_5min,
        \"load_15min\": $load_15min,
        \"uptime\": \"$uptime_formatted\",
        \"uptime_seconds\": $uptime_seconds
    }"
}

# Main collection function
collect_all_metrics() {
    log_message "INFO" "Starting comprehensive metrics collection..." >&2
    
    detect_os
    check_root
    
    # Collect metrics, redirecting stderr to avoid log messages in JSON
    local cpu_metrics=$(collect_cpu_metrics 2>/dev/null)
    local gpu_metrics=$(collect_gpu_metrics 2>/dev/null)
    local disk_metrics=$(collect_disk_metrics 2>/dev/null)
    local memory_metrics=$(collect_memory_metrics 2>/dev/null)
    local network_metrics=$(collect_network_metrics 2>/dev/null)
    local system_load=$(collect_system_load 2>/dev/null)
    
    # Combine all metrics into JSON
    local all_metrics="{
        \"timestamp\": \"$(date -Iseconds 2>/dev/null || date)\",
        \"hostname\": \"$(hostname 2>/dev/null || echo 'unknown')\",
        \"cpu\": $cpu_metrics,
        \"gpu\": $gpu_metrics,
        \"disk\": $disk_metrics,
        \"memory\": $memory_metrics,
        \"network\": $network_metrics,
        \"system_load\": $system_load
    }"
    
    # Save to file (only JSON, no log messages)
    echo "$all_metrics" > "$METRICS_FILE"
    log_message "INFO" "Metrics saved to $METRICS_FILE" >&2
    
    # Output JSON to stdout (for other scripts to capture)
    echo "$all_metrics"
}

# Export functions for use in other scripts
export -f collect_cpu_metrics
export -f collect_gpu_metrics
export -f collect_disk_metrics
export -f collect_memory_metrics
export -f collect_network_metrics
export -f collect_system_load
export -f collect_all_metrics
export -f log_message

# If script is run directly, collect metrics
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    collect_all_metrics
fi

