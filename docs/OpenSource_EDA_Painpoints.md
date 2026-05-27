# Open Source EDA Toolchain — Pain Points & Recommendations
## RoboCore-1 Development Experience Report
**Project:** RoboCore-1 RISC-V Robotics SoC  
**Process:** SkyWater SKY130 130nm  
**Toolchain:** OpenLane (Yosys + OpenROAD + Magic + KLayout)  
**Date:** May 2026  
**Author:** RoboCore-1 Engineering Team

---

## Executive Summary

During the development of RoboCore-1, a 135,000-cell RISC-V robotics SoC on SKY130 130nm, we encountered numerous critical failures, crashes, and workarounds across every layer of the open source EDA toolchain. This document catalogues each pain point, its root cause, the workaround applied, and the recommended fix for a next-generation EDA toolchain.

Total synthesis runs attempted: **12+**  
Total Vast.ai compute cost: **~$15**  
Total engineering time lost to tool issues: **~40 hours**

---

## 1. Yosys — Synthesis

### 1.1 Multi-Dimensional Array Ports Rejected
**Tool:** Yosys 0.30  
**Severity:** Critical — blocks synthesis  
**Symptom:**
```
Error: Array ports not supported in synthesis
```
**Root Cause:** Yosys cannot synthesize Verilog modules with array-typed ports (e.g., `input [31:0] data [0:7]`). All array ports must be manually flattened to packed vectors before synthesis.

**Workaround Applied:**
```verilog
// Before (fails)
input [31:0] pid_target [0:7];

// After (works)
input [255:0] pid_target_flat; // 8 × 32 = 256 bits
```
Required manual flattening of all PID, encoder, safety, and watchdog array ports across 6 modules.

**Recommended Fix for Custom EDA:**
- Automatic array port flattening as a pre-synthesis pass
- Detect array ports and emit flattened equivalents with index macros
- Zero user intervention required

---

### 1.2 Multiple Driver Detection Causes Silent Optimization
**Tool:** Yosys 0.30  
**Severity:** High — functional bug, silent  
**Symptom:**
```
Warning: Driver-driver conflict for \u_dma.ch_desc[4][3] between cell 
$flatten\u_dma.$procdff$166482.Q and constant 1'0: Resolved using constant.
```
**Root Cause:** When a register (`ch_desc`) is driven by two separate `always` blocks (sequencer and config slave), Yosys resolves the conflict by forcing the signal to constant 0. This silently breaks functionality — the DMA descriptor index was always 0, disabling chaining and auto-reload.

**Workaround Applied:** Removed `ch_desc` reset from config slave always block. Added reset to sequencer always block only. Single driver per register enforced.

**Recommended Fix for Custom EDA:**
- Detect multiple-driver conflicts and **error** rather than silently resolve
- Provide clear error: "Register X driven by always blocks at lines Y and Z — resolve to single driver"
- Offer automated fix suggestion: move reset to the primary always block

---

### 1.3 Unused Module Synthesis (PicoRV32 MUL/DIV)
**Tool:** Yosys 0.30  
**Severity:** High — causes 50,000+ extra cells  
**Symptom:** PicoRV32 with `ENABLE_MUL=0` still synthesizes `picorv32_pcpi_mul`, `picorv32_pcpi_fast_mul`, `picorv32_pcpi_div` modules, adding ~50,000 cells.

**Root Cause:** Yosys synthesizes all defined modules in the file regardless of whether they're instantiated or parameterized away. Generate blocks don't fully exclude unused modules from synthesis.

**Workaround Applied:** Accepted extra cells, increased die size to 6×6mm to accommodate.

**Recommended Fix for Custom EDA:**
- True dead-code elimination at module level
- Trace instantiation graph from top module, exclude unreachable modules
- Report: "Module X defined but never instantiated — excluded from synthesis"

---

### 1.4 Latch Inference Causes Synthesis Checker Failure
**Tool:** Yosys + OpenLane checker  
**Severity:** Medium — blocks flow  
**Symptom:**
```
[ERROR]: Step 1 (synthesis) failed — latches detected
$_DLATCH_N_ inferred in robocore1_top
```
**Root Cause:** The AXI arbiter's `arb_dma` register had an incomplete sensitivity list causing latch inference. OpenLane's `check_synth_misc` rejects any design with inferred latches.

**Workaround Applied:** Set `QUIT_ON_SYNTH_CHECKS: 0` in config. Fixed RTL to ensure complete assignments in all branches.

**Recommended Fix for Custom EDA:**
- Latch inference should be a **warning with fix suggestion**, not a hard error
- Automatically suggest: "Add else branch to always block at line X to prevent latch"
- Offer one-click fix for common latch patterns

---

### 1.5 Descriptor RAM Synthesized as Registers (Not SRAM)
**Tool:** Yosys 0.30  
**Severity:** High — causes 100,000+ extra cells  
**Symptom:** `reg [31:0] desc_ram [0:511]` synthesized as 16,384 flip-flops instead of inferred SRAM, adding ~100,000 cells.

**Root Cause:** Yosys's memory inference heuristics failed to match the flat array access pattern (`desc_ram[ch*64 + desc*4 + word]`) as a RAM. Computed indices prevent SRAM inference.

**Workaround Applied:** Reduced `DESC_DEPTH` from 16 to 4 to reduce cell count from 160k to 135k.

**Recommended Fix for Custom EDA:**
- Smarter RAM inference that handles computed index expressions
- Explicit `(* ram_style = "block" *)` attribute support
- Warning when large arrays are synthesized as registers: "Array of 512× 32-bit synthesized as FFs — consider using RAM macro"

---

## 2. OpenLane — Flow Orchestration

### 2.1 No Resume from Failed Step
**Tool:** OpenLane v1.0.2  
**Severity:** High — wastes hours of compute  
**Symptom:** Flow fails at step 32 (STA). Must restart from step 1 (synthesis), wasting 2+ hours.

**Root Cause:** OpenLane's `-from` and `-to` flags were removed in v1.0.2. No checkpoint/resume capability exists.

**Workaround Applied:** Used `-tag` and `-overwrite` flags, which still restarts from step 1 in most cases.

**Recommended Fix for Custom EDA:**
- Proper checkpoint system — save state after every step
- Resume from any step: `flow.tcl --resume-from detailed_routing`
- Automatic checkpoint on Ctrl+C
- Step-level caching: skip synthesis if RTL unchanged

---

### 2.2 Buffered Log — No Real-Time Progress
**Tool:** OpenLane v1.0.2  
**Severity:** Medium — makes monitoring impossible  
**Symptom:** `openlane.log` only updates in batches. During multi-hour routing steps, no indication of progress for 30+ minutes.

**Workaround Applied:** Built custom `auto_save.sh` monitor script that polls individual step logs every 60 seconds.

**Recommended Fix for Custom EDA:**
- Real-time streaming log output
- Progress bar per step: "Global routing: 67% complete, estimated 23 min remaining"
- WebSocket-based live dashboard accessible from any browser
- Push notifications (email/webhook) on completion or failure

---

### 2.3 Config Changes Don't Apply to In-Progress Run
**Tool:** OpenLane v1.0.2  
**Severity:** Medium — causes wasted runs  
**Symptom:** Updating `config.json` during a run has no effect. Must kill and restart entire flow.

**Workaround Applied:** Kill flow, update config, restart from scratch.

**Recommended Fix for Custom EDA:**
- Hot-reload config between steps
- "Apply config change from next step" option
- Config diff viewer: show what changed since last run

---

### 2.4 Linter Rejects SKY130 Standard Cells
**Tool:** Verilator (via OpenLane)  
**Severity:** Medium — blocks flow start  
**Symptom:**
```
%Error: Can't resolve module reference: 'sky130_fd_sc_hd__dlclkp_1'
```
The ICG (clock gate) cell from SKY130 standard library is unknown to Verilator, causing lint failure before synthesis even starts.

**Workaround Applied:** Created manual blackbox stub `icg_bb.v` for every SKY130 special cell used.

**Recommended Fix for Custom EDA:**
- Auto-load PDK cell stubs before linting
- Maintain a library of blackbox stubs for all standard cells in supported PDKs
- Zero user intervention for PDK cells

---

### 2.5 No Auto-Save on Completion
**Tool:** OpenLane v1.0.2  
**Severity:** High — GDS lost when instance terminates  
**Symptom:** On cloud instances (Vast.ai), if the instance is destroyed before the user manually copies results, all outputs are lost. Lost 2 complete synthesis runs worth of results.

**Workaround Applied:** Custom `auto_save.sh` script that monitors for manufacturability.rpt and auto-pushes to GitHub.

**Recommended Fix for Custom EDA:**
- Built-in cloud storage integration (S3, GCS, GitHub)
- Auto-push results after every completed step
- Configurable: `OUTPUT_BUCKET: s3://my-bucket/robocore1/`
- Email notification with download link when complete

---

## 3. OpenROAD — Place and Route

### 3.1 Global Placement Diverges on Dense Designs
**Tool:** OpenROAD (RePlAce)  
**Severity:** Critical — blocks all routing  
**Symptom:**
```
[ERROR GPL-0305] RePlAce diverged at newStepLength.
```
**Root Cause:** With 159,000 cells on a 5.5×5.5mm die (density ~0.30), the Nesterov solver diverges and cannot converge. Overflow stays at ~0.12 and never reduces.

**Workaround Applied:** Increased die to 6×6mm, reduced density to 0.28. Reduced cell count by disabling PicoRV32 MUL/DIV.

**Recommended Fix for Custom EDA:**
- Automatic density estimation before placement: "At current cell count, recommend die area of X mm²"
- Adaptive density target — automatically reduce if convergence fails
- Better divergence detection with graceful fallback: "Diverged at iteration 3000, retrying with lower density"
- ML-based placement initialization using historical successful placements

---

### 3.2 Routing Resizer Crashes (Segfault) on Large Designs
**Tool:** OpenROAD resizer_routing_design.tcl  
**Severity:** Critical — blocks routing  
**Symptom:**
```
sta::sourceTclFile in openroad
Tcl_Main in libtcl8.5.so
[segfault]
```
**Root Cause:** The global routing resizer crashes with a segfault after 60-90 minutes on designs with 135,000+ cells. TCL stack overflow or memory corruption in the resizer.

**Workaround Applied:** Disabled routing resizer entirely (`GLB_RESIZER_TIMING_OPTIMIZATIONS: 0`). Accepted timing degradation.

**Recommended Fix for Custom EDA:**
- Memory-safe resizer implementation (Rust instead of C++)
- Incremental resizing — process in chunks of 10,000 cells
- Timeout with graceful partial result: "Resizer timeout after 30 min — applied optimizations to 80% of critical paths"
- Crash recovery — checkpoint resizer state every 5 minutes

---

### 3.3 Global Router Fails with Overflow on Large Designs
**Tool:** OpenROAD FastRoute  
**Severity:** Critical — blocks detailed routing  
**Symptom:**
```
[INFO GRT-0101] Running extra iterations to remove overflow.
[INFO GRT-0103] Extra Run for hard benchmark.
[segfault after 90+ minutes]
```
**Root Cause:** Met5 routing resources reduced by 57% due to macro blockages. FastRoute cannot find legal routes for all nets and eventually crashes.

**Workaround Applied:** Recovered routed DEF from results directory. Used Magic manually to generate GDS from DEF.

**Recommended Fix for Custom EDA:**
- Better routing resource analysis before routing: "Met5 utilization will be 57% — consider rerouting macros or increasing die"
- Partial routing recovery — save progress every 10,000 nets routed
- Alternative routing modes: fewer optimization passes for faster completion
- Dead-net detection: skip routing for nets with no load

---

### 3.4 No Incremental Routing
**Tool:** OpenROAD  
**Severity:** High — wastes hours  
**Symptom:** Any RTL change requires full re-route from scratch. A 1-line RTL fix triggers 3+ hours of re-routing.

**Workaround Applied:** Accept full re-routes. Plan RTL changes carefully to batch them.

**Recommended Fix for Custom EDA:**
- Incremental routing: re-route only affected nets when RTL changes
- Net change detection: "15 nets affected by RTL change — incremental route in ~8 min"
- Hierarchy-aware routing: re-route only changed module's nets

---

### 3.5 Clock Tree Synthesis Ignores Gated Clocks
**Tool:** OpenROAD TritonCTS  
**Severity:** Medium — timing analysis inaccurate  
**Symptom:** CTS treats gated clocks (`can_gclk`, `ec_gclk`, `dma_gclk`) as primary clocks and builds separate clock trees, inflating cell count and power estimates.

**Workaround Applied:** Accepted extra clock trees. Power estimate less accurate.

**Recommended Fix for Custom EDA:**
- Native ICG-aware CTS
- Detect `dlclkp` cells and treat downstream as gated clock domain
- Optimize clock tree insertion only for always-on paths
- Accurate power estimation per clock domain

---

## 4. Magic — GDS Generation

### 4.1 GDS Streaming Crashes on Large Designs
**Tool:** Magic 8.3  
**Severity:** High — GDS not generated  
**Symptom:** OpenLane's Magic GDS streaming step crashes after completing routing. No error message — process just exits.

**Root Cause:** Memory exhaustion during GDS streaming of a 6×6mm die with 135,000 cells and SKY130 SRAM macros.

**Workaround Applied:** Ran Magic manually outside OpenLane with the routed DEF file. Successfully generated 49MB GDS.

**Recommended Fix for Custom EDA:**
- Streaming GDS generation — write GDS in chunks, not all-at-once
- Memory limit configuration: `GDS_MAX_MEMORY: 8GB`
- Progress reporting: "GDS streaming: 45% complete, 234MB written"
- Parallel GDS generation for hierarchical designs

---

### 4.2 KLayout XOR Check Fails on SRAM Macros
**Tool:** KLayout (via OpenLane step 35)  
**Severity:** Medium — false failure  
**Symptom:**
```
[ERROR]: There are XOR differences in the design
```
**Root Cause:** KLayout XOR check compares Magic GDS with KLayout GDS. SKY130 SRAM macros have different cell representations in each tool, causing false XOR differences.

**Workaround Applied:** Set `QUIT_ON_XOR_ERROR: 0` in config.

**Recommended Fix for Custom EDA:**
- Macro-aware XOR check — exclude known-good hard macros from comparison
- Whitelist: `XOR_EXCLUDE_MACROS: [sky130_sram_*, sram_wrapper]`
- Report only actual routing differences, not macro representation differences

---

## 5. PDK Integration

### 5.1 SRAM Macro Blackbox Override
**Tool:** Yosys + OpenLane  
**Severity:** Critical — SRAM synthesized as logic  
**Symptom:**
```
Replacing existing blackbox module \sram_wrapper at sram_stubs.v
```
**Root Cause:** `sram_stubs.v` in the `src/` directory overrides the proper blackbox stub with full RTL, causing Yosys to synthesize the SRAM internals as standard cells (~50,000 extra cells).

**Workaround Applied:** Removed `sram_stubs.v` from OpenLane `src/` directory. Created proper blackbox stub in `macros/verilog/`.

**Recommended Fix for Custom EDA:**
- Strict blackbox enforcement: once a module is declared blackbox, reject any subsequent definition
- Error: "Module sram_wrapper redefined at src/sram_stubs.v — conflicts with blackbox at macros/verilog/sram_wrapper_bb.v"
- Separate blackbox and synthesis source directories enforced by tool

---

### 5.2 PDK Version Management
**Tool:** ciel (PDK manager)  
**Severity:** Medium — reproducibility risk  
**Symptom:** Different PDK versions produce different timing results. No automatic version pinning in synthesis runs.

**Workaround Applied:** Manually specified exact PDK commit hash: `0fe599b2afb6708d281543108caf8310912f54af`

**Recommended Fix for Custom EDA:**
- Automatic PDK version locking in run directory
- Lock file: `pdk.lock` with exact commit hash, verified on each run
- Warning if PDK version changed since last successful run
- PDK changelog integration: "PDK updated — 3 timing model changes affect your design"

---

## 6. Cloud Infrastructure

### 6.1 No Native Cloud Integration
**Tool:** OpenLane (all versions)  
**Severity:** High — manual effort, lost results  
**Symptom:** All results stored locally in Docker container. If instance terminates (crash, out of credits, timeout), all results lost permanently. Lost 2 complete synthesis runs.

**Workaround Applied:** Custom bash auto-save script polling every 60 seconds, pushing to GitHub via personal access token.

**Recommended Fix for Custom EDA:**
- Native S3/GCS/GitHub integration built into flow
- Step-level artifact upload: upload DEF, netlist, reports after each step
- Configurable: `ARTIFACT_STORAGE: github://user/repo/branch`
- Cost estimation before run: "Estimated 4 hours at $0.30/hr = ~$1.20"

---

### 6.2 SSH Disconnection Kills Flow
**Tool:** OpenLane (Docker-based)  
**Severity:** High — requires tmux workaround  
**Symptom:** SSH disconnection during routing kills the Docker container's interactive session, sometimes killing the flow process.

**Workaround Applied:** tmux sessions, `nohup`, Docker daemon mode.

**Recommended Fix for Custom EDA:**
- Flow runs as a daemon by default, not interactive
- Web-based UI accessible from any browser
- No SSH required — submit job, monitor via web dashboard
- Mobile notifications on completion

---

### 6.3 No Cost Visibility
**Tool:** Vast.ai + OpenLane  
**Severity:** Medium — budget overruns  
**Symptom:** No way to know how long a run will take or how much it will cost before starting. Ran out of credits mid-route multiple times.

**Workaround Applied:** Manual credit monitoring, destroying instances when low.

**Recommended Fix for Custom EDA:**
- Pre-run estimation: "Based on cell count and die size, estimated runtime: 3.5 hours"
- Budget limit: `MAX_COST: $5.00 — stop if exceeded`
- Cost alerts: notify at 50%, 80%, 100% of budget
- Resume from checkpoint if budget exhausted — don't lose work

---

## 7. Summary Table

| Tool | Issue | Severity | Lost Time |
|---|---|---|---|
| Yosys | Array ports rejected | Critical | 4 hours |
| Yosys | Multiple driver silent fix | Critical | 6 hours |
| Yosys | Unused modules synthesized | High | 3 hours |
| Yosys | SRAM inferred as registers | High | 2 hours |
| OpenLane | No resume from step | High | 8 hours |
| OpenLane | No auto-save | High | 4 hours |
| OpenLane | Linter rejects PDK cells | Medium | 1 hour |
| OpenROAD | Placement diverges | Critical | 4 hours |
| OpenROAD | Resizer segfault | Critical | 3 hours |
| OpenROAD | Router overflow crash | Critical | 5 hours |
| Magic | GDS streaming crash | High | 2 hours |
| KLayout | False XOR failures | Medium | 1 hour |
| PDK | SRAM blackbox override | Critical | 3 hours |
| Cloud | No native integration | High | 4 hours |

**Total engineering time lost to tool issues: ~50 hours**  
**Total compute credits wasted on failed runs: ~$12**

---

## 8. Recommended Architecture for Next-Generation EDA

Based on our experience, a next-generation open EDA toolchain should be built on these principles:

### 8.1 Memory Safety
All core tools (synthesis, P&R, router) should be implemented in **Rust** or **modern C++** with sanitizers. The segfaults we experienced in OpenROAD are unacceptable in production tools.

### 8.2 Incremental Everything
Every step should support incremental operation:
- Incremental synthesis (only re-synthesize changed modules)
- Incremental placement (only re-place affected cells)
- Incremental routing (only re-route affected nets)

### 8.3 AI-Assisted Closure
- Predict timing violations before routing using ML
- Suggest floorplan based on historical successful runs
- Auto-tune synthesis strategy based on timing results

### 8.4 Cloud-Native Architecture
- Jobs submitted via API, not SSH
- Results stored in cloud storage automatically
- Web dashboard for monitoring
- Cost estimation and budget controls

### 8.5 Developer Experience First
- Clear error messages with fix suggestions
- One-command setup: `eda init --pdk sky130 --design robocore1`
- IDE integration (VS Code extension)
- Simulation integrated with synthesis

### 8.6 PDK Abstraction Layer
- Single RTL source, multiple target PDKs
- Automatic cell mapping between PDK libraries
- PDK version management like npm/pip

---

## 9. Conclusion

The open source EDA toolchain (OpenLane + Yosys + OpenROAD + Magic) is a remarkable achievement that enabled RoboCore-1 to go from RTL to silicon at zero cost. However, for commercial-grade chip development, these tools have critical reliability, usability, and performance gaps.

The ~50 hours of engineering time lost to tool issues — on a single chip — represents a massive opportunity. At typical engineering rates ($150/hr), that's **$7,500 lost per chip per engineer**. For a chip company doing 10 designs per year with 5 engineers, that's **$375,000/year** in wasted engineering time.

A next-generation EDA toolchain that solves these problems — built by engineers who have actually experienced the pain — could capture significant value in the rapidly growing open silicon market.

**RoboCore-1 is not just a chip. It's the specification for the EDA tools we wish had existed.**

---

*Document prepared by the RoboCore-1 Engineering Team*  
*May 2026*  
*Based on 12+ synthesis runs, ~$15 cloud compute, ~50 hours engineering time*
