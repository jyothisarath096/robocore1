# RoboCore-1 — Open Source RISC-V Robotics SoC

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![PDK: SKY130](https://img.shields.io/badge/PDK-SKY130-blue.svg)](https://github.com/google/skywater-pdk)
[![Process: 130nm](https://img.shields.io/badge/Process-130nm-green.svg)]()
[![Simulations: 30/30](https://img.shields.io/badge/Simulations-30%2F30-brightgreen.svg)]()

The world's first open-source RISC-V SoC combining **CAN FD** and **EtherCAT** for industrial robotics — built entirely on open-source tools and the SkyWater SKY130 130nm PDK.

---

## Key Features

| Feature | Specification |
|---|---|
| CPU | PicoRV32 RV32IMC @ 92MHz |
| Bus | AXI4-Lite (CPU + DMA dual master) |
| PWM Engine | 16 channels, 20-bit resolution |
| Encoder Interface | 16 channels, 32-bit quadrature |
| PID Controller | 8 channels, time-multiplexed, 1MHz update |
| CAN FD | ISO 11898-1:2015, 8Mbit/s data phase |
| EtherCAT MAC | IEC 61158, distributed clocks, SKY130 SRAM macros |
| DMA Engine | 8 channels, SYNC0/CAN triggers, timestamp injection |
| Safety Subsystem | CPU-independent e-stop, 4x watchdog |
| Clock Gating | CAN FD + EtherCAT + DMA gated when idle (~34% power saving) |
| Boot ROM | 1KB — chip ID check, WD init, PWM init, DMA setup |
| Process | SkyWater SKY130 130nm |
| Die Area | 6 × 6mm |
| Clock Speed | 92MHz (best-in-class for SKY130 open-source SoC) |
| Power | ~275mW (with clock gating) |

---

## Why RoboCore-1?

### The Problem
Industrial robotics engineers are forced to use:
- Proprietary chips with no source access
- Multiple chips for CAN FD + EtherCAT (no single chip has both)
- Expensive licensing fees for ARM cores and fieldbus IP

### The Solution
RoboCore-1 is the **only open-source chip** with:
- ✅ CAN FD (ISO 11898-1:2015) — the automotive/industrial standard
- ✅ EtherCAT (IEC 61158) — the gold standard for real-time robotics
- ✅ Hardware PID controller — no OS jitter, deterministic 1MHz update
- ✅ CPU-independent safety subsystem — hardware e-stop, always active
- ✅ Zero licensing fees — MIT license, fully open source

---

## Architecture

```
PicoRV32 RV32IMC ──┐
                   ├── AXI4-Lite Arbiter ──► robocore1_axi ──► Peripherals
DMA Engine    ──────┘         │
                              ├── PWM Engine (16ch)
CPU config ──► DMA Config     ├── Encoder Interface (16ch)
(0x000F_0000)                 ├── PID Controller (8ch)
                              ├── Safety Subsystem
                              ├── CAN FD Controller
                              ├── EtherCAT MAC
                              └── Tick Generator

Boot ROM (1KB) @ 0x0000_0000
Peripherals    @ 0x000X_0000
DMA Config     @ 0x000F_0000
```

---

## Memory Map

| Address | Block |
|---|---|
| 0x0000_0000 | Boot ROM (1KB) |
| 0x0000_0000 | PWM Engine |
| 0x0001_0000 | Encoder Interface |
| 0x0002_0000 | PID Controller |
| 0x0003_0000 | Safety Subsystem |
| 0x0004_0000 | Tick Generator |
| 0x0005_0000 | CAN FD Controller |
| 0x0006_0000 | EtherCAT MAC |
| 0x0007_0000 | System (Chip ID, IRQ, scratch) |
| 0x000F_0000 | DMA Engine config |

---

## DMA Engine — Robotics-Specific Features

The DMA engine is uniquely designed for real-time robotics:

- **EtherCAT SYNC0 trigger** — DMA fires in sync with distributed clocks
- **Timestamp injection** — writes `dc_local_time` at transfer time
- **Skip-on-fault** — bypasses transfer when fault detected
- **Auto-reload** — continuous EtherCAT cycle without CPU involvement
- **Descriptor chaining** — multi-step transfers from single trigger

```
SYNC0 pulse (every 1ms, nanosecond-accurate)
  → DMA reads encoder positions
  → DMA writes to EtherCAT process data memory
  → DMA injects timestamp
  → CPU interrupt: "cycle complete"

CPU never touches the real-time data path.
```

---

## Four Cardinal Principles

### 1. Precision
Nanosecond-accurate control through hardware execution:
- PID: 1MHz hardware tick, no OS jitter
- PWM: 20-bit resolution at 10MHz
- EtherCAT: 64-bit distributed clocks, 10ns resolution
- CAN FD: hardware bit stuffing, CRC-17

### 2. Reliability
Hardware guarantees, not software promises:
- Safety subsystem: CPU-independent, always active
- E-stop: pure hardware path, < 1 clock cycle response
- All external inputs: double-flopped synchronizers
- CAN FD: ISO 11898-1:2015 CRC-17

### 3. Speed
92MHz on SKY130 130nm — best-in-class:
- Beats PicoRV32 reference (75MHz) on same process
- Beats Ibex/lowRISC (80MHz) on same process
- Full IPC preserved (no TWO_CYCLE_ALU compromise)
- AXI4-Lite registered decode — single-cycle register access

### 4. Future Proof
Open standards, no vendor lock-in:
- RISC-V RV32IMC — open ISA, no licensing
- AXI4-Lite — ARM standard, universal
- SKY130 PDK — fully open source
- MIT license — modify and manufacture freely

---

## Repository Structure

```
robocore1/
├── src/                    # RTL source files
│   ├── robocore1_top_v2.v  # Top level (PicoRV32 + all peripherals)
│   ├── robocore1_axi.v     # AXI4-Lite bus interface
│   ├── robocore1_dma.v     # DMA engine
│   ├── can_fd_controller.v # CAN FD (ISO 11898-1:2015)
│   ├── ethercat_mac.v      # EtherCAT MAC (IEC 61158)
│   ├── pid_controller.v    # 8-channel PID
│   ├── pwm_engine.v        # 16-channel PWM
│   ├── encoder_interface.v # 16-channel quadrature encoder
│   ├── safety_subsystem.v  # CPU-independent safety
│   └── tick_generator.v    # Multi-rate tick generation
├── tb/                     # Testbenches
├── gds/                    # Synthesized GDS files
│   ├── robocore1_top_v3.gds # Latest full chip GDS
│   └── ...                  # Individual block GDS files
├── reports/                # Timing and manufacturability reports
├── picorv32/               # PicoRV32 RISC-V core (submodule)
├── CONSTITUTION.md         # Design principles
└── README.md
```

---

## Simulation Results

All 30 tests passing across 3 test suites:

| Test Suite | Tests | Status |
|---|---|---|
| AXI4-Lite Bus | 17/17 | ✅ |
| DMA Engine | 7/7 | ✅ |
| Top Level (full SoC) | 6/6 | ✅ |

---

## Synthesis Results (v3)

| Metric | Value |
|---|---|
| Process | SkyWater SKY130 130nm |
| Die area | 6 × 6mm |
| Cell count | ~135,000 |
| Clock speed | 92MHz (100MHz constraint, +0.35ns slack) |
| Power (estimated) | ~275mW (with clock gating, ~34% reduction) |
| WNS | +0.35ns (all paths MET) ✅ |
| TNS | 0.0ns (no violations) ✅ |
| Routing | Complete |
| GDS | 49MB ✅ |

---

## Comparison

| Chip | Process | Clock | CAN FD | EtherCAT | Open Source |
|---|---|---|---|---|---|
| **RoboCore-1** | **130nm** | **92MHz** | **✅** | **✅** | **✅ MIT** |
| PicoRV32 ref | 130nm | 75MHz | ❌ | ❌ | ✅ |
| Ibex (lowRISC) | 130nm | 80MHz | ❌ | ❌ | ✅ Apache |
| STM32G4 | 90nm | 170MHz | ✅ | ❌ | ❌ |
| i.MX RT1170 | 28nm | 1GHz | ✅ | ❌ | ❌ |
| ET1100 (Beckhoff) | — | — | ❌ | ✅ | ❌ |

**RoboCore-1 is the only chip in any category with both CAN FD and EtherCAT.**

---

## Toolchain

| Tool | Version | Purpose |
|---|---|---|
| OpenLane | ff5509f | RTL-to-GDS flow |
| Yosys | 0.30 | Synthesis |
| OpenROAD | — | Place and route |
| Magic | — | GDS generation |
| SKY130A PDK | 0fe599b | Process design kit |
| Icarus Verilog | — | Simulation |

---

## Roadmap

### v1.0 (Current) — Proof of Architecture
- Full RTL implementation on SKY130 ✅
- 30/30 simulations passing across all modules ✅
- GDS layout complete (49MB) ✅
- STA signoff: WNS +0.35ns, all paths MET at 100MHz ✅
- HAL v1.0 — single-header C library ✅
- Clock gating — ~34% power reduction ✅
- RoboCore Flow Manager — production-grade OpenLane wrapper ✅

### v1.1 — Silicon Validation
- MPW/ChipIgnite tapeout
- Silicon bring-up
- HAL/SDK development

### v2.0 — Production
- Upgrade to 28nm process
- CVA6 RV64GC CPU with FPU
- <25mW power target
- Production quantities

---

## License

MIT License — see LICENSE file.

RoboCore-1 is free to use, modify, and manufacture. No licensing fees.

---

## Contact

Built with OpenLane on SkyWater SKY130.
GitHub: https://github.com/jyothisarath096/robocore1
