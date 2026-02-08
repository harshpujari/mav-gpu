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
         
end module