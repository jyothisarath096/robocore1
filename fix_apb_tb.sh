#!/bin/bash
python3 << 'PYEOF'
with open('/Users/buddhi/robocore1/src/robocore1_apb_tb.v', 'r') as f:
    content = f.read()

# Fix declarations
replacements = [
    ("wire [31:0] pid_target  [0:7];", "wire [255:0] pid_target_flat;"),
    ("wire [15:0] pid_kp      [0:7];", "wire [127:0] pid_kp_flat;"),
    ("wire [15:0] pid_ki      [0:7];", "wire [127:0] pid_ki_flat;"),
    ("wire [15:0] pid_kd      [0:7];", "wire [127:0] pid_kd_flat;"),
    ("wire [15:0] pid_out_max [0:7];", "wire [127:0] pid_out_max_flat;"),
    ("reg  [15:0] pid_out     [0:7];", "reg  [127:0] pid_out_flat;"),
]
for old, new in replacements:
    if old in content:
        content = content.replace(old, new)
        print(f"Fixed decl: {old[:40]}")
    else:
        print(f"NOT FOUND: {old[:40]}")

# Fix port connections
inst_replacements = [
    ("    .pid_target     (pid_target),",   "    .pid_target_flat  (pid_target_flat),"),
    ("    .pid_kp         (pid_kp),",        "    .pid_kp_flat      (pid_kp_flat),"),
    ("    .pid_ki         (pid_ki),",        "    .pid_ki_flat      (pid_ki_flat),"),
    ("    .pid_kd         (pid_kd),",        "    .pid_kd_flat      (pid_kd_flat),"),
    ("    .pid_out_max    (pid_out_max),",   "    .pid_out_max_flat (pid_out_max_flat),"),
    ("    .pid_out        (pid_out),",       "    .pid_out_flat     (pid_out_flat),"),
]
for old, new in inst_replacements:
    if old in content:
        content = content.replace(old, new)
        print(f"Fixed port: {old[:40]}")
    else:
        print(f"NOT FOUND port: {old[:40]}")

# Fix pid_out initialisation loop
old_init = """    for (ch = 0; ch < 8; ch = ch + 1) begin
        pid_out[ch]       = 16'd500;
        pid_at_target[ch] = 0;
        pid_saturated[ch] = 0;
    end
    pid_at_target = 8'h0;
    pid_saturated = 8'h0;"""

new_init = """    pid_out_flat  = 0;
    for (ch = 0; ch < 8; ch = ch + 1)
        pid_out_flat[ch*16 +: 16] = 16'd500;
    pid_at_target = 8'h0;
    pid_saturated = 8'h0;"""

if old_init in content:
    content = content.replace(old_init, new_init)
    print("Fixed pid_out init loop")
else:
    print("NOT FOUND: pid_out init loop")

# Fix pid_kp read test
content = content.replace(
    "    if (pid_kp[0] == 16'd20)\n        $display(\"PASS: PID Kp[0] = 20\");\n    else\n        $display(\"FAIL: PID Kp wrong: %0d\", pid_kp[0]);",
    "    if (pid_kp_flat[0*16 +: 16] == 16'd20)\n        $display(\"PASS: PID Kp[0] = 20\");\n    else\n        $display(\"FAIL: PID Kp wrong: %0d\", pid_kp_flat[0*16 +: 16]);"
)

# Fix pid_target read test
content = content.replace(
    "    if (pid_target[0] == 32'd2000)\n        $display(\"PASS: PID target[0] = 2000\");\n    else\n        $display(\"FAIL: PID target wrong: %0d\", pid_target[0]);",
    "    if (pid_target_flat[0*32 +: 32] == 32'd2000)\n        $display(\"PASS: PID target[0] = 2000\");\n    else\n        $display(\"FAIL: PID target wrong: %0d\", pid_target_flat[0*32 +: 32]);"
)

with open('/Users/buddhi/robocore1/src/robocore1_apb_tb.v', 'w') as f:
    f.write(content)
print("Done — robocore1_apb_tb.v fixed")
PYEOF
