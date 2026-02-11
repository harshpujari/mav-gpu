`default_nettype none
`timescale 1ns/1ns

module alu(
    input wire clock,                              // Clock signal - heartbeat of the circuit
    input wire reset,                            // Reset everything to 0
    input wire enable,                           // Is this ALU active? (some threads may be inactive)
    input reg [2:0] core_state,                  // 3-bit state: which stage is the core in?
    input reg [1:0] decoded_alu_arithmetic_selector,  // 2-bit: which operation? (ADD/SUB/MUL/DIV)
    input reg decoded_alu_output_selector,            // 1-bit: arithmetic or comparison?
    input reg [7:0] rs,                          // 8-bit: first operand (source register 1)
    input reg [7:0] rt,                          // 8-bit: second operand (source register 2)
    output wire [7:0] alu_out                    
);

localparam ADD = 2'b00,      // 00 in binary = ADD
           SUB = 2'b01,      // 01 = SUB
           MUL = 2'b10,      // 10 = MUL
           DIV = 2'b11;      // 11 = DIV

    // Internal register to hold ALU output
    reg [7:0] alu_out_reg;
    assign alu_out = alu_out_reg;

    // EXECUTE stage state (from core_state)
    localparam EXECUTE = 3'b101;

    always @(posedge clock) begin
        if (reset) begin
            alu_out_reg <= 8'b0;
        end else if (enable) begin
            // Perform computation only in EXECUTE stage
            if (core_state == EXECUTE) begin
                if (decoded_alu_output_selector == 1'b1) begin
                    // Comparison mode: set NZP flags in alu_out[2:0]
                    // [2] = negative, [1] = zero, [0] = positive
                    alu_out_reg <= {5'b0,
                                   (rs < rt),      // negative (rs - rt < 0)
                                   (rs == rt),     // zero     (rs - rt == 0)
                                   (rs > rt)};     // positive (rs - rt > 0)
                end else begin
                    // Arithmetic mode: execute ADD/SUB/MUL/DIV
                    case (decoded_alu_arithmetic_selector)
                        ADD: alu_out_reg <= rs + rt;
                        SUB: alu_out_reg <= rs - rt;
                        MUL: alu_out_reg <= rs * rt;
                        DIV: alu_out_reg <= rs / rt;
                    endcase
                end
            end
        end
    end

endmodule