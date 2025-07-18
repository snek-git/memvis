#!/bin/bash

# Memory Address Space Visualizer
# Usage: ./memvis.sh <pid> [width]

if [ $# -lt 1 ]; then
    echo "Usage: $0 <pid> [width]"
    echo "  pid   - Process ID to visualize"
    echo "  width - Terminal width for visualization (default: 80)"
    exit 1
fi

PID=$1
WIDTH=${2:-80}

if [ ! -f "/proc/$PID/maps" ]; then
    echo "Error: Process $PID not found or no permission"
    exit 1
fi

# Colors for different memory types
declare -A COLORS
COLORS[text]="\033[32m"      # Green for executable
COLORS[data]="\033[33m"      # Yellow for data
COLORS[heap]="\033[31m"      # Red for heap
COLORS[stack]="\033[34m"     # Blue for stack
COLORS[lib]="\033[35m"       # Magenta for libraries
COLORS[anon]="\033[36m"      # Cyan for anonymous
COLORS[vdso]="\033[37m"      # White for vdso/vvar
COLORS[gap]="\033[90m"       # Dark gray for gaps
RESET="\033[0m"

# Function to get color based on mapping type
get_color() {
    local line="$1"
    local perms=$(echo "$line" | awk '{print $2}')
    local path=$(echo "$line" | awk '{print $6}')
    
    if [[ "$path" == *"[heap]"* ]]; then
        echo -n "${COLORS[heap]}"
    elif [[ "$path" == *"[stack]"* ]]; then
        echo -n "${COLORS[stack]}"
    elif [[ "$path" == *"[vdso]"* || "$path" == *"[vvar]"* ]]; then
        echo -n "${COLORS[vdso]}"
    elif [[ "$perms" == *"x"* && "$path" != "" ]]; then
        if [[ "$path" == *".so"* ]]; then
            echo -n "${COLORS[lib]}"
        else
            echo -n "${COLORS[text]}"
        fi
    elif [[ "$path" == "" ]]; then
        echo -n "${COLORS[anon]}"
    else
        echo -n "${COLORS[data]}"
    fi
}

# Read memory map and calculate address ranges
echo "Memory map visualization for PID $PID"
echo "Legend: $(echo -e "${COLORS[text]}■${RESET}") Text $(echo -e "${COLORS[data]}■${RESET}") Data $(echo -e "${COLORS[heap]}■${RESET}") Heap $(echo -e "${COLORS[stack]}■${RESET}") Stack $(echo -e "${COLORS[lib]}■${RESET}") Libs $(echo -e "${COLORS[anon]}■${RESET}") Anon $(echo -e "${COLORS[gap]}■${RESET}") Gap"
echo

# Filter out kernel space and get reasonable user space ranges
USER_MAPS=$(awk '$1 !~ /^ffff/ && $1 != "" {print $1}' /proc/$PID/maps)

if [ -z "$USER_MAPS" ]; then
    echo "No user space mappings found"
    exit 1
fi

# Get min and max addresses from user space only (numeric sort)
MIN_ADDR=$(echo "$USER_MAPS" | cut -d'-' -f1 | python3 -c "
import sys
addrs = [int(line.strip(), 16) for line in sys.stdin if line.strip()]
print(f'{min(addrs):x}' if addrs else '0')
")
MAX_ADDR=$(echo "$USER_MAPS" | cut -d'-' -f2 | python3 -c "
import sys
addrs = [int(line.strip(), 16) for line in sys.stdin if line.strip()]
print(f'{max(addrs):x}' if addrs else '0')
")

# Use python for 64-bit arithmetic to avoid bash overflow
RANGE_INFO=$(python3 -c "
min_addr = int('$MIN_ADDR', 16)
max_addr = int('$MAX_ADDR', 16)
total_range = max_addr - min_addr
print(f'{min_addr} {max_addr} {total_range}')
")

read MIN_ADDR_DEC MAX_ADDR_DEC TOTAL_RANGE <<< "$RANGE_INFO"

echo "Address range: 0x$MIN_ADDR - 0x$MAX_ADDR"
echo "Total virtual address space: $((TOTAL_RANGE / 1024 / 1024)) MB"
echo

# Generate visualization with python for 64-bit math
python3 -c "
import sys

width = $WIDTH
min_addr = $MIN_ADDR_DEC
max_addr = $MAX_ADDR_DEC
total_range = $TOTAL_RANGE

if total_range <= 0:
    print('Invalid address range')
    sys.exit(1)

scale = max(1, total_range // width)

# Initialize visualization array
mapped = [False] * width
colors = ['gap'] * width

# Color mapping
color_codes = {
    'text': '\033[32m',
    'data': '\033[33m', 
    'heap': '\033[31m',
    'stack': '\033[34m',
    'lib': '\033[35m',
    'anon': '\033[36m',
    'vdso': '\033[37m',
    'gap': '\033[90m'
}

def get_color_type(perms, path):
    if '[heap]' in path:
        return 'heap'
    elif '[stack]' in path:
        return 'stack'
    elif '[vdso]' in path or '[vvar]' in path:
        return 'vdso'
    elif 'x' in perms and path and path != '':
        if '.so' in path:
            return 'lib'
        else:
            return 'text'
    elif not path or path == '':
        return 'anon'
    else:
        return 'data'

# Read and process mappings
with open('/proc/$PID/maps', 'r') as f:
    for line in f:
        parts = line.strip().split()
        if not parts or parts[0].startswith('ffff'):
            continue
            
        addr_range = parts[0]
        perms = parts[1] if len(parts) > 1 else ''
        path = parts[5] if len(parts) > 5 else ''
        
        if '-' not in addr_range:
            continue
            
        start_hex, end_hex = addr_range.split('-')
        try:
            start_dec = int(start_hex, 16)
            end_dec = int(end_hex, 16)
        except:
            continue
            
        if start_dec < min_addr or end_dec > max_addr:
            continue
            
        start_pos = max(0, (start_dec - min_addr) // scale)
        end_pos = min(width - 1, (end_dec - min_addr) // scale)
        
        color_type = get_color_type(perms, path)
        
        for i in range(int(start_pos), int(end_pos) + 1):
            if i < width:
                mapped[i] = True
                colors[i] = color_type

# Print visualization
print('[', end='')
for i in range(width):
    if mapped[i]:
        print(f'{color_codes[colors[i]]}■\033[0m', end='')
    else:
        print(f'{color_codes[\"gap\"]}·\033[0m', end='')
print(']')

print(f'Each character represents ~{scale // 1024} KB of address space')
"

echo

# Show detailed breakdown
echo
echo "Detailed memory regions (user space only):"
awk '$1 !~ /^ffff/ && $1 != "" {
    start = strtonum("0x" substr($1, 1, index($1, "-") - 1))
    end = strtonum("0x" substr($1, index($1, "-") + 1))
    size = end - start
    printf "0x%s %8.1f KB %s %s\n", $1, size/1024, $2, ($6 ? $6 : "[anonymous]")
}' /proc/$PID/maps | head -20

USER_REGIONS=$(awk '$1 !~ /^ffff/ && $1 != ""' /proc/$PID/maps | wc -l)
if [ $USER_REGIONS -gt 20 ]; then
    echo "... ($(( USER_REGIONS - 20 )) more regions)"
fi
