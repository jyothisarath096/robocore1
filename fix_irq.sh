#!/bin/bash
# Fix interrupt logic in robocore1_apb.v
cd ~/robocore1/src

# Use Python to do the multi-line replacement reliably
python3 << 'PYEOF'
with open('robocore1_apb.v', 'r') as f:
    content = f.read()

old = """    end else begin
        // Latch incoming interrupts
        irq_pending <= irq_pending | irq_in;

        // Clear acknowledged interrupts
        irq_pending <= irq_pending & ~irq_clear;
        irq_clear   <= 0;

        // Active = pending and not masked
        irq_active <= irq_pending & ~irq_mask;
    end
end

// IRQ output — any active interrupt
assign irq_out = |irq_active;"""

new = """    end else begin
        // Latch and clear in single assignment — no race condition
        irq_pending <= (irq_pending | irq_in) & ~irq_clear;
        irq_clear   <= 0;

        // Active = pending and not masked
        irq_active  <= (irq_pending | irq_in) & ~irq_mask;
    end
end

// IRQ output — combinatorial for zero-latency response
assign irq_out = |((irq_pending | irq_in) & ~irq_mask);"""

if old in content:
    content = content.replace(old, new)
    with open('robocore1_apb.v', 'w') as f:
        f.write(content)
    print("Fixed successfully")
else:
    print("Pattern not found — check manually")
PYEOF
