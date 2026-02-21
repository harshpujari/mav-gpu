`default_nettype none
`timescale 1ns/1ns

// REGISTER FILE
// Each thread has its own register file: 13 general-purpose + 3 read-only registers
// Read-only registers: R13 = %blockIdx, R14 = %blockDim, R15 = %threadIdx
module registers #(
    parameter THREADS_PER_BLOCK = 4,
    parameter THREAD_ID = 0,
    parameter DATA_BITS = 8
) (
    input wire clock,                                // Clock signal
    input wire reset,                                // Reset all registers to 0
    input wire enable,                               // Is this thread active? (inactive if block has fewer threads)

    // Kernel execution context
    input reg [7:0] block_id,                        // Current block being executed

    // Core pipeline state
    input reg [2:0] core_state,                      // 3-bit state: which stage is the core in?

    // Decoded instruction signals
    input reg [3:0] decoded_rd_address,              // 4-bit: destination register address (R0-R15)
    input reg [3:0] decoded_rs_address,              // 4-bit: source register 1 address
    input reg [3:0] decoded_rt_address,              // 4-bit: source register 2 address

    // Control signals from decoder
    input reg decoded_reg_write_enable,              // 1-bit: should we write to rd?
    input reg [1:0] decoded_reg_input_selector,      // 2-bit: where does the write data come from?
    input reg [DATA_BITS-1:0] decoded_immediate,     // 8-bit: immediate/constant value from instruction

    // Data inputs from other units
    input reg [DATA_BITS-1:0] alu_out,               // 8-bit: result from ALU (arithmetic/comparison)
    input reg [DATA_BITS-1:0] lsu_out,               // 8-bit: result from LSU (memory load)

    // Register outputs for operands
    output reg [7:0] rs,                             // 8-bit: value of source register 1
    output reg [7:0] rt                              // 8-bit: value of source register 2
);

    // Write data source selection
    localparam ARITHMETIC = 2'b00,   // ALU result (ADD, SUB, MUL, DIV)
               MEMORY     = 2'b01,   // LSU result (LDR)
               CONSTANT   = 2'b10;   // Immediate value (CONST)

    // Core pipeline stages we care about
    localparam REQUEST = 3'b011;     // Read rs/rt from register file
    localparam UPDATE  = 3'b110;     // Write result back to rd

    // 16 registers per thread (R0-R12 writable, R13-R15 read-only)
    reg [7:0] registers [15:0];

    integer i;

    always @(posedge clock) begin
        if (reset) begin
            rs <= 8'b0;
            rt <= 8'b0;

            // Clear all general-purpose registers
            for (i = 0; i < 13; i = i + 1) begin
                registers[i] <= 8'b0;
            end

            // Initialize read-only registers
            registers[13] <= 8'b0;              // %blockIdx (set per block dispatch)
            registers[14] <= THREADS_PER_BLOCK;  // %blockDim (fixed at synthesis)
            registers[15] <= THREAD_ID;          // %threadIdx (fixed at synthesis)
        end else if (enable) begin
            // Keep block_id in sync (updated each dispatch)
            registers[13] <= block_id;

            // REQUEST stage: read source registers into rs/rt
            if (core_state == REQUEST) begin
                rs <= registers[decoded_rs_address];
                rt <= registers[decoded_rt_address];
            end

            // UPDATE stage: write result back to destination register
            if (core_state == UPDATE) begin
                // Only general-purpose registers (R0-R12) are writable
                if (decoded_reg_write_enable && decoded_rd_address < 13) begin
                    case (decoded_reg_input_selector)
                        ARITHMETIC: registers[decoded_rd_address] <= alu_out;
                        MEMORY:     registers[decoded_rd_address] <= lsu_out;
                        CONSTANT:   registers[decoded_rd_address] <= decoded_immediate;
                    endcase
                end
            end
        end
    end

endmodule
