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