# Core - Line by Line Explanation

This document explains every line of `core.sv` for learning purposes.

Unlike the leaf modules, `core.sv` contains almost no logic of its own — it is a
**structural** module that wires the other units together. So this doc focuses
on the *connections* and the *generate loop* rather than an `always` block.

---

## What the Core Does

A core is one self-contained compute unit. It owns **one** shared control
pipeline (scheduler + fetcher + decoder) and **replicates** the per-thread
datapath (registers + ALU + LSU + PC) once per thread. All threads march through
the same instruction in lock-step — this is **SIMT** (Single Instruction,
Multiple Threads).

```
                         ┌──────────────────────── CORE ────────────────────────┐
                         │                                                       │
   start/block_id ──────▶│  ┌───────────┐   ┌─────────┐   ┌──────────┐          │
   thread_count          │  │ scheduler │──▶│ fetcher │──▶│ decoder  │          │
                         │  └─────┬─────┘   └────┬────┘   └────┬─────┘          │
                         │   core_state    program mem    decoded_* signals     │
                         │        │  (broadcast to every unit below)            │
                         │        ▼                                             │
                         │  ┌───────────────────────────────────────────────┐  │
                         │  │  generate: one datapath per thread (×N)        │  │
                         │  │  ┌───────────┐ ┌─────┐ ┌─────┐ ┌─────┐         │  │
                         │  │  │ registers │ │ ALU │ │ LSU │ │ PC  │  lane i │  │
                         │  │  └───────────┘ └─────┘ └─────┘ └─────┘         │  │
                         │  └───────────────────────────────────────────────┘  │
                         └───────────────────────────────────────────────────────┘
                                  │ program mem channel │ per-thread data mem channels
                                  ▼                     ▼
```

- **Shared (one per core):** scheduler, fetcher, decoder.
- **Replicated (one per thread):** registers, ALU, LSU, PC.

---

## File Header (Lines 1-2)

```systemverilog
`default_nettype none
`timescale 1ns/1ns
```
Disable implicit nets, set the simulation time unit/precision to 1ns.

---

## Module Declaration (Lines 10-16)

```systemverilog
module core #(
    parameter THREADS_PER_BLOCK     = 4,
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter DATA_MEM_ADDR_BITS    = 8,
    parameter DATA_MEM_DATA_BITS    = 8
) (
```

| Parameter               | Default | Purpose                                   |
|-------------------------|---------|-------------------------------------------|
| `THREADS_PER_BLOCK`     | 4       | Lanes in the block = datapath copies      |
| `PROGRAM_MEM_ADDR_BITS` | 8       | Program memory address width              |
| `PROGRAM_MEM_DATA_BITS` | 16      | Instruction word width                    |
| `DATA_MEM_ADDR_BITS`    | 8       | Data memory address width                 |
| `DATA_MEM_DATA_BITS`    | 8       | Data memory word width                    |

These flow down into the submodule instantiations so everything stays
consistent.

---

## Ports

### Clock + Block Launch (Lines 17-24)

```systemverilog
input  wire clock,
input  wire reset,
input  wire start,
output wire done,
input  wire [7:0] block_id,
input  wire [$clog2(THREADS_PER_BLOCK):0] thread_count,
```

| Signal         | Dir | Purpose                                              |
|----------------|-----|------------------------------------------------------|
| `start`        | in  | Dispatcher: launch this block                        |
| `done`         | out | Block finished (wired straight from the scheduler)   |
| `block_id`     | in  | Which block this core is running (sets `%blockIdx`)  |
| `thread_count` | in  | How many lanes are active (for SIMT masking)         |

**The `$clog2` width:** `$clog2(THREADS_PER_BLOCK)` is the number of bits needed
to *index* the threads; the extra `+1` (`:0`) lets `thread_count` represent the
full count (e.g. for 4 threads it must hold the value 4, which needs 3 bits).

---

### Program Memory Channel (Lines 27-30)

```systemverilog
output wire                             program_mem_read_valid,
output wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address,
input  wire                             program_mem_read_ready,
input  wire [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data,
```

A **single** read channel — there is one fetcher per core, so one program-memory
port. These pass straight through to the fetcher.

---

### Data Memory Channels (Lines 33-40)

```systemverilog
output wire                          data_mem_read_valid    [THREADS_PER_BLOCK-1:0],
output wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address  [THREADS_PER_BLOCK-1:0],
input  wire                          data_mem_read_ready    [THREADS_PER_BLOCK-1:0],
input  wire [DATA_MEM_DATA_BITS-1:0] data_mem_read_data     [THREADS_PER_BLOCK-1:0],
output wire                          data_mem_write_valid   [THREADS_PER_BLOCK-1:0],
output wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [THREADS_PER_BLOCK-1:0],
output wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data    [THREADS_PER_BLOCK-1:0],
input  wire                          data_mem_write_ready   [THREADS_PER_BLOCK-1:0]
```

**One read + one write channel per thread**, exposed as unpacked arrays. Each
thread's LSU gets its own slot, so a memory controller upstream can arbitrate all
the lanes. (Today the testbench answers these directly; tomorrow a `controller`
will sit between them and external memory.)

---

## Internal Wires (Lines 43-71)

### Shared Control / Fetch (Lines 43-47)

```systemverilog
wire [2:0] core_state;
wire [7:0] current_pc;
wire       fetcher_done;
wire [PROGRAM_MEM_DATA_BITS-1:0] instruction;
```

The "spine" of the core: `core_state` from the scheduler, `current_pc` from the
scheduler, `fetcher_done`/`instruction` from the fetcher.

### Decoded Signals (Lines 49-63)

```systemverilog
wire [3:0] decoded_rd_address;
...
wire       decoded_ret;
```

Every control signal the decoder produces, declared once and **fanned out** to
all per-thread units. One decode is shared by every lane (SIMT).

### Per-Thread Datapath Signals (Lines 65-71)

```systemverilog
wire [7:0] rs        [THREADS_PER_BLOCK-1:0];
wire [7:0] rt        [THREADS_PER_BLOCK-1:0];
wire [7:0] alu_out   [THREADS_PER_BLOCK-1:0];
wire [7:0] lsu_out   [THREADS_PER_BLOCK-1:0];
wire [1:0] lsu_state [THREADS_PER_BLOCK-1:0];
wire [7:0] next_pc   [THREADS_PER_BLOCK-1:0];
```

**Arrays, one element per thread.** These connect each lane's units to each
other (e.g. `rs[i]` from the register file feeds `alu_unit`/`lsu_unit`) and back
up to the scheduler (`lsu_state[]`, `next_pc[]`).

---

## Shared Unit: Scheduler (Lines 73-89)

```systemverilog
scheduler #(.THREADS_PER_BLOCK (THREADS_PER_BLOCK)) sched ( ... );
```

The control FSM. Consumes `fetcher_done`, the whole `lsu_state[]` array, and
`next_pc[]`; produces `core_state`, `current_pc`, and the core's `done` output.
Note `done` is connected **directly** to the core's output port.

---

## Shared Unit: Fetcher (Lines 91-106)

```systemverilog
fetcher #( ... ) fetch_unit (
    .mem_read_valid   (program_mem_read_valid),
    ...
);
```

Drives the core's program-memory port and returns `fetcher_done` + `instruction`
into the spine. One fetcher, shared by all threads.

---

## Shared Unit: Decoder (Lines 108-128)

```systemverilog
decoder dec_unit (
    .instruction (instruction),
    .decoded_rd_address (decoded_rd_address),
    ...
);
```

Takes the fetched `instruction` and explodes it into the `decoded_*` control
wires that every lane consumes.

---

## Per-Thread Datapath: the Generate Loop (Lines 130-209)

```systemverilog
genvar i;
generate
    for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin : threads
        wire enable = (i < thread_count);
        ...
    end
endgenerate
```

**`generate` + `for`** stamps out `THREADS_PER_BLOCK` identical copies of the
datapath at *elaboration* time (compile time, not runtime). Each copy lives in
its own scope `threads[i]`.

**`wire enable = (i < thread_count);`** is the SIMT mask. `i` is a compile-time
constant per copy; comparing it to the runtime `thread_count` yields each lane's
`enable`. Lanes whose index is `>= thread_count` are frozen.

Inside the loop, four units are instantiated per thread:

| Instance     | Module      | Key per-thread wiring                          |
|--------------|-------------|------------------------------------------------|
| `reg_file`   | `registers` | `THREAD_ID = i`; outputs `rs[i]`, `rt[i]`      |
| `alu_unit`   | `alu`       | reads `rs[i]`/`rt[i]`, drives `alu_out[i]`     |
| `lsu_unit`   | `lsu`       | drives `data_mem_*[i]`, `lsu_out[i]`, `lsu_state[i]` |
| `pc_unit`    | `pc`        | drives `next_pc[i]`                            |

### registers (Lines 137-157)

`THREAD_ID = i` gives each lane its own `%threadIdx` (R15). Reads produce
`rs[i]`/`rt[i]`; writeback takes `alu_out[i]` or `lsu_out[i]`.

### alu (Lines 159-169)

Pure datapath: consumes `rs[i]`/`rt[i]` and the shared `decoded_alu_*` controls,
produces `alu_out[i]`.

### lsu (Lines 171-190)

Connects this lane's memory channels to the core's external `data_mem_*[i]`
arrays, and reports `lsu_state[i]` back up to the scheduler.

### pc (Lines 192-207)

Computes `next_pc[i]` from the shared `current_pc` and the decoded branch
controls. The scheduler picks one lane's `next_pc` to advance the shared PC.

---

## One Instruction's Journey (Data Flow)

`ADD R2, R0, R1` through the core, stage by stage:

```
FETCH   : fetcher reads program_mem[current_pc] ─▶ instruction
DECODE  : decoder splits instruction ─▶ decoded_rd/rs/rt, alu_arith=ADD, reg_write
REQUEST : each reg_file[i] reads rs[i]=R0, rt[i]=R1
WAIT    : no memory op → passes straight through
EXECUTE : each alu_unit[i] computes alu_out[i] = rs[i] + rt[i]
UPDATE  : each reg_file[i] writes R2 <= alu_out[i]; scheduler advances current_pc
```

Every lane does this **simultaneously** — same instruction, different register
contents.

---

## Hardware Synthesized

```
   ┌─────────────────────────── CORE ───────────────────────────┐
   │   ┌──────────┐                                              │
   │   │scheduler │── core_state ──┬──────┬──────┬──────┐        │
   │   └──────────┘── current_pc ──┤      │      │      │        │
   │        ▲  ▲                   ▼      ▼      ▼      ▼        │
   │        │  │                ┌────────────────────────┐      │
   │   ┌────┴┐ │ instruction    │  thread 0 datapath     │      │
   │   │fetch│ │  ┌────────┐    │  reg│alu│lsu│pc         │      │
   │   └──┬──┘ └──│decoder │──▶ ├────────────────────────┤      │
   │      │       └────────┘    │  thread 1 datapath     │      │
   │  program mem               ├────────────────────────┤      │
   │                            │  thread 2 datapath     │      │
   │  lsu_state[]/next_pc[] ◀───│  thread 3 datapath     │      │
   │                            └───────────┬────────────┘      │
   │                              per-thread data mem channels  │
   └────────────────────────────────────────────────────────────┘
```

---

## Common Gotchas

1. **Shared vs replicated.** Scheduler, fetcher, and decoder are instantiated
   *once*; registers/ALU/LSU/PC are instantiated *per thread* inside the
   generate loop. Putting a control unit inside the loop (or a datapath unit
   outside it) breaks the SIMT model.

2. **`enable = (i < thread_count)` is the SIMT mask.** It works because `i` is a
   generate constant. This is what lets a 4-lane core run a 3-element block
   without the 4th lane corrupting memory.

3. **Arrays everywhere.** `rs`, `rt`, `alu_out`, `lsu_out`, `lsu_state`,
   `next_pc`, and all the `data_mem_*` ports are per-thread unpacked arrays.
   Index them by lane (`[i]`); forgetting the index connects the wrong widths.

4. **One decode feeds all lanes.** The `decoded_*` wires fan out to every
   thread. There is exactly one program counter and one instruction stream per
   core — threads cannot diverge in this design.

5. **`done` is a pass-through.** It comes straight from the scheduler; the core
   adds no completion logic of its own.

6. **The data-memory ports need an arbiter eventually.** Today each lane's
   channel is answered directly by the testbench. With multiple cores sharing
   real memory, a `controller` must arbitrate these — that is the next module to
   build.
