`default_nettype none
`timescale 1ns/1ns

// SCHEDULER
// The core's control FSM. It walks every instruction through the 6 execution
// stages and broadcasts the current stage as `core_state` - the signal that
// gates the fetcher, decoder, register file, ALU, LSU and PC.
//
//   FETCH -> DECODE -> REQUEST -> WAIT -> EXECUTE -> UPDATE -> (FETCH | DONE)
//
// Two stages can stall:
//   FETCH : waits for `fetcher_done` (instruction back from program memory)
//   WAIT  : waits for every thread's LSU to finish any memory traffic
//
// All threads in the block are assumed to share control flow, so a single
// `current_pc` is kept and refreshed from the threads' `next_pc` in UPDATE.
module scheduler #(
    parameter THREADS_PER_BLOCK = 4
) (
    input  wire clock,
    input  wire reset,
    input  wire start,                           // Dispatcher: begin executing this block

    // Decoder signals that influence sequencing
    input  wire decoded_mem_read_enable,         // (informational) this is a LDR
    input  wire decoded_mem_write_enable,        // (informational) this is a STR
    input  wire decoded_ret,                      // RET: block is finished after UPDATE

    // Fetcher status
    input  wire fetcher_done,                     // Instruction has been fetched

    // Per-thread LSU status (busy while REQUESTING/WAITING)
    input  wire [1:0] lsu_state [THREADS_PER_BLOCK-1:0],

    // Program counter: scheduler owns current_pc, threads compute next_pc
    input  wire [7:0] next_pc [THREADS_PER_BLOCK-1:0],
    output reg  [7:0] current_pc,

    // Broadcast pipeline stage + block-complete flag
    output reg  [2:0] core_state,
    output reg        done
);

    // Canonical 3-bit pipeline encoding (shared with every core module)
    localparam IDLE    = 3'b000,
               FETCH   = 3'b001,
               DECODE  = 3'b010,
               REQUEST = 3'b011,
               WAIT    = 3'b100,
               EXECUTE = 3'b101,
               UPDATE  = 3'b110,
               DONE    = 3'b111;

    // LSU states that mean "memory still in flight"
    localparam LSU_REQUESTING = 2'b01,
               LSU_WAITING    = 2'b10;

    integer i;
    reg     any_lsu_busy;

    always @(posedge clock) begin
        if (reset) begin
            current_pc <= 8'b0;
            core_state <= IDLE;
            done       <= 1'b0;
        end else begin
            case (core_state)
                IDLE: begin
                    // Hold until the dispatcher launches this block
                    if (start) core_state <= FETCH;
                end

                FETCH: begin
                    // Wait for the instruction to come back from program memory
                    if (fetcher_done) core_state <= DECODE;
                end

                DECODE: begin
                    // Decoder latches this cycle; control signals ready next
                    core_state <= REQUEST;
                end

                REQUEST: begin
                    // Register operands read, LSUs armed for any memory op
                    core_state <= WAIT;
                end

                WAIT: begin
                    // Stall until no thread's LSU is mid-transaction
                    any_lsu_busy = 1'b0;
                    for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin
                        if (lsu_state[i] == LSU_REQUESTING ||
                            lsu_state[i] == LSU_WAITING)
                            any_lsu_busy = 1'b1;
                    end
                    if (!any_lsu_busy) core_state <= EXECUTE;
                end

                EXECUTE: begin
                    // ALU result / loaded data is now available
                    core_state <= UPDATE;
                end

                UPDATE: begin
                    if (decoded_ret) begin
                        // RET: this block is finished
                        core_state <= DONE;
                        done       <= 1'b1;
                    end else begin
                        // Advance PC (threads assumed convergent) and loop
                        current_pc <= next_pc[THREADS_PER_BLOCK-1];
                        core_state <= FETCH;
                    end
                end

                DONE: begin
                    // Block complete - stay here until reset
                end
            endcase
        end
    end

endmodule
