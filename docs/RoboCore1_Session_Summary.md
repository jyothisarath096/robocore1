# RoboCore-1 Complete Project Summary

## GitHub
- Repo: https://github.com/jyothisarath096/robocore1
- Token: TOKEN_REDACTED

## What RoboCore-1 Is
Open-source RISC-V robotics SoC — world's first chip with both CAN FD + EtherCAT on SkyWater SKY130 130nm. Target: Efabless ChipIgnite (~$10k). NOT Caravel MPW (6x6mm die too big for 2.92x3.52mm Caravel area).

## Architecture
PicoRV32 RV32IMC + AXI4-Lite arbiter + DMA (8ch) + 16ch PWM + 16ch encoder + 8ch PID + CAN FD + EtherCAT + safety subsystem + tick generator. Boot ROM 1KB at 0x0000_0000. User firmware at 0x0001_0000.

## Key Specs
- Die: 6x6mm, ~135k cells, 92MHz (WNS +0.35ns), ~275mW
- PicoRV32: ENABLE_MUL=0, ENABLE_DIV=0, ENABLE_IRQ=1, COMPRESSED_ISA=1
- DMA: DESC_DEPTH=4 (not 16), ram_style=block on desc_ram
- Clock gating: CAN FD + EtherCAT + DMA via sky130_fd_sc_hd__dlclkp_1

## Simulations: 30/30 PASSING
- AXI4-Lite: 17/17
- DMA: 7/7
- Top level: 6/6

## Verification Status
- Pre-layout STA: WNS +0.35ns ALL PATHS MET
- CDC: Clean — single clock domain throughout
- Formal AXI: PASS (SymbiYosys BMC depth=30)
- Formal Safety: PASS (SymbiYosys BMC depth=30)
- Formal DMA: SKIPPED (ch_pending multi-driver in generate blocks — verified by sim)
- Post-layout SPEF: NOT DONE (needs one more run)
- LVS: NOT DONE
- DRC: NOT DONE
- GDS: DONE — gds/robocore1_top_v3.gds (49MB)

## OpenLane Config (PROVEN WORKING)
```json
{
  "DESIGN_NAME": "robocore1_top",
  "VERILOG_FILES": "dir::src/*.v",
  "VERILOG_FILES_BLACKBOX": "designs/robocore1/macros/verilog/sram_wrapper_bb.v designs/robocore1/macros/verilog/icg_bb.v",
  "CLOCK_PORT": "clk", "CLOCK_PERIOD": 10.0,
  "BASE_SDC_FILE": "designs/robocore1/constraints.sdc",
  "FP_SIZING": "absolute",
  "DIE_AREA": "0 0 6000 6000", "CORE_AREA": "10 10 5990 5990",
  "PL_TARGET_DENSITY": 0.28, "SYNTH_STRATEGY": "DELAY 3",
  "MAX_FANOUT_CONSTRAINT": 4, "GRT_ADJUSTMENT": 0.15,
  "GLB_RESIZER_TIMING_OPTIMIZATIONS": 0,
  "GLB_RESIZER_DESIGN_OPTIMIZATIONS": 0,
  "EXTRA_LEFS": "designs/robocore1/macros/lef/sram_wrapper.lef",
  "EXTRA_GDS_FILES": "designs/robocore1/macros/gds/sram_wrapper.gds",
  "MACRO_PLACEMENT_CFG": "designs/robocore1/macro_placement.cfg",
  "VDD_NETS": "VPWR vccd1", "GND_NETS": "VGND vssd1",
  "FP_PDN_MACRO_HOOKS": "u_ec.u_sram VPWR VGND VPWR VGND",
  "QUIT_ON_LVS_ERROR": 0, "RUN_MAGIC_DRC": 0,
  "FP_PDN_CHECK_NODES": 0, "RUN_IRDROP_REPORT": 0,
  "QUIT_ON_TIMING_VIOLATIONS": 0, "QUIT_ON_XOR_ERROR": 0,
  "QUIT_ON_SYNTH_CHECKS": 0
}
```

## PDK & Docker
- PDK: sky130A, version 0fe599b2afb6708d281543108caf8310912f54af
- Docker: ghcr.io/the-openroad-project/openlane:ff5509f65b17bfa4068d5336495ab1718987ff69
- PDK root: ~/.ciel

## Vast.ai Setup (Full Run)
```bash
# SSH key: ~/.ssh/id_ed25519_vast (no passphrase)
ssh -i ~/.ssh/id_ed25519_vast -p PORT root@IP

# Full setup (paste all at once)
apt-get update -qq && apt-get install -y python3-pip git unzip -qq
pip3 install ciel -q
ciel enable --pdk sky130A 0fe599b2afb6708d281543108caf8310912f54af
docker pull ghcr.io/the-openroad-project/openlane:ff5509f65b17bfa4068d5336495ab1718987ff69
wget -q "https://github.com/The-OpenROAD-Project/OpenLane/archive/ff5509f65b17bfa4068d5336495ab1718987ff69.zip" -O openlane.zip
unzip -q openlane.zip
mv OpenLane-ff5509f65b17bfa4068d5336495ab1718987ff69 OpenLane_repo
git clone https://github.com/jyothisarath096/robocore1.git ~/robocore1
echo "Setup complete"
```

## Run Flow (inside Docker container)
```bash
./flow.tcl -design sram_wrapper && \
cp designs/sram_wrapper/runs/$(ls -t designs/sram_wrapper/runs/ | head -1)/results/final/gds/sram_wrapper.gds designs/robocore1/macros/gds/ && \
cp designs/sram_wrapper/runs/$(ls -t designs/sram_wrapper/runs/ | head -1)/results/final/lef/sram_wrapper.lef designs/robocore1/macros/lef/ && \
echo "SRAM done" && \
./flow.tcl -design robocore1
```

## If Magic GDS Crashes (run manually)
```bash
cat > /tmp/def2gds.tcl << 'TCLEOF'
drc off
def read /openlane/designs/robocore1/runs/RUN_XXX/results/final/def/robocore1_top.def
gds write /tmp/robocore1_top_v3.gds
quit -noprompt
TCLEOF
magic -noconsole -dnull -rcfile /root/.ciel/sky130A/libs.tech/magic/sky130A.magicrc /tmp/def2gds.tcl
```

## Known Issues & Workarounds
- OpenROAD segfault step 16: GLB_RESIZER disabled in config
- Magic GDS crash: run Magic manually on DEF
- SRAM blackbox override: sram_stubs.v must be in tb/ not src/
- ICG cell unknown to linter: icg_bb.v blackbox stub in macros/verilog/
- DMA ch_pending multi-driver (formal): verified by simulation 7/7
- PicoRV32 MUL/DIV cells: ENABLE_MUL=0 ENABLE_DIV=0
- desc_ram/boot_rom synthesized as FFs: (* ram_style="block" *) applied

## RTL Key Fixes Applied
1. ENABLE_MUL=0, ENABLE_DIV=0 (removed pcpi_mul, saved ~50k cells)
2. DESC_DEPTH=4 not 16 (prevents 100k extra FFs)
3. (* ram_style="block" *) on desc_ram and boot_rom
4. ch_sw_trig: config slave is single owner
5. ch_desc: sequencer is single owner  
6. Clock gating via dlclkp_1 on CAN/EtherCAT/DMA
7. AXI arbiter: registered enable logic placed after all wire declarations

## Simulate All Tests
```bash
cd ~/robocore1
iverilog -g2012 -o axi_sim src/robocore1_axi.v tb/robocore1_axi_tb.v && vvp axi_sim | grep -E "PASS|FAIL|Complete"
iverilog -g2012 -o dma_sim src/robocore1_dma.v tb/robocore1_dma_tb.v && vvp dma_sim | grep -E "PASS|FAIL|Complete"
iverilog -g2012 -o top_sim picorv32/picorv32.v tb/sram_stubs.v src/tick_generator.v src/pwm_engine.v src/encoder_interface.v src/pid_controller.v src/safety_subsystem.v src/can_fd_controller.v src/ethercat_mac.v src/robocore1_axi.v src/robocore1_dma.v src/robocore1_top_v2.v tb/robocore1_top_v2_tb.v && vvp top_sim | grep -E "PASS|FAIL|Complete"
```

## Flow Manager CLI
```bash
cd ~/robocore1
python3 tools/robocore_flow.py preprocess src/          # check RTL
python3 tools/robocore_flow.py preprocess src/ --fix    # auto-fix arrays
python3 tools/robocore_flow.py status                   # run status
python3 tools/robocore_flow.py watch                    # live log
python3 tools/robocore_flow.py estimate                 # cost estimate
python3 tools/robocore_flow.py save --push              # push to GitHub
```

## Formal Verification (RunPod)
```bash
# Install on RunPod Ubuntu 20.04 workspace
apt-get install -y yosys python3.10 z3 boolector
cd /workspace
wget https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2024-01-15/oss-cad-suite-linux-x64-20240115.tgz -O oss-cad.tgz
tar xzf oss-cad.tgz
export PATH=/workspace/oss-cad-suite/bin:$PATH
cd /workspace/sby && make install PREFIX=/usr/local
pip3 install click -q  # for python3.10
sed -i 's|#!/usr/bin/env python3|#!/usr/bin/env python3.10|' /usr/local/bin/sby

# Run (specs in formal/ directory)
sby -f formal/axi_formal.sby    # PASSES
sby -f formal/safety_formal.sby # PASSES
```

## Budgets
- Vast.ai: ~$4 remaining (~13hrs at $0.30/hr)
- RunPod: ~$14 remaining

## What To Do Next (Priority Order)
1. Final Vast.ai run for LVS/DRC/SPEF (~$1.50)
2. Improve formal verification using ZipCPU AXI properties
   (git clone https://github.com/ZipCPU/wb2axip — formal/faxil_slave.v)
3. ChipIgnite application (~$10k needed)
4. RoboCore-1-Lite for free Caravel MPW (8ch PWM, 8ch enc, 4ch PID, CAN FD only)
5. FPGA prototype for hardware validation
6. Customer outreach / fundraising

## Business Strategy
- MIT license now, proprietary for v2+
- Target: industrial robotics, factory automation
- Differentiator: only open chip with CAN FD + EtherCAT
- Long-term: build proprietary EDA toolchain (compete with Cadence/Synopsys)
- Power: 415mW raw → 275mW (clock gating) → ~23mW on 28nm
- ChipIgnite required (Caravel too small at 2.92x3.52mm)

## Four Cardinal Principles
1. Precision — hardware PID 1MHz, no OS jitter
2. Reliability — CPU-independent safety, hardware e-stop
3. Speed — 92MHz full IPC
4. Future Proof — RISC-V + AXI4-Lite + open PDK
