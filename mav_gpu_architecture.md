# mav-gpu

A minimal GPU in Verilog, built from scratch to learn how GPUs work.

## Architecture

```
+------------------------------------------------------------------+
|                              GPU                                  |
|                                                                   |
|  +--------------------+                                           |
|  | Device Control Reg |  (thread_count)                           |
|  +--------------------+                                           |
|            |                                                      |
|            v                                                      |
|  +--------------------+                                           |
|  |    Dispatcher      |  (distributes blocks to cores)            |
|  +--------------------+                                           |
|            |                                                      |
|     +------+------+                                               |
|     |             |                                               |
|     v             v                                               |
|  +-------+     +-------+                                          |
|  |Core 0 |     |Core 1 | ...                                      |
|  |       |     |       |                                          |
|  | +---+ |     | +---+ |    Each Core:                            |
|  | |SCH| |     | |SCH| |    - Scheduler                           |
|  | +---+ |     | +---+ |    - Fetcher                             |
|  | |FET| |     | |FET| |    - Decoder                             |
|  | +---+ |     | +---+ |                                          |
|  | |DEC| |     | |DEC| |    Each Thread:                          |
|  | +---+ |     | +---+ |    - ALU (math)                          |
|  |       |     |       |    - LSU (memory)                        |
|  | T0 T1 |     | T0 T1 |    - PC  (program counter)               |
|  | T2 T3 |     | T2 T3 |    - RegFile (registers)                 |
|  +-------+     +-------+                                          |
|       |             |                                             |
|       +------+------+                                             |
|              |                                                    |
|              v                                                    |
|  +------------------------+                                       |
|  |        Cache           |                                       |
|  +------------------------+                                       |
|              |                                                    |
|              v                                                    |
|  +------------------------+                                       |
|  |   Memory Controllers   |                                       |
|  |  (Program)    (Data)   |                                       |
|  +------------------------+                                       |
+------------------------------------------------------------------+
               |
               v
+------------------------------------------------------------------+
|                       External Memory                             |
|  +-------------------------+  +-------------------------+         |
|  | Program Memory          |  | Data Memory             |         |
|  | (8-bit addr, 16-bit data)|  | (8-bit addr, 8-bit data)|        |
|  +-------------------------+  +-------------------------+         |
+------------------------------------------------------------------+
```

## Execution Cycle (6 stages)

```
FETCH --> DECODE --> REQUEST --> WAIT --> EXECUTE --> UPDATE
  ^                                                      |
  |______________________________________________________|
```

## ISA (11 Instructions)

```
NOP    - Do nothing, will be used to wait for something (memory, other threads)
BRnzp  - Branch if condition matches
CMP    - Compare two registers
ADD    - Add
SUB    - Subtract
MUL    - Multiply
DIV    - Divide
LDR    - Load from memory
STR    - Store to memory
CONST  - Load constant
RET    - End thread
```

## Instruction Details

### NOP (No Operation)

**History:** NOP is one of the oldest instructions in computing, present since the earliest computers in the 1940s-50s. The PDP-11 and Intel 8080 both had NOP instructions. The name comes from "No OPeration."

**What it does:** Consumes one clock cycle without changing any registers, memory, or flags. The processor simply advances to the next instruction.

**Why it's needed:**
- **Timing/Synchronization:** Wait for memory operations or other threads to complete
- **Pipeline stalls:** Fill pipeline bubbles when data dependencies exist
- **Alignment:** Pad code to memory boundaries for performance
- **Debugging:** Replace instructions temporarily without changing code layout

**Real use case:** In a GPU, when Thread 0 requests data from memory (which takes multiple cycles), it executes NOPs while waiting for the data to arrive, allowing other threads to continue working.

---

### BRnzp (Branch if Condition)

**History:** Conditional branching dates back to the 1940s with ENIAC and was formalized in the von Neumann architecture. The "nzp" notation (negative/zero/positive) comes from the LC-3 educational architecture, making conditions explicit in the instruction name.

**What it does:** Checks condition codes (set by a previous CMP instruction) and jumps to a target address if the specified condition matches. The "nzp" bits specify which conditions trigger the branch:
- n = negative (result < 0)
- z = zero (result == 0)
- p = positive (result > 0)

**Why it's needed:** Enables control flow - if statements, loops, and function calls. Without branching, programs would only execute linearly.

**Real use case:**
```
CMP R0, R1      ; Compare loop counter with limit
BRnz LOOP_END   ; If counter <= 0, exit loop
; ... loop body ...
BR LOOP_START   ; Jump back to start
```

---

### CMP (Compare)

**History:** Compare instructions emerged in early computers like the IBM 704 (1954). They evolved from subtract operations - comparing is essentially subtracting and checking the result without storing it.

**What it does:** Subtracts the second operand from the first and sets condition codes (negative, zero, positive) based on the result. The actual subtraction result is discarded.

**Why it's needed:** Separates comparison from arithmetic. You can compare values without modifying them, then use BRnzp to act on the result.

**Real use case:**
```
CMP R0, R1      ; Is R0 equal to R1?
BRz EQUAL       ; If zero flag set (R0-R1=0), they're equal
; ... handle not equal ...
```

---

### ADD (Addition)

**History:** Addition is fundamental to computing - Charles Babbage's Analytical Engine (1837) could add. Binary addition circuits (adders) were among the first digital logic circuits built.

**What it does:** Adds two values (registers or register + immediate) and stores the result in a destination register.

**Why it's needed:** Core arithmetic operation. Used for:
- Mathematical calculations
- Pointer arithmetic (array indexing)
- Loop counters
- Address calculations

**Real use case:** In GPU shader code calculating pixel position:
```
ADD R2, R0, R1   ; R2 = base_address + offset
ADD R3, R3, 1    ; Increment loop counter
```

---

### SUB (Subtraction)

**History:** Like addition, subtraction was in Babbage's design. In digital systems, subtraction is typically implemented using two's complement addition (invert and add 1).

**What it does:** Subtracts the second operand from the first and stores the result.

**Why it's needed:**
- Distance/difference calculations
- Countdown loops
- Negative number handling
- Comparison (CMP is often SUB that discards the result)

**Real use case:** Calculating distance between two vertices:
```
SUB R2, R0, R1   ; R2 = vertex1.x - vertex2.x
MUL R2, R2, R2   ; R2 = (difference)^2
```

---

### MUL (Multiplication)

**History:** Hardware multiplication was a luxury in early computers - the EDSAC (1949) took 5.4ms to multiply. Early microprocessors like the 8080 had no MUL instruction; you had to use repeated addition.

**What it does:** Multiplies two values and stores the result. In simple implementations, may only keep the lower bits of the result.

**Why it's needed:** Essential for:
- Graphics transformations (scaling, rotation matrices)
- Physics calculations
- Array indexing with stride
- Signal processing

**Real use case:** Scaling a vertex position in a shader:
```
CONST R1, 2      ; Load scale factor
MUL R0, R0, R1   ; position = position * 2
```

---

### DIV (Division)

**History:** Hardware division is complex - many early CPUs omitted it. The Intel 8086 (1978) was notable for including DIV. Division circuits are significantly larger than multipliers.

**What it does:** Divides the first operand by the second. May also produce a remainder in some architectures.

**Why it's needed:**
- Averaging values
- Normalizing vectors
- Converting coordinate systems
- Calculating ratios

**Real use case:** Normalizing a color value:
```
CONST R1, 255    ; Max color value
DIV R0, R0, R1   ; Normalize to 0.0-1.0 range
```

**Note:** Division is slow (often 10-40 cycles vs 1-4 for multiply), so GPUs often use reciprocal multiplication instead.

---

### LDR (Load Register)

**History:** Load/Store architecture was pioneered by CDC 6600 (1964) and became standard with RISC designs in the 1980s. The name "LDR" comes from ARM architecture conventions.

**What it does:** Reads a value from memory at a specified address and places it into a register.

**Why it's needed:** Registers are tiny but fast; memory is huge but slow. LDR bridges this gap, bringing data from memory into registers where the ALU can process it.

**Real use case:** Loading a pixel from a texture:
```
CONST R1, 0x100  ; Texture base address
ADD R1, R1, R0   ; Add pixel offset
LDR R2, R1       ; Load pixel value into R2
```

---

### STR (Store Register)

**History:** Paired with LDR, store instructions complete the load/store architecture. Together they enforce that all computation happens on registers, simplifying CPU design.

**What it does:** Writes the value from a register to a memory address.

**Why it's needed:** Results of computation must be saved back to memory for:
- Output (framebuffer, computed data)
- Sharing between threads
- Persisting beyond register lifetime

**Real use case:** Writing a computed pixel to the framebuffer:
```
; R0 = pixel address, R1 = color value
STR R1, R0       ; Write color to framebuffer
```

---

### CONST (Load Constant)

**History:** Immediate/constant loading has existed since early computers. RISC architectures often have dedicated instructions because they use fixed-width instructions that can't embed large constants directly.

**What it does:** Loads a hard-coded numeric value into a register. The value is encoded in the instruction itself, not fetched from memory.

**Why it's needed:**
- Initialize values (counters, addresses, constants)
- Magic numbers (π, screen dimensions, masks)
- Setting up base addresses
- Loop bounds

**Real use case:**
```
CONST R0, 64     ; Screen width
CONST R1, 0      ; Initialize counter to 0
CONST R2, 0xFF   ; Bit mask for byte extraction
```

---

### RET (Return / End Thread)

**History:** Return instructions date to subroutine support in the 1950s. In GPU contexts, RET often means "end this thread's execution" rather than returning from a function.

**What it does:** Signals that the current thread has finished executing. The thread's results are committed, and it no longer consumes execution resources.

**Why it's needed:**
- Tells the scheduler this thread is done
- Allows resources to be reallocated
- Triggers completion handling (e.g., "all threads done")
- In some designs, synchronizes with other threads

**Real use case:** End of a pixel shader:
```
; All computation done, result in R0
STR R0, R7       ; Write final pixel to framebuffer
RET              ; Thread complete, scheduler can reclaim slot
```