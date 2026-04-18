`default_nettype none
`timescale 1ns/1ns

// PROGRAM COUNTER
// One PC per thread. Two responsibilities:
//   1. EXECUTE stage: compute next_pc (PC+1 by default, branch target on BRnzp)
//   2. UPDATE  stage: latch the NZP condition register from a CMP result
//
// NZP is set by CMP (decoded_nzp_write_enable=1, alu_out[2:0] = {N,Z,P}) and
// consumed by BRnzp (decoded_pc_mux=1, decoded_nzp = condition mask) to decide
// whether the branch is taken: taken iff (nzp & decoded_nzp) != 0.
//
// Threads can in principle diverge (each has its own PC), but we currently
// assume all threads in a block walk the same control flow.
module pc #(
    parameter DATA_BITS             = 8,
    parameter PROGRAM_MEM_ADDR_BITS = 8
) (
    input wire clock,                                      // Heartbeat - all updates on rising edge
    input wire reset,                                      // Force PC=0, NZP=0
    input wire enable,                                     // Is this thread active? (SIMT masking)

    // Pipeline state
    input wire [2:0] core_state,                           // Which stage is the core in?

    // Decoded control signals
    input wire [2:0] decoded_nzp,                          // BRnzp condition mask: which flags trigger branch
    input wire [DATA_BITS-1:0] decoded_immediate,          // Branch target address
    input wire decoded_nzp_write_enable,                   // CMP wants to write NZP this UPDATE
    input wire decoded_pc_mux,                             // 0 = PC+1, 1 = branch target

    // ALU output - bottom 3 bits are the fresh NZP result from a CMP that just executed
    input wire [DATA_BITS-1:0] alu_out,

    // PC interface
    input  wire [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,
    output reg  [PROGRAM_MEM_ADDR_BITS-1:0] next_pc
);

    // Pipeline stages we care about
    localparam EXECUTE = 3'b101;
    localparam UPDATE  = 3'b110;

    // Condition register: {N, Z, P} - latched from the most recent CMP
    reg [2:0] nzp;

    always @(posedge clock) begin
        if (reset) begin
            nzp     <= 3'b000;
            next_pc <= {PROGRAM_MEM_ADDR_BITS{1'b0}};
        end else if (enable) begin
            // EXECUTE stage: choose next PC
            if (core_state == EXECUTE) begin
                if (decoded_pc_mux) begin
                    // BRnzp: branch only if any latched flag matches the requested mask
                    if ((nzp & decoded_nzp) != 3'b000)
                        next_pc <= decoded_immediate;
                    else
                        next_pc <= current_pc + 1;
                end else begin
                    // Default: sequential execution
                    next_pc <= current_pc + 1;
                end
            end

            // UPDATE stage: latch new NZP flags from a CMP result
            if (core_state == UPDATE) begin
                if (decoded_nzp_write_enable) begin
                    nzp <= alu_out[2:0];
                end
            end
        end
    end

endmodule
