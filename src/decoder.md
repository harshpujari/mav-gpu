# Decoder - Line by Line Explanation

This document explains every line of `decoder.sv` for learning purposes.

---

## File Header (Lines 1-2)

```systemverilog
`default_nettype none
`timescale 1ns/1ns
```

Same as all other modules. `default_nettype none` catches typos at compile time. `timescale` sets simulation time units.

---

## What Does the Decoder Do?

The decoder is the **translation layer** between raw bits and hardware actions.

Every instruction is 16 bits. The decoder reads those bits and sets a collection of control signals that tell every other unit (ALU, register file, LSU, PC) what to do this cycle.

```
16-bit instruction
        │
        ▼
┌──────────────┐
│   DECODER    │──▶ reg_write_enable
│              │──▶ alu_arithmetic_selector
│  (runs once  │──▶ alu_output_selector
│   per instr) │──▶ mem_read_enable
│              │──▶ mem_write_enable
│              │──▶ nzp_write_enable
│              │──▶ reg_input_selector
└──────────────│──▶ pc_mux
               │──▶ decoded_ret
               │
               │──▶ rd_address
               │──▶ rs_address
               │──▶ rt_address
               │──▶ immediate
               └──▶ nzp condition
```

---

## Instruction Format

All instructions are 16 bits wide:

```
 15  14  13  12 │ 11  10   9   8 │  7   6   5   4 │  3   2   1   0
└───────────────┘└───────────────┘└───────────────┘└───────────────┘
    opcode [4]       rd/nzp [4]        rs [4]             rt [4]
                                  └─────────────────────────────────┘
                                            immediate [8]
```

| Bits | Field | Used By |
|------|-------|---------|
| [15:12] | Opcode | Decoder `case` statement |
| [11:8] | `rd` (destination register) | All register-writing instructions |
| [11:9] | `nzp` condition mask | BRnzp only (overlaps rd) |
| [7:4] | `rs` (source register 1) | ALU, LDR, STR |
| [3:0] | `rt` (source register 2) | ALU, STR |
| [7:0] | `immediate` | CONST, BRnzp branch target |

**Note:** `nzp` and `rd` overlap the same bits. `immediate` overlaps `rs` and `rt`. That's fine because each instruction only uses one interpretation.

---

## Module Declaration (Lines 6-36)

```systemverilog
module decoder (
    input wire clock,
    input wire reset,
    input reg [2:0] core_state,
    input reg [15:0] instruction,
    ...
);
```

**What it does:** Declares the decoder module with its ports.

| Port | Direction | Width | Purpose |
|------|-----------|-------|---------|
| `clock` | input wire | 1 | Heartbeat |
| `reset` | input wire | 1 | Force outputs to 0 |
| `core_state` | input reg | 3 | Which pipeline stage is active? |
| `instruction` | input reg | 16 | The fetched instruction to decode |

---

### Output Ports - Instruction Fields

```systemverilog
output reg [3:0] decoded_rd_address,
output reg [3:0] decoded_rs_address,
output reg [3:0] decoded_rt_address,
output reg [2:0] decoded_nzp,
output reg [7:0] decoded_immediate,
```

These are raw bit extractions from the instruction. They feed the register file (for addressing), the PC unit (nzp), and the registers/LSU (immediate).

| Signal | Bits | Width | Purpose |
|--------|------|-------|---------|
| `decoded_rd_address` | [11:8] | 4 | Which register to write result into |
| `decoded_rs_address` | [7:4] | 4 | First operand register address |
| `decoded_rt_address` | [3:0] | 4 | Second operand register address |
| `decoded_nzp` | [11:9] | 3 | Condition bits for branch (N/Z/P) |
| `decoded_immediate` | [7:0] | 8 | Constant value or branch offset |

---

### Output Ports - Control Signals

```systemverilog
output reg decoded_reg_write_enable,
output reg decoded_mem_read_enable,
output reg decoded_mem_write_enable,
output reg decoded_nzp_write_enable,
output reg [1:0] decoded_reg_input_selector,
output reg [1:0] decoded_alu_arithmetic_selector,
output reg decoded_alu_output_selector,
output reg decoded_pc_mux,
output reg decoded_ret
```

These are the "control signals" - each one enables or selects behavior in another unit.

| Signal | Width | Controls | Meaning When High |
|--------|-------|----------|-------------------|
| `decoded_reg_write_enable` | 1 | Register file | Write result to `rd` |
| `decoded_mem_read_enable` | 1 | LSU | Issue a memory read |
| `decoded_mem_write_enable` | 1 | LSU | Issue a memory write |
| `decoded_nzp_write_enable` | 1 | PC unit | Update the NZP condition register |
| `decoded_reg_input_selector` | 2 | Register file | Which source to write to `rd` |
| `decoded_alu_arithmetic_selector` | 2 | ALU | Which arithmetic op (ADD/SUB/MUL/DIV) |
| `decoded_alu_output_selector` | 1 | ALU | Arithmetic (0) vs comparison (1) mode |
| `decoded_pc_mux` | 1 | PC unit | Normal increment (0) vs branch target (1) |
| `decoded_ret` | 1 | Scheduler | This thread is done |

---

## Local Parameters (Lines 38-57)

### Opcodes

```systemverilog
localparam NOP   = 4'b0000,
           BRnzp = 4'b0001,
           CMP   = 4'b0010,
           ADD   = 4'b0011,
           SUB   = 4'b0100,
           MUL   = 4'b0101,
           DIV   = 4'b0110,
           LDR   = 4'b0111,
           STR   = 4'b1000,
           CONST = 4'b1001,
           RET   = 4'b1111;
```

**What it does:** Names the 4-bit opcode values so the `case` statement is readable.

| Opcode | Binary | Instruction | Operation |
|--------|--------|-------------|-----------|
| NOP | 0000 | No-op | Do nothing |
| BRnzp | 0001 | Branch | Jump if NZP condition matches |
| CMP | 0010 | Compare | Set NZP flags from rs vs rt |
| ADD | 0011 | Add | rd = rs + rt |
| SUB | 0100 | Subtract | rd = rs - rt |
| MUL | 0101 | Multiply | rd = rs * rt |
| DIV | 0110 | Divide | rd = rs / rt |
| LDR | 0111 | Load | rd = memory[rs] |
| STR | 1000 | Store | memory[rs] = rt |
| CONST | 1001 | Constant | rd = immediate |
| RET | 1111 | Return | Thread done |

---

### Register Write Source

```systemverilog
localparam REG_SRC_ARITHMETIC = 2'b00,
           REG_SRC_MEMORY     = 2'b01,
           REG_SRC_CONSTANT   = 2'b10;
```

**What it does:** Names the 3 possible sources for writing to a destination register.

| Value | Name | When Used |
|-------|------|-----------|
| `00` | ARITHMETIC | ADD, SUB, MUL, DIV, CMP |
| `01` | MEMORY | LDR (memory load) |
| `10` | CONSTANT | CONST (immediate) |

These values must match the `case` statement inside `registers.sv`.

---

### ALU Operation Selection

```systemverilog
localparam ALU_ADD = 2'b00,
           ALU_SUB = 2'b01,
           ALU_MUL = 2'b10,
           ALU_DIV = 2'b11;
```

**What it does:** Names the 4 arithmetic operations for `decoded_alu_arithmetic_selector`.

These values must match the `case` statement inside `alu.sv`.

---

### Pipeline Stage

```systemverilog
localparam DECODE = 3'b010;
```

**What it does:** The decoder only runs in pipeline stage 2.

**Full pipeline for reference:**
```
Stage │ Binary │ Name
──────┼────────┼─────────
  0   │  000   │ IDLE
  1   │  001   │ FETCH
  2   │  010   │ DECODE   ← decoder runs here
  3   │  011   │ REQUEST  (register file reads rs/rt)
  4   │  100   │ (waiting / memory)
  5   │  101   │ EXECUTE  (ALU runs)
  6   │  110   │ UPDATE   (register file writes rd)
```

---

## The Always Block

### Reset Logic

```systemverilog
always @(posedge clock) begin
    if (reset) begin
        decoded_rd_address            <= 4'b0;
        decoded_rs_address            <= 4'b0;
        ...
        decoded_ret                   <= 1'b0;
    end
```

**What it does:** On reset, clears every output to 0.

**Why clear all outputs?** If the decoder outputs are left at stale values, other units might see a "phantom" write enable or memory access from a previous instruction. Zeroing on reset ensures everything starts clean.

---

### DECODE Stage Guard

```systemverilog
end else begin
    if (core_state == DECODE) begin
```

**What it does:** The decoder only updates its outputs during the DECODE stage.

**Why?** After decoding, the control signals need to stay stable for the downstream pipeline stages (REQUEST, EXECUTE, UPDATE). If the decoder updated every cycle, it would corrupt the signals mid-instruction.

---

### Extracting Instruction Fields

```systemverilog
decoded_rd_address <= instruction[11:8];
decoded_rs_address <= instruction[7:4];
decoded_rt_address <= instruction[3:0];
decoded_immediate  <= instruction[7:0];
decoded_nzp        <= instruction[11:9];
```

**What it does:** Slices the 16-bit instruction into named fields.

**Example: `ADD R3, R1, R2` encoded as `0011_0011_0001_0010`:**
```
0011  │ 0011 │ 0001 │ 0010
 ADD  │  R3  │  R1  │  R2
[15:12]│[11:8]│[7:4] │[3:0]
```
- `decoded_rd_address` = `0011` = 3 (R3)
- `decoded_rs_address` = `0001` = 1 (R1)
- `decoded_rt_address` = `0010` = 2 (R2)

**Example: `CONST R5, #42` encoded as `1001_0101_0010_1010`:**
```
1001  │ 0101 │ 0010_1010
CONST │  R5  │    42
[15:12]│[11:8]│  [7:0]
```
- `decoded_rd_address` = 5 (R5)
- `decoded_immediate` = 42

---

### Defaulting Control Signals to 0

```systemverilog
decoded_reg_write_enable        <= 1'b0;
decoded_mem_read_enable         <= 1'b0;
decoded_mem_write_enable        <= 1'b0;
decoded_nzp_write_enable        <= 1'b0;
decoded_reg_input_selector      <= 2'b0;
decoded_alu_arithmetic_selector <= 2'b0;
decoded_alu_output_selector     <= 1'b0;
decoded_pc_mux                  <= 1'b0;
decoded_ret                     <= 1'b0;
```

**What it does:** Resets all control signals to 0 before the `case` statement sets them.

**Why not just rely on reset?** Because these are clocked registers - they hold their value from cycle to cycle. If the previous instruction was an ADD (which sets `reg_write_enable = 1`), the next NOP would also see `reg_write_enable = 1` unless we explicitly clear it here.

This is the "default-then-override" pattern:
```
Every DECODE cycle:
  1. Clear everything to 0
  2. Set only what THIS instruction needs
```

---

### The Case Statement - Per-Instruction Control

```systemverilog
case (instruction[15:12])
```

**What it does:** Switches on the 4-bit opcode to configure control signals.

---

#### NOP

```systemverilog
NOP: begin
    // No control signals needed - everything stays 0
end
```

All signals are already 0 from the defaults above. Nothing happens.

---

#### BRnzp

```systemverilog
BRnzp: begin
    decoded_pc_mux <= 1'b1;
end
```

**What it does:** Tells the PC unit to use the branch target (from `decoded_immediate`) instead of PC+1.

**When does the branch actually happen?** The PC unit checks the live NZP register against `decoded_nzp` bits at UPDATE time. If they match, it takes the branch.

---

#### CMP

```systemverilog
CMP: begin
    decoded_alu_output_selector <= 1'b1;
    decoded_nzp_write_enable    <= 1'b1;
end
```

**What it does:**
- `alu_output_selector = 1` → ALU runs in comparison mode (outputs NZP flags, not arithmetic result)
- `nzp_write_enable = 1` → PC unit stores those flags in its NZP register

**Note:** CMP does NOT set `reg_write_enable`. The NZP result goes to the PC unit, not a register.

---

#### ADD / SUB / MUL / DIV

```systemverilog
ADD: begin
    decoded_reg_write_enable        <= 1'b1;
    decoded_reg_input_selector      <= REG_SRC_ARITHMETIC;
    decoded_alu_arithmetic_selector <= ALU_ADD;
end
```

All four arithmetic instructions follow the same pattern, only `alu_arithmetic_selector` differs:

| Instruction | `alu_arithmetic_selector` | Result |
|-------------|--------------------------|--------|
| ADD | `ALU_ADD` (00) | rs + rt |
| SUB | `ALU_SUB` (01) | rs - rt |
| MUL | `ALU_MUL` (10) | rs * rt |
| DIV | `ALU_DIV` (11) | rs / rt |

`reg_input_selector = REG_SRC_ARITHMETIC` tells the register file to write the ALU result into rd.

---

#### LDR

```systemverilog
LDR: begin
    decoded_reg_write_enable   <= 1'b1;
    decoded_reg_input_selector <= REG_SRC_MEMORY;
    decoded_mem_read_enable    <= 1'b1;
end
```

**What it does:**
- `mem_read_enable = 1` → LSU sends a memory read request for address `rs`
- `reg_input_selector = REG_SRC_MEMORY` → register file writes the LSU result into rd (not the ALU)
- `reg_write_enable = 1` → the write actually happens

---

#### STR

```systemverilog
STR: begin
    decoded_mem_write_enable <= 1'b1;
end
```

**What it does:** LSU writes `rt` to memory address `rs`.

**Note:** No `reg_write_enable` - STR doesn't write to any register.

---

#### CONST

```systemverilog
CONST: begin
    decoded_reg_write_enable   <= 1'b1;
    decoded_reg_input_selector <= REG_SRC_CONSTANT;
end
```

**What it does:** Writes the immediate value directly into rd, bypassing both the ALU and LSU.

**Example:** `CONST R2, #100` → R2 = 100

---

#### RET

```systemverilog
RET: begin
    decoded_ret <= 1'b1;
end
```

**What it does:** Signals to the scheduler that this thread has finished executing. The scheduler uses this to mark the thread as done and eventually signal `done` to the dispatcher.

---

## Control Signal Summary Table

| Instruction | reg_write | mem_read | mem_write | nzp_write | reg_src | alu_arith | alu_cmp | pc_branch | ret |
|-------------|-----------|----------|-----------|-----------|---------|-----------|---------|-----------|-----|
| NOP | 0 | 0 | 0 | 0 | - | - | 0 | 0 | 0 |
| BRnzp | 0 | 0 | 0 | 0 | - | - | 0 | **1** | 0 |
| CMP | 0 | 0 | 0 | **1** | - | - | **1** | 0 | 0 |
| ADD | **1** | 0 | 0 | 0 | ARITH | **ADD** | 0 | 0 | 0 |
| SUB | **1** | 0 | 0 | 0 | ARITH | **SUB** | 0 | 0 | 0 |
| MUL | **1** | 0 | 0 | 0 | ARITH | **MUL** | 0 | 0 | 0 |
| DIV | **1** | 0 | 0 | 0 | ARITH | **DIV** | 0 | 0 | 0 |
| LDR | **1** | **1** | 0 | 0 | **MEM** | - | 0 | 0 | 0 |
| STR | 0 | 0 | **1** | 0 | - | - | 0 | 0 | 0 |
| CONST | **1** | 0 | 0 | 0 | **CONST** | - | 0 | 0 | 0 |
| RET | 0 | 0 | 0 | 0 | - | - | 0 | 0 | **1** |

---

## Control Flow Diagram

```
                    posedge clock
                          │
                          ▼
                    ┌───────────┐
                    │  reset?   │
                    └─────┬─────┘
                      yes │ no
              ┌───────────┴───────────┐
              ▼                       ▼
        all outputs = 0       ┌──────────────┐
                              │ core_state   │
                              │  == DECODE?  │
                              └──────┬───────┘
                                 yes │ no
                    ┌────────────────┴─────────┐
                    ▼                          ▼
            Extract fields              (hold previous
            Default signals to 0         output values)
                    │
                    ▼
            case(opcode)
            ┌───────────────────────────────────────┐
            │ NOP   │ BRnzp │ CMP │ ADD/SUB/MUL/DIV │
            │  -    │ pc_mux│ cmp │   alu + reg_wr   │
            │       │       │ nzp │                  │
            ├───────┴───────┴─────┴──────────────────┤
            │ LDR        │ STR       │ CONST │ RET   │
            │ mem_rd     │ mem_wr    │ imm   │ ret=1 │
            │ reg_wr     │           │ reg_wr│       │
            └────────────┴───────────┴───────┴───────┘
```

---

## Hardware Synthesized

The decoder is mostly combinational logic wrapped in flip-flops (because it's clocked). It synthesizes roughly to:

```
                    ┌──────────────────────────────────────────────┐
                    │                 DECODER                       │
                    │                                              │
instruction[15:12] ─┼──▶ ┌─────────────────┐                     │
                    │    │   4-to-11        │──▶ reg_write_enable  │
                    │    │   Decoder        │──▶ mem_read_enable   │
                    │    │   (case stmt)    │──▶ mem_write_enable  │
                    │    └─────────────────┘──▶ nzp_write_enable  │
                    │                      ──▶ reg_input_selector │
                    │                      ──▶ alu_arith_selector │
                    │                      ──▶ alu_output_selector│
                    │                      ──▶ pc_mux             │
                    │                      ──▶ decoded_ret        │
                    │                                              │
instruction[11:8]  ─┼──▶ D flip-flop ──▶ decoded_rd_address      │
instruction[7:4]   ─┼──▶ D flip-flop ──▶ decoded_rs_address      │
instruction[3:0]   ─┼──▶ D flip-flop ──▶ decoded_rt_address      │
instruction[7:0]   ─┼──▶ D flip-flop ──▶ decoded_immediate       │
instruction[11:9]  ─┼──▶ D flip-flop ──▶ decoded_nzp             │
                    │                                              │
core_state ────────▶│──▶ (enable gate for all outputs)           │
clock ─────────────▶│──▶ (all flip-flops)                        │
reset ─────────────▶│──▶ (all flip-flops)                        │
                    └──────────────────────────────────────────────┘
```

---

## Common Gotchas

1. **Forgetting the default-zero block:** If you remove the block that zeros all control signals before the `case`, stale signals from the previous instruction leak into the current one. E.g., an ADD followed by a NOP would still see `reg_write_enable = 1`.

2. **NZP vs RD bit overlap:** `decoded_nzp` and `decoded_rd_address` overlap at `[11:8]`/`[11:9]`. Only BRnzp uses `decoded_nzp`; all others use `decoded_rd_address`. Don't mix them up.

3. **Immediate vs RS/RT overlap:** `decoded_immediate` (`[7:0]`) overlaps `decoded_rs_address` (`[7:4]`) and `decoded_rt_address` (`[3:0]`). Only CONST and BRnzp use `decoded_immediate` as the real value; arithmetic instructions use `rs`/`rt`.

4. **Decoder outputs are registered (clocked):** Unlike a pure combinational decoder, this one updates on clock edges. This means outputs are available one cycle after the DECODE stage. Downstream units must read them in the following stage.

5. **CMP doesn't write a register:** CMP updates the NZP condition register inside the PC unit, not a general-purpose register. `decoded_reg_write_enable` stays 0 for CMP.

6. **STR needs both rs and rt:** STR uses `rs` as the memory address and `rt` as the data to store. Both register addresses are decoded correctly since the bit fields are always extracted regardless of instruction type.
