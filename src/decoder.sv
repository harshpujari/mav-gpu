`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION DECODER
// > Decodes a 16-bit instruction into control signals for the rest of the pipeline
// > Runs in the DECODE stage - one decoder shared across all threads in a core
// > Outputs are held until the next DECODE stage
module decoder (
    input wire clock,                                   // Clock signal - heartbeat of the circuit
    input wire reset,                                   // Reset all outputs to 0

    input reg [2:0] core_state,                         // 3-bit state: which pipeline stage is active?
    input reg [15:0] instruction,                       // 16-bit instruction word fetched from program memory

    // Instruction Fields (extracted bit slices)
    output reg [3:0] decoded_rd_address,                // 4-bit: destination register address (bits [11:8])
    output reg [3:0] decoded_rs_address,                // 4-bit: source register 1 address (bits [7:4])
    output reg [3:0] decoded_rt_address,                // 4-bit: source register 2 address (bits [3:0])
    output reg [2:0] decoded_nzp,                       // 3-bit: NZP condition mask for BRnzp (bits [11:9])
    output reg [7:0] decoded_immediate,                 // 8-bit: immediate/constant value (bits [7:0])

    // Control Signals
    output reg decoded_reg_write_enable,                // 1-bit: should we write a result back to rd?
    output reg decoded_mem_read_enable,                 // 1-bit: should we issue a memory read (LDR)?
    output reg decoded_mem_write_enable,                // 1-bit: should we issue a memory write (STR)?
    output reg decoded_nzp_write_enable,                // 1-bit: should we update the NZP condition register?
    output reg [1:0] decoded_reg_input_selector,        // 2-bit: which result to write into rd? (ALU / memory / immediate)
    output reg [1:0] decoded_alu_arithmetic_selector,   // 2-bit: which arithmetic op should the ALU perform?
    output reg decoded_alu_output_selector,             // 1-bit: ALU in arithmetic mode (0) or comparison mode (1)?
    output reg decoded_pc_mux,                          // 1-bit: next PC from increment (0) or branch target (1)?

    // Thread Termination
    output reg decoded_ret                              // 1-bit: this thread is done executing (RET instruction)
);

    // Instruction opcodes - top 4 bits [15:12] of the instruction word
    localparam NOP   = 4'b0000,   // No operation
               BRnzp = 4'b0001,   // Conditional branch based on NZP flags
               CMP   = 4'b0010,   // Compare rs and rt, write NZP flags
               ADD   = 4'b0011,   // rd = rs + rt
               SUB   = 4'b0100,   // rd = rs - rt
               MUL   = 4'b0101,   // rd = rs * rt
               DIV   = 4'b0110,   // rd = rs / rt
               LDR   = 4'b0111,   // rd = memory[rs]
               STR   = 4'b1000,   // memory[rs] = rt
               CONST = 4'b1001,   // rd = immediate
               RET   = 4'b1111;   // Signal thread completion

    // Register write source selection (matches decoded_reg_input_selector encoding)
    localparam REG_SRC_ARITHMETIC = 2'b00,   // Write ALU arithmetic/comparison result
               REG_SRC_MEMORY     = 2'b01,   // Write memory load result (LDR)
               REG_SRC_CONSTANT   = 2'b10;   // Write immediate value (CONST)

    // ALU arithmetic operation selection (matches decoded_alu_arithmetic_selector encoding)
    localparam ALU_ADD = 2'b00,
               ALU_SUB = 2'b01,
               ALU_MUL = 2'b10,
               ALU_DIV = 2'b11;

    // Pipeline stage we care about
    localparam DECODE = 3'b010;   // Decoder is active during stage 2

    always @(posedge clock) begin
        if (reset) begin
            decoded_rd_address            <= 4'b0;
            decoded_rs_address            <= 4'b0;
            decoded_rt_address            <= 4'b0;
            decoded_nzp                   <= 3'b0;
            decoded_immediate             <= 8'b0;
            decoded_reg_write_enable      <= 1'b0;
            decoded_mem_read_enable       <= 1'b0;
            decoded_mem_write_enable      <= 1'b0;
            decoded_nzp_write_enable      <= 1'b0;
            decoded_reg_input_selector    <= 2'b0;
            decoded_alu_arithmetic_selector <= 2'b0;
            decoded_alu_output_selector   <= 1'b0;
            decoded_pc_mux                <= 1'b0;
            decoded_ret                   <= 1'b0;
        end else begin
            if (core_state == DECODE) begin
                // --- Extract instruction fields ---
                // These are always pulled from the same bit positions regardless of opcode
                decoded_rd_address <= instruction[11:8];   // destination register
                decoded_rs_address <= instruction[7:4];    // source register 1
                decoded_rt_address <= instruction[3:0];    // source register 2
                decoded_immediate  <= instruction[7:0];    // immediate (overlaps rs/rt fields)
                decoded_nzp        <= instruction[11:9];   // NZP condition bits (overlaps rd field)

                // --- Default all control signals to 0 ---
                // Each instruction explicitly sets only the signals it needs.
                // Everything else stays 0 to avoid stale state from a previous instruction.
                decoded_reg_write_enable        <= 1'b0;
                decoded_mem_read_enable         <= 1'b0;
                decoded_mem_write_enable        <= 1'b0;
                decoded_nzp_write_enable        <= 1'b0;
                decoded_reg_input_selector      <= 2'b0;
                decoded_alu_arithmetic_selector <= 2'b0;
                decoded_alu_output_selector     <= 1'b0;
                decoded_pc_mux                  <= 1'b0;
                decoded_ret                     <= 1'b0;

                // --- Set control signals per opcode ---
                case (instruction[15:12])
                    NOP: begin
                        // No control signals needed - everything stays 0
                    end

                    BRnzp: begin
                        // Branch: next PC comes from immediate field, not increment
                        decoded_pc_mux <= 1'b1;
                    end

                    CMP: begin
                        // Compare: ALU runs in comparison mode, result updates NZP register
                        decoded_alu_output_selector <= 1'b1;
                        decoded_nzp_write_enable    <= 1'b1;
                    end

                    ADD: begin
                        decoded_reg_write_enable        <= 1'b1;
                        decoded_reg_input_selector      <= REG_SRC_ARITHMETIC;
                        decoded_alu_arithmetic_selector <= ALU_ADD;
                    end

                    SUB: begin
                        decoded_reg_write_enable        <= 1'b1;
                        decoded_reg_input_selector      <= REG_SRC_ARITHMETIC;
                        decoded_alu_arithmetic_selector <= ALU_SUB;
                    end

                    MUL: begin
                        decoded_reg_write_enable        <= 1'b1;
                        decoded_reg_input_selector      <= REG_SRC_ARITHMETIC;
                        decoded_alu_arithmetic_selector <= ALU_MUL;
                    end

                    DIV: begin
                        decoded_reg_write_enable        <= 1'b1;
                        decoded_reg_input_selector      <= REG_SRC_ARITHMETIC;
                        decoded_alu_arithmetic_selector <= ALU_DIV;
                    end

                    LDR: begin
                        // Load: read from memory, write result to rd
                        decoded_reg_write_enable   <= 1'b1;
                        decoded_reg_input_selector <= REG_SRC_MEMORY;
                        decoded_mem_read_enable    <= 1'b1;
                    end

                    STR: begin
                        // Store: write rt to memory address in rs (no register writeback)
                        decoded_mem_write_enable <= 1'b1;
                    end

                    CONST: begin
                        // Constant: load immediate value directly into rd
                        decoded_reg_write_enable   <= 1'b1;
                        decoded_reg_input_selector <= REG_SRC_CONSTANT;
                    end

                    RET: begin
                        // Return: signal that this thread is done
                        decoded_ret <= 1'b1;
                    end
                endcase
            end
        end
    end

endmodule
