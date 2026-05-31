`default_nettype none
`timescale 1ns/1ns

// LOAD / STORE UNIT
// One LSU per thread (hence `enable` for SIMT masking). Handles the two memory
// instructions, LDR and STR, by talking to data memory over a valid -> ready
// handshake - the same pattern the fetcher uses for program memory.
//
//   LDR rd, [rs]  -> read  data_mem[rs], result appears on lsu_out (-> regfile)
//   STR [rs], rt  -> write data_mem[rs] = rt
//
// Lifecycle across the pipeline:
//   REQUEST stage : kick off (move IDLE -> REQUESTING)
//   (internal)    : drive the request, then wait for ready
//   UPDATE  stage : retire (move DONE -> IDLE) once the result has been consumed
module lsu (
    input  wire clock,                          // Heartbeat
    input  wire reset,                          // Force back to IDLE, clear outputs
    input  wire enable,                         // Is this thread active? (SIMT masking)

    input  wire [2:0] core_state,               // Which pipeline stage is the core in?

    // Decoded control signals (mutually exclusive for memory ops)
    input  wire decoded_mem_read_enable,        // LDR: read from memory
    input  wire decoded_mem_write_enable,       // STR: write to memory

    // Operands from the register file
    input  wire [7:0] rs,                       // Memory address
    input  wire [7:0] rt,                       // Data to store (STR only)

    // Data-memory read channel (we drive the request, controller answers)
    output reg        mem_read_valid,
    output reg [7:0]  mem_read_address,
    input  wire       mem_read_ready,
    input  wire [7:0] mem_read_data,

    // Data-memory write channel
    output reg        mem_write_valid,
    output reg [7:0]  mem_write_address,
    output reg [7:0]  mem_write_data,
    input  wire       mem_write_ready,

    // Result handed back to the register file (LDR)
    output reg [7:0]  lsu_out
);

    // Core pipeline stages we care about (canonical encoding)
    localparam REQUEST = 3'b011;    // Kick off the memory transaction
    localparam UPDATE  = 3'b110;    // Transaction retires here

    // LSU's own transaction state machine
    localparam LSU_IDLE       = 2'b00,   // Nothing in flight
               LSU_REQUESTING = 2'b01,   // Drive the request onto the bus
               LSU_WAITING    = 2'b10,   // Request issued, waiting for ready
               LSU_DONE       = 2'b11;   // Transaction complete, holding result
    reg [1:0] lsu_state;

    always @(posedge clock) begin
        if (reset) begin
            lsu_state         <= LSU_IDLE;
            mem_read_valid    <= 1'b0;
            mem_read_address  <= 8'b0;
            mem_write_valid   <= 1'b0;
            mem_write_address <= 8'b0;
            mem_write_data    <= 8'b0;
            lsu_out           <= 8'b0;
        end else if (enable) begin
            // Only LDR/STR drive the LSU; every other instruction leaves it idle.
            if (decoded_mem_read_enable || decoded_mem_write_enable) begin
                case (lsu_state)
                    LSU_IDLE: begin
                        // Arm once the core reaches the REQUEST stage
                        if (core_state == REQUEST) begin
                            lsu_state <= LSU_REQUESTING;
                        end
                    end

                    LSU_REQUESTING: begin
                        // Put the request on the appropriate channel
                        if (decoded_mem_read_enable) begin
                            mem_read_valid   <= 1'b1;
                            mem_read_address <= rs;
                        end else begin
                            mem_write_valid   <= 1'b1;
                            mem_write_address <= rs;
                            mem_write_data    <= rt;
                        end
                        lsu_state <= LSU_WAITING;
                    end

                    LSU_WAITING: begin
                        // Wait for the controller to acknowledge
                        if (decoded_mem_read_enable && mem_read_ready) begin
                            mem_read_valid <= 1'b0;            // drop the request
                            lsu_out        <= mem_read_data;   // latch the loaded value
                            lsu_state      <= LSU_DONE;
                        end else if (decoded_mem_write_enable && mem_write_ready) begin
                            mem_write_valid <= 1'b0;           // drop the request
                            lsu_state       <= LSU_DONE;
                        end
                    end

                    LSU_DONE: begin
                        // Retire once the result has been consumed in UPDATE
                        if (core_state == UPDATE) begin
                            lsu_state <= LSU_IDLE;
                        end
                    end
                endcase
            end
        end
    end

endmodule
