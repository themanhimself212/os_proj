#!/usr/bin/env python3
"""
Generate HTML Dashboard from metrics.json
Creates a standalone HTML file that can be opened in any browser
"""

import json
import os
from datetime import datetime

# File paths
METRICS_FILE = "reports/metrics.json"
OUTPUT_FILE = "reports/dashboard.html"


def load_metrics():
    """Load the metrics JSON file"""
    try:
        with open(METRICS_FILE, 'r') as f:
            data = json.load(f)
        return data
    except FileNotFoundError:
        print(f"Error: Could not find {METRICS_FILE}")
        print("Run './scripts/monitor.sh -o' first to collect metrics")
        return None
    except Exception as e:
        print(f"Error loading metrics: {e}")
        return None


def format_bytes(bytes_value):
    """Convert bytes to readable format"""
    if bytes_value == 0:
        return "0 B"
    
    # Convert to appropriate unit
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if bytes_value < 1024:
            return f"{bytes_value:.2f} {unit}"
        bytes_value = bytes_value / 1024
    return f"{bytes_value:.2f} PB"


def get_status_color(percent):
    """Get color based on usage percentage"""
    if percent < 50:
        return "#28a745"  # green
    elif percent < 80:
        return "#ffc107"  # yellow
    else:
        return "#dc3545"  # red


def generate_html(metrics):
    """Generate the HTML dashboard"""
    
    # Get data from metrics
    cpu = metrics.get("cpu", {})
    memory = metrics.get("memory", {})
    disks = metrics.get("disk", [])
    gpu = metrics.get("gpu", {})
    networks = metrics.get("network", [])
    system_load = metrics.get("system_load", {})
    
    # CPU values
    cpu_usage = cpu.get("cpu_usage_percent", 0)
    cpu_cores = cpu.get("cpu_cores", 0)
    cpu_temp = cpu.get("cpu_temperature", "N/A")
    cpu_model = cpu.get("cpu_model", "Unknown")
    load_avg = cpu.get("load_average", "N/A")
    
    # Memory values
    mem_total = memory.get("memory_total_mb", 0)
    mem_used = memory.get("memory_used_mb", 0)
    mem_available = memory.get("memory_available_mb", 0)
    mem_percent = memory.get("memory_usage_percent", 0)
    swap_total = memory.get("swap_total_mb", 0)
    swap_used = memory.get("swap_used_mb", 0)
    swap_percent = memory.get("swap_usage_percent", 0)
    
    # Filter out system disks (keep only main ones)
    main_disks = []
    for disk in disks:
        fs = disk.get("filesystem", "")
        if not fs.startswith("devfs") and not fs.startswith("map"):
            main_disks.append(disk)
    
    # Filter active network interfaces
    active_networks = []
    for net in networks:
        if net.get("rx_bytes", 0) > 0 or net.get("tx_bytes", 0) > 0:
            active_networks.append(net)
    
    # Start building HTML
    html = f"""<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Monitor Dashboard</title>
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        
        body {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
            min-height: 100vh;
        }}
        
        .container {{
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
            overflow: hidden;
        }}
        
        .header {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
        }}
        
        .header h1 {{
            font-size: 2.5em;
            margin-bottom: 10px;
        }}
        
        .info-bar {{
            display: flex;
            justify-content: space-around;
            padding: 20px;
            background: #f8f9fa;
            border-bottom: 2px solid #e9ecef;
        }}
        
        .info-item {{
            text-align: center;
        }}
        
        .info-item label {{
            display: block;
            color: #6c757d;
            font-size: 0.9em;
            margin-bottom: 5px;
        }}
        
        .info-item value {{
            display: block;
            font-size: 1.2em;
            font-weight: bold;
            color: #333;
        }}
        
        .section {{
            padding: 30px;
            border-bottom: 1px solid #e9ecef;
        }}
        
        .section:last-child {{
            border-bottom: none;
        }}
        
        .section-title {{
            font-size: 1.8em;
            margin-bottom: 20px;
            color: #667eea;
        }}
        
        .metrics-row {{
            display: flex;
            flex-wrap: wrap;
            gap: 20px;
            margin-bottom: 20px;
        }}
        
        .metric-card {{
            flex: 1;
            min-width: 200px;
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #667eea;
        }}
        
        .metric-card h3 {{
            color: #6c757d;
            font-size: 0.9em;
            margin-bottom: 10px;
        }}
        
        .metric-card .value {{
            font-size: 2em;
            font-weight: bold;
            color: #333;
        }}
        
        .progress-bar {{
            width: 100%;
            height: 25px;
            background: #e9ecef;
            border-radius: 12px;
            overflow: hidden;
            margin-top: 10px;
        }}
        
        .progress-fill {{
            height: 100%;
            border-radius: 12px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
            font-size: 0.85em;
        }}
        
        table {{
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }}
        
        table th {{
            background: #667eea;
            color: white;
            padding: 12px;
            text-align: left;
        }}
        
        table td {{
            padding: 12px;
            border-bottom: 1px solid #e9ecef;
        }}
        
        table tr:hover {{
            background: #f8f9fa;
        }}
        
        .badge {{
            display: inline-block;
            padding: 4px 10px;
            border-radius: 4px;
            color: white;
            font-size: 0.85em;
            font-weight: bold;
        }}
        
        .footer {{
            text-align: center;
            padding: 20px;
            background: #f8f9fa;
            color: #6c757d;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📊 System Monitor Dashboard</h1>
            <p>System Metrics Overview</p>
        </div>
        
        <div class="info-bar">
            <div class="info-item">
                <label>Hostname</label>
                <value>{metrics.get("hostname", "Unknown")}</value>
            </div>
            <div class="info-item">
                <label>Last Update</label>
                <value>{metrics.get("timestamp", "N/A")}</value>
            </div>
            <div class="info-item">
                <label>Uptime</label>
                <value>{system_load.get("uptime", "N/A")}</value>
            </div>
        </div>
        
        <!-- CPU Section -->
        <div class="section">
            <div class="section-title">🖥️ CPU Metrics</div>
            <div class="metrics-row">
                <div class="metric-card">
                    <h3>CPU Usage</h3>
                    <div class="value">{cpu_usage:.1f}%</div>
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: {cpu_usage}%; background: {get_status_color(cpu_usage)};">
                            {cpu_usage:.1f}%
                        </div>
                    </div>
                </div>
                <div class="metric-card">
                    <h3>CPU Cores</h3>
                    <div class="value">{cpu_cores}</div>
                </div>
                <div class="metric-card">
                    <h3>Temperature</h3>
                    <div class="value">{cpu_temp}</div>
                </div>
                <div class="metric-card">
                    <h3>Load Average</h3>
                    <div class="value">{load_avg}</div>
                </div>
            </div>
            <p style="margin-top: 15px; color: #6c757d;"><strong>Model:</strong> {cpu_model}</p>
        </div>
        
        <!-- Memory Section -->
        <div class="section">
            <div class="section-title">💾 Memory Metrics</div>
            <div class="metrics-row">
                <div class="metric-card">
                    <h3>Total Memory</h3>
                    <div class="value">{mem_total / 1024:.2f} GB</div>
                </div>
                <div class="metric-card">
                    <h3>Used Memory</h3>
                    <div class="value">{mem_used / 1024:.2f} GB</div>
                </div>
                <div class="metric-card">
                    <h3>Available Memory</h3>
                    <div class="value">{mem_available / 1024:.2f} GB</div>
                </div>
                <div class="metric-card">
                    <h3>Memory Usage</h3>
                    <div class="value">
                        <span class="badge" style="background: {get_status_color(mem_percent)};">{mem_percent:.1f}%</span>
                    </div>
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: {mem_percent}%; background: {get_status_color(mem_percent)};">
                            {mem_percent:.1f}%
                        </div>
                    </div>
                </div>
            </div>
"""
    
    # Add swap if available
    if swap_total > 0:
        html += f"""
            <div class="metrics-row" style="margin-top: 20px;">
                <div class="metric-card">
                    <h3>Swap Total</h3>
                    <div class="value">{swap_total / 1024:.2f} GB</div>
                </div>
                <div class="metric-card">
                    <h3>Swap Used</h3>
                    <div class="value">{swap_used / 1024:.2f} GB</div>
                </div>
                <div class="metric-card">
                    <h3>Swap Usage</h3>
                    <div class="value">
                        <span class="badge" style="background: {get_status_color(swap_percent)};">{swap_percent:.1f}%</span>
                    </div>
                    <div class="progress-bar">
                        <div class="progress-fill" style="width: {swap_percent}%; background: {get_status_color(swap_percent)};">
                            {swap_percent:.1f}%
                        </div>
                    </div>
                </div>
            </div>
"""
    
    # Disk Section
    html += """
        </div>
        
        <div class="section">
            <div class="section-title">💿 Disk Metrics</div>
"""
    
    if main_disks:
        html += """
            <table>
                <thead>
                    <tr>
                        <th>Filesystem</th>
                        <th>Size</th>
                        <th>Used</th>
                        <th>Available</th>
                        <th>Usage %</th>
                    </tr>
                </thead>
                <tbody>
"""
        for disk in main_disks:
            usage = disk.get("use_percent", 0)
            size = disk.get("size", "N/A")
            used = disk.get("used", "N/A")
            available = disk.get("available", "N/A")
            
            # Format size strings
            if size.endswith('Gi'):
                size = size.replace('Gi', ' GB')
            if used.endswith('Gi'):
                used = used.replace('Gi', ' GB')
            if available.endswith('Gi'):
                available = available.replace('Gi', ' GB')
            
            html += f"""
                    <tr>
                        <td>{disk.get("filesystem", "N/A")}</td>
                        <td>{size}</td>
                        <td>{used}</td>
                        <td>{available}</td>
                        <td>
                            <span class="badge" style="background: {get_status_color(usage)};">{usage}%</span>
                        </td>
                    </tr>
"""
        html += """
                </tbody>
            </table>
"""
    else:
        html += '<p style="color: #6c757d;">No disk information available</p>'
    
    # GPU Section
    html += """
        </div>
        
        <div class="section">
            <div class="section-title">🎮 GPU Metrics</div>
            <div class="metrics-row">
"""
    html += f"""
                <div class="metric-card">
                    <h3>GPU Usage</h3>
                    <div class="value">{gpu.get("gpu_usage_percent", "N/A")}</div>
                </div>
                <div class="metric-card">
                    <h3>GPU Temperature</h3>
                    <div class="value">{gpu.get("gpu_temperature", "N/A")}</div>
                </div>
                <div class="metric-card">
                    <h3>GPU Memory</h3>
                    <div class="value">{gpu.get("gpu_memory", "N/A")}</div>
                </div>
"""
    
    # Network Section
    html += """
            </div>
        </div>
        
        <div class="section">
            <div class="section-title">🌐 Network Metrics</div>
"""
    
    if active_networks:
        html += """
            <table>
                <thead>
                    <tr>
                        <th>Interface</th>
                        <th>IP Address</th>
                        <th>RX Bytes</th>
                        <th>TX Bytes</th>
                        <th>RX Packets</th>
                        <th>TX Packets</th>
                    </tr>
                </thead>
                <tbody>
"""
        for net in active_networks:
            html += f"""
                    <tr>
                        <td>{net.get("interface", "N/A")}</td>
                        <td>{net.get("ip_address", "N/A")}</td>
                        <td>{format_bytes(net.get("rx_bytes", 0))}</td>
                        <td>{format_bytes(net.get("tx_bytes", 0))}</td>
                        <td>{net.get("rx_packets", 0):,}</td>
                        <td>{net.get("tx_packets", 0):,}</td>
                    </tr>
"""
        html += """
                </tbody>
            </table>
"""
    else:
        html += '<p style="color: #6c757d;">No active network interfaces</p>'
    
    # System Load Section
    html += """
        </div>
        
        <div class="section">
            <div class="section-title">⚙️ System Load</div>
            <div class="metrics-row">
"""
    html += f"""
                <div class="metric-card">
                    <h3>Load (1 min)</h3>
                    <div class="value">{system_load.get("load_1min", 0):.2f}</div>
                </div>
                <div class="metric-card">
                    <h3>Load (5 min)</h3>
                    <div class="value">{system_load.get("load_5min", 0):.2f}</div>
                </div>
                <div class="metric-card">
                    <h3>Load (15 min)</h3>
                    <div class="value">{system_load.get("load_15min", 0):.2f}</div>
                </div>
                <div class="metric-card">
                    <h3>Uptime</h3>
                    <div class="value">{system_load.get("uptime", "N/A")}</div>
                </div>
            </div>
        </div>
"""
    
    # Footer
    html += f"""
        <div class="footer">
            Generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
        </div>
    </div>
</body>
</html>
"""
    
    return html


def main():
    """Main function to generate the dashboard"""
    print(f"Loading metrics from {METRICS_FILE}...")
    
    metrics = load_metrics()
    if metrics is None:
        return
    
    print("Generating HTML dashboard...")
    html = generate_html(metrics)
    
    # Make sure reports directory exists
    os.makedirs(os.path.dirname(OUTPUT_FILE), exist_ok=True)
    
    # Write HTML file
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as f:
        f.write(html)
    
    print(f"✅ Dashboard generated successfully!")
    print(f"📄 File: {OUTPUT_FILE}")
    print(f"🌐 Open in browser: file://{os.path.abspath(OUTPUT_FILE)}")


if __name__ == "__main__":
    main()
