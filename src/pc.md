# Program Counter - Line by Line Explanation

This document explains every line of `pc.sv` for learning purposes.

---

## What the PC Does

The Program Counter has **two jobs**, each tied to a different pipeline stage:

| Stage      | Job                                                      |
|------------|----------------------------------------------------------|
| `EXECUTE`  | Compute `next_pc` — usually `PC+1`, or branch target     |
| `UPDATE`   | Latch the NZP condition register from a `CMP` result     |

```
                   ┌─────────────┐
   current_pc ────▶│             │
                   │             │
   decoded_pc_mux ─│             │
   decoded_nzp ────│  Program    │
   decoded_imm ────│  Counter    │──▶ next_pc
                   │             │
   alu_out[2:0] ──▶│  + nzp reg  │
   nzp_write_en ──▶│             │
                   └─────────────┘
                          ▲
                          │
                     core_state
```

The NZP register is the bridge between `CMP` and `BRnzp`:
- `CMP` writes `{N, Z, P}` flags into NZP via `alu_out[2:0]`.
- `BRnzp` checks `(nzp & decoded_nzp) != 0` to decide if the branch is taken.

---

## File Header (Lines 1-2)

```systemverilog
`default_nettype none
```
**What it does:** Disables implicit net declarations.

**Why it matters:** Without this, a typo (e.g., `nex_pc`) silently creates a new 1-bit wire instead of erroring. This catches typos at compile time.

```systemverilog
`timescale 1ns/1ns
```
**What it does:** Sets the simulation time unit and precision to 1ns.

---

## Module Declaration (Lines 14-17)

```systemverilog
module pc #(
    parameter DATA_BITS             = 8,
    parameter PROGRAM_MEM_ADDR_BITS = 8
) (
```

| Parameter                | Default | Purpose                                      |
|--------------------------|---------|----------------------------------------------|
| `DATA_BITS`              | 8       | Width of `decoded_immediate` and `alu_out`   |
| `PROGRAM_MEM_ADDR_BITS`  | 8       | Width of `current_pc` and `next_pc`          |

**Why parameters?** The GPU instantiates one PC per thread. Parameters let you change instruction memory address width (e.g., to 16 bits for a larger program) without rewriting the module.

---

## Input Ports

### Clock and Control (Lines 18-20)

```systemverilog
input wire clock,
input wire reset,
input wire enable,
```

| Signal   | Purpose                                                       |
|----------|---------------------------------------------------------------|
| `clock`  | All updates happen on rising edge                             |
| `reset`  | Force `next_pc = 0`, `nzp = 000`                              |
| `enable` | Is this thread active? (SIMT masking — inactive threads freeze) |

**SIMT context:** If a block has 3 threads but the hardware supports 4, the unused thread's `enable` is held low, freezing its PC.

---

### Pipeline State (Line 23)

```systemverilog
input wire [2:0] core_state,
```

The PC cares about two stages:
- **EXECUTE (`101`)**: compute `next_pc`
- **UPDATE (`110`)**: latch `nzp` from a CMP result

All other stages: PC does nothing.

---

### Decoded Control Signals (Lines 26-29)

```systemverilog
input wire [2:0] decoded_nzp,
input wire [DATA_BITS-1:0] decoded_immediate,
input wire decoded_nzp_write_enable,
input wire decoded_pc_mux,
```

| Signal                       | Width | Purpose                                      |
|------------------------------|-------|----------------------------------------------|
| `decoded_nzp`                | 3-bit | BRnzp condition mask (which flags fire)      |
| `decoded_immediate`          | 8-bit | Branch target address                        |
| `decoded_nzp_write_enable`   | 1-bit | CMP wants to update NZP this cycle           |
| `decoded_pc_mux`             | 1-bit | 0 = PC+1, 1 = branch target                  |

**Where do these come from?** The decoder sets them based on the opcode:

| Opcode  | `decoded_pc_mux` | `decoded_nzp_write_enable` | `decoded_nzp`       |
|---------|------------------|----------------------------|---------------------|
| `BRnzp` | `1`              | `0`                        | from `instr[11:9]`  |
| `CMP`   | `0`              | `1`                        | unused              |
| others  | `0`              | `0`                        | unused              |

---

### ALU Output (Line 32)

```systemverilog
input wire [DATA_BITS-1:0] alu_out,
```

**Purpose:** Result from the ALU. Only the bottom 3 bits matter — `alu_out[2:0]` is the fresh `{N, Z, P}` from a CMP.

**ALU encoding (from `alu.sv`):**
```
alu_out = {5'b0, (rs < rt), (rs == rt), (rs > rt)}
                  ─────N───  ─────Z────  ─────P────
                  bit 2      bit 1       bit 0
```

---

### PC Interface (Lines 35-36)

```systemverilog
input  wire [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
output reg  [PROGRAM_MEM_ADDR_BITS-1:0] next_pc
```

| Signal       | Direction | Purpose                                                |
|--------------|-----------|--------------------------------------------------------|
| `current_pc` | input     | Where the thread is now (driven by the scheduler)      |
| `next_pc`    | output    | Where the thread should be next cycle                  |

**Why is `current_pc` an input?** This module computes `next_pc`, but the *current* PC is owned by the scheduler/core, which feeds it back in. This separation makes branch divergence possible (the core can choose which thread's PC to advance).

---

## Local Parameters (Lines 40-41)

```systemverilog
localparam EXECUTE = 3'b101;
localparam UPDATE  = 3'b110;
```

Named constants for the two stages this module reacts to. Same encoding used everywhere else in the GPU.

---

## NZP Register (Line 44)

```systemverilog
reg [2:0] nzp;
```

A 3-bit register holding the most recent `{N, Z, P}` flags. Persists across instructions until the next `CMP` overwrites it. This is what `BRnzp` consults.

---

## The Always Block

### Reset Logic (Lines 47-49)

```systemverilog
if (reset) begin
    nzp     <= 3'b000;
    next_pc <= {PROGRAM_MEM_ADDR_BITS{1'b0}};
end
```

On reset:
- `nzp` cleared so any BRnzp before the first CMP is not taken (`(0 & mask) == 0`).
- `next_pc` zeroed — the thread will start at instruction 0.

**The `{PROGRAM_MEM_ADDR_BITS{1'b0}}` syntax:** This is a *replication* — it creates a vector of N zeros where N = `PROGRAM_MEM_ADDR_BITS`. With the default, it's just `8'b0`.

---

### EXECUTE Stage - Compute next_pc (Lines 52-62)

```systemverilog
if (core_state == EXECUTE) begin
    if (decoded_pc_mux) begin
        if ((nzp & decoded_nzp) != 3'b000)
            next_pc <= decoded_immediate;
        else
            next_pc <= current_pc + 1;
    end else begin
        next_pc <= current_pc + 1;
    end
end
```

**Three cases:**

| `decoded_pc_mux` | `(nzp & decoded_nzp)` | Result                       |
|------------------|-----------------------|------------------------------|
| `0` (not BRnzp)  | —                     | `next_pc = current_pc + 1`   |
| `1` (BRnzp)      | non-zero (match)      | `next_pc = decoded_immediate`|
| `1` (BRnzp)      | zero (no match)       | `next_pc = current_pc + 1`   |

**Worked example — `BRz LOOP_END` after `CMP R0, R1` where R0 == R1:**
1. `CMP` runs in EXECUTE → ALU produces `alu_out = 8'b00000_010` (Z set).
2. UPDATE stage latches `nzp = 3'b010`.
3. Next instruction `BRz LOOP_END` decodes: `decoded_pc_mux = 1`, `decoded_nzp = 3'b010`, `decoded_immediate = LOOP_END`.
4. EXECUTE: `(010 & 010) == 010 != 0` → branch taken, `next_pc = LOOP_END`.

**Worked example — same `BRz` but R0 != R1 and R0 < R1:**
1. CMP produces `alu_out = 8'b00000_100` (N set).
2. UPDATE latches `nzp = 3'b100`.
3. EXECUTE: `(100 & 010) == 000` → not taken, `next_pc = current_pc + 1`.

---

### UPDATE Stage - Latch NZP (Lines 65-69)

```systemverilog
if (core_state == UPDATE) begin
    if (decoded_nzp_write_enable) begin
        nzp <= alu_out[2:0];
    end
end
```

**When does this fire?**
- Only on a `CMP` instruction (the only opcode that sets `decoded_nzp_write_enable`).
- The decoder also sets `decoded_alu_output_selector = 1` for CMP, so the ALU runs in comparison mode and produces NZP flags in `alu_out[2:0]`.

**Why latch in UPDATE and not EXECUTE?** Same reason the register file writes back in UPDATE — it's the conventional "writeback" point in the pipeline. Keeping all writes in one stage avoids hazards.

---

## Pipeline Timing Diagram

```
Clock:    ──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──
            └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘

State:    FETCH│DECODE│REQUEST│ WAIT │EXECUTE│UPDATE│
                                       │  ▲   │  ▲
                                       │  │   │  │
PC action:                             │ Pick │Latch
                                       │next_pc│ nzp
                                       │       │(if CMP)
```

---

## Hardware Synthesized

```
                    ┌────────────────────────────────────┐
                    │           PROGRAM COUNTER           │
                    │                                     │
   current_pc ─────▶│     ┌─────┐                         │
                    │     │ +1  │──┐                      │
                    │     └─────┘  │                      │
                    │              │  ┌─────┐             │
   decoded_imm ────▶│──────────────┴─▶│ MUX │──▶ next_pc │
                    │                 └──┬──┘             │
                    │                    │                │
                    │   ┌─────────┐      │                │
   decoded_nzp ────▶│──▶│  AND    │      │                │
                    │   │  != 0   │──────┘                │
        nzp ───────▶│──▶│         │  (branch-taken)       │
                    │   └─────────┘                       │
                    │       ▲                             │
   decoded_pc_mux ──┼───────┘                             │
                    │                                     │
                    │   ┌─────────┐                       │
   alu_out[2:0] ───▶│──▶│  NZP    │                       │
   nzp_write_en ───▶│──▶│  reg    │──┐                    │
                    │   └─────────┘  │                    │
                    │                └─────────────────┐  │
                    │                                  │  │
   core_state ─────▶│ (timing for both writes)         │  │
   clock ──────────▶│                                  │  │
   reset ──────────▶│                                  │  │
   enable ─────────▶│                                  │  │
                    └──────────────────────────────────┴──┘
```

---

## Common Gotchas

1. **NZP is sticky.** It only changes on CMP. A branch can use NZP from a CMP many instructions earlier — fine if intentional, a bug if not. Convention: always run CMP immediately before the BRnzp that needs it.

2. **Empty mask never branches.** `decoded_nzp = 000` makes `(nzp & 000) == 000`, so the branch is *never* taken regardless of NZP. This is how `NOP`-like behavior emerges if a BRnzp is decoded with all condition bits clear.

3. **Full mask `nzp = 111` is unconditional branch.** Equivalent to `JMP` once any flag is set. After reset NZP is `000` so even `BR nzp` won't branch until the first CMP.

4. **PC arithmetic wraps.** With `PROGRAM_MEM_ADDR_BITS = 8`, `current_pc + 1` from `255` gives `0`. Programs longer than 256 instructions need a wider PC (bump the parameter).

5. **`current_pc` is an input, not internal state.** The PC module computes `next_pc` but doesn't *hold* the current PC. The core's scheduler owns the live PC and feeds it back in each cycle. If you forget to drive `current_pc`, you'll get `X`s in simulation.

6. **Reset takes precedence over enable.** Even if `enable = 0`, a `reset` will still clear NZP and next_pc. Matches the behavior in `registers.sv`.
