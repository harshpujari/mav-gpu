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

## Architecture Component Details

### Device Control Register

**History:** Control registers date back to the earliest programmable computers. The IBM System/360 (1964) formalized the concept of control and status registers (CSRs). In GPUs, NVIDIA's CUDA introduced the concept of configuring kernel launches through device-side registers.

**What it does:** Stores configuration parameters that control GPU operation, such as `thread_count`. The host CPU writes to this register to tell the GPU how many threads to launch before starting execution.

**Why it's needed:**
- **Configuration:** Sets up execution parameters before launch
- **Host-Device communication:** Bridge between CPU and GPU
- **Flexibility:** Same hardware can run different workload sizes
- **Synchronization:** Signals when to start/stop execution

**Real use case:** Before running a shader on 64 pixels, the CPU writes `64` to the thread_count register. The GPU reads this value and knows to spawn 64 threads, one per pixel.

---

### Dispatcher

**History:** Work distribution mechanisms evolved from batch processing systems in the 1960s. Modern GPU dispatchers descend from the "Grid/Block/Thread" hierarchy introduced by NVIDIA's CUDA in 2007, which revolutionized how parallel work is organized.

**What it does:** Takes the total work (thread_count) and distributes it across available cores. It divides threads into blocks and assigns blocks to cores, balancing the workload.

**Why it's needed:**
- **Load balancing:** Ensures all cores stay busy
- **Scalability:** Same program runs on GPUs with different core counts
- **Abstraction:** Programmers don't need to manually assign work to cores
- **Resource management:** Tracks which cores are available

**Real use case:** With 64 threads and 2 cores (4 threads each), the dispatcher creates 16 blocks of 4 threads. It assigns blocks 0-7 to Core 0 and blocks 8-15 to Core 1, keeping both cores equally busy.

---

### Core

**History:** The concept of multiple processing cores dates to the CDC 6600 (1964) with its peripheral processors. GPU cores evolved from fixed-function pixel pipelines in the 1990s to programmable "Streaming Multiprocessors" (NVIDIA) or "Compute Units" (AMD) in the 2000s.

**What it does:** A self-contained processing unit that executes multiple threads. Each core has its own scheduler, fetcher, decoder, and multiple thread execution units. Cores operate independently in parallel.

**Why it's needed:**
- **Parallelism:** Multiple cores = multiple independent execution streams
- **Throughput:** More cores = more work done simultaneously
- **Isolation:** Failures or stalls in one core don't affect others
- **Scalability:** Add more cores for more performance

**Real use case:** Core 0 might be processing pixels 0-15 of an image while Core 1 simultaneously processes pixels 16-31, doubling the throughput compared to a single core.

---

### Scheduler (SCH)

**History:** Thread scheduling originated in timesharing systems like CTSS (1961). GPU schedulers evolved from simple round-robin to sophisticated warp schedulers that hide memory latency by switching between thread groups.

**What it does:** Decides which thread executes each cycle. When a thread stalls (waiting for memory), the scheduler switches to another ready thread, keeping the execution units busy.

**Why it's needed:**
- **Latency hiding:** Memory access takes many cycles; switch to other work while waiting
- **Fairness:** Ensures all threads make progress
- **Efficiency:** Maximizes ALU utilization by always having work ready
- **Deadlock prevention:** Manages dependencies between threads

**Real use case:** Thread 0 issues a memory load (takes 100 cycles). Instead of waiting, the scheduler runs Threads 1, 2, 3... By the time it cycles back to Thread 0, the data has arrived. Zero cycles wasted.

---

### Fetcher (FET)

**History:** Instruction fetching has existed since stored-program computers (EDSAC, 1949). Modern fetchers include prefetching (Intel 8086) and branch prediction to keep the pipeline full.

**What it does:** Reads the next instruction from program memory using the Program Counter (PC). It sends a memory request and receives the raw instruction bits.

**Why it's needed:**
- **Instruction supply:** The processor needs instructions to execute
- **Decoupling:** Separates memory access from execution
- **Pipelining:** Can fetch next instruction while current one executes
- **Abstraction:** Hides memory latency from the rest of the pipeline

**Real use case:** PC = 0x10, Fetcher sends read request to program memory address 0x10, receives 16-bit instruction `0x1234`, passes it to the decoder.

---

### Decoder (DEC)

**History:** Instruction decoding dates to the earliest computers. RISC architectures (1980s) simplified decoding with fixed-width instructions. CISC processors like x86 have complex multi-stage decoders.

**What it does:** Takes raw instruction bits and extracts: opcode (which operation), source registers, destination register, immediate values, and other fields. Converts binary encoding to control signals.

**Why it's needed:**
- **Interpretation:** Translates compact binary encoding into actionable signals
- **Flexibility:** Same hardware handles different instruction types
- **Efficiency:** Compact instruction encoding saves memory
- **Control:** Generates signals that drive ALU, registers, memory units

**Real use case:** Instruction `0x1234` is decoded as: opcode=ADD, dest=R1, src1=R2, src2=R3. The decoder outputs control signals: ALU_op=ADD, write_reg=R1, read_reg1=R2, read_reg2=R3.

---

### ALU (Arithmetic Logic Unit)

**History:** The ALU concept was defined in von Neumann's 1945 "First Draft" report. The first single-chip ALU was the Intel 74181 (1970). Modern GPUs have hundreds of ALUs per chip.

**What it does:** Performs arithmetic operations (ADD, SUB, MUL, DIV) and logical operations (AND, OR, comparison). Takes two inputs and produces one output based on the operation code.

**Why it's needed:**
- **Computation:** The actual "work" of the processor happens here
- **Speed:** Hardwired circuits are faster than software calculation
- **Versatility:** One unit handles all math/logic operations
- **Parallelism:** GPUs have many ALUs for massive throughput

**Real use case:** Inputs: A=5, B=3, Op=MUL. Output: 15. This single operation might be calculating one component of a vertex transformation in a 3D graphics shader.

---

### LSU (Load/Store Unit)

**History:** Load/Store units became distinct from ALUs in RISC architectures (1980s). The CDC 6600 was an early machine with separate functional units for memory operations.

**What it does:** Handles all memory operations (LDR, STR). Calculates addresses, sends requests to the memory system, and handles data transfer between registers and memory.

**Why it's needed:**
- **Memory access:** ALU computes, LSU moves data
- **Address calculation:** May involve base + offset arithmetic
- **Synchronization:** Manages memory request/response timing
- **Coalescing:** Can combine multiple thread requests into one memory transaction

**Real use case:** Thread executes `LDR R0, [R1]`. LSU takes address from R1 (say, 0x50), sends read request to memory, waits for response, writes returned data into R0.

---

### PC (Program Counter)

**History:** The program counter was part of von Neumann's original architecture (1945). Also called Instruction Pointer (IP) in x86. It's the most fundamental register in any processor.

**What it does:** Holds the memory address of the current/next instruction to execute. Normally increments by instruction size after each instruction. Branch instructions modify it to jump elsewhere.

**Why it's needed:**
- **Sequential execution:** Tracks where we are in the program
- **Control flow:** Modified by branches to implement loops/conditionals
- **Per-thread state:** Each thread has its own PC (threads can diverge)
- **Debugging:** Knowing the PC tells you exactly where execution is

**Real use case:** PC=0x00, execute instruction, PC becomes 0x02. If that instruction was `BR 0x10`, PC becomes 0x10 instead, jumping to a different part of the program.

---

### Register File (RegFile)

**History:** Register files evolved from single accumulators in early computers to multiple general-purpose registers (IBM System/360, 1964). GPUs have massive register files to support many threads.

**What it does:** A small, fast memory array holding the working data for a thread. Typically 8-32 registers per thread. Supports reading two registers and writing one register per cycle.

**Why it's needed:**
- **Speed:** Registers are the fastest storage (single-cycle access)
- **Operand supply:** ALU needs data from somewhere close
- **Temporary storage:** Hold intermediate calculation results
- **Per-thread state:** Each thread has private registers

**Real use case:** Computing `a = b + c * d`:
```
R0 = c (from memory)
R1 = d (from memory)
R2 = R0 * R1       ; R2 = c * d
R3 = b (from memory)
R0 = R3 + R2       ; R0 = b + c*d (reusing R0)
```

---

### Cache

**History:** Caches were invented for the IBM System/360 Model 85 (1968). The idea came from observing that programs access the same memory locations repeatedly (locality). GPUs added caches relatively late, with NVIDIA's Fermi (2010) adding significant L1/L2 caches.

**What it does:** Stores recently accessed data closer to the cores. When data is requested, the cache checks if it has a copy (hit) before going to slow main memory (miss).

**Why it's needed:**
- **Speed:** Cache access is ~10x faster than memory
- **Bandwidth:** Reduces traffic to memory controllers
- **Locality:** Programs often reuse data (spatial/temporal locality)
- **Shared data:** Multiple threads accessing same data hit cache

**Real use case:** Thread 0 loads texture pixel at address 0x100. It's cached. Threads 1-15 also need nearby pixels (0x101-0x10F). Cache serves them all instantly instead of 16 separate memory requests.

---

### Memory Controllers

**History:** Memory controllers were originally separate chips. Integration onto the CPU/GPU die began in the 2000s (AMD Athlon 64, 2003). Modern GPUs have multiple controllers for bandwidth.

**What it does:** Manages communication between the GPU and external memory. Handles read/write requests, timing, refresh (for DRAM), and arbitration between multiple requesters.

**Why it's needed:**
- **Protocol handling:** Memory (DDR, GDDR) has complex timing requirements
- **Arbitration:** Multiple cores compete for memory access
- **Bandwidth optimization:** Reorders requests for efficiency
- **Separation:** Program memory vs data memory have different needs

**Real use case:** Core 0 and Core 1 both request data simultaneously. The memory controller queues the requests, sends them to DRAM respecting timing constraints, and routes responses back to the correct cores.

---

### Program Memory

**History:** The concept of stored programs (code in memory) was revolutionary in the 1940s, replacing hardwired programming. Harvard architecture (separate program/data memory) was used in the Harvard Mark I (1944).

**What it does:** Stores the compiled shader/kernel instructions. Read-only during execution. Addressed by the Program Counter, returns instruction bits to the Fetcher.

**Why it's needed:**
- **Instruction storage:** The program has to live somewhere
- **Separation:** Isolates code from data (security, simplicity)
- **Read-only:** Instructions don't change during execution
- **Shared:** All threads read from the same program memory

**Real use case:** A pixel shader compiled to 20 instructions is loaded into program memory at addresses 0x00-0x28. All 64 threads fetch and execute these same instructions (with different data).

---

### Data Memory

**History:** Data memory has existed since the earliest computers. The separation from program memory (Harvard architecture) allows simultaneous instruction fetch and data access, improving performance.

**What it does:** Stores input data, output results, and intermediate values. Read/write accessible. This is where textures, vertex data, and framebuffer pixels live.

**Why it's needed:**
- **Input:** Source data for computation (textures, vertices)
- **Output:** Results of computation (rendered pixels)
- **Working space:** Large arrays that don't fit in registers
- **Thread communication:** Shared memory for thread cooperation

**Real use case:** Input texture at addresses 0x000-0x0FF. Output framebuffer at addresses 0x100-0x1FF. Each thread loads a pixel from input, processes it, stores result to output.

---

## Execution Cycle Details

### FETCH Stage

**What happens:** The fetcher uses the PC to read an instruction from program memory. A memory request is sent, and we wait for the instruction bits to return.

**Why it's a separate stage:** Memory access takes time. By making it explicit, we can overlap fetching with other work.

---

### DECODE Stage

**What happens:** The raw instruction bits are parsed. Opcode is extracted, register numbers are identified, immediate values are sign-extended, and control signals are generated.

**Why it's a separate stage:** Decoding is combinational logic that takes time. Separating it allows pipelining.

---

### REQUEST Stage

**What happens:** If the instruction needs memory (LDR/STR), the LSU calculates the address and sends a request to the memory system. For ALU operations, operands are read from registers.

**Why it's a separate stage:** Sets up everything needed for execution. Memory requests are initiated early to hide latency.

---

### WAIT Stage

**What happens:** For memory operations, we wait for data to return from cache/memory. For ALU operations, this may be a pass-through or used for multi-cycle operations (like division).

**Why it's a separate stage:** Memory latency is variable and unpredictable. This stage absorbs that variability.

---

### EXECUTE Stage

**What happens:** The ALU performs the actual computation, or the memory data becomes available. The result is produced and ready to be stored.

**Why it's a separate stage:** This is where the actual work happens. Keeping it separate allows clear timing.
---

### UPDATE Stage

**What happens:** Results are written back to the register file. The PC is updated (incremented, or set to branch target). Thread state is updated for the next cycle.

**Why it's a separate stage:** Ensures clean state transitions. All writes happen at the same time, avoiding hazards.

---

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