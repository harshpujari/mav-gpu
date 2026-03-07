`default_nettype none
`timescale 1ns/1ns

module registers_tb;
    reg        clock;
    reg        reset;
    reg        enable;
    reg  [7:0] block_id;
    reg  [2:0] core_state;
    reg  [3:0] decoded_rd_address;
    reg  [3:0] decoded_rs_address;
    reg  [3:0] decoded_rt_address;
    reg        decoded_reg_write_enable;
    reg  [1:0] decoded_reg_input_selector;
    reg  [7:0] decoded_immediate;
    reg  [7:0] alu_out;
    reg  [7:0] lsu_out;

    wire [7:0] rs;
    wire [7:0] rt;

    // Use non-zero THREAD_ID so we can distinguish it from a zero default
    localparam THREADS_PER_BLOCK = 4;
    localparam THREAD_ID         = 2;

    registers #(
        .THREADS_PER_BLOCK (THREADS_PER_BLOCK),
        .THREAD_ID         (THREAD_ID),
        .DATA_BITS         (8)
    ) uut (
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
        .alu_out                    (alu_out),
        .lsu_out                    (lsu_out),
        .rs                         (rs),
        .rt                         (rt)
    );

    // Clock generation: 10ns period (100MHz)
    always #5 clock = ~clock;

    // Pipeline stages
    localparam REQUEST = 3'b011;
    localparam UPDATE  = 3'b110;

    // Write source selection
    localparam ARITHMETIC = 2'b00;
    localparam MEMORY     = 2'b01;
    localparam CONSTANT   = 2'b10;

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

    // Write a value into a register via the UPDATE stage
    task write_reg;
        input [3:0] rd;
        input [1:0] src;
        input [7:0] val_alu;
        input [7:0] val_lsu;
        input [7:0] val_imm;
        begin
            decoded_reg_write_enable   = 1;
            decoded_rd_address         = rd;
            decoded_reg_input_selector = src;
            alu_out                    = val_alu;
            lsu_out                    = val_lsu;
            decoded_immediate          = val_imm;
            core_state                 = UPDATE;
            #10;
            decoded_reg_write_enable   = 0;
        end
    endtask

    // Latch rs from a register address via the REQUEST stage
    task read_rs;
        input [3:0] addr;
        begin
            decoded_rs_address = addr;
            core_state         = REQUEST;
            #10;
        end
    endtask

    // Latch rt from a register address via the REQUEST stage
    task read_rt;
        input [3:0] addr;
        begin
            decoded_rt_address = addr;
            core_state         = REQUEST;
            #10;
        end
    endtask

    initial begin
        $dumpfile("registers_tb.vcd");
        $dumpvars(0, registers_tb);

        clock                      = 0;
        reset                      = 1;
        enable                     = 0;
        block_id                   = 8'd0;
        core_state                 = 3'b000;
        decoded_rd_address         = 4'd0;
        decoded_rs_address         = 4'd0;
        decoded_rt_address         = 4'd0;
        decoded_reg_write_enable   = 0;
        decoded_reg_input_selector = 2'b00;
        decoded_immediate          = 8'd0;
        alu_out                    = 8'd0;
        lsu_out                    = 8'd0;

        $display("\n========================================");
        $display("Register File Testbench Starting");
        $display("(THREAD_ID=%0d, THREADS_PER_BLOCK=%0d)", THREAD_ID, THREADS_PER_BLOCK);
        $display("========================================\n");

        // Reset sequence
        #20;
        reset  = 0;
        enable = 1;
        #10;

        // ==========================================
        // Test Reset Values (read-only registers)
        // ==========================================
        $display("--- Reset Values ---\n");

        read_rs(14);
        check_signal(rs, THREADS_PER_BLOCK, "Reset: R14 (%blockDim) = THREADS_PER_BLOCK");

        read_rs(15);
        check_signal(rs, THREAD_ID, "Reset: R15 (%threadIdx) = THREAD_ID");

        read_rs(13);
        check_signal(rs, 0, "Reset: R13 (%blockIdx) = 0");

        // ==========================================
        // Test Write via CONSTANT, Read Back
        // ==========================================
        $display("\n--- Write via CONSTANT ---\n");

        write_reg(4'd0, CONSTANT, 8'd0, 8'd0, 8'd42);
        read_rs(4'd0);
        check_signal(rs, 42, "CONST: R0 = 42");

        write_reg(4'd7, CONSTANT, 8'd0, 8'd0, 8'd200);
        read_rs(4'd7);
        check_signal(rs, 200, "CONST: R7 = 200");

        // ==========================================
        // Test Write via ALU (ARITHMETIC), Read Back
        // ==========================================
        $display("\n--- Write via ALU (ARITHMETIC) ---\n");

        write_reg(4'd1, ARITHMETIC, 8'd99, 8'd0, 8'd0);
        read_rs(4'd1);
        check_signal(rs, 99, "ALU: R1 = 99");

        write_reg(4'd5, ARITHMETIC, 8'd255, 8'd0, 8'd0);
        read_rs(4'd5);
        check_signal(rs, 255, "ALU: R5 = 255");

        // ==========================================
        // Test Write via Memory (LSU), Read Back
        // ==========================================
        $display("\n--- Write via Memory (MEMORY) ---\n");

        write_reg(4'd2, MEMORY, 8'd0, 8'd173, 8'd0);
        read_rs(4'd2);
        check_signal(rs, 173, "MEM: R2 = 173");

        // ==========================================
        // Test Two-Operand Read (rs and rt simultaneously)
        // ==========================================
        $display("\n--- Two-Operand Read ---\n");

        write_reg(4'd3, CONSTANT, 8'd0, 8'd0, 8'd77);
        write_reg(4'd4, CONSTANT, 8'd0, 8'd0, 8'd88);

        decoded_rs_address = 4'd3;
        decoded_rt_address = 4'd4;
        core_state         = REQUEST;
        #10;
        check_signal(rs, 77, "Two-op: rs = R3 = 77");
        check_signal(rt, 88, "Two-op: rt = R4 = 88");

        // ==========================================
        // Test Read-Only Protection (R13, R14, R15)
        // ==========================================
        $display("\n--- Read-Only Protection ---\n");

        // Attempt to overwrite R14 (%blockDim)
        write_reg(4'd14, CONSTANT, 8'd0, 8'd0, 8'd99);
        read_rs(4'd14);
        check_signal(rs, THREADS_PER_BLOCK, "Read-only: R14 unchanged after write attempt");

        // Attempt to overwrite R15 (%threadIdx)
        write_reg(4'd15, CONSTANT, 8'd0, 8'd0, 8'd99);
        read_rs(4'd15);
        check_signal(rs, THREAD_ID, "Read-only: R15 unchanged after write attempt");

        // ==========================================
        // Test Block ID Update (R13 = %blockIdx)
        // ==========================================
        $display("\n--- Block ID Update ---\n");

        block_id   = 8'd7;
        core_state = 3'b000;   // Any non-REQUEST/UPDATE state - R13 still updates
        #10;
        read_rs(4'd13);
        check_signal(rs, 7, "BlockID: R13 = block_id = 7");

        block_id = 8'd15;
        #10;
        read_rs(4'd13);
        check_signal(rs, 15, "BlockID: R13 updates to 15");

        // ==========================================
        // Test Enable Masking
        // ==========================================
        $display("\n--- Enable Masking ---\n");

        // Establish a known value in rs (R0 = 42)
        read_rs(4'd0);
        check_signal(rs, 42, "Enable setup: rs = R0 = 42");

        // Disable thread - REQUEST should not update rs even if address changes
        enable             = 0;
        decoded_rs_address = 4'd7;   // R7 = 200 (written earlier)
        core_state         = REQUEST;
        #10;
        check_signal(rs, 42, "Enable=0: rs holds previous value (not updated to R7=200)");

        // Re-enable - now the read should go through
        enable = 1;
        #10;
        check_signal(rs, 200, "Enable=1: rs updates to R7 = 200");

        // ==========================================
        // Test Reset Clears General-Purpose Registers
        // ==========================================
        $display("\n--- Reset Clears Registers ---\n");

        reset = 1;
        #10;
        check_signal(rs, 0, "Reset: rs output = 0");
        reset  = 0;
        enable = 1;

        // R0 was 42 before reset - should now be 0
        read_rs(4'd0);
        check_signal(rs, 0, "Reset: R0 = 0 after reset");

        // Read-only registers restore to their parameter values
        read_rs(4'd14);
        check_signal(rs, THREADS_PER_BLOCK, "Reset: R14 restored to THREADS_PER_BLOCK");

        read_rs(4'd15);
        check_signal(rs, THREAD_ID, "Reset: R15 restored to THREAD_ID");

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
