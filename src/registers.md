# Register File - Line by Line Explanation

This document explains every line of `registers.sv` for learning purposes.

---

## File Header (Lines 1-2)

```systemverilog
`default_nettype none
```
**What it does:** Disables implicit net declarations.

**Why it matters:** Without this, if you typo a signal name (e.g., `registrs` instead of `registers`), Verilog silently creates a new 1-bit wire instead of giving an error. This directive forces you to declare all signals explicitly - catching typos at compile time.

```systemverilog
`timescale 1ns/1ns
```
**What it does:** Sets the time unit and precision for simulation.

**Format:** `` `timescale <unit>/<precision> ``

| Part | Meaning |
|------|---------|
| `1ns` (unit) | `#1` in code = 1 nanosecond |
| `1ns` (precision) | Simulator resolves time to 1ns granularity |

---

## Module Declaration (Lines 4-9)

```systemverilog
module registers #(
    parameter THREADS_PER_BLOCK = 4,
    parameter THREAD_ID = 0,
    parameter DATA_BITS = 8
) (
```

**What it does:** Declares a parameterized module named `registers`.

| Parameter | Default | Purpose |
|-----------|---------|---------|
| `THREADS_PER_BLOCK` | 4 | How many threads run in parallel (stored in R14) |
| `THREAD_ID` | 0 | Which thread this register file belongs to (stored in R15) |
| `DATA_BITS` | 8 | Width of each register (8-bit = 0-255 range) |

**Why parameters?** The GPU instantiates multiple register files (one per thread). Parameters let us reuse the same module with different `THREAD_ID` values:

```systemverilog
// In the core module, you might see:
registers #(.THREAD_ID(0)) thread0_regs (...);
registers #(.THREAD_ID(1)) thread1_regs (...);
registers #(.THREAD_ID(2)) thread2_regs (...);
registers #(.THREAD_ID(3)) thread3_regs (...);
```

---

## Input Ports (Lines 10-28)

### Clock and Control Signals

```systemverilog
input wire clock,
input wire reset,
input wire enable,
```

| Signal | Purpose |
|--------|---------|
| `clock` | The heartbeat - all updates happen on rising edge |
| `reset` | Force all registers to known initial state |
| `enable` | Is this thread active? (SIMT masking) |

**GPU Context:** In SIMT execution, some threads may be inactive (e.g., if block has 3 threads but hardware supports 4). `enable` controls this.

---

### Kernel Context

```systemverilog
input reg [7:0] block_id,
```

**Purpose:** Which block is currently being executed.

**GPU Execution Model:**
```
Kernel Launch
    │
    ├── Block 0  ──▶ [Thread 0, Thread 1, Thread 2, Thread 3]
    ├── Block 1  ──▶ [Thread 0, Thread 1, Thread 2, Thread 3]
    ├── Block 2  ──▶ [Thread 0, Thread 1, Thread 2, Thread 3]
    └── ...
```

Each thread needs to know its block ID to compute global indices (e.g., `globalIdx = blockIdx * blockDim + threadIdx`).

---

### Pipeline State

```systemverilog
input reg [2:0] core_state,
```

**Purpose:** Which pipeline stage is the core executing?

The register file cares about two stages:
- **REQUEST (011):** Read `rs` and `rt` values
- **UPDATE (110):** Write result back to `rd`

---

### Decoded Instruction Signals

```systemverilog
input reg [3:0] decoded_rd_address,
input reg [3:0] decoded_rs_address,
input reg [3:0] decoded_rt_address,
```

**Purpose:** 4-bit register addresses extracted from the instruction.

| Signal | Meaning | Range |
|--------|---------|-------|
| `decoded_rd_address` | Destination register | R0-R15 |
| `decoded_rs_address` | Source register 1 | R0-R15 |
| `decoded_rt_address` | Source register 2 | R0-R15 |

**Example instruction:** `ADD R3, R1, R2` (R3 = R1 + R2)
- `rd` = 3 (R3)
- `rs` = 1 (R1)
- `rt` = 2 (R2)

---

### Control Signals

```systemverilog
input reg decoded_reg_write_enable,
input reg [1:0] decoded_reg_input_mux,
input reg [DATA_BITS-1:0] decoded_immediate,
```

| Signal | Width | Purpose |
|--------|-------|---------|
| `decoded_reg_write_enable` | 1-bit | Should we write to `rd`? |
| `decoded_reg_input_mux` | 2-bit | Where does write data come from? |
| `decoded_immediate` | 8-bit | Constant value from instruction |

**Write source selection:**

| `decoded_reg_input_mux` | Source | Example Instruction |
|-------------------------|--------|---------------------|
| `00` (ARITHMETIC) | ALU result | `ADD R1, R2, R3` |
| `01` (MEMORY) | LSU result | `LDR R1, R2` |
| `10` (CONSTANT) | Immediate | `CONST R1, #42` |

---

### Data Inputs

```systemverilog
input reg [DATA_BITS-1:0] alu_out,
input reg [DATA_BITS-1:0] lsu_out,
```

**Purpose:** Results from other execution units.

| Signal | Source | When Used |
|--------|--------|-----------|
| `alu_out` | Arithmetic Logic Unit | ADD, SUB, MUL, DIV, CMP |
| `lsu_out` | Load/Store Unit | LDR (memory load) |

---

## Output Ports (Lines 30-32)

```systemverilog
output reg [7:0] rs,
output reg [7:0] rt
```

**Purpose:** The values read from source registers.

**Data flow:**
```
┌──────────────────────────────────────────────┐
│              Register File                    │
│                                              │
│  decoded_rs_address ──▶ ┌────────┐           │
│                         │        │──▶ rs     │
│                         │ 16x8   │           │
│                         │ Memory │           │
│                         │        │──▶ rt     │
│  decoded_rt_address ──▶ └────────┘           │
│                                              │
└──────────────────────────────────────────────┘
```

These outputs feed directly into the ALU as operands.

---

## Local Parameters (Lines 35-41)

```systemverilog
localparam ARITHMETIC = 2'b00,
           MEMORY     = 2'b01,
           CONSTANT   = 2'b10;

localparam REQUEST = 3'b011;
localparam UPDATE  = 3'b110;
```

**What it does:** Defines named constants for readability.

**Write source mux:**

| Name | Binary | Decimal | Meaning |
|------|--------|---------|---------|
| `ARITHMETIC` | `00` | 0 | Write ALU result |
| `MEMORY` | `01` | 1 | Write memory load result |
| `CONSTANT` | `10` | 2 | Write immediate value |

**Pipeline stages:**

| Name | Binary | Decimal | Action |
|------|--------|---------|--------|
| `REQUEST` | `011` | 3 | Read rs, rt from registers |
| `UPDATE` | `110` | 6 | Write result to rd |

---

## Register Array (Line 44)

```systemverilog
reg [7:0] registers [15:0];
```

**What it does:** Declares an array of 16 registers, each 8 bits wide.

**Syntax breakdown:**
```
reg [7:0]      registers    [15:0]
────────       ─────────    ──────
bit width      array name   array size
(each reg      (16 elements: registers[0] to registers[15])
is 8 bits)
```

**Memory layout:**
```
┌─────────────────────────────────────────────┐
│  R0   │  R1  │  R2  │ ... │  R12 │ R13│R14│R15│
├───────┼──────┼──────┼─────┼──────┼────┼───┼───┤
│ 8-bit │8-bit │8-bit │ ... │8-bit │ BI │BD │TI │
│general│ purpose      ...  │      │    │   │   │
└─────────────────────────────────────────────┘
         ▲ Writable (R0-R12)  ▲    Read-only ▲
                              │    (R13-R15)
                              │
                         BI = blockIdx
                         BD = blockDim
                         TI = threadIdx
```

---

## Loop Variable (Line 46)

```systemverilog
integer i;
```

**What it does:** Declares a loop counter for the `for` loop in reset.

**Note:** `integer` is a 32-bit signed type, only used for loops/indices. It doesn't synthesize to actual hardware registers.

---

## The Always Block (Lines 48-80)

### Reset Logic (Lines 49-60)

```systemverilog
always @(posedge clock) begin
    if (reset) begin
        rs <= 8'b0;
        rt <= 8'b0;

        for (i = 0; i < 13; i = i + 1) begin
            registers[i] <= 8'b0;
        end

        registers[13] <= 8'b0;
        registers[14] <= THREADS_PER_BLOCK;
        registers[15] <= THREAD_ID;
    end
```

**What it does on reset:**

1. Clear output registers (`rs`, `rt`)
2. Clear general-purpose registers (R0-R12) using a loop
3. Initialize read-only registers:

| Register | Name | Initial Value |
|----------|------|---------------|
| R13 | `%blockIdx` | 0 (updated each block dispatch) |
| R14 | `%blockDim` | `THREADS_PER_BLOCK` (fixed at synthesis) |
| R15 | `%threadIdx` | `THREAD_ID` (fixed at synthesis) |

**The `for` loop:**
```systemverilog
for (i = 0; i < 13; i = i + 1) begin
    registers[i] <= 8'b0;
end
```

This synthesizes to parallel reset logic, not an actual loop. The synthesizer "unrolls" it:
```systemverilog
// What the synthesizer actually creates:
registers[0]  <= 8'b0;
registers[1]  <= 8'b0;
registers[2]  <= 8'b0;
// ... (all 13 happen simultaneously)
registers[12] <= 8'b0;
```

---

### Main Operation (Lines 61-78)

```systemverilog
end else if (enable) begin
    registers[13] <= block_id;

    if (core_state == REQUEST) begin
        rs <= registers[decoded_rs_address];
        rt <= registers[decoded_rt_address];
    end

    if (core_state == UPDATE) begin
        if (decoded_reg_write_enable && decoded_rd_address < 13) begin
            case (decoded_reg_input_mux)
                ARITHMETIC: registers[decoded_rd_address] <= alu_out;
                MEMORY:     registers[decoded_rd_address] <= lsu_out;
                CONSTANT:   registers[decoded_rd_address] <= decoded_immediate;
            endcase
        end
    end
end
```

**Block ID Update:**
```systemverilog
registers[13] <= block_id;
```
Keeps R13 (`%blockIdx`) synchronized with the current block being executed.

---

**REQUEST Stage - Register Read:**
```systemverilog
if (core_state == REQUEST) begin
    rs <= registers[decoded_rs_address];
    rt <= registers[decoded_rt_address];
end
```

**Example:** For instruction `ADD R5, R2, R7`:
- `decoded_rs_address` = 2
- `decoded_rt_address` = 7
- `rs` gets value of R2
- `rt` gets value of R7

---

**UPDATE Stage - Register Write:**
```systemverilog
if (core_state == UPDATE) begin
    if (decoded_reg_write_enable && decoded_rd_address < 13) begin
```

**Two conditions must be met:**
1. `decoded_reg_write_enable` is high (instruction writes to a register)
2. `decoded_rd_address < 13` (can't write to read-only registers R13-R15)

**The case statement selects the write source:**
```systemverilog
case (decoded_reg_input_mux)
    ARITHMETIC: registers[decoded_rd_address] <= alu_out;
    MEMORY:     registers[decoded_rd_address] <= lsu_out;
    CONSTANT:   registers[decoded_rd_address] <= decoded_immediate;
endcase
```

| Instruction | Mux Value | Source |
|-------------|-----------|--------|
| `ADD R1, R2, R3` | ARITHMETIC | `alu_out` |
| `LDR R1, R2` | MEMORY | `lsu_out` |
| `CONST R1, #42` | CONSTANT | `decoded_immediate` |

---

## Module End (Line 82)

```systemverilog
endmodule
```

**What it does:** Closes the module definition.

---

## Pipeline Timing Diagram

```
Clock:    ──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──
            └──┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──┘

State:    FETCH│DECODE│REQUEST│  ...  │EXECUTE│UPDATE│
               │      │   ▲   │       │       │  ▲   │
               │      │   │   │       │       │  │   │
               │      │   │   │       │       │  │   │
Action:        │      │ Read  │       │       │Write │
               │      │rs, rt │       │       │to rd │
```

---

## Hardware Synthesized

This Verilog synthesizes to approximately:

```
                    ┌─────────────────────────────────────────┐
                    │           REGISTER FILE                  │
                    │                                          │
                    │   ┌─────────────────────────────────┐   │
decoded_rs_address ─┼──▶│                                 │   │
                    │   │     16 x 8-bit Register Array   │──▶│──▶ rs[7:0]
decoded_rt_address ─┼──▶│                                 │   │
                    │   │  ┌────┬────┬────┬─────┬────────┐│──▶│──▶ rt[7:0]
                    │   │  │ R0 │ R1 │ R2 │ ... │  R15   ││   │
                    │   │  └────┴────┴────┴─────┴────────┘│   │
decoded_rd_address ─┼──▶│         ▲                       │   │
                    │   └─────────┼───────────────────────┘   │
                    │             │                            │
                    │   ┌─────────┴─────────┐                  │
                    │   │   Write Data MUX   │                 │
                    │   └─────────┬─────────┘                  │
                    │       ▲     ▲     ▲                      │
                    │       │     │     │                      │
            alu_out─┼───────┘     │     └───────────────decoded_immediate
            lsu_out─┼─────────────┘                            │
                    │                                          │
  reg_input_mux[1:0]┼──────────▶ (select)                     │
  reg_write_enable ─┼──────────▶ (enable)                     │
  core_state[2:0] ──┼──────────▶ (timing)                     │
          clock ────┼──────────▶ (all registers)              │
          reset ────┼──────────▶ (all registers)              │
          enable ───┼──────────▶ (all registers)              │
                    └─────────────────────────────────────────┘
```

---

## Read-Only Register Usage Examples

**In GPU kernel code (assembly):**

```asm
; Calculate global thread index
; globalIdx = blockIdx * blockDim + threadIdx

CONST R0, #0        ; R0 = 0 (accumulator)
MUL R1, R13, R14    ; R1 = blockIdx * blockDim
ADD R0, R1, R15     ; R0 = R1 + threadIdx = globalIdx

; Now R0 contains the unique global index for this thread
; Thread 0 of Block 2 with blockDim=4:
;   globalIdx = 2 * 4 + 0 = 8
```

---

## Common Gotchas

1. **Writing to read-only registers:** The condition `decoded_rd_address < 13` prevents this, but if you forget it, R13-R15 would get corrupted.

2. **Timing of rs/rt read:** The values are captured in REQUEST stage. If you use them before that stage completes, you get stale data.

3. **Block ID synchronization:** R13 is updated every cycle when enabled. If `block_id` changes mid-instruction, R13 reflects the new value immediately.

4. **Parameter vs runtime:** `THREAD_ID` and `THREADS_PER_BLOCK` are **compile-time** constants. You can't change them at runtime - they're baked into the hardware.

5. **Uninitialized registers:** After reset, R0-R12 are 0. Code that assumes specific initial values will break.
