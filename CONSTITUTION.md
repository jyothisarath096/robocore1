# RoboCore-1 Design Constitution

Every architectural decision, every parameter choice, every block design
must be evaluated against these four cardinal principles before proceeding.
If a decision cannot satisfy all four — it must be justified or rejected.

---

## The Four Cardinal Principles

### 1. Better Precision
- Position resolution must exceed software-based competitors
- Timing jitter must be deterministic and bounded — not probabilistic
- All counters sized for worst-case range, never truncated for convenience
- Analog inputs: maximum bit depth the process supports
- PID update rate: 10MHz minimum (10x industry standard)
- Encoder decode: 4x quadrature minimum
- PWM resolution: 20-bit minimum

### 2. Better Reliability
- Every external signal double-flopped — no exceptions
- Safety logic must function when CPU is dead
- No single point of failure in safety path
- Fault conditions are sticky — CPU must explicitly acknowledge
- Watchdog timers cannot be disabled by software once armed
- Error counters follow CAN/industrial spec exactly
- All state machines have explicit error/recovery states
- No combinatorial loops — all feedback paths registered

### 3. Better Speed
- PID loop: 10MHz hardware (not software)
- Communication: always implement the fastest current standard
- No polling where interrupts are possible
- No software bit-banging where hardware peripherals exist
- Bus architecture: pipelined, not blocking
- DMA capable where data volumes justify it

### 4. Future Proofed
- Prefer open standards over proprietary protocols
- Prefer the successor standard over the incumbent
  (CAN FD over CAN 2.0B, TSN over EtherCAT where possible)
- All parameters configurable at synthesis time
- All registers memory-mapped and CPU-accessible
- RTL written in portable Verilog — no vendor primitives
- Design for the 10-year horizon, not the 2-year horizon

---

## Decision Checklist

Before any architectural decision is finalised, answer:

| Question | Principle |
|---|---|
| Does this improve or maintain position/timing accuracy? | Precision |
| Does this fail safely when power, CPU, or bus fails? | Reliability |
| Is there a faster standard or approach available? | Speed |
| Will this still be relevant in 10 years? | Future Proof |

If any answer is NO — redesign before proceeding.

---

## Applied to Communication Stack

| Protocol | Precision | Reliability | Speed | Future Proof | Decision |
|---|---|---|---|---|---|
| CAN 2.0B | ❌ 8 bytes | ✅ | ❌ 1Mbit/s | ❌ legacy | REJECTED |
| CAN FD | ✅ 64 bytes | ✅ | ✅ 8Mbit/s | ✅ current std | ADOPTED |
| EtherCAT | ✅ | ✅ | ✅ 100Mbit/s | ⚠️ 10yr horizon | ADOPTED |
| TSN Ethernet | ✅ | ✅ | ✅ 1Gbit/s | ✅ 20yr horizon | ADOPTED (MAC+PHY if) |

## Applied to Motion Control

| Block | Precision | Reliability | Speed | Future Proof | Decision |
|---|---|---|---|---|---|
| Software PID | ❌ jitter | ❌ CPU dependent | ❌ ~50kHz | ❌ | REJECTED |
| Hardware PID 1MHz | ✅ | ✅ | ⚠️ | ✅ | SUPERSEDED |
| Hardware PID 10MHz | ✅✅ | ✅ | ✅ | ✅ | ADOPTED |
| 16-bit PWM | ⚠️ | ✅ | ✅ | ⚠️ | SUPERSEDED |
| 20-bit PWM | ✅✅ | ✅ | ✅ | ✅ | ADOPTED |
| 2x encoder decode | ⚠️ | ✅ | ✅ | ⚠️ | SUPERSEDED |
| 4x encoder decode | ✅✅ | ✅ | ✅ | ✅ | ADOPTED |

---

## Current Block Status

| Block | P | R | S | F | Status |
|---|---|---|---|---|---|
| PWM Engine (16ch, 20-bit) | ✅ | ✅ | ✅ | ✅ | Verified |
| Encoder Interface (4x) | ✅ | ✅ | ✅ | ✅ | Verified |
| PID Controller (10MHz) | ✅ | ✅ | ✅ | ✅ | Verified |
| Safety Subsystem | ✅ | ✅ | ✅ | ✅ | Verified |
| Tick Generator (10MHz) | ✅ | ✅ | ✅ | ✅ | Verified |
| CAN FD Controller | — | — | — | — | Next |
| EtherCAT MAC | — | — | — | — | Planned |
| TSN Interface | — | — | — | — | Planned |
| RISC-V Core | — | — | — | — | Planned |
| Top Level SoC | — | — | — | — | Planned |

---

## Version
v1.0 — established May 2026
RoboCore-1 — open source robotics SoC for factory automation
https://github.com/jyothisarath096/robocore1
