`default_nettype none
`timescale 1ns/1ns

// CORE
// One self-contained compute unit. It owns a single control pipeline
// (scheduler + fetcher + decoder) shared by all threads in a block, and
// replicates the per-thread datapath (registers + ALU + LSU + PC) once per
// thread. Every thread marches through the same instruction in lock-step
// (SIMT); lanes with index >= thread_count are masked off via `enable`.
module core #(
    parameter THREADS_PER_BLOCK     = 4,
    parameter PROGRAM_MEM_ADDR_BITS = 8,
    parameter PROGRAM_MEM_DATA_BITS = 16,
    parameter DATA_MEM_ADDR_BITS    = 8,
    parameter DATA_MEM_DATA_BITS    = 8
) (
    input  wire clock,
    input  wire reset,

    // Block launch handshake (from the dispatcher)
    input  wire start,
    output wire done,
    input  wire [7:0] block_id,
    input  wire [$clog2(THREADS_PER_BLOCK):0] thread_count,   // active lanes in this block

    // Program memory - single shared fetch channel
    output wire                             program_mem_read_valid,
    output wire [PROGRAM_MEM_ADDR_BITS-1:0] program_mem_read_address,
    input  wire                             program_mem_read_ready,
    input  wire [PROGRAM_MEM_DATA_BITS-1:0] program_mem_read_data,

    // Data memory - one read + one write channel per thread
    output wire                          data_mem_read_valid    [THREADS_PER_BLOCK-1:0],
    output wire [DATA_MEM_ADDR_BITS-1:0] data_mem_read_address  [THREADS_PER_BLOCK-1:0],
    input  wire                          data_mem_read_ready    [THREADS_PER_BLOCK-1:0],
    input  wire [DATA_MEM_DATA_BITS-1:0] data_mem_read_data     [THREADS_PER_BLOCK-1:0],
    output wire                          data_mem_write_valid   [THREADS_PER_BLOCK-1:0],
    output wire [DATA_MEM_ADDR_BITS-1:0] data_mem_write_address [THREADS_PER_BLOCK-1:0],
    output wire [DATA_MEM_DATA_BITS-1:0] data_mem_write_data    [THREADS_PER_BLOCK-1:0],
    input  wire                          data_mem_write_ready   [THREADS_PER_BLOCK-1:0]
);

    // ---- Shared control / fetch signals ----
    wire [2:0] core_state;
    wire [7:0] current_pc;
    wire       fetcher_done;
    wire [PROGRAM_MEM_DATA_BITS-1:0] instruction;

    // ---- Decoded instruction fields + control signals (one decoder per core) ----
    wire [3:0] decoded_rd_address;
    wire [3:0] decoded_rs_address;
    wire [3:0] decoded_rt_address;
    wire [2:0] decoded_nzp;
    wire [7:0] decoded_immediate;
    wire       decoded_reg_write_enable;
    wire       decoded_mem_read_enable;
    wire       decoded_mem_write_enable;
    wire       decoded_nzp_write_enable;
    wire [1:0] decoded_reg_input_selector;
    wire [1:0] decoded_alu_arithmetic_selector;
    wire       decoded_alu_output_selector;
    wire       decoded_pc_mux;
    wire       decoded_ret;

    // ---- Per-thread datapath signals ----
    wire [7:0] rs        [THREADS_PER_BLOCK-1:0];
    wire [7:0] rt        [THREADS_PER_BLOCK-1:0];
    wire [7:0] alu_out   [THREADS_PER_BLOCK-1:0];
    wire [7:0] lsu_out   [THREADS_PER_BLOCK-1:0];
    wire [1:0] lsu_state [THREADS_PER_BLOCK-1:0];
    wire [7:0] next_pc   [THREADS_PER_BLOCK-1:0];

    // ---- Scheduler: produces core_state + current_pc, raises done on RET ----
    scheduler #(
        .THREADS_PER_BLOCK (THREADS_PER_BLOCK)
    ) sched (
        .clock                    (clock),
        .reset                    (reset),
        .start                    (start),
        .decoded_mem_read_enable  (decoded_mem_read_enable),
        .decoded_mem_write_enable (decoded_mem_write_enable),
        .decoded_ret              (decoded_ret),
        .fetcher_done             (fetcher_done),
        .lsu_state                (lsu_state),
        .next_pc                  (next_pc),
        .current_pc               (current_pc),
        .core_state               (core_state),
        .done                     (done)
    );

    // ---- Fetcher: shared instruction fetch from program memory ----
    fetcher #(
        .PROGRAM_MEM_ADDR_BITS (PROGRAM_MEM_ADDR_BITS),
        .PROGRAM_MEM_DATA_BITS (PROGRAM_MEM_DATA_BITS)
    ) fetch_unit (
        .clock            (clock),
        .reset            (reset),
        .core_state       (core_state),
        .current_pc       (current_pc),
        .mem_read_valid   (program_mem_read_valid),
        .mem_read_address (program_mem_read_address),
        .mem_read_ready   (program_mem_read_ready),
        .mem_read_data    (program_mem_read_data),
        .fetcher_done     (fetcher_done),
        .instruction      (instruction)
    );

    // ---- Decoder: shared instruction decode ----
    decoder dec_unit (
        .clock                           (clock),
        .reset                           (reset),
        .core_state                      (core_state),
        .instruction                     (instruction),
        .decoded_rd_address              (decoded_rd_address),
        .decoded_rs_address              (decoded_rs_address),
        .decoded_rt_address              (decoded_rt_address),
        .decoded_nzp                     (decoded_nzp),
        .decoded_immediate               (decoded_immediate),
        .decoded_reg_write_enable        (decoded_reg_write_enable),
        .decoded_mem_read_enable         (decoded_mem_read_enable),
        .decoded_mem_write_enable        (decoded_mem_write_enable),
        .decoded_nzp_write_enable        (decoded_nzp_write_enable),
        .decoded_reg_input_selector      (decoded_reg_input_selector),
        .decoded_alu_arithmetic_selector (decoded_alu_arithmetic_selector),
        .decoded_alu_output_selector     (decoded_alu_output_selector),
        .decoded_pc_mux                  (decoded_pc_mux),
        .decoded_ret                     (decoded_ret)
    );

    // ---- Per-thread datapath (registers + ALU + LSU + PC) ----
    genvar i;
    generate
        for (i = 0; i < THREADS_PER_BLOCK; i = i + 1) begin : threads
            // Lane active only if its index is below the block's thread_count
            wire enable = (i < thread_count);

            registers #(
                .THREADS_PER_BLOCK (THREADS_PER_BLOCK),
                .THREAD_ID         (i),
                .DATA_BITS         (DATA_MEM_DATA_BITS)
            ) reg_file (
                .clock                      (clock),
                .reset                      (reset),
                .enable                     (enable),
                .block_id                   (block_id),
                .core_state                 (core_state),
                .decoded_rd_address         (decoded_rd_address),
                .decoded_rs_address         (decoded_rs_address),
                .decoded_rt_address         (decoded_rt_address),
                .decoded_reg_write_enable   (decoded_reg_write_enable),
                .decoded_reg_input_selector (decoded_reg_input_selector),
                .decoded_immediate          (decoded_immediate),
                .alu_out                    (alu_out[i]),
                .lsu_out                    (lsu_out[i]),
                .rs                         (rs[i]),
                .rt                         (rt[i])
            );

            alu alu_unit (
                .clock                           (clock),
                .reset                           (reset),
                .enable                          (enable),
                .core_state                      (core_state),
                .decoded_alu_arithmetic_selector (decoded_alu_arithmetic_selector),
                .decoded_alu_output_selector     (decoded_alu_output_selector),
                .rs                              (rs[i]),
                .rt                              (rt[i]),
                .alu_out                         (alu_out[i])
            );

            lsu lsu_unit (
                .clock                    (clock),
                .reset                    (reset),
                .enable                   (enable),
                .core_state               (core_state),
                .decoded_mem_read_enable  (decoded_mem_read_enable),
                .decoded_mem_write_enable (decoded_mem_write_enable),
                .rs                       (rs[i]),
                .rt                       (rt[i]),
                .mem_read_valid           (data_mem_read_valid[i]),
                .mem_read_address         (data_mem_read_address[i]),
                .mem_read_ready           (data_mem_read_ready[i]),
                .mem_read_data            (data_mem_read_data[i]),
                .mem_write_valid          (data_mem_write_valid[i]),
                .mem_write_address        (data_mem_write_address[i]),
                .mem_write_data           (data_mem_write_data[i]),
                .mem_write_ready          (data_mem_write_ready[i]),
                .lsu_out                  (lsu_out[i]),
                .lsu_state                (lsu_state[i])
            );

            pc #(
                .DATA_BITS             (DATA_MEM_DATA_BITS),
                .PROGRAM_MEM_ADDR_BITS (PROGRAM_MEM_ADDR_BITS)
            ) pc_unit (
                .clock                    (clock),
                .reset                    (reset),
                .enable                   (enable),
                .core_state               (core_state),
                .decoded_nzp              (decoded_nzp),
                .decoded_immediate        (decoded_immediate),
                .decoded_nzp_write_enable (decoded_nzp_write_enable),
                .decoded_pc_mux           (decoded_pc_mux),
                .alu_out                  (alu_out[i]),
                .current_pc               (current_pc),
                .next_pc                  (next_pc[i])
            );
        end
    endgenerate

endmodule
