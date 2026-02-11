# Makefile for ALU testbench simulation
# Uses Icarus Verilog (iverilog) for compilation and vvp for simulation

# Directories
SRC_DIR = ../src
TEST_DIR = .

# Source files
ALU_SRC = $(SRC_DIR)/alu.sv
ALU_TB = $(TEST_DIR)/alu_tb.sv

# Output files
ALU_OUT = alu_tb.vvp
ALU_VCD = alu_tb.vcd

# Compiler flags
IVERILOG = iverilog
IVFLAGS = -g2012 -Wall
VVP = vvp

# Default target
all: alu

# Compile and run ALU testbench
alu: $(ALU_OUT)
	$(VVP) $(ALU_OUT)

# Compile ALU testbench
$(ALU_OUT): $(ALU_SRC) $(ALU_TB)
	$(IVERILOG) $(IVFLAGS) -o $(ALU_OUT) $(ALU_TB) $(ALU_SRC)

# View waveforms (requires GTKWave)
waves: $(ALU_VCD)
	gtkwave $(ALU_VCD) &

# Generate VCD without opening viewer
vcd: alu

# Clean build artifacts
clean:
	rm -f *.vvp *.vcd

# Help
help:
	@echo "Available targets:"
	@echo "  all    - Compile and run ALU testbench (default)"
	@echo "  alu    - Compile and run ALU testbench"
	@echo "  waves  - Open waveform viewer (requires GTKWave)"
	@echo "  vcd    - Generate VCD waveform file"
	@echo "  clean  - Remove build artifacts"
	@echo "  help   - Show this help message"

.PHONY: all alu waves vcd clean help
