`default_nettype none
`timescale 1ns/1ns

// CORE TESTBENCH
// Full end-to-end integration test: loads a tiny kernel into a mock program
// memory, launches a block of 4 threads, and checks that each thread executed
// the program (fetch -> decode -> regfile -> ALU -> store) and wrote its result
// to its own slot in data memory.
//
//   CONST R0, 5
//   CONST R1, 3
//   ADD   R2, R0, R1      ; R2 = 8
//   STR   [R15], R2       ; data_mem[threadIdx] = 8
//   RET
module core_tb;
    localparam THREADS_PER_BLOCK = 4;

    reg        clock;
    reg        reset;
    reg        start;
    reg  [7:0] block_id;
    reg  [2:0] thread_count;
    wire       done;

    // Program memory channel (shared)
    wire        pmem_read_valid;
    wire [7:0]  pmem_read_address;
    reg         pmem_read_ready;
    reg  [15:0] pmem_read_data;

    // Data memory channels (per thread)
    wire        dmem_read_valid    [THREADS_PER_BLOCK-1:0];
    wire [7:0]  dmem_read_address  [THREADS_PER_BLOCK-1:0];
    reg         dmem_read_ready    [THREADS_PER_BLOCK-1:0];
    reg  [7:0]  dmem_read_data     [THREADS_PER_BLOCK-1:0];
    wire        dmem_write_valid   [THREADS_PER_BLOCK-1:0];
    wire [7:0]  dmem_write_address [THREADS_PER_BLOCK-1:0];
    wire [7:0]  dmem_write_data    [THREADS_PER_BLOCK-1:0];
    reg         dmem_write_ready   [THREADS_PER_BLOCK-1:0];

    core #(
        .THREADS_PER_BLOCK     (THREADS_PER_BLOCK),
        .PROGRAM_MEM_ADDR_BITS (8),
        .PROGRAM_MEM_DATA_BITS (16),
        .DATA_MEM_ADDR_BITS    (8),
        .DATA_MEM_DATA_BITS    (8)
    ) uut (
        .clock                    (clock),
        .reset                    (reset),
        .start                    (start),
        .done                     (done),
        .block_id                 (block_id),
        .thread_count             (thread_count),
        .program_mem_read_valid   (pmem_read_valid),
        .program_mem_read_address (pmem_read_address),
        .program_mem_read_ready   (pmem_read_ready),
        .program_mem_read_data    (pmem_read_data),
        .data_mem_read_valid      (dmem_read_valid),
        .data_mem_read_address    (dmem_read_address),
        .data_mem_read_ready      (dmem_read_ready),
        .data_mem_read_data       (dmem_read_data),
        .data_mem_write_valid     (dmem_write_valid),
        .data_mem_write_address   (dmem_write_address),
        .data_mem_write_data      (dmem_write_data),
        .data_mem_write_ready     (dmem_write_ready)
    );

    // Clock: 10ns period
    always #5 clock = ~clock;

    // Backing memories
    reg [15:0] prog_mem [0:255];
    reg [7:0]  data_mem [0:255];

    // ----- Mock program memory (1-cycle latency) -----
    integer pcnt = 0;
    always @(posedge clock) begin
        if (reset) begin
            pmem_read_ready <= 0; pmem_read_data <= 0; pcnt <= 0;
        end else if (pmem_read_valid && !pmem_read_ready) begin
            if (pcnt >= 1) begin
                pmem_read_ready <= 1;
                pmem_read_data  <= prog_mem[pmem_read_address];
                pcnt            <= 0;
            end else pcnt <= pcnt + 1;
        end else begin
            pmem_read_ready <= 0; pcnt <= 0;
        end
    end

    // ----- Mock data memory (per-thread, 1-cycle latency) -----
    integer rdc [THREADS_PER_BLOCK-1:0];
    integer wrc [THREADS_PER_BLOCK-1:0];
    integer k;
    always @(posedge clock) begin
        if (reset) begin
            for (k = 0; k < THREADS_PER_BLOCK; k = k + 1) begin
                dmem_read_ready[k]  <= 0; dmem_read_data[k] <= 0; rdc[k] <= 0;
                dmem_write_ready[k] <= 0; wrc[k] <= 0;
            end
        end else begin
            for (k = 0; k < THREADS_PER_BLOCK; k = k + 1) begin
                // read channel
                if (dmem_read_valid[k] && !dmem_read_ready[k]) begin
                    if (rdc[k] >= 1) begin
                        dmem_read_ready[k] <= 1;
                        dmem_read_data[k]  <= data_mem[dmem_read_address[k]];
                        rdc[k]             <= 0;
                    end else rdc[k] <= rdc[k] + 1;
                end else begin
                    dmem_read_ready[k] <= 0; rdc[k] <= 0;
                end
                // write channel
                if (dmem_write_valid[k] && !dmem_write_ready[k]) begin
                    if (wrc[k] >= 1) begin
                        dmem_write_ready[k]            <= 1;
                        data_mem[dmem_write_address[k]] <= dmem_write_data[k];
                        wrc[k]                         <= 0;
                    end else wrc[k] <= wrc[k] + 1;
                end else begin
                    dmem_write_ready[k] <= 0; wrc[k] <= 0;
                end
            end
        end
    end

    integer tests_passed = 0;
    integer tests_failed = 0;
    integer guard;

    task check_signal;
        input integer actual;
        input integer expected;
        input [255:0] label;
        begin
            if (actual === expected) begin
                $display("[PASS] %s", label);
                tests_passed = tests_passed + 1;
            end else begin
                $display("[FAIL] %s: expected %0d, got %0d", label, expected, actual);
                tests_failed = tests_failed + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("core_tb.vcd");
        $dumpvars(0, core_tb);

        // Kernel
        prog_mem[0] = 16'h9005;   // CONST R0, 5
        prog_mem[1] = 16'h9103;   // CONST R1, 3
        prog_mem[2] = 16'h3201;   // ADD   R2, R0, R1
        prog_mem[3] = 16'h80F2;   // STR   [R15], R2   (R15 = threadIdx)
        prog_mem[4] = 16'hF000;   // RET

        clock           = 0;
        reset           = 1;
        start           = 0;
        block_id        = 8'd0;
        thread_count    = 3'd4;     // full block: all 4 lanes active
        pmem_read_ready = 0;
        pmem_read_data  = 0;
        for (k = 0; k < THREADS_PER_BLOCK; k = k + 1) begin
            dmem_read_ready[k]  = 0;
            dmem_read_data[k]   = 0;
            dmem_write_ready[k] = 0;
        end
        for (k = 0; k < 256; k = k + 1) data_mem[k] = 8'd0;

        $display("\n========================================");
        $display("Core Testbench Starting");
        $display("========================================\n");

        // Reset, then launch the block
        #20;
        reset = 0;
        #10;
        start = 1;

        // Run until the core signals completion
        guard = 0;
        while (done !== 1'b1 && guard < 1000) begin
            #10;
            guard = guard + 1;
        end

        $display("\n--- Kernel finished (guard = %0d cycles) ---\n", guard);

        check_signal(done, 1, "core asserts done");

        // Each thread should have stored 8 at data_mem[threadIdx]
        check_signal(data_mem[0], 8, "thread 0: data_mem[0] = 8");
        check_signal(data_mem[1], 8, "thread 1: data_mem[1] = 8");
        check_signal(data_mem[2], 8, "thread 2: data_mem[2] = 8");
        check_signal(data_mem[3], 8, "thread 3: data_mem[3] = 8");

        // Untouched memory stays zero
        check_signal(data_mem[4], 0, "data_mem[4] untouched = 0");

        // ==========================================
        // Summary
        // ==========================================
        #20;
        $display("\n========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Passed: %d", tests_passed);
        $display("Failed: %d", tests_failed);
        $display("========================================\n");

        if (tests_failed == 0)
            $display("ALL TESTS PASSED!\n");
        else
            $display("SOME TESTS FAILED!\n");

        $finish;
    end

endmodule
