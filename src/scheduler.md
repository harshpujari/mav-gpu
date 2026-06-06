# Scheduler - Line by Line Explanation

This document explains every line of `scheduler.sv` for learning purposes.

---

## What the Scheduler Does

The scheduler is the **core's control FSM**. It walks every instruction through
the six execution stages and broadcasts the current stage as `core_state` — the
single signal that gates the fetcher, decoder, register file, ALU, LSU and PC.

```
   FETCH ─▶ DECODE ─▶ REQUEST ─▶ WAIT ─▶ EXECUTE ─▶ UPDATE ─┐
     ▲                                                      │
     └──────────────────── (not RET) ──────────────────────┘
                                                            │
                                                       (RET)│
                                                            ▼
                                                          DONE
```

```
                  ┌──────────────────────────┐
   start ────────▶│                          │──▶ core_state  (to all units)
   fetcher_done ─▶│                          │──▶ current_pc  (to fetcher/PC)
   lsu_state[] ──▶│      Scheduler           │──▶ done        (to dispatcher)
   next_pc[] ────▶│      (control FSM)       │
   decoded_ret ──▶│                          │
                  └──────────────────────────┘
```

**Two stages can stall:**
- `FETCH` waits for `fetcher_done` (instruction back from program memory).
- `WAIT` waits for every thread's LSU to finish any memory traffic.

All threads in the block are assumed to share control flow, so a **single**
`current_pc` is kept and refreshed from the threads' `next_pc` in UPDATE.

---

## File Header (Lines 1-2)

```systemverilog
`default_nettype none
`timescale 1ns/1ns
```
Disable implicit nets, set the simulation time unit/precision to 1ns. Standard
boilerplate.

---

## Module Declaration (Lines 17-19)

```systemverilog
module scheduler #(
    parameter THREADS_PER_BLOCK = 4
) (
```

| Parameter           | Default | Purpose                                       |
|---------------------|---------|-----------------------------------------------|
| `THREADS_PER_BLOCK` | 4       | How many per-thread LSUs / PCs to watch       |

This parameter sizes the `lsu_state` and `next_pc` input arrays.

---

## Input / Output Ports

### Clock and Launch (Lines 20-22)

```systemverilog
input  wire clock,
input  wire reset,
input  wire start,
```

| Signal  | Purpose                                                  |
|---------|----------------------------------------------------------|
| `clock` | Updates on the rising edge                               |
| `reset` | Force back to IDLE, `current_pc = 0`, `done = 0`         |
| `start` | The dispatcher's "go" — launches this block from IDLE    |

---

### Decoder Signals (Lines 25-27)

```systemverilog
input  wire decoded_mem_read_enable,    // (informational) this is a LDR
input  wire decoded_mem_write_enable,   // (informational) this is a STR
input  wire decoded_ret,                // RET: block is finished after UPDATE
```

Only `decoded_ret` actually drives logic (it ends the block). The two
`decoded_mem_*` signals are carried for clarity/future use — the scheduler
decides *when memory is done* by watching `lsu_state`, not these flags.

---

### Fetcher Status (Line 30)

```systemverilog
input  wire fetcher_done,
```

The handshake from the fetcher: high once the instruction is latched. This is
what releases the FETCH stall.

---

### Per-Thread LSU Status (Line 33)

```systemverilog
input  wire [1:0] lsu_state [THREADS_PER_BLOCK-1:0],
```

An **unpacked array** — one 2-bit `lsu_state` per thread. The scheduler scans
these to decide whether any memory operation is still in flight.

**Syntax note:** `[1:0] name [N-1:0]` is a packed-then-unpacked array: each
element is 2 bits wide (`[1:0]`), and there are `N` elements (`[N-1:0]`).

---

### Program Counter (Lines 36-37)

```systemverilog
input  wire [7:0] next_pc [THREADS_PER_BLOCK-1:0],
output reg  [7:0] current_pc,
```

| Signal       | Dir | Purpose                                            |
|--------------|-----|----------------------------------------------------|
| `next_pc[]`  | in  | Each thread's computed next PC (from its `pc` unit)|
| `current_pc` | out | The live PC the scheduler owns and broadcasts      |

The scheduler **owns** the program counter; the per-thread `pc` modules only
*compute* candidate next values.

---

### Outputs (Lines 40-41)

```systemverilog
output reg  [2:0] core_state,
output reg        done
```

| Signal       | Purpose                                                  |
|--------------|----------------------------------------------------------|
| `core_state` | The current pipeline stage — broadcast to every unit     |
| `done`       | Raised when the block hits RET; tells the dispatcher     |

---

## Pipeline Encoding (Lines 44-52)

```systemverilog
localparam IDLE    = 3'b000,
           FETCH   = 3'b001,
           DECODE  = 3'b010,
           REQUEST = 3'b011,
           WAIT    = 3'b100,
           EXECUTE = 3'b101,
           UPDATE  = 3'b110,
           DONE    = 3'b111;
```

The **canonical encoding** every module shares. The scheduler is the one place
these codes are actually *produced*; everywhere else they are consumed.

---

## LSU Busy States (Lines 54-56)

```systemverilog
localparam LSU_REQUESTING = 2'b01,
           LSU_WAITING    = 2'b10;
```

The two `lsu_state` values that mean "memory still in flight". (IDLE and DONE
mean "not busy".) These must match the encoding in `lsu.sv`.

---

## Scratch Variables (Lines 58-59)

```systemverilog
integer i;
reg     any_lsu_busy;
```

- `i` — loop index for scanning the LSU array.
- `any_lsu_busy` — a temporary flag computed each WAIT cycle (see below).

---

## The Always Block (Lines 61-121)

### Reset Logic (Lines 62-65)

```systemverilog
if (reset) begin
    current_pc <= 8'b0;
    core_state <= IDLE;
    done       <= 1'b0;
end
```

Start parked in IDLE at PC 0, not done.

---

### State: IDLE (Lines 68-71)

```systemverilog
IDLE: begin
    if (start) core_state <= FETCH;
end
```

Wait for the dispatcher's `start`, then begin the first fetch.

---

### State: FETCH (Lines 73-76)

```systemverilog
FETCH: begin
    if (fetcher_done) core_state <= DECODE;
end
```

**Stall point #1.** Hold here until the fetcher reports the instruction is
ready, then advance to DECODE.

---

### State: DECODE (Lines 78-81)

```systemverilog
DECODE: begin
    core_state <= REQUEST;
end
```

One cycle to let the decoder latch the instruction; control signals are valid
the next cycle. Unconditional advance.

---

### State: REQUEST (Lines 83-86)

```systemverilog
REQUEST: begin
    core_state <= WAIT;
end
```

During this cycle the register file reads `rs`/`rt` and the LSUs arm for any
memory op. Unconditional advance to WAIT.

---

### State: WAIT (Lines 88-97)

```systemverilog
WAIT: begin
    any_lsu_busy = 1'b0;
    for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin
        if (lsu_state[i] == LSU_REQUESTING ||
            lsu_state[i] == LSU_WAITING)
            any_lsu_busy = 1'b1;
    end
    if (!any_lsu_busy) core_state <= EXECUTE;
end
```

**Stall point #2.** Scan every thread's LSU. If *any* is mid-transaction, hold
in WAIT; once all are settled, advance to EXECUTE.

**Why `=` (blocking) for `any_lsu_busy`?** It is a throwaway temporary computed
and consumed *within this same evaluation*. Blocking assignment makes it behave
like a local variable. `core_state` still uses `<=` (non-blocking) because it is
real sequential state.

**For a non-memory instruction**, every LSU is IDLE, so `any_lsu_busy` stays 0
and WAIT passes through in a single cycle.

---

### State: EXECUTE (Lines 99-102)

```systemverilog
EXECUTE: begin
    core_state <= UPDATE;
end
```

The ALU result / loaded data is now available. Advance to writeback.

---

### State: UPDATE (Lines 104-114)

```systemverilog
UPDATE: begin
    if (decoded_ret) begin
        core_state <= DONE;
        done       <= 1'b1;
    end else begin
        current_pc <= next_pc[THREADS_PER_BLOCK-1];
        core_state <= FETCH;
    end
end
```

The branch point of the whole FSM:

| Condition       | Action                                                    |
|-----------------|-----------------------------------------------------------|
| `decoded_ret`   | block is finished → go to DONE, raise `done`              |
| otherwise       | latch `current_pc = next_pc[last thread]`, loop to FETCH  |

**Why `next_pc[THREADS_PER_BLOCK-1]`?** All threads are assumed to share control
flow (convergent), so any thread's next PC is fine — the last one is picked by
convention. (See Gotcha #3 for the partial-block caveat.)

---

### State: DONE (Lines 116-118)

```systemverilog
DONE: begin
    // Block complete - stay here until reset
end
```

A sticky terminal state. The block stays done until `reset`. The dispatcher sees
`done` and can recycle this core for another block.

---

## Pipeline Timing Diagram

One non-memory instruction (memory-free, so WAIT is a single cycle):

```
Clock:       ─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─┐ ┌─
              └─┘ └─┘ └─┘ └─┘ └─┘ └─┘ └─┘

core_state:  FETCH DECODE REQUEST WAIT EXECUTE UPDATE FETCH
                ▲                                  │
            (waits for                        (current_pc
           fetcher_done)                      <= next_pc)
```

With a memory instruction, WAIT repeats until every `lsu_state` leaves
REQUESTING/WAITING.

---

## Hardware Synthesized

```
              ┌────────────────────────────────────────────┐
              │                  SCHEDULER                   │
              │                                              │
 start ───────┼─▶┌───────────────┐                          │
 fetcher_done ┼─▶│   8-state      │──▶ core_state ───────────┼──▶ (all units)
 decoded_ret ─┼─▶│   pipeline     │                          │
              │  │   FSM          │──▶ done ─────────────────┼──▶ (dispatcher)
 lsu_state[] ─┼─▶│                │   ┌──────────┐           │
              │  │  ┌──────────┐  │   │ 8-bit PC │           │
              │  │  │ any_lsu_ │  │   │ register │── current_pc ▶ (fetcher/PC)
 next_pc[] ───┼─▶│  │ busy scan│  │   └────▲─────┘           │
              │  │  └──────────┘  │        │                 │
              │  └───────┬────────┘────────┘                 │
              │ clock/reset                                  │
              └────────────────────────────────────────────┘
```

---

## Common Gotchas

1. **The scheduler is the only producer of `core_state`.** Every other module
   *reads* the pipeline encoding; this FSM is what makes it move. A bug here
   stalls the entire core.

2. **WAIT watches `lsu_state`, not `decoded_mem_*`.** Memory latency is variable,
   so the scheduler waits for the LSUs to actually report done rather than
   assuming a fixed number of cycles.

3. **`next_pc[THREADS_PER_BLOCK-1]` assumes a full, convergent block.** If the
   last lane is masked off (a partial block) it never advances its PC, so the
   convergent-PC shortcut breaks. The current tests run full blocks; supporting
   partial blocks cleanly would pick an *active* thread's `next_pc` instead.

4. **`DONE` is sticky.** Only `reset` leaves it. The dispatcher relies on this to
   detect completion before reusing the core.

5. **Blocking vs non-blocking in WAIT.** `any_lsu_busy` uses `=` because it is a
   per-cycle scratch value; `core_state`/`current_pc`/`done` use `<=` because
   they are real registers. Swapping these would introduce subtle race bugs.

6. **`start` only matters in IDLE.** Once running, the scheduler ignores `start`;
   it loops through the stages on its own until RET.
