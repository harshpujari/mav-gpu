`default_nettype none
`timescale 1ns/1ns

// MEMORY CONTROLLER
// Arbitrates many consumer request channels onto a smaller number of physical
// memory channels. Each physical channel runs an independent little FSM:
//   1. IDLE          - pick a pending consumer request (lowest index first)
//   2. READ/WRITE_WAITING  - forward it to memory, wait for ready
//   3. READ/WRITE_RELAYING - hand the response back, wait for the consumer to ack
//   4. back to IDLE  - free the channel (and the consumer) for the next request
//
// Used twice in the GPU: once for program memory (consumers = core fetchers,
// read-only in practice) and once for data memory (consumers = thread LSUs,
// read + write). A `consumer_busy` scoreboard stops two channels grabbing the
// same consumer in the same cycle.
//
// Per-consumer / per-channel buses are FLATTENED into packed vectors (consumer
// k's address = consumer_read_address[k*ADDR_BITS +: ADDR_BITS]). This keeps the
// module portable across simulators that dislike unpacked array ports.
module controller #(
    parameter ADDR_BITS     = 8,
    parameter DATA_BITS     = 16,
    parameter NUM_CONSUMERS = 4,    // request channels coming in (>= 2)
    parameter NUM_CHANNELS  = 1     // physical memory channels going out
) (
    input  wire clock,
    input  wire reset,

    // ----- Consumer side (requests in from cores) -----
    input  wire [NUM_CONSUMERS-1:0]           consumer_read_valid,
    input  wire [NUM_CONSUMERS*ADDR_BITS-1:0] consumer_read_address,
    output reg  [NUM_CONSUMERS-1:0]           consumer_read_ready,
    output reg  [NUM_CONSUMERS*DATA_BITS-1:0] consumer_read_data,
    input  wire [NUM_CONSUMERS-1:0]           consumer_write_valid,
    input  wire [NUM_CONSUMERS*ADDR_BITS-1:0] consumer_write_address,
    input  wire [NUM_CONSUMERS*DATA_BITS-1:0] consumer_write_data,
    output reg  [NUM_CONSUMERS-1:0]           consumer_write_ready,

    // ----- Memory side (forwarded to actual memory) -----
    output reg  [NUM_CHANNELS-1:0]            mem_read_valid,
    output reg  [NUM_CHANNELS*ADDR_BITS-1:0]  mem_read_address,
    input  wire [NUM_CHANNELS-1:0]            mem_read_ready,
    input  wire [NUM_CHANNELS*DATA_BITS-1:0]  mem_read_data,
    output reg  [NUM_CHANNELS-1:0]            mem_write_valid,
    output reg  [NUM_CHANNELS*ADDR_BITS-1:0]  mem_write_address,
    output reg  [NUM_CHANNELS*DATA_BITS-1:0]  mem_write_data,
    input  wire [NUM_CHANNELS-1:0]            mem_write_ready
);

    // Width needed to name a consumer
    localparam CONSUMER_IDX_BITS = $clog2(NUM_CONSUMERS);

    // Per-channel arbitration FSM
    localparam IDLE           = 3'b000,
               READ_WAITING   = 3'b001,
               WRITE_WAITING  = 3'b010,
               READ_RELAYING  = 3'b011,
               WRITE_RELAYING = 3'b100;

    // Internal unpacked arrays are fine (only *ports* are flattened)
    reg [2:0]                   channel_state    [NUM_CHANNELS-1:0];
    reg [CONSUMER_IDX_BITS-1:0] current_consumer [NUM_CHANNELS-1:0];

    // Scoreboard: which consumers are already claimed by some channel.
    // BLOCKING-assigned so claims/releases are visible to later channels within
    // the same clock evaluation (prevents double-serving).
    reg [NUM_CONSUMERS-1:0] consumer_busy;

    integer c;      // channel index
    integer k;      // consumer index
    reg     found;  // "this channel claimed a consumer this cycle"

    always @(posedge clock) begin
        if (reset) begin
            consumer_read_ready  <= {NUM_CONSUMERS{1'b0}};
            consumer_write_ready <= {NUM_CONSUMERS{1'b0}};
            consumer_read_data   <= {(NUM_CONSUMERS*DATA_BITS){1'b0}};
            mem_read_valid       <= {NUM_CHANNELS{1'b0}};
            mem_write_valid      <= {NUM_CHANNELS{1'b0}};
            mem_read_address     <= {(NUM_CHANNELS*ADDR_BITS){1'b0}};
            mem_write_address    <= {(NUM_CHANNELS*ADDR_BITS){1'b0}};
            mem_write_data       <= {(NUM_CHANNELS*DATA_BITS){1'b0}};
            consumer_busy         = {NUM_CONSUMERS{1'b0}};
            for (c = 0; c < NUM_CHANNELS; c = c + 1) begin
                channel_state[c]    <= IDLE;
                current_consumer[c] <= {CONSUMER_IDX_BITS{1'b0}};
            end
        end else begin
            for (c = 0; c < NUM_CHANNELS; c = c + 1) begin
                case (channel_state[c])
                    IDLE: begin
                        // Serve the lowest-index pending request that no other
                        // channel has already claimed this cycle.
                        found = 1'b0;
                        for (k = 0; k < NUM_CONSUMERS; k = k + 1) begin
                            if (!found && !consumer_busy[k]) begin
                                if (consumer_read_valid[k]) begin
                                    found                = 1'b1;
                                    consumer_busy[k]      = 1'b1;
                                    current_consumer[c]  <= k[CONSUMER_IDX_BITS-1:0];
                                    mem_read_valid[c]    <= 1'b1;
                                    mem_read_address[c*ADDR_BITS +: ADDR_BITS]
                                        <= consumer_read_address[k*ADDR_BITS +: ADDR_BITS];
                                    channel_state[c]     <= READ_WAITING;
                                end else if (consumer_write_valid[k]) begin
                                    found                = 1'b1;
                                    consumer_busy[k]      = 1'b1;
                                    current_consumer[c]  <= k[CONSUMER_IDX_BITS-1:0];
                                    mem_write_valid[c]   <= 1'b1;
                                    mem_write_address[c*ADDR_BITS +: ADDR_BITS]
                                        <= consumer_write_address[k*ADDR_BITS +: ADDR_BITS];
                                    mem_write_data[c*DATA_BITS +: DATA_BITS]
                                        <= consumer_write_data[k*DATA_BITS +: DATA_BITS];
                                    channel_state[c]     <= WRITE_WAITING;
                                end
                            end
                        end
                    end

                    READ_WAITING: begin
                        // Forwarded read is in flight; relay the data when it lands
                        if (mem_read_ready[c]) begin
                            mem_read_valid[c]                       <= 1'b0;
                            consumer_read_ready[current_consumer[c]] <= 1'b1;
                            consumer_read_data[current_consumer[c]*DATA_BITS +: DATA_BITS]
                                <= mem_read_data[c*DATA_BITS +: DATA_BITS];
                            channel_state[c]                        <= READ_RELAYING;
                        end
                    end

                    WRITE_WAITING: begin
                        if (mem_write_ready[c]) begin
                            mem_write_valid[c]                        <= 1'b0;
                            consumer_write_ready[current_consumer[c]] <= 1'b1;
                            channel_state[c]                          <= WRITE_RELAYING;
                        end
                    end

                    READ_RELAYING: begin
                        // Hold the response until the consumer drops its request,
                        // then release the consumer and free the channel.
                        if (!consumer_read_valid[current_consumer[c]]) begin
                            consumer_busy[current_consumer[c]]       = 1'b0;
                            consumer_read_ready[current_consumer[c]] <= 1'b0;
                            channel_state[c]                         <= IDLE;
                        end
                    end

                    WRITE_RELAYING: begin
                        if (!consumer_write_valid[current_consumer[c]]) begin
                            consumer_busy[current_consumer[c]]        = 1'b0;
                            consumer_write_ready[current_consumer[c]] <= 1'b0;
                            channel_state[c]                          <= IDLE;
                        end
                    end
                endcase
            end
        end
    end

endmodule
