# Makefile for GPU testbench simulation
# Uses Icarus Verilog (iverilog) for compilation and vvp for simulation

# Directories
SRC_DIR = ../src
TEST_DIR = .

# Source files
ALU_SRC       = $(SRC_DIR)/alu.sv
ALU_TB        = $(TEST_DIR)/alu_tb.sv
DECODER_SRC   = $(SRC_DIR)/decoder.sv
DECODER_TB    = $(TEST_DIR)/decoder_tb.sv
REGISTERS_SRC = $(SRC_DIR)/registers.sv
REGISTERS_TB  = $(TEST_DIR)/registers_tb.sv
PC_SRC        = $(SRC_DIR)/pc.sv
PC_TB         = $(TEST_DIR)/pc_tb.sv
FETCHER_SRC   = $(SRC_DIR)/fetcher.sv
FETCHER_TB    = $(TEST_DIR)/fetcher_tb.sv
LSU_SRC       = $(SRC_DIR)/lsu.sv
LSU_TB        = $(TEST_DIR)/lsu_tb.sv
SCHEDULER_SRC = $(SRC_DIR)/scheduler.sv
SCHEDULER_TB  = $(TEST_DIR)/scheduler_tb.sv
CORE_SRC      = $(SRC_DIR)/core.sv $(SRC_DIR)/scheduler.sv $(SRC_DIR)/fetcher.sv $(SRC_DIR)/decoder.sv $(SRC_DIR)/alu.sv $(SRC_DIR)/lsu.sv $(SRC_DIR)/registers.sv $(SRC_DIR)/pc.sv
CORE_TB       = $(TEST_DIR)/core_tb.sv

# Output files
ALU_OUT       = alu_tb.vvp
ALU_VCD       = alu_tb.vcd
DECODER_OUT   = decoder_tb.vvp
DECODER_VCD   = decoder_tb.vcd
REGISTERS_OUT = registers_tb.vvp
REGISTERS_VCD = registers_tb.vcd
PC_OUT        = pc_tb.vvp
PC_VCD        = pc_tb.vcd
FETCHER_OUT   = fetcher_tb.vvp
FETCHER_VCD   = fetcher_tb.vcd
LSU_OUT       = lsu_tb.vvp
LSU_VCD       = lsu_tb.vcd
SCHEDULER_OUT = scheduler_tb.vvp
SCHEDULER_VCD = scheduler_tb.vcd
CORE_OUT      = core_tb.vvp
CORE_VCD      = core_tb.vcd

# Compiler flags
IVERILOG = iverilog
IVFLAGS  = -g2012 -Wall
VVP      = vvp

# Default target - run all testbenches
all: alu decoder registers pc fetcher lsu scheduler core

# Compile and run ALU testbench
alu: $(ALU_OUT)
	$(VVP) $(ALU_OUT)

$(ALU_OUT): $(ALU_SRC) $(ALU_TB)
	$(IVERILOG) $(IVFLAGS) -o $(ALU_OUT) $(ALU_TB) $(ALU_SRC)

# Compile and run decoder testbench
decoder: $(DECODER_OUT)
	$(VVP) $(DECODER_OUT)

$(DECODER_OUT): $(DECODER_SRC) $(DECODER_TB)
	$(IVERILOG) $(IVFLAGS) -o $(DECODER_OUT) $(DECODER_TB) $(DECODER_SRC)

# Compile and run register file testbench
registers: $(REGISTERS_OUT)
	$(VVP) $(REGISTERS_OUT)

$(REGISTERS_OUT): $(REGISTERS_SRC) $(REGISTERS_TB)
	$(IVERILOG) $(IVFLAGS) -o $(REGISTERS_OUT) $(REGISTERS_TB) $(REGISTERS_SRC)

# Compile and run program counter testbench
pc: $(PC_OUT)
	$(VVP) $(PC_OUT)

$(PC_OUT): $(PC_SRC) $(PC_TB)
	$(IVERILOG) $(IVFLAGS) -o $(PC_OUT) $(PC_TB) $(PC_SRC)

# Compile and run fetcher testbench
fetcher: $(FETCHER_OUT)
	$(VVP) $(FETCHER_OUT)

$(FETCHER_OUT): $(FETCHER_SRC) $(FETCHER_TB)
	$(IVERILOG) $(IVFLAGS) -o $(FETCHER_OUT) $(FETCHER_TB) $(FETCHER_SRC)

# Compile and run LSU testbench
lsu: $(LSU_OUT)
	$(VVP) $(LSU_OUT)

$(LSU_OUT): $(LSU_SRC) $(LSU_TB)
	$(IVERILOG) $(IVFLAGS) -o $(LSU_OUT) $(LSU_TB) $(LSU_SRC)

# Compile and run scheduler testbench
scheduler: $(SCHEDULER_OUT)
	$(VVP) $(SCHEDULER_OUT)

$(SCHEDULER_OUT): $(SCHEDULER_SRC) $(SCHEDULER_TB)
	$(IVERILOG) $(IVFLAGS) -o $(SCHEDULER_OUT) $(SCHEDULER_TB) $(SCHEDULER_SRC)

# Compile and run core integration testbench (instantiates all submodules)
core: $(CORE_OUT)
	$(VVP) $(CORE_OUT)

$(CORE_OUT): $(CORE_SRC) $(CORE_TB)
	$(IVERILOG) $(IVFLAGS) -o $(CORE_OUT) $(CORE_TB) $(CORE_SRC)

# View waveforms (requires GTKWave)
waves-alu: $(ALU_VCD)
	gtkwave $(ALU_VCD) &

waves-decoder: $(DECODER_VCD)
	gtkwave $(DECODER_VCD) &

waves-registers: $(REGISTERS_VCD)
	gtkwave $(REGISTERS_VCD) &

waves-pc: $(PC_VCD)
	gtkwave $(PC_VCD) &

waves-fetcher: $(FETCHER_VCD)
	gtkwave $(FETCHER_VCD) &

waves-lsu: $(LSU_VCD)
	gtkwave $(LSU_VCD) &

waves-scheduler: $(SCHEDULER_VCD)
	gtkwave $(SCHEDULER_VCD) &

waves-core: $(CORE_VCD)
	gtkwave $(CORE_VCD) &

# Clean build artifacts
clean:
	rm -f *.vvp *.vcd

# Help
help:
	@echo "Available targets:"
	@echo "  all             - Compile and run all testbenches (default)"
	@echo "  alu             - Compile and run ALU testbench"
	@echo "  decoder         - Compile and run decoder testbench"
	@echo "  registers       - Compile and run register file testbench"
	@echo "  pc              - Compile and run program counter testbench"
	@echo "  fetcher         - Compile and run fetcher testbench"
	@echo "  lsu             - Compile and run LSU testbench"
	@echo "  scheduler       - Compile and run scheduler testbench"
	@echo "  core            - Compile and run core integration testbench"
	@echo "  waves-alu       - Open ALU waveform viewer (requires GTKWave)"
	@echo "  waves-decoder   - Open decoder waveform viewer (requires GTKWave)"
	@echo "  waves-registers - Open register file waveform viewer (requires GTKWave)"
	@echo "  waves-pc        - Open program counter waveform viewer (requires GTKWave)"
	@echo "  waves-fetcher   - Open fetcher waveform viewer (requires GTKWave)"
	@echo "  waves-lsu       - Open LSU waveform viewer (requires GTKWave)"
	@echo "  waves-scheduler - Open scheduler waveform viewer (requires GTKWave)"
	@echo "  waves-core      - Open core waveform viewer (requires GTKWave)"
	@echo "  clean           - Remove build artifacts"
	@echo "  help            - Show this help message"

.PHONY: all alu decoder registers pc fetcher lsu scheduler core waves-alu waves-decoder waves-registers waves-pc waves-fetcher waves-lsu waves-scheduler waves-core clean help
