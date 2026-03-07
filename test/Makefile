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

# Output files
ALU_OUT       = alu_tb.vvp
ALU_VCD       = alu_tb.vcd
DECODER_OUT   = decoder_tb.vvp
DECODER_VCD   = decoder_tb.vcd
REGISTERS_OUT = registers_tb.vvp
REGISTERS_VCD = registers_tb.vcd

# Compiler flags
IVERILOG = iverilog
IVFLAGS  = -g2012 -Wall
VVP      = vvp

# Default target - run all testbenches
all: alu decoder registers

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

# View waveforms (requires GTKWave)
waves-alu: $(ALU_VCD)
	gtkwave $(ALU_VCD) &

waves-decoder: $(DECODER_VCD)
	gtkwave $(DECODER_VCD) &

waves-registers: $(REGISTERS_VCD)
	gtkwave $(REGISTERS_VCD) &

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
	@echo "  waves-alu       - Open ALU waveform viewer (requires GTKWave)"
	@echo "  waves-decoder   - Open decoder waveform viewer (requires GTKWave)"
	@echo "  waves-registers - Open register file waveform viewer (requires GTKWave)"
	@echo "  clean           - Remove build artifacts"
	@echo "  help            - Show this help message"

.PHONY: all alu decoder registers waves-alu waves-decoder waves-registers clean help
