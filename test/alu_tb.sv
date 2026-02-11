`default_nettype none
`timescale 1ns/1ns

module alu_tb;
    // Testbench signals
    reg clock;
    reg reset;
    reg enable;
    reg [2:0] core_state;
    reg [1:0] decoded_alu_arithmetic_selector;
    reg decoded_alu_output_selector;
    reg [7:0] rs;
    reg [7:0] rt;
    wire [7:0] alu_out;

    // Instantiate the ALU
    alu uut (
        .clock(clock),
        .reset(reset),
        .enable(enable),
        .core_state(core_state),
        .decoded_alu_arithmetic_selector(decoded_alu_arithmetic_selector),
        .decoded_alu_output_selector(decoded_alu_output_selector),
        .rs(rs),
        .rt(rt),
        .alu_out(alu_out)
    );

    // Clock generation: 10ns period (100MHz)
    always #5 clock = ~clock;

    // State parameters
    localparam EXECUTE = 3'b101;

    // ALU operation parameters
    localparam ADD = 2'b00;
    localparam SUB = 2'b01;
    localparam MUL = 2'b10;
    localparam DIV = 2'b11;

    // Test counter
    integer tests_passed = 0;
    integer tests_failed = 0;

    // Task to check result
    task check_result;
        input [7:0] expected;
        input [255:0] test_name;  // String for test name
        begin
            if (alu_out === expected) begin
                $display("[PASS] %s: got %d", test_name, alu_out);
                tests_passed = tests_passed + 1;
            end else begin
                $display("[FAIL] %s: expected %d, got %d", test_name, expected, alu_out);
                tests_failed = tests_failed + 1;
            end
        end
    endtask

    initial begin
        // Setup waveform dump
        $dumpfile("alu_tb.vcd");
        $dumpvars(0, alu_tb);

        // Initialize signals
        clock = 0;
        reset = 1;
        enable = 0;
        core_state = 3'b000;
        decoded_alu_arithmetic_selector = 2'b00;
        decoded_alu_output_selector = 0;
        rs = 8'b0;
        rt = 8'b0;

        $display("\n========================================");
        $display("ALU Testbench Starting");
        $display("========================================\n");

        // Reset sequence
        #20;
        reset = 0;
        enable = 1;
        core_state = EXECUTE;
        #10;

        // ==========================================
        // Test Arithmetic Operations
        // ==========================================
        $display("--- Testing Arithmetic Operations ---\n");

        // Test ADD: 5 + 3 = 8
        decoded_alu_output_selector = 0;  // Arithmetic mode
        decoded_alu_arithmetic_selector = ADD;
        rs = 8'd5;
        rt = 8'd3;
        #10;
        check_result(8'd8, "ADD: 5 + 3");

        // Test ADD: 100 + 55 = 155
        rs = 8'd100;
        rt = 8'd55;
        #10;
        check_result(8'd155, "ADD: 100 + 55");

        // Test ADD overflow: 200 + 100 = 44 (wraps around)
        rs = 8'd200;
        rt = 8'd100;
        #10;
        check_result(8'd44, "ADD overflow: 200 + 100");

        // Test SUB: 10 - 3 = 7
        decoded_alu_arithmetic_selector = SUB;
        rs = 8'd10;
        rt = 8'd3;
        #10;
        check_result(8'd7, "SUB: 10 - 3");

        // Test SUB underflow: 3 - 10 = 249 (wraps around)
        rs = 8'd3;
        rt = 8'd10;
        #10;
        check_result(8'd249, "SUB underflow: 3 - 10");

        // Test MUL: 6 * 7 = 42
        decoded_alu_arithmetic_selector = MUL;
        rs = 8'd6;
        rt = 8'd7;
        #10;
        check_result(8'd42, "MUL: 6 * 7");

        // Test MUL: 15 * 15 = 225
        rs = 8'd15;
        rt = 8'd15;
        #10;
        check_result(8'd225, "MUL: 15 * 15");

        // Test DIV: 20 / 4 = 5
        decoded_alu_arithmetic_selector = DIV;
        rs = 8'd20;
        rt = 8'd4;
        #10;
        check_result(8'd5, "DIV: 20 / 4");

        // Test DIV: 100 / 7 = 14 (integer division)
        rs = 8'd100;
        rt = 8'd7;
        #10;
        check_result(8'd14, "DIV: 100 / 7");

        // ==========================================
        // Test Comparison Operations
        // ==========================================
        $display("\n--- Testing Comparison Operations ---\n");
        decoded_alu_output_selector = 1;  // Comparison mode

        // Test: rs < rt (5 < 10) -> negative flag set
        rs = 8'd5;
        rt = 8'd10;
        #10;
        check_result(8'b00000100, "CMP: 5 < 10 (N=1,Z=0,P=0)");

        // Test: rs == rt (7 == 7) -> zero flag set
        rs = 8'd7;
        rt = 8'd7;
        #10;
        check_result(8'b00000010, "CMP: 7 == 7 (N=0,Z=1,P=0)");

        // Test: rs > rt (15 > 8) -> positive flag set
        rs = 8'd15;
        rt = 8'd8;
        #10;
        check_result(8'b00000001, "CMP: 15 > 8 (N=0,Z=0,P=1)");

        // ==========================================
        // Test Enable Signal
        // ==========================================
        $display("\n--- Testing Enable Signal ---\n");

        // Disable ALU and change inputs - output should not change
        enable = 0;
        decoded_alu_output_selector = 0;
        decoded_alu_arithmetic_selector = ADD;
        rs = 8'd50;
        rt = 8'd50;
        #10;
        // Output should still be from previous test (comparison result)
        check_result(8'b00000001, "Enable=0: Output unchanged");

        // Re-enable and verify it works again
        enable = 1;
        #10;
        check_result(8'd100, "Enable=1: ADD 50 + 50");

        // ==========================================
        // Test Core State
        // ==========================================
        $display("\n--- Testing Core State ---\n");

        // Set to non-EXECUTE state - output should not change
        core_state = 3'b000;  // Not EXECUTE
        rs = 8'd1;
        rt = 8'd1;
        #10;
        check_result(8'd100, "Non-EXECUTE state: Output unchanged");

        // Return to EXECUTE state
        core_state = EXECUTE;
        #10;
        check_result(8'd2, "EXECUTE state: ADD 1 + 1");

        // ==========================================
        // Test Reset
        // ==========================================
        $display("\n--- Testing Reset ---\n");

        reset = 1;
        #10;
        check_result(8'd0, "Reset: Output = 0");
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

        if (tests_failed == 0) begin
            $display("ALL TESTS PASSED!\n");
        end else begin
            $display("SOME TESTS FAILED!\n");
        end

        $finish;
    end

endmodule
