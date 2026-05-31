`default_nettype none
`timescale 1ns/1ns

// LSU TESTBENCH
// Drives the load/store unit with a mock data memory (separate read and write
// channels, each with a configurable latency) and checks that LDR returns the
// stored value and STR writes the right data to the right address.
module lsu_tb;
    reg        clock;
    reg        reset;
    reg        enable;
    reg  [2:0] core_state;
    reg        decoded_mem_read_enable;
    reg        decoded_mem_write_enable;
    reg  [7:0] rs;
    reg  [7:0] rt;

    // Read channel (LSU drives request, mock answers)
    wire        mem_read_valid;
    wire [7:0]  mem_read_address;
    reg         mem_read_ready;
    reg  [7:0]  mem_read_data;

    // Write channel
    wire        mem_write_valid;
    wire [7:0]  mem_write_address;
    wire [7:0]  mem_write_data;
    reg         mem_write_ready;

    wire [7:0]  lsu_out;

    lsu uut (
        .clock                    (clock),
        .reset                    (reset),
        .enable                   (enable),
        .core_state               (core_state),
        .decoded_mem_read_enable  (decoded_mem_read_enable),
        .decoded_mem_write_enable (decoded_mem_write_enable),
        .rs                       (rs),
        .rt                       (rt),
        .mem_read_valid           (mem_read_valid),
        .mem_read_address         (mem_read_address),
        .mem_read_ready           (mem_read_ready),
        .mem_read_data            (mem_read_data),
        .mem_write_valid          (mem_write_valid),
        .mem_write_address        (mem_write_address),
        .mem_write_data           (mem_write_data),
        .mem_write_ready          (mem_write_ready),
        .lsu_out                  (lsu_out)
    );

    // Clock generation: 10ns period
    always #5 clock = ~clock;

    // Pipeline stages (must match lsu.sv)
    localparam DECODE  = 3'b010;
    localparam REQUEST = 3'b011;
    localparam UPDATE  = 3'b110;

    // ----- Mock data memory -----
    reg [7:0] data_mem [0:255];

    integer rd_latency = 1;
    integer rd_cnt     = 0;
    always @(posedge clock) begin
        if (reset) begin
            mem_read_ready <= 1'b0;
            mem_read_data  <= 8'b0;
            rd_cnt         <= 0;
        end else if (mem_read_valid && !mem_read_ready) begin
            if (rd_cnt >= rd_latency) begin
                mem_read_ready <= 1'b1;
                mem_read_data  <= data_mem[mem_read_address];
                rd_cnt         <= 0;
            end else begin
                rd_cnt <= rd_cnt + 1;
            end
        end else begin
            mem_read_ready <= 1'b0;
            rd_cnt         <= 0;
        end
    end

    integer wr_latency = 1;
    integer wr_cnt     = 0;
    always @(posedge clock) begin
        if (reset) begin
            mem_write_ready <= 1'b0;
            wr_cnt          <= 0;
        end else if (mem_write_valid && !mem_write_ready) begin
            if (wr_cnt >= wr_latency) begin
                mem_write_ready              <= 1'b1;
                data_mem[mem_write_address]  <= mem_write_data;
                wr_cnt                       <= 0;
            end else begin
                wr_cnt <= wr_cnt + 1;
            end
        end else begin
            mem_write_ready <= 1'b0;
            wr_cnt          <= 0;
        end
    end

    integer tests_passed = 0;
    integer tests_failed = 0;

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

    // Run a LDR: REQUEST -> wait for the read handshake -> retire in UPDATE.
    task do_load;
        input [7:0] addr;
        integer guard;
        reg     seen;
        begin
            decoded_mem_read_enable  = 1;
            decoded_mem_write_enable = 0;
            rs = addr;
            core_state = REQUEST;
            seen = 0; guard = 0;
            while (!(seen && mem_read_valid === 1'b0) && guard < 50) begin
                if (mem_read_valid === 1'b1) seen = 1;
                #10; guard = guard + 1;
            end
            core_state = UPDATE; #10;           // retire (DONE -> IDLE)
            decoded_mem_read_enable = 0;
            core_state = DECODE; #10;           // park outside the memory stages
        end
    endtask

    // Run a STR: REQUEST -> wait for the write handshake -> retire in UPDATE.
    task do_store;
        input [7:0] addr;
        input [7:0] val;
        integer guard;
        reg     seen;
        begin
            decoded_mem_read_enable  = 0;
            decoded_mem_write_enable = 1;
            rs = addr;
            rt = val;
            core_state = REQUEST;
            seen = 0; guard = 0;
            while (!(seen && mem_write_valid === 1'b0) && guard < 50) begin
                if (mem_write_valid === 1'b1) seen = 1;
                #10; guard = guard + 1;
            end
            core_state = UPDATE; #10;
            decoded_mem_write_enable = 0;
            core_state = DECODE; #10;
        end
    endtask

    initial begin
        $dumpfile("lsu_tb.vcd");
        $dumpvars(0, lsu_tb);

        // Preload data memory
        data_mem[8'h10] = 8'h42;
        data_mem[8'h11] = 8'h07;
        data_mem[8'h80] = 8'hFE;

        clock                    = 0;
        reset                    = 1;
        enable                   = 0;
        core_state               = DECODE;
        decoded_mem_read_enable  = 0;
        decoded_mem_write_enable = 0;
        rs                       = 0;
        rt                       = 0;
        mem_read_ready           = 0;
        mem_read_data            = 0;
        mem_write_ready          = 0;

        $display("\n========================================");
        $display("LSU Testbench Starting");
        $display("========================================\n");

        // Reset sequence
        #20;
        check_signal(lsu_out,         0, "Reset: lsu_out = 0");
        check_signal(mem_read_valid,  0, "Reset: mem_read_valid = 0");
        check_signal(mem_write_valid, 0, "Reset: mem_write_valid = 0");

        reset  = 0;
        enable = 1;
        #10;

        // ==========================================
        // LDR
        // ==========================================
        $display("\n--- LDR (load) ---\n");

        do_load(8'h10);
        check_signal(lsu_out,        8'h42, "LDR [0x10] -> lsu_out = 0x42");
        check_signal(mem_read_valid, 0,     "LDR: read request deasserted");

        do_load(8'h11);
        check_signal(lsu_out, 8'h07, "LDR [0x11] -> lsu_out = 0x07");

        do_load(8'h80);
        check_signal(lsu_out, 8'hFE, "LDR [0x80] -> lsu_out = 0xFE");

        // ==========================================
        // STR
        // ==========================================
        $display("\n--- STR (store) ---\n");

        do_store(8'h20, 8'h99);
        check_signal(data_mem[8'h20],  8'h99, "STR 0x99 -> [0x20] writes memory");
        check_signal(mem_write_valid,  0,     "STR: write request deasserted");

        do_store(8'h21, 8'hAB);
        check_signal(data_mem[8'h21], 8'hAB, "STR 0xAB -> [0x21]");

        // Load back what we just stored
        do_load(8'h20);
        check_signal(lsu_out, 8'h99, "LDR [0x20] reads back 0x99 (store/load round-trip)");

        // ==========================================
        // Slow memory: LSU must wait for ready
        // ==========================================
        $display("\n--- Slow memory ---\n");

        rd_latency = 5;
        do_load(8'h11);
        check_signal(lsu_out, 8'h07, "Slow LDR [0x11] still returns 0x07");
        rd_latency = 1;

        // ==========================================
        // Enable masking: disabled thread issues nothing
        // ==========================================
        $display("\n--- Enable masking ---\n");

        enable                  = 0;
        decoded_mem_read_enable = 1;
        rs                      = 8'h80;     // would load 0xFE if active
        core_state              = REQUEST;
        #50;
        check_signal(mem_read_valid, 0,     "Disabled: no read request issued");
        check_signal(lsu_out,        8'h07, "Disabled: lsu_out unchanged (still 0x07)");
        decoded_mem_read_enable = 0;
        core_state              = DECODE;
        enable                  = 1;
        #10;

        // Works again once re-enabled
        do_load(8'h80);
        check_signal(lsu_out, 8'hFE, "Re-enabled: LDR [0x80] -> 0xFE");

        // ==========================================
        // Reset clears state
        // ==========================================
        $display("\n--- Reset clears state ---\n");

        reset = 1;
        #10;
        check_signal(lsu_out,         0, "Reset: lsu_out = 0");
        check_signal(mem_read_valid,  0, "Reset: mem_read_valid = 0");
        check_signal(mem_write_valid, 0, "Reset: mem_write_valid = 0");
        reset = 0;
        #10;

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
