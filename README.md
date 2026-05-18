# RoboCore-1

An open-source RISC-V robotics SoC designed for factory automation.
Built on the SkyWater SKY130 130nm process.

## Overview
RoboCore-1 is a purpose-built chip for industrial robot control.
It provides hardware-accelerated motion control with deterministic,
real-time performance — no OS jitter, no cache misses.

## Key Features
- 16-channel hardware PWM engine (motor drive)
- 16-channel quadrature encoder interface (position feedback)
- 8-channel hardware PID controller (1MHz update rate)
- Safety subsystem (watchdog, E-stop, brownout, fault management)
- RISC-V RV32IMC core (coming)
- EtherCAT MAC (coming)
- CAN 2.0B controller (coming)

## Process
SkyWater SKY130 (130nm) via Efabless OpenMPW

## Toolchain
- OpenLane (RTL to GDSII)
- Verilator / Icarus Verilog (simulation)
- KLayout (layout viewing)

## License
MIT License — fully open source
