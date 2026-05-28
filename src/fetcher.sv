`default_nettype none
`timescale 1ns/1ns

// INSTRUCTION FETCHER
// > Runs in the FETCH stage - one fetcher shared across all threads in a core
// > Uses the current PC to request the next instruction from program memory
// > Issues an async read request, waits for the response, then latches the
//   16-bit instruction word so the decoder can pick it up in DECODE.
//
// Program-memory handshake (the same pattern the LSU and memory controller
// will reuse later):
//   1. Assert mem_read_valid with mem_read_address = current_pc
//   2. Hold until the controller answers with mem_read_ready
//   3. Latch mem_read_data into `instruction`, raise fetcher_done, drop valid
//
// One fetch per FETCH stage; fetcher_done tells the scheduler the instruction
// is ready so it can advance the core to DECODE.
module fetcher #(
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16
) (
    input  wire clock,                                          // Heartbeat - all updates on rising edge
    input  wire reset,                                          // Force back to IDLE, clear outputs

    input  wire [2:0] core_state,                               // Which pipeline stage is the core in?

    // Program counter - address of the instruction we need to fetch
    input  wire [PROGRAM_MEM_ADDR_BITS-1:0] current_pc,

    // Program-memory read channel (we drive the request, controller answers)
    output reg                              mem_read_valid,     // We want to read...
    output reg  [PROGRAM_MEM_ADDR_BITS-1:0] mem_read_address,   // ...at this address
    input  wire                             mem_read_ready,     // Controller: your data is valid
    input  wire [PROGRAM_MEM_DATA_BITS-1:0] mem_read_data,      // ...here it is

    // Result handed to the decoder
    output reg                              fetcher_done,       // Instruction is latched and valid
    output reg  [PROGRAM_MEM_DATA_BITS-1:0] instruction         // The fetched 16-bit instruction word
);

    // ----- Core pipeline stages: canonical 3-bit encoding -----
    // Shared by every core module. The scheduler (built later) owns/drives these;
    // the codes already assumed by alu/decoder/registers/pc imply this layout.
    localparam IDLE    = 3'b000,
               FETCH   = 3'b001,
               DECODE  = 3'b010,
               REQUEST = 3'b011,
               WAIT    = 3'b100,
               EXECUTE = 3'b101,
               UPDATE  = 3'b110,
               DONE    = 3'b111;

    // ----- Fetcher's own little request state machine -----
    localparam FETCHER_IDLE     = 2'b00,   // Nothing in flight
               FETCHER_FETCHING = 2'b01,   // Request issued, waiting for ready
               FETCHER_DONE     = 2'b10;    // Instruction latched, holding result
    reg [1:0] fetcher_state;

    always @(posedge clock) begin
        if (reset) begin
            fetcher_state    <= FETCHER_IDLE;
            mem_read_valid   <= 1'b0;
            mem_read_address <= {PROGRAM_MEM_ADDR_BITS{1'b0}};
            fetcher_done     <= 1'b0;
            instruction      <= {PROGRAM_MEM_DATA_BITS{1'b0}};
        end else begin
            // TODO (next increment): FETCH-stage request -> ready handshake ->
            // latch instruction -> raise fetcher_done; clear on leaving FETCH.
        end
    end

endmodule
