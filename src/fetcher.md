# Instruction Fetcher - Line by Line Explanation

This document explains every line of `fetcher.sv` for learning purposes.

---

## What the Fetcher Does

There is **one fetcher per core**, shared by all threads. Its whole job is to
turn the current PC into an instruction:

| Stage     | Job                                                            |
|-----------|----------------------------------------------------------------|
| `FETCH`   | Send a read request to program memory at `current_pc`          |
| (waiting) | Hold the request until memory answers                          |
| (done)    | Latch the 16-bit instruction, raise `fetcher_done`             |

```
                   ┌──────────────────────┐
   current_pc ────▶│                      │──▶ mem_read_valid
                   │                      │──▶ mem_read_address
   core_state ────▶│   Instruction        │
                   │   Fetcher            │◀── mem_read_ready
   mem_read_ready ▶│                      │◀── mem_read_data
   mem_read_data ─▶│                      │
                   │                      │──▶ fetcher_done
                   │                      │──▶ instruction
                   └──────────────────────┘
                            ▲
                            │
                       core_state
```

The fetcher speaks a **valid → ready handshake** with program memory:
1. Assert `mem_read_valid` with `mem_read_address = current_pc`.
2. Hold until memory replies with `mem_read_ready`.
3. Latch `mem_read_data` into `instruction` and raise `fetcher_done`.

`fetcher_done` is the signal the scheduler waits on before leaving the FETCH
stage. This is the **same handshake pattern** the LSU uses for data memory.

---

## File Header (Lines 1-2)

```systemverilog
`default_nettype none
```
**What it does:** Disables implicit net declarations.

**Why it matters:** Without this, a typo like `mem_read_redy` silently creates a
new 1-bit wire instead of erroring. This forces every signal to be declared,
catching typos at compile time.

```systemverilog
`timescale 1ns/1ns
```
**What it does:** Sets the simulation time unit and precision to 1ns, so `#5`
means "wait 5 nanoseconds".

---

## Module Declaration (Lines 18-21)

```systemverilog
module fetcher #(
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16
) (
```

| Parameter                | Default | Purpose                                  |
|--------------------------|---------|------------------------------------------|
| `PROGRAM_MEM_ADDR_BITS`  | 8       | Width of the PC / instruction address    |
| `PROGRAM_MEM_DATA_BITS`  | 16      | Width of one instruction word            |

**Why parameters?** Program memory is 8-bit addressed (256 instructions max) and
16-bit wide in this GPU, but parameterizing lets you grow either without
rewriting the module.

---

## Input / Output Ports

### Clock and Control (Lines 22-25)

```systemverilog
input  wire clock,
input  wire reset,
input  wire [2:0] core_state,
```

| Signal       | Purpose                                                |
|--------------|--------------------------------------------------------|
| `clock`      | All updates happen on the rising edge                  |
| `reset`      | Force the fetcher back to IDLE and clear outputs       |
| `core_state` | Which pipeline stage the core is in (only FETCH matters) |

**Note:** The fetcher has **no `enable`** — unlike the ALU/PC/registers, it is a
per-*core* unit, not a per-*thread* unit. All threads share one fetch.

---

### Program Counter (Line 28)

```systemverilog
input  wire [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
```

**Purpose:** The address of the instruction we need. Driven by the scheduler,
which owns the live PC.

---

### Program-Memory Read Channel (Lines 31-34)

```systemverilog
output reg                              mem_read_valid,
output reg  [PROGRAM_MEM_ADDR_BITS-1:0] mem_read_address,
input  wire                             mem_read_ready,
input  wire [PROGRAM_MEM_DATA_BITS-1:0] mem_read_data,
```

This is one side of a **valid/ready handshake**:

| Signal             | Dir | Meaning                                       |
|--------------------|-----|-----------------------------------------------|
| `mem_read_valid`   | out | "I want to read" (we drive this)              |
| `mem_read_address` | out | The address we want                           |
| `mem_read_ready`   | in  | "Your data is on the bus" (memory drives this)|
| `mem_read_data`    | in  | The 16-bit instruction coming back            |

**Why `reg` on the outputs?** They are driven inside a clocked `always` block,
so they need to be `reg` (storage), not `wire`.

---

### Result to the Decoder (Lines 37-38)

```systemverilog
output reg                              fetcher_done,
output reg  [PROGRAM_MEM_DATA_BITS-1:0] instruction
```

| Signal         | Purpose                                                    |
|----------------|------------------------------------------------------------|
| `fetcher_done` | Pulses high when the instruction is latched and valid      |
| `instruction`  | The fetched 16-bit word, held until the next fetch         |

**Note:** No comma after the last port — common syntax gotcha.

---

## Core Pipeline Stages (Lines 41-51)

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

The **canonical 3-bit pipeline encoding**, shared by every core module. The
fetcher only reacts to `FETCH` (`001`), but it defines the whole set so the
naming matches everywhere. The scheduler is what actually *drives* `core_state`.

---

## Fetcher's Own State Machine (Lines 53-57)

```systemverilog
localparam FETCHER_IDLE     = 2'b00,   // Nothing in flight
           FETCHER_FETCHING = 2'b01,   // Request issued, waiting for ready
           FETCHER_DONE     = 2'b10;   // Instruction latched, holding result
reg [1:0] fetcher_state;
```

**Don't confuse the two state variables:**
- `core_state` — where the *whole core* is in the 6-stage pipeline (input).
- `fetcher_state` — where *this fetcher* is in its 3-step handshake (internal).

```
   FETCHER_IDLE ──(core enters FETCH)──▶ FETCHER_FETCHING
        ▲                                      │
        │                              (mem_read_ready)
   (core leaves FETCH)                          ▼
        └──────────────────────────────  FETCHER_DONE
```

---

## The Always Block (Lines 59-102)

```systemverilog
always @(posedge clock) begin
```
Runs on every rising clock edge — this is sequential logic.

### Reset Logic (Lines 60-65)

```systemverilog
if (reset) begin
    fetcher_state    <= FETCHER_IDLE;
    mem_read_valid   <= 1'b0;
    mem_read_address <= {PROGRAM_MEM_ADDR_BITS{1'b0}};
    fetcher_done     <= 1'b0;
    instruction      <= {PROGRAM_MEM_DATA_BITS{1'b0}};
end
```

On reset, everything returns to the idle baseline: no request, no done flag,
zeroed instruction.

**The `{N{1'b0}}` syntax:** *replication* — a vector of `N` zeros, where `N` is
the parameter. With defaults, `{PROGRAM_MEM_DATA_BITS{1'b0}}` is just `16'b0`.

---

### State: FETCHER_IDLE (Lines 68-76)

```systemverilog
FETCHER_IDLE: begin
    if (core_state == FETCH) begin
        fetcher_state    <= FETCHER_FETCHING;
        mem_read_valid   <= 1'b1;
        mem_read_address <= current_pc;
    end
end
```

**What it does:** Sit idle until the core reaches the FETCH stage, then fire the
read request: raise `mem_read_valid` and put `current_pc` on the address bus.

---

### State: FETCHER_FETCHING (Lines 78-86)

```systemverilog
FETCHER_FETCHING: begin
    if (mem_read_ready) begin
        fetcher_state  <= FETCHER_DONE;
        mem_read_valid <= 1'b0;
        instruction    <= mem_read_data;
        fetcher_done   <= 1'b1;
    end
end
```

**What it does:** The request is in flight. When memory answers (`mem_read_ready`
goes high), in one step: drop the request, latch the returned word into
`instruction`, and raise `fetcher_done` to tell the scheduler.

**Why drop `mem_read_valid` here?** A clean handshake deasserts the request as
soon as the data is taken — otherwise memory might think we want a second read.

---

### State: FETCHER_DONE (Lines 88-95)

```systemverilog
FETCHER_DONE: begin
    if (core_state != FETCH) begin
        fetcher_state <= FETCHER_IDLE;
        fetcher_done  <= 1'b0;
    end
end
```

**What it does:** Hold `instruction` and `fetcher_done` steady while the core is
still in FETCH (so the scheduler is guaranteed to see them). Once the scheduler
advances the core out of FETCH (into DECODE), re-arm: drop `fetcher_done` and
return to IDLE, ready for the next instruction.

---

### Default (Lines 97-99)

```systemverilog
default: begin
    fetcher_state <= FETCHER_IDLE;
end
```

**Why a default?** `fetcher_state` is 2-bit (4 values) but only 3 are used.
`2'b11` is unreachable in normal operation — the default snaps any stray state
back to IDLE, which prevents lock-ups if the register ever glitches.

---

## Pipeline Timing Diagram

A fetch with a 1-cycle memory latency:

```
Clock:        ──┐ ┌──┐ ┌──┐ ┌──┐ ┌──┐ ┌──
                └─┘  └─┘  └─┘  └─┘  └─┘

core_state:    FETCH FETCH FETCH FETCH DECODE
fetcher_state: IDLE  FETCH- FETCH- DONE  IDLE
                     ING    ING
mem_read_valid:  0    1      1     0     0
mem_read_ready:  0    0      1     -     -
fetcher_done:    0    0      0     1     0
                                   ▲
                              instruction latched
```

---

## Hardware Synthesized

```
              ┌────────────────────────────────────────┐
              │            INSTRUCTION FETCHER           │
              │                                          │
 current_pc ──┼─────────────────▶ mem_read_address ─────┼──▶ (to prog mem)
              │                                          │
 core_state ──┼──▶┌──────────┐                           │
              │   │  2-bit   │──▶ mem_read_valid ────────┼──▶
 mem_ready ───┼──▶│  FSM     │                           │
              │   │ (IDLE/   │   ┌──────────┐            │
 mem_data ────┼──▶│ FETCHING/│──▶│ 16-bit   │            │
              │   │  DONE)   │   │ instr reg│── instruction ▶ (to decoder)
              │   └────┬─────┘   └──────────┘            │
              │        │──────────▶ fetcher_done ────────┼──▶ (to scheduler)
              │ clock ─┤                                 │
              │ reset ─┘                                 │
              └──────────────────────────────────────────┘
```

---

## Common Gotchas

1. **`fetcher_state` ≠ `core_state`.** One is the fetcher's private 2-bit
   handshake state; the other is the core's 3-bit pipeline stage fed in from the
   scheduler. They change independently.

2. **No `enable` port.** The fetcher is per-core, not per-thread, so there is no
   SIMT masking here. Threads diverging in control flow is *not* modeled at the
   fetch level — all threads share one instruction stream.

3. **`instruction` is held, `fetcher_done` is pulsed.** `instruction` keeps its
   value until the next successful fetch overwrites it, but `fetcher_done` only
   stays high while the core is still in FETCH. Sample the instruction while
   `fetcher_done` is high.

4. **The request must be dropped on acknowledge.** Forgetting
   `mem_read_valid <= 0` in FETCHER_FETCHING would leave a dangling request and
   could trigger a spurious second read.

5. **One fetch per FETCH stage.** The FSM only re-arms after the core *leaves*
   FETCH. If the scheduler never advances (e.g., `fetcher_done` is ignored), the
   fetcher parks in DONE forever — by design.
