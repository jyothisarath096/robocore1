# RoboCore-1 Production Formal Verification Suite

## Overview

This is the full production-grade formal verification suite for RoboCore-1,
required before silicon submission. It replaces the basic BMC-30 proofs with
industry-standard property coverage across all four pillars.

---

## Suite 1: AXI Protocol Compliance (`axi_proto.sby`)
**Mode:** PROVE depth=40 | **Engine:** smtbmc z3

Full ARM AXI4-Lite protocol compliance using ZipCPU-style properties.

| ID  | Property | ARM Spec Ref |
|-----|----------|--------------|
| P1  | Write SM valid states (0-2 only) | §A3 |
| P2  | Read SM valid states (0-2 only) | §A3 |
| P3  | BRESP ∈ {OKAY, SLVERR} only — never EXOKAY/DECERR | §A3.4.4 |
| P4  | RRESP ∈ {OKAY, SLVERR} only | §A3.4.4 |
| P5  | BVALID sticky until BREADY | §A3.2.2 |
| P6  | RVALID sticky until RREADY | §A3.2.2 |
| P7  | BVALID only asserted after accepted write | §A3.3 |
| P8  | No new write handshake while BVALID pending | §A3.3 single-outstanding |
| P9  | AWREADY == WREADY always (AXI4-Lite) | AXI4-Lite spec |
| P10 | irq_out == OR(irq_active) | Design spec |
| P11 | irq_active & irq_mask == 0 always | Design spec |
| P12 | CHIP_ID always reads 0xAC010002 | Register spec |
| P13 | RRESP=SLVERR on unmapped read BLOCK>7 | Design spec |
| P14 | BRESP=SLVERR on unmapped write BLOCK>7 | Design spec |
| P15 | Scratch register round-trips (write → readback matches) | Design spec |
| P16 | wd_pet is a pulse — cleared when not in WR_DECODE | Safety spec |

**Assumptions (master model):**
- A1: AWVALID stable until AWREADY
- A2: WVALID stable until WREADY
- A3: ARVALID stable until ARREADY
- A4: AWVALID == WVALID always (AXI4-Lite simultaneous AW+W)
- A5: Address stable until handshake
- A6: WSTRB no-X

---

## Suite 2: Safety SIL2 (`safety_sil2.sby`)
**Mode:** PROVE depth=40 | **Engine:** smtbmc z3

IEC 61508 SIL2-grade formal safety properties.

| ID      | Property | IEC 61508 Ref |
|---------|----------|---------------|
| SIL2-1  | ESTOP → safe_state within 2 cycles | SIL2 diagnostic coverage |
| SIL2-2  | safe_state is STICKY while ESTOP active | SIL2 latching requirement |
| SIL2-3  | fault_clear has NO EFFECT while ESTOP active | SIL2 inhibit |
| SIL2-4  | fault_clear has NO EFFECT while safe_state asserted | SIL2 inhibit |
| SIL2-5  | Watchdog ALWAYS expires after timeout (no pet) | SIL2 WD requirement |
| SIL2-6  | WD fault bits are STICKY in fault_reg | SIL2 latching |
| SIL2-7  | Brownout → safe_state within 2 cycles | SIL2 diagnostic |
| SIL2-8  | fault_in[0..2] independently latch into fault_reg | SIL2 coverage |
| SIL2-9  | Double-flop synchronizer not bypassed | SIL2 immunity |
| SIL2-10 | fault_reg only clearable when system is safe | SIL2 inhibit |
| SIL2-11 | Any fault_in[0..5] immediately asserts safe_state (combinatorial) | SIL2 response time |
| SIL2-12 | safe_state exactly matches combinatorial definition | SIL2 traceability |

---

## Suite 3: DMA Correctness (`dma.sby`)
**Mode:** BMC depth=50 | **Engine:** smtbmc z3

No data loss, correct ordering, auto-reload, chaining.

| ID     | Property |
|--------|----------|
| DMA-1  | Sequencer SM always in valid states (0-12) |
| DMA-2  | No simultaneous read + write AXI transactions |
| DMA-3  | seq_words decrements by exactly 1 per write response |
| DMA-4  | Auto-reload resets ch_desc to 0 |
| DMA-5  | Chain increments ch_desc by 1 |
| DMA-6  | irq_complete fires at SEQ_DONE |
| DMA-7  | irq_complete and irq_chain are single-cycle pulses |
| DMA-8  | Timestamp write (SEQ_TSWRITE) only when ctrl[11] set |
| DMA-9  | DMA master AWVALID/ARVALID stable until READY (master must not violate AXI) |
| DMA-10 | No transfer starts on a disabled channel |
| DMA-11 | ch_pending cleared when sequencer loads descriptor |
| DMA-12 | Round-robin pointer advances correctly (mod 8) |
| DMA-13 | Config slave responds with bvalid after aw+w |

---

## Suite 4: Cover Completeness (`cover_completeness.sby`)
**Mode:** COVER depth=60 | **Engine:** smtbmc z3

Every register, every IRQ, every safety state must be reachable.

| Category | Count | Description |
|----------|-------|-------------|
| AXI states | 6 | All WR/RD SM states |
| Register writes | 16 | All writable regs in blocks 0-7 |
| Register reads | 16 | All readable regs in blocks 0-7 |
| SLVERR paths | 2 | Unmapped read + write |
| IRQ paths | 7 | Rise, fall, each bit, masked |
| Safety paths | 12 | Every fault source + recovery |

---

## Running on RunPod

```bash
# 1. Start RunPod with Ubuntu 20.04, ~4GB RAM, A4000 GPU optional
# 2. Install oss-cad-suite
wget https://github.com/YosysHQ/oss-cad-suite-build/releases/download/2024-01-15/oss-cad-suite-linux-x64-20240115.tgz -O oss-cad.tgz
tar xzf oss-cad.tgz
export PATH=/workspace/oss-cad-suite/bin:$PATH

# 3. Clone and run
git clone https://github.com/jyothisarath096/robocore1.git /workspace
chmod +x /workspace/formal/prod/run_formal_prod.sh
/workspace/formal/prod/run_formal_prod.sh

# Run individual suites
/workspace/formal/prod/run_formal_prod.sh axi
/workspace/formal/prod/run_formal_prod.sh safety
/workspace/formal/prod/run_formal_prod.sh dma
/workspace/formal/prod/run_formal_prod.sh cover
```

---

## Pass Criteria (Go/No-Go for ChipIgnite)

| Suite | Mode | Required |
|-------|------|----------|
| axi_proto | PROVE | All 16 assertions PROVEN |
| safety_sil2 | PROVE | All 12 SIL2 assertions PROVEN |
| dma | BMC | All 13 assertions pass BMC-50 |
| cover_completeness | COVER | All cover goals REACHED |

**If any assertion FAILS:** Do NOT submit. The failure trace from SymbiYosys
will show the exact RTL path that violates the property. Fix the RTL and rerun.

---

## Known Limitations

1. **DMA formal uses BMC (not PROVE)** — the `ch_pending` multi-driver
   in generate blocks prevents induction. BMC-50 provides strong bounded
   confidence. The 7/7 simulation results provide complementary coverage.

2. **Watchdog timeout set to 3 cycles in safety formal** — real chip uses
   24-bit timeouts (millions of cycles). The proof is parameterized by
   timeout value; BMC cannot exhaustively cover 2^24 counts. The key
   property (must expire eventually) is proven via the starvation counter.

3. **AXI: PROVE mode requires statedt flag** — `smtbmc --statedt z3`
   enables state-dependent temporal induction needed for liveness properties.
