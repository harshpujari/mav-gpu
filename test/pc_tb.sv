`default_nettype none
`timescale 1ns/1ns

module pc_tb;
    reg        clock;
    reg        reset;
    reg        enable;
    reg  [2:0] core_state;
    reg  [2:0] decoded_nzp;
    reg  [7:0] decoded_immediate;
    reg        decoded_nzp_write_enable;
    reg        decoded_pc_mux;
    reg  [7:0] alu_out;
    reg  [7:0] current_pc;

    wire [7:0] next_pc;

    pc #(
        .DATA_BITS             (8),
        .PROGRAM_MEM_ADDR_BITS (8)
    ) uut (
        .clock                    (clock),
        .reset                    (reset),
        .enable                   (enable),
        .core_state               (core_state),
        .decoded_nzp              (decoded_nzp),
        .decoded_immediate        (decoded_immediate),
        .decoded_nzp_write_enable (decoded_nzp_write_enable),
        .decoded_pc_mux           (decoded_pc_mux),
        .alu_out                  (alu_out),
        .current_pc               (current_pc),
        .next_pc                  (next_pc)
    );

    // Clock generation: 10ns period (100MHz)
    always #5 clock = ~clock;

    // Pipeline stages
    localparam FETCH   = 3'b000;
    localparam EXECUTE = 3'b101;
    localparam UPDATE  = 3'b110;

    // ALU comparison output encoding: {5'b0, N, Z, P}
    localparam [7:0] ALU_NEG  = 8'b00000_100;
    localparam [7:0] ALU_ZERO = 8'b00000_010;
    localparam [7:0] ALU_POS  = 8'b00000_001;

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

    // Drive a CMP-style UPDATE: latch nzp from alu_out[2:0]
    task latch_nzp;
        input [7:0] alu_value;
        begin
            decoded_nzp_write_enable = 1;
            alu_out                  = alu_value;
            core_state               = UPDATE;
            #10;
            decoded_nzp_write_enable = 0;
            core_state               = FETCH;
        end
    endtask

    // Drive an EXECUTE for a sequential (non-branch) instruction
    task step_sequential;
        input [7:0] pc_in;
        begin
            decoded_pc_mux    = 0;
            decoded_nzp       = 3'b000;
            decoded_immediate = 8'd0;
            current_pc        = pc_in;
            core_state        = EXECUTE;
            #10;
            core_state        = FETCH;
        end
    endtask

    // Drive an EXECUTE for a BRnzp instruction
    task step_branch;
        input [7:0] pc_in;
        input [2:0] nzp_mask;
        input [7:0] target;
        begin
            decoded_pc_mux    = 1;
            decoded_nzp       = nzp_mask;
            decoded_immediate = target;
            current_pc        = pc_in;
            core_state        = EXECUTE;
            #10;
            core_state        = FETCH;
        end
    endtask

    initial begin
        $dumpfile("pc_tb.vcd");
        $dumpvars(0, pc_tb);

        clock                    = 0;
        reset                    = 1;
        enable                   = 0;
        core_state               = FETCH;
        decoded_nzp              = 3'b000;
        decoded_immediate        = 8'd0;
        decoded_nzp_write_enable = 0;
        decoded_pc_mux           = 0;
        alu_out                  = 8'd0;
        current_pc               = 8'd0;

        $display("\n========================================");
        $display("Program Counter Testbench Starting");
        $display("========================================\n");

        // Reset sequence
        #20;
        reset  = 0;
        enable = 1;
        #10;

        check_signal(next_pc, 0, "Reset: next_pc = 0");

        // ==========================================
        // Sequential PC Increment
        // ==========================================
        $display("\n--- Sequential PC Increment ---\n");

        step_sequential(8'd0);
        check_signal(next_pc, 1, "Seq: PC=0 -> next_pc=1");

        step_sequential(8'd1);
        check_signal(next_pc, 2, "Seq: PC=1 -> next_pc=2");

        step_sequential(8'd42);
        check_signal(next_pc, 43, "Seq: PC=42 -> next_pc=43");

        step_sequential(8'd255);
        check_signal(next_pc, 0, "Seq: PC=255 -> wraps to 0 (8-bit)");

        // ==========================================
        // BRnzp with empty NZP - never taken
        // ==========================================
        $display("\n--- BRnzp with empty NZP ---\n");

        // After reset NZP=0; (0 & anything) == 0, so branch never taken
        step_branch(8'd10, 3'b111, 8'd99);
        check_signal(next_pc, 11, "BR: NZP=000, mask=111 -> not taken (PC+1)");

        // ==========================================
        // CMP -> NEGATIVE, branch on n
        // ==========================================
        $display("\n--- NZP=N ---\n");

        latch_nzp(ALU_NEG);

        step_branch(8'd20, 3'b100, 8'd80);
        check_signal(next_pc, 80, "BR: NZP=N, mask=n   -> taken to 80");

        step_branch(8'd20, 3'b010, 8'd80);
        check_signal(next_pc, 21, "BR: NZP=N, mask=z   -> not taken");

        step_branch(8'd20, 3'b001, 8'd80);
        check_signal(next_pc, 21, "BR: NZP=N, mask=p   -> not taken");

        step_branch(8'd20, 3'b111, 8'd123);
        check_signal(next_pc, 123, "BR: NZP=N, mask=nzp -> taken to 123");

        // ==========================================
        // CMP -> ZERO, branch on z
        // ==========================================
        $display("\n--- NZP=Z ---\n");

        latch_nzp(ALU_ZERO);

        step_branch(8'd30, 3'b010, 8'd200);
        check_signal(next_pc, 200, "BR: NZP=Z, mask=z   -> taken to 200");

        step_branch(8'd30, 3'b101, 8'd200);
        check_signal(next_pc, 31, "BR: NZP=Z, mask=np  -> not taken");

        // ==========================================
        // CMP -> POSITIVE, branch on p
        // ==========================================
        $display("\n--- NZP=P ---\n");

        latch_nzp(ALU_POS);

        step_branch(8'd40, 3'b001, 8'd150);
        check_signal(next_pc, 150, "BR: NZP=P, mask=p   -> taken to 150");

        step_branch(8'd40, 3'b110, 8'd150);
        check_signal(next_pc, 41, "BR: NZP=P, mask=nz  -> not taken");

        // ==========================================
        // NZP persists until next CMP
        // ==========================================
        $display("\n--- NZP persistence ---\n");

        // NZP is currently P; a sequential step shouldn't clobber it
        step_sequential(8'd50);
        check_signal(next_pc, 51, "Seq doesn't disturb NZP");

        step_branch(8'd50, 3'b001, 8'd77);
        check_signal(next_pc, 77, "BR: P still latched -> taken to 77");

        // ==========================================
        // nzp_write_enable=0 doesn't change NZP
        // ==========================================
        $display("\n--- NZP write-protect ---\n");

        // Try to "fake" updating NZP without the enable bit
        decoded_nzp_write_enable = 0;
        alu_out                  = ALU_NEG;
        core_state               = UPDATE;
        #10;
        core_state               = FETCH;

        // Should still be POSITIVE - branch on p must succeed
        step_branch(8'd60, 3'b001, 8'd88);
        check_signal(next_pc, 88, "BR: NZP unchanged (still P) -> taken to 88");

        // ==========================================
        // Enable masking: PC frozen when disabled
        // ==========================================
        $display("\n--- Enable Masking ---\n");

        enable = 0;
        step_sequential(8'd100);
        check_signal(next_pc, 88, "Enable=0: next_pc holds previous value");

        enable = 1;
        step_sequential(8'd100);
        check_signal(next_pc, 101, "Enable=1: next_pc updates again");

        // ==========================================
        // Reset clears NZP and next_pc
        // ==========================================
        $display("\n--- Reset Clears State ---\n");

        latch_nzp(ALU_POS);   // make NZP non-zero before reset
        reset = 1;
        #10;
        check_signal(next_pc, 0, "Reset: next_pc = 0");

        reset  = 0;
        enable = 1;
        // After reset NZP=0 - any BRnzp must NOT take
        step_branch(8'd10, 3'b111, 8'd200);
        check_signal(next_pc, 11, "Reset cleared NZP - BR not taken");

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
