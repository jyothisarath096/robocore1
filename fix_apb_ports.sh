#!/bin/bash
python3 << 'PYEOF'
with open('/Users/buddhi/robocore1/src/robocore1_apb.v', 'r') as f:
    content = f.read()

# Fix array ports — flatten to wide buses
replacements = [
    # PID outputs
    ("    output reg  [31:0]  pid_target  [0:7],",
     "    output reg  [255:0] pid_target_flat,   // 8x32 flattened"),
    ("    output reg  [15:0]  pid_kp      [0:7],",
     "    output reg  [127:0] pid_kp_flat,       // 8x16 flattened"),
    ("    output reg  [15:0]  pid_ki      [0:7],",
     "    output reg  [127:0] pid_ki_flat,        // 8x16 flattened"),
    ("    output reg  [15:0]  pid_kd      [0:7],",
     "    output reg  [127:0] pid_kd_flat,        // 8x16 flattened"),
    ("    output reg  [15:0]  pid_out_max [0:7],",
     "    output reg  [127:0] pid_out_max_flat,   // 8x16 flattened"),
    ("    output reg  [7:0]   pid_enable,",
     "    output reg  [7:0]   pid_enable,"),
    ("    input  wire [15:0]  pid_out     [0:7],",
     "    input  wire [127:0] pid_out_flat,       // 8x16 flattened"),
    ("    input  wire [7:0]   pid_at_target,",
     "    input  wire [7:0]   pid_at_target,"),
    ("    input  wire [7:0]   pid_saturated,",
     "    input  wire [7:0]   pid_saturated,"),
    # CAN tx_data
    ("    output reg  [511:0] can_tx_data,",
     "    output reg  [511:0] can_tx_data,"),
    ("    input  wire [511:0] can_rx_data,",
     "    input  wire [511:0] can_rx_data,"),
]

for old, new in replacements:
    if old in content:
        content = content.replace(old, new)
        print(f"Fixed: {old.strip()[:50]}")
    else:
        print(f"NOT FOUND: {old.strip()[:50]}")

# Now fix internal usages of pid_target, pid_kp etc arrays
# Replace array indexing with flat bus slicing

# Fix pid_target reads/writes
import re

# Replace pid_target[ch] with pid_target_flat[ch*32 +: 32]
content = re.sub(r'\bpid_target\[(\w+)\]', 
                 lambda m: f'pid_target_flat[{m.group(1)}*32 +: 32]', content)
content = re.sub(r'\bpid_kp\[(\w+)\]',
                 lambda m: f'pid_kp_flat[{m.group(1)}*16 +: 16]', content)
content = re.sub(r'\bpid_ki\[(\w+)\]',
                 lambda m: f'pid_ki_flat[{m.group(1)}*16 +: 16]', content)
content = re.sub(r'\bpid_kd\[(\w+)\]',
                 lambda m: f'pid_kd_flat[{m.group(1)}*16 +: 16]', content)
content = re.sub(r'\bpid_out_max\[(\w+)\]',
                 lambda m: f'pid_out_max_flat[{m.group(1)}*16 +: 16]', content)
content = re.sub(r'\bpid_out\[(\w+)\]',
                 lambda m: f'pid_out_flat[{m.group(1)}*16 +: 16]', content)

print("\nReplaced array indexing with flat bus slicing")

# Fix reset block — remove array declarations in reset
old_reset = """        begin : pid_reset
            integer p;
            for (p = 0; p < 8; p = p + 1) begin
                pid_target[p]  <= 32'd0;
                pid_kp[p]      <= 16'd10;
                pid_ki[p]      <= 16'd1;
                pid_kd[p]      <= 16'd5;
                pid_out_max[p] <= 16'd1000;
            end
        end"""

new_reset = """        // Reset PID flat buses
        pid_target_flat  <= 0;
        pid_kp_flat      <= {8{16'd10}};
        pid_ki_flat      <= {8{16'd1}};
        pid_kd_flat      <= {8{16'd5}};
        pid_out_max_flat <= {8{16'd1000}};"""

if old_reset in content:
    content = content.replace(old_reset, new_reset)
    print("Fixed PID reset block")
else:
    print("WARNING: PID reset block not found — check manually")

with open('/Users/buddhi/robocore1/src/robocore1_apb.v', 'w') as f:
    f.write(content)

print("\nDone — robocore1_apb.v fixed")
PYEOF
