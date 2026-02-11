# ALU (Arithmetic Logic Unit) - Line by Line Explanation

This document explains every line of `alu.sv` for learning purposes.

---

## File Header (Lines 1-2)

```systemverilog
`default_nettype none
```
**What it does:** Disables implicit net declarations.

**Why it matters:** Without this, if you typo a signal name (e.g., `clok` instead of `clock`), Verilog silently creates a new 1-bit wire instead of giving an error. This directive forces you to declare all signals explicitly - catching typos at compile time.

```systemverilog
`timescale 1ns/1ns
```
**What it does:** Sets the time unit and precision for simulation.

**Format:** `` `timescale <unit>/<precision> ``

| Part | Meaning |
|------|---------|
| `1ns` (unit) | `#1` in code = 1 nanosecond |
| `1ns` (precision) | Simulator resolves time to 1ns granularity |

**Example:** `#5` means "wait 5 nanoseconds"

---

## Module Declaration (Lines 4-14)

```systemverilog
module alu(
```
**What it does:** Declares a new hardware module named `alu`.

**Analogy:** Like a function definition, but for hardware. This "function" runs continuously and in parallel with everything else.

---

### Input Ports (Lines 5-12)

```systemverilog
input wire clock,
```
| Keyword | Meaning |
|---------|---------|
| `input` | Signal comes from outside this module |
| `wire` | Continuous connection (like a physical wire) |
| `clock` | Name of the signal |

**Purpose:** The clock is the "heartbeat" - all sequential logic updates on clock edges.

---

```systemverilog
input wire reset,
```
**Purpose:** When high (1), forces the ALU to a known initial state. Essential for:
- Simulation (starting from a known state)
- Real hardware (power-on reset)

---

```systemverilog
input wire enable,
```
**Purpose:** Allows the ALU to be "turned off" while clock is still running.

**GPU Context:** In SIMT (Single Instruction, Multiple Threads), some threads may be masked/inactive. This signal controls that.

---

```systemverilog
input reg [2:0] core_state,
```
| Part | Meaning |
|------|---------|
| `[2:0]` | 3-bit bus (bits 2, 1, and 0) |
| `reg` | Can hold a value (though here it's an input, so driven externally) |

**Purpose:** The GPU core has multiple pipeline stages. This tells the ALU which stage is active.

**Possible values:** `000` to `111` (0-7 in decimal), but only `101` (EXECUTE) triggers computation.

---

```systemverilog
input reg [1:0] decoded_alu_arithmetic_selector,
```
**Purpose:** 2-bit selector for which arithmetic operation to perform.

| Binary | Decimal | Operation |
|--------|---------|-----------|
| `00` | 0 | ADD |
| `01` | 1 | SUB |
| `10` | 2 | MUL |
| `11` | 3 | DIV |

---

```systemverilog
input reg decoded_alu_output_selector,
```
**Purpose:** 1-bit mode selector.

| Value | Mode |
|-------|------|
| `0` | Arithmetic (ADD/SUB/MUL/DIV) |
| `1` | Comparison (output NZP flags) |

---

```systemverilog
input reg [7:0] rs,
input reg [7:0] rt,
```
**Purpose:** The two 8-bit operands (source registers).

**Naming:** `rs` and `rt` are traditional MIPS register names:
- `rs` = Register Source
- `rt` = Register Target

**Range:** 0-255 (unsigned 8-bit)

---

```systemverilog
output wire [7:0] alu_out
```
**Purpose:** The 8-bit result of the ALU operation.

**Note:** No comma after the last port - this is a common syntax gotcha!

---

## Local Parameters (Lines 16-19)

```systemverilog
localparam ADD = 2'b00,
           SUB = 2'b01,
           MUL = 2'b10,
           DIV = 2'b11;
```

**What it does:** Defines named constants.

| Keyword | Meaning |
|---------|---------|
| `localparam` | Constant, local to this module (can't be overridden) |
| `2'b00` | 2-bit binary value `00` |

**Why use this:** Instead of writing `2'b00` everywhere, we write `ADD`. This is:
- More readable
- Easier to change
- Self-documenting

---

## Internal Register (Lines 22-23)

```systemverilog
reg [7:0] alu_out_reg;
assign alu_out = alu_out_reg;
```

**Why two signals?**

```
┌─────────────────────────────────────────┐
│  always @(posedge clock)                │
│     │                                   │
│     ▼                                   │
│  alu_out_reg  ──────▶  alu_out          │
│  (register)      assign   (wire/output) │
│  "storage"              "connection"    │
└─────────────────────────────────────────┘
```

- `alu_out_reg`: Internal storage (can be written in `always` block)
- `alu_out`: Output port (directly mirrors the register)
- `assign`: Continuous assignment - `alu_out` always equals `alu_out_reg`

**Rule:** You can't directly assign to an `output wire` inside an `always` block. This pattern solves that.

---

## Execute State Parameter (Line 26)

```systemverilog
localparam EXECUTE = 3'b101;
```

**Purpose:** The ALU only computes when the core is in the EXECUTE stage (stage 5 of the pipeline).

**Binary:** `101` = 5 in decimal

---

## The Always Block (Lines 28-52)

```systemverilog
always @(posedge clock) begin
```

**What it does:** This block executes on every **rising edge** of the clock.

```
clock:  ___/▔▔▔\___/▔▔▔\___/▔▔▔\___
           ↑       ↑       ↑
           │       │       │
        Execute  Execute  Execute
         block    block    block
```

| Keyword | Meaning |
|---------|---------|
| `always` | This block runs repeatedly forever |
| `@(...)` | Sensitivity list - when to trigger |
| `posedge clock` | Trigger on rising edge of clock |

---

### Reset Logic (Lines 29-30)

```systemverilog
if (reset) begin
    alu_out_reg <= 8'b0;
end
```

**What it does:** If `reset` is high, set output to 0.

**The `<=` operator:** This is **non-blocking assignment**.

| Operator | Name | Behavior |
|----------|------|----------|
| `<=` | Non-blocking | Updates happen at end of time step (use in sequential logic) |
| `=` | Blocking | Updates happen immediately (use in combinational logic) |

**Rule of thumb:** Always use `<=` inside `always @(posedge clock)` blocks.

---

### Enable Check (Line 31)

```systemverilog
end else if (enable) begin
```

**What it does:** Only proceed if the ALU is enabled.

**GPU Context:** If this thread is masked (inactive), `enable` is low and the ALU holds its previous value.

---

### State Check (Line 33)

```systemverilog
if (core_state == EXECUTE) begin
```

**What it does:** Only compute during the EXECUTE pipeline stage.

**Pipeline stages might be:**
```
000 = FETCH
001 = DECODE
010 = ...
101 = EXECUTE  ← ALU active here
110 = WRITEBACK
...
```

---

### Mode Selection (Lines 34-49)

#### Comparison Mode (Lines 34-40)

```systemverilog
if (decoded_alu_output_selector == 1'b1) begin
    alu_out_reg <= {5'b0,
                   (rs < rt),
                   (rs == rt),
                   (rs > rt)};
end
```

**What it does:** Compares `rs` and `rt`, outputs NZP (Negative/Zero/Positive) flags.

**The `{}` operator:** Concatenation - joins bits together.

```
alu_out_reg = { 5'b0,     (rs < rt),  (rs == rt), (rs > rt) }
               ─────     ──────────  ───────────  ──────────
              bits 7-3     bit 2        bit 1       bit 0
              (unused)   Negative      Zero       Positive
```

**Example:** If `rs = 5` and `rt = 10`:
- `rs < rt` → `1` (true)
- `rs == rt` → `0` (false)
- `rs > rt` → `0` (false)
- Result: `8'b00000100` = 4

---

#### Arithmetic Mode (Lines 41-48)

```systemverilog
end else begin
    case (decoded_alu_arithmetic_selector)
        ADD: alu_out_reg <= rs + rt;
        SUB: alu_out_reg <= rs - rt;
        MUL: alu_out_reg <= rs * rt;
        DIV: alu_out_reg <= rs / rt;
    endcase
end
```

**The `case` statement:** Like a switch statement in C.

| Selector | Operation | Example (rs=10, rt=3) |
|----------|-----------|----------------------|
| `00` (ADD) | `rs + rt` | 10 + 3 = 13 |
| `01` (SUB) | `rs - rt` | 10 - 3 = 7 |
| `10` (MUL) | `rs * rt` | 10 × 3 = 30 |
| `11` (DIV) | `rs / rt` | 10 ÷ 3 = 3 (integer) |

**Note on overflow:** These are 8-bit operations. `200 + 100 = 44` (wraps around at 256).

**Note on division:** Integer division only. `10 / 3 = 3`, not 3.33.

---

## Module End (Line 54)

```systemverilog
endmodule
```

**What it does:** Closes the module definition.

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
        out <= 0              ┌───────────┐
                              │  enable?  │
                              └─────┬─────┘
                                yes │ no
                    ┌───────────────┴───────────┐
                    ▼                           ▼
              ┌───────────┐               (hold value)
              │ EXECUTE?  │
              └─────┬─────┘
                yes │ no
    ┌───────────────┴───────────────┐
    ▼                               ▼
┌────────────┐                (hold value)
│ selector?  │
└─────┬──────┘
   0  │  1
┌─────┴─────┐
▼           ▼
Arithmetic  Comparison
(case)      (NZP flags)
```

---

## Hardware Synthesized

This Verilog synthesizes to approximately:

```
        ┌─────────────────────────────────────────┐
        │                 ALU                      │
        │  ┌─────────┐                            │
rs[7:0]─┼─▶│         │    ┌──────┐                │
        │  │  Adder/ │───▶│      │                │
rt[7:0]─┼─▶│  Mult/  │    │ MUX  │───▶alu_out_reg─┼──▶alu_out
        │  │  Div    │    │      │        │       │
        │  └─────────┘    │      │        │       │
        │  ┌─────────┐    │      │   ┌────┴────┐  │
        │  │Comparator├──▶│      │   │ 8-bit   │  │
        │  └─────────┘    └──┬───┘   │ Register│  │
        │                    │       └────┬────┘  │
        │  selector─────────▶│            │       │
        │  enable────────────┼────────────┤       │
        │  reset─────────────┼────────────┤       │
        │  clock─────────────┼────────────┘       │
        │  core_state────────┘                    │
        └─────────────────────────────────────────┘
```

---

## Common Gotchas

1. **Forgetting `<= ` vs `=`**: Use `<=` in sequential (clocked) logic
2. **Missing `default` in case**: If selector has undefined value, behavior is undefined
3. **Division by zero**: `rs / 0` is undefined - real hardware needs protection
4. **Signed vs unsigned**: This ALU treats everything as unsigned. `-1` would be `255`
