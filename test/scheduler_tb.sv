`default_nettype none
`timescale 1ns/1ns

// SCHEDULER TESTBENCH
// Mocks the fetcher / LSU / PC signals and walks the scheduler through full
// instruction cycles, checking the stage sequence, the FETCH and WAIT stalls,
// the PC advance in UPDATE, and RET completion.
module scheduler_tb;
    localparam THREADS_PER_BLOCK = 4;

    reg        clock;
    reg        reset;
    reg        start;
    reg        decoded_mem_read_enable;
    reg        decoded_mem_write_enable;
    reg        decoded_ret;
    reg        fetcher_done;
    reg  [1:0] lsu_state [THREADS_PER_BLOCK-1:0];
    reg  [7:0] next_pc   [THREADS_PER_BLOCK-1:0];

    wire [7:0] current_pc;
    wire [2:0] core_state;
    wire       done;

    scheduler #(
        .THREADS_PER_BLOCK (THREADS_PER_BLOCK)
    ) uut (
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

    // Clock generation: 10ns period
    always #5 clock = ~clock;

    // Pipeline stages (must match scheduler.sv)
    localparam IDLE    = 3'b000;
    localparam FETCH   = 3'b001;
    localparam DECODE  = 3'b010;
    localparam REQUEST = 3'b011;
    localparam WAIT    = 3'b100;
    localparam EXECUTE = 3'b101;
    localparam UPDATE  = 3'b110;
    localparam DONE    = 3'b111;

    localparam LSU_IDLE    = 2'b00;
    localparam LSU_WAITING = 2'b10;

    integer tests_passed = 0;
    integer tests_failed = 0;
    integer t;

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

    // Advance exactly one clock (one rising edge)
    task tick;
        begin
            #10;
        end
    endtask

    initial begin
        $dumpfile("scheduler_tb.vcd");
        $dumpvars(0, scheduler_tb);

        clock                    = 0;
        reset                    = 1;
        start                    = 0;
        decoded_mem_read_enable  = 0;
        decoded_mem_write_enable = 0;
        decoded_ret              = 0;
        fetcher_done             = 0;
        for (t = 0; t < THREADS_PER_BLOCK; t = t + 1) begin
            lsu_state[t] = LSU_IDLE;
            next_pc[t]   = 8'd0;
        end

        $display("\n========================================");
        $display("Scheduler Testbench Starting");
        $display("========================================\n");

        // Reset
        #20;
        check_signal(core_state, IDLE, "Reset: core_state = IDLE");
        check_signal(current_pc, 0,    "Reset: current_pc = 0");
        check_signal(done,       0,    "Reset: done = 0");
        reset = 0;
        #10;

        // ==========================================
        // A full ALU-style instruction cycle (no memory, no RET)
        // ==========================================
        $display("\n--- Full cycle: IDLE -> ... -> FETCH ---\n");

        check_signal(core_state, IDLE, "Still IDLE before start");

        start = 1;
        tick;
        check_signal(core_state, FETCH, "start -> FETCH");

        // FETCH stalls until the fetcher is done
        fetcher_done = 0;
        tick;
        check_signal(core_state, FETCH, "FETCH stalls while fetcher not done");
        fetcher_done = 1;
        tick;
        check_signal(core_state, DECODE, "fetcher_done -> DECODE");

        tick;
        check_signal(core_state, REQUEST, "DECODE -> REQUEST");

        // Set the next PC the threads computed; UPDATE should latch it
        for (t = 0; t < THREADS_PER_BLOCK; t = t + 1) next_pc[t] = 8'd1;

        tick;
        check_signal(core_state, WAIT, "REQUEST -> WAIT");

        // No memory in flight -> WAIT passes straight through
        tick;
        check_signal(core_state, EXECUTE, "WAIT (no LSU busy) -> EXECUTE");

        tick;
        check_signal(core_state, UPDATE, "EXECUTE -> UPDATE");

        tick;
        check_signal(core_state, FETCH, "UPDATE (no RET) -> FETCH");
        check_signal(current_pc, 1,     "UPDATE advances current_pc to next_pc (1)");

        // ==========================================
        // Second cycle: a memory instruction stalls WAIT
        // ==========================================
        $display("\n--- WAIT stalls on a busy LSU ---\n");

        // already in FETCH with fetcher_done=1
        tick;  check_signal(core_state, DECODE,  "cycle2: -> DECODE");
        tick;  check_signal(core_state, REQUEST, "cycle2: -> REQUEST");

        // Thread 2 has a memory op in flight
        lsu_state[2] = LSU_WAITING;
        for (t = 0; t < THREADS_PER_BLOCK; t = t + 1) next_pc[t] = 8'd2;

        tick;  check_signal(core_state, WAIT, "cycle2: -> WAIT");
        tick;  check_signal(core_state, WAIT, "WAIT holds while LSU busy");
        tick;  check_signal(core_state, WAIT, "WAIT still holds");

        // Memory finishes
        lsu_state[2] = LSU_IDLE;
        tick;  check_signal(core_state, EXECUTE, "LSU idle -> EXECUTE");

        // ==========================================
        // RET ends the block
        // ==========================================
        $display("\n--- RET -> DONE ---\n");

        decoded_ret = 1;
        tick;  check_signal(core_state, UPDATE, "EXECUTE -> UPDATE");
        tick;
        check_signal(core_state, DONE, "UPDATE with RET -> DONE");
        check_signal(done,       1,    "done asserted");

        // DONE is sticky
        tick;
        check_signal(core_state, DONE, "DONE stays until reset");

        // ==========================================
        // Reset returns to IDLE
        // ==========================================
        $display("\n--- Reset clears state ---\n");

        reset = 1;
        #10;
        check_signal(core_state, IDLE, "Reset: core_state = IDLE");
        check_signal(done,       0,    "Reset: done = 0");
        reset = 0;

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
