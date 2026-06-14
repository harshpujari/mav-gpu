# Load / Store Unit - Line by Line Explanation

This document explains every line of `lsu.sv` for learning purposes.

---

## What the LSU Does

There is **one LSU per thread**. It is the only unit that talks to *data*
memory, handling the two memory instructions:

| Instruction      | Effect                                        |
|------------------|-----------------------------------------------|
| `LDR rd, [rs]`   | read `data_mem[rs]` → `lsu_out` (→ register file) |
| `STR [rs], rt`   | write `data_mem[rs] = rt`                      |

```
                    ┌──────────────────────┐
   rs (address) ───▶│                       │──▶ mem_read_valid / address
   rt (data) ──────▶│                       │◀── mem_read_ready / data
                    │   Load / Store        │
   decoded_mem_ ───▶│   Unit                │──▶ mem_write_valid / addr / data
   read/write_en    │                       │◀── mem_write_ready
                    │                       │
   core_state ─────▶│                       │──▶ lsu_out  (loaded value)
   enable ─────────▶│                       │──▶ lsu_state (busy indicator)
                    └──────────────────────┘
```

The LSU uses the **same valid → ready handshake** as the fetcher, but on the
*data* memory and with **two channels** (read and write). It exposes its own
`lsu_state` so the scheduler can stall the WAIT stage until memory settles.

---

## File Header (Lines 1-2)

```systemverilog
`default_nettype none
`timescale 1ns/1ns
```
Disable implicit nets (catch typos at compile time) and set the simulation time
unit/precision to 1ns. Same boilerplate as every other module.

---

## Module Declaration (Line 16)

```systemverilog
module lsu (
```

**No parameters here** — the LSU is hard-wired to the data memory width (8-bit
address, 8-bit data). Unlike the fetcher, everything is a fixed 8 bits.

---

## Input / Output Ports

### Clock and Control (Lines 17-21)

```systemverilog
input  wire clock,
input  wire reset,
input  wire enable,
input  wire [2:0] core_state,
```

| Signal       | Purpose                                                  |
|--------------|----------------------------------------------------------|
| `clock`      | Updates on the rising edge                               |
| `reset`      | Force back to IDLE, clear all outputs                    |
| `enable`     | Is this thread active? (SIMT masking — inactive lanes freeze) |
| `core_state` | Which pipeline stage the core is in                      |

**Why an `enable` (when the fetcher had none)?** The LSU is **per-thread**. In a
4-thread block running on 3 elements, the unused lane's `enable` is held low so
its LSU never issues a phantom memory request.

---

### Decoded Control Signals (Lines 24-25)

```systemverilog
input  wire decoded_mem_read_enable,    // LDR
input  wire decoded_mem_write_enable,   // STR
```

These come from the decoder. **Mutually exclusive** — a given instruction is
either a load, a store, or neither. If both are 0, the LSU stays idle.

---

### Operands (Lines 28-29)

```systemverilog
input  wire [7:0] rs,    // Memory address
input  wire [7:0] rt,    // Data to store (STR only)
```

Read out of the register file in the REQUEST stage:
- `rs` is **always** the memory address (for both LDR and STR).
- `rt` is the value to store (used by STR only; ignored by LDR).

---

### Data-Memory Read Channel (Lines 32-35)

```systemverilog
output reg        mem_read_valid,
output reg [7:0]  mem_read_address,
input  wire       mem_read_ready,
input  wire [7:0] mem_read_data,
```

The read side of the handshake — identical in spirit to the fetcher's channel.

| Signal             | Dir | Meaning                                  |
|--------------------|-----|------------------------------------------|
| `mem_read_valid`   | out | "I want to read"                         |
| `mem_read_address` | out | from `rs`                                |
| `mem_read_ready`   | in  | "data is valid"                          |
| `mem_read_data`    | in  | the loaded byte                          |

---

### Data-Memory Write Channel (Lines 38-41)

```systemverilog
output reg        mem_write_valid,
output reg [7:0]  mem_write_address,
output reg [7:0]  mem_write_data,
input  wire       mem_write_ready,
```

The write side. Same handshake, plus a `mem_write_data` output carrying `rt`.

---

### Results (Lines 44-47)

```systemverilog
output reg [7:0]  lsu_out,
output reg [1:0]  lsu_state
```

| Signal      | Purpose                                                    |
|-------------|------------------------------------------------------------|
| `lsu_out`   | The loaded value (LDR), forwarded to the register file     |
| `lsu_state` | This LSU's transaction state — read by the **scheduler**   |

**Why expose `lsu_state`?** The scheduler must stall in the WAIT stage until
*every* thread's memory traffic is done. It does that by watching each LSU's
`lsu_state` (see `scheduler.sv`).

---

## Pipeline Stages We Care About (Lines 50-52)

```systemverilog
localparam REQUEST = 3'b011;    // Kick off the memory transaction
localparam UPDATE  = 3'b110;    // Transaction retires here
```

The LSU only reacts to two of the six `core_state` stages: it *arms* in REQUEST
and *retires* in UPDATE. The actual bus activity happens internally in between.

---

## LSU State Machine (Lines 54-58)

```systemverilog
localparam LSU_IDLE       = 2'b00,   // Nothing in flight
           LSU_REQUESTING = 2'b01,   // Drive the request onto the bus
           LSU_WAITING    = 2'b10,   // Request issued, waiting for ready
           LSU_DONE       = 2'b11;   // Transaction complete, holding result
```

A 4-state handshake. Note `lsu_state` is the **output reg** declared in the port
list (line 47) — there is no separate internal copy.

```
   IDLE ─(REQUEST stage)─▶ REQUESTING ─(next cycle)─▶ WAITING
    ▲                                                   │
    │                                          (mem_*_ready)
   (UPDATE stage)                                        ▼
    └──────────────────────────────────────────────  DONE
```

---

## The Always Block (Lines 60-114)

### Reset Logic (Lines 61-68)

```systemverilog
if (reset) begin
    lsu_state         <= LSU_IDLE;
    mem_read_valid    <= 1'b0;
    mem_read_address  <= 8'b0;
    mem_write_valid   <= 1'b0;
    mem_write_address <= 8'b0;
    mem_write_data    <= 8'b0;
    lsu_out           <= 8'b0;
end
```

Clears both channels and the result back to a known idle baseline.

---

### Enable + Memory-Op Gate (Lines 69-71)

```systemverilog
end else if (enable) begin
    if (decoded_mem_read_enable || decoded_mem_write_enable) begin
```

Two guards before any work happens:
1. `enable` — skip masked-off threads entirely (they hold their values).
2. `read_enable || write_enable` — only LDR/STR drive the FSM. For an ADD or a
   CONST, both are 0, so the LSU sits in IDLE and never reports busy.

**Why this matters:** If a non-memory instruction could push the LSU out of
IDLE, the scheduler would stall WAIT for no reason on every single instruction.

---

### State: LSU_IDLE (Lines 73-78)

```systemverilog
LSU_IDLE: begin
    if (core_state == REQUEST) begin
        lsu_state <= LSU_REQUESTING;
    end
end
```

Arm the transaction when the core reaches REQUEST. No bus activity yet — we wait
one cycle so the register file's `rs`/`rt` reads have settled.

---

### State: LSU_REQUESTING (Lines 80-91)

```systemverilog
LSU_REQUESTING: begin
    if (decoded_mem_read_enable) begin
        mem_read_valid   <= 1'b1;
        mem_read_address <= rs;
    end else begin
        mem_write_valid   <= 1'b1;
        mem_write_address <= rs;
        mem_write_data    <= rt;
    end
    lsu_state <= LSU_WAITING;
end
```

Put the request on the **appropriate channel**:
- **LDR:** raise `mem_read_valid`, address = `rs`.
- **STR:** raise `mem_write_valid`, address = `rs`, data = `rt`.

Then advance to WAITING. By now `rs`/`rt` are stable (read during REQUEST, one
cycle earlier).

---

### State: LSU_WAITING (Lines 93-103)

```systemverilog
LSU_WAITING: begin
    if (decoded_mem_read_enable && mem_read_ready) begin
        mem_read_valid <= 1'b0;
        lsu_out        <= mem_read_data;
        lsu_state      <= LSU_DONE;
    end else if (decoded_mem_write_enable && mem_write_ready) begin
        mem_write_valid <= 1'b0;
        lsu_state       <= LSU_DONE;
    end
end
```

Wait for the controller to acknowledge the right channel:

| Op  | Condition                | Action on ready                              |
|-----|--------------------------|----------------------------------------------|
| LDR | `mem_read_ready`         | drop valid, latch `lsu_out = mem_read_data`  |
| STR | `mem_write_ready`        | drop valid (nothing to latch)                |

Either way, advance to DONE.

---

### State: LSU_DONE (Lines 105-110)

```systemverilog
LSU_DONE: begin
    if (core_state == UPDATE) begin
        lsu_state <= LSU_IDLE;
    end
end
```

Hold the result and stay "not busy"-but-done until the core reaches UPDATE (the
writeback stage, where `lsu_out` gets written into the register file). Then
re-arm to IDLE for the next instruction.

---

## Pipeline Timing Diagram

A `LDR` with a 1-cycle data-memory latency:

```
core_state:  REQUEST  WAIT    WAIT    WAIT   EXECUTE UPDATE
lsu_state:   IDLE→    REQ→    WAIT→   WAIT→  DONE    DONE→IDLE
             REQ      WAIT    WAIT    DONE
mem_read_valid: 0      1       1       0      0       0
mem_read_ready: 0      0       1       -      -       -
lsu_out:        -      -       -    latched   held    held
```

The scheduler sees `lsu_state ∈ {REQUESTING, WAITING}` and **holds WAIT** until
the LSU reaches DONE.

---

## Hardware Synthesized

```
              ┌──────────────────────────────────────────────┐
              │               LOAD / STORE UNIT               │
              │                                               │
 rs ──────────┼──┬──────────────▶ mem_read_address ──────────┼──▶
              │  └──────────────▶ mem_write_address ──────────┼──▶
 rt ──────────┼─────────────────▶ mem_write_data ────────────┼──▶
              │                                               │
 core_state ──┼─▶┌──────────┐──▶ mem_read_valid  ────────────┼──▶
 mem_*_ready ─┼─▶│  2-bit   │──▶ mem_write_valid ────────────┼──▶
              │  │  FSM     │                                 │
 mem_read_ ───┼─▶│ IDLE/REQ/│──▶ lsu_state ───────────────────┼──▶ (scheduler)
 data         │  │ WAIT/DONE│   ┌─────────┐                   │
              │  └────┬─────┘──▶│ 8-bit   │── lsu_out ────────┼──▶ (regfile)
 enable ──────┼───────┤        │ out reg │                   │
 clock/reset ─┼───────┘        └─────────┘                   │
              └──────────────────────────────────────────────┘
```

---

## Common Gotchas

1. **`rs` is always the address.** For both LDR and STR the address comes from
   `rs`. Only the *data* differs: STR uses `rt`, LDR produces `lsu_out`. Mixing
   these up is the classic load/store bug.

2. **The IDLE→REQUESTING delay is intentional.** The LSU waits a cycle in IDLE
   before driving the bus so the register file's REQUEST-stage read of `rs`/`rt`
   has completed. Driving the address too early would capture stale operands.

3. **Non-memory instructions must leave it in IDLE.** The
   `read_enable || write_enable` gate is what keeps the scheduler from stalling
   WAIT on every ADD/CONST. Remove it and the pipeline crawls.

4. **`lsu_state` is the stall signal.** The scheduler stays in WAIT while any
   thread's `lsu_state` is REQUESTING or WAITING. If you forget to wire
   `lsu_state` out, the scheduler can race ahead before the load finishes.

5. **Reset beats enable.** Like the other units, a `reset` clears state even when
   `enable = 0`.

6. **`lsu_out` persists.** It holds the last loaded value until the next LDR
   overwrites it; it is consumed by the register file in UPDATE.
