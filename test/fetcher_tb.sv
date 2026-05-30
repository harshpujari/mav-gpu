`default_nettype none
`timescale 1ns/1ns

// FETCHER TESTBENCH
// Drives the fetcher with a mock program memory that answers the
// valid -> ready handshake after a configurable latency, and checks that the
// correct instruction word comes back for the requested PC.
module fetcher_tb;
    reg        clock;
    reg        reset;
    reg  [2:0] core_state;
    reg  [7:0] current_pc;

    // Program-memory read channel (driven by the fetcher, answered by the mock)
    wire        mem_read_valid;
    wire [7:0]  mem_read_address;
    reg         mem_read_ready;
    reg  [15:0] mem_read_data;

    // Results out of the fetcher
    wire        fetcher_done;
    wire [15:0] instruction;

    fetcher #(
        .PROGRAM_MEM_ADDR_BITS (8),
        .PROGRAM_MEM_DATA_BITS (16)
    ) uut (
        .clock            (clock),
        .reset            (reset),
        .core_state       (core_state),
        .current_pc       (current_pc),
        .mem_read_valid   (mem_read_valid),
        .mem_read_address (mem_read_address),
        .mem_read_ready   (mem_read_ready),
        .mem_read_data    (mem_read_data),
        .fetcher_done     (fetcher_done),
        .instruction      (instruction)
    );

    // Clock generation: 10ns period (100MHz)
    always #5 clock = ~clock;

    // Pipeline stages (must match the encoding in fetcher.sv)
    localparam FETCH  = 3'b001;
    localparam DECODE = 3'b010;

    // ----- Mock program memory -----
    reg [15:0] prog_mem [0:255];
    integer    mem_latency   = 1;   // cycles before the memory answers a request
    integer    mem_wait_cnt  = 0;

    always @(posedge clock) begin
        if (reset) begin
            mem_read_ready <= 1'b0;
            mem_read_data  <= 16'b0;
            mem_wait_cnt   <= 0;
        end else if (mem_read_valid && !mem_read_ready) begin
            // Request in flight: count down the latency, then answer for one cycle
            if (mem_wait_cnt >= mem_latency) begin
                mem_read_ready <= 1'b1;
                mem_read_data  <= prog_mem[mem_read_address];
                mem_wait_cnt   <= 0;
            end else begin
                mem_wait_cnt <= mem_wait_cnt + 1;
            end
        end else begin
            mem_read_ready <= 1'b0;
            mem_wait_cnt   <= 0;
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

    // Enter FETCH at `addr` and block until the fetcher reports done.
    // (instruction + fetcher_done are held valid on return, before re-arming.)
    task start_fetch;
        input [7:0] addr;
        integer guard;
        begin
            current_pc = addr;
            core_state = FETCH;
            guard = 0;
            while (fetcher_done !== 1'b1 && guard < 100) begin
                #10;
                guard = guard + 1;
            end
        end
    endtask

    // Advance the core out of FETCH so the fetcher re-arms for the next request.
    task end_fetch;
        begin
            core_state = DECODE;
            #10;
        end
    endtask

    initial begin
        $dumpfile("fetcher_tb.vcd");
        $dumpvars(0, fetcher_tb);

        // Preload the mock program memory with a few recognizable words
        prog_mem[0]  = 16'h3120;   // ADD   R1, R2, R0
        prog_mem[1]  = 16'h9105;   // CONST R1, 5
        prog_mem[2]  = 16'h0000;   // NOP
        prog_mem[3]  = 16'hF000;   // RET
        prog_mem[42] = 16'hABCD;   // arbitrary, for a non-sequential fetch

        clock          = 0;
        reset          = 1;
        core_state     = DECODE;   // start parked outside FETCH
        current_pc     = 8'd0;
        mem_read_ready = 0;
        mem_read_data  = 0;

        $display("\n========================================");
        $display("Fetcher Testbench Starting");
        $display("========================================\n");

        // Reset sequence
        #20;
        check_signal(fetcher_done,   0, "Reset: fetcher_done = 0");
        check_signal(mem_read_valid, 0, "Reset: mem_read_valid = 0");
        check_signal(instruction,    0, "Reset: instruction = 0");

        reset = 0;
        #10;

        // ==========================================
        // Basic fetch
        // ==========================================
        $display("\n--- Basic fetch ---\n");

        start_fetch(8'd0);
        check_signal(instruction,    prog_mem[0], "Fetch @0 -> prog_mem[0] (0x3120)");
        check_signal(fetcher_done,   1,           "Fetch @0: fetcher_done asserted");
        check_signal(mem_read_valid, 0,           "Fetch @0: valid dropped after handshake");
        end_fetch();
        check_signal(fetcher_done,   0,           "done clears after leaving FETCH (re-arm)");

        // ==========================================
        // Sequential fetches
        // ==========================================
        $display("\n--- Sequential fetches ---\n");

        start_fetch(8'd1);
        check_signal(instruction, prog_mem[1], "Fetch @1 -> CONST (0x9105)");
        end_fetch();

        start_fetch(8'd2);
        check_signal(instruction, prog_mem[2], "Fetch @2 -> NOP (0x0000)");
        end_fetch();

        start_fetch(8'd3);
        check_signal(instruction, prog_mem[3], "Fetch @3 -> RET (0xF000)");
        end_fetch();

        // ==========================================
        // Non-sequential address
        // ==========================================
        $display("\n--- Non-sequential address ---\n");

        start_fetch(8'd42);
        check_signal(instruction, prog_mem[42], "Fetch @42 -> 0xABCD");
        end_fetch();

        // ==========================================
        // Slow memory: fetcher must wait for ready
        // ==========================================
        $display("\n--- Slow memory (high latency) ---\n");

        mem_latency = 5;
        start_fetch(8'd1);
        check_signal(instruction,  prog_mem[1], "Slow fetch @1 still returns 0x9105");
        check_signal(fetcher_done, 1,           "Slow fetch: done eventually asserted");
        end_fetch();
        mem_latency = 1;

        // ==========================================
        // Reset mid-life clears outputs
        // ==========================================
        $display("\n--- Reset clears state ---\n");

        reset = 1;
        #10;
        check_signal(fetcher_done,   0, "Reset: fetcher_done = 0");
        check_signal(mem_read_valid, 0, "Reset: mem_read_valid = 0");
        check_signal(instruction,    0, "Reset: instruction = 0");
        reset = 0;
        #10;

        // Fetch works again after reset
        start_fetch(8'd0);
        check_signal(instruction, prog_mem[0], "Post-reset fetch @0 -> 0x3120");
        end_fetch();

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
