1. alu.sv        → Test: does 2+3=5?
2. regfile.sv    → Test: write R1, read R1 back
3. pc.sv         → Test: increment, branch
4. decoder.sv    → Test: feed instruction, check control signals
5. fetcher.sv    → Test: fetch from mock memory
6. lsu.sv        → Test: load/store from mock memory
7. scheduler.sv  → Test: state machine transitions
8. core.sv       → Test: run single instruction
9. controller.sv → Test: handle memory requests
10. dispatcher.sv → Test: distribute blocks
11. gpu.sv       → Test: run full kernel

What's happening RN ?
Week 1: ALU + testbench
Week 2: RegFile + PC + testbenches
Week 3: Decoder + Fetcher
...