`default_nettype none
`timescale 1ns/1ns

module decoder_tb;
    reg         clock;
    reg         reset;
    reg  [2:0]  core_state;
    reg  [15:0] instruction;

    wire [3:0]  decoded_rd_address;
    wire [3:0]  decoded_rs_address;
    wire [3:0]  decoded_rt_address;
    wire [2:0]  decoded_nzp;
    wire [7:0]  decoded_immediate;
    wire        decoded_reg_write_enable;
    wire        decoded_mem_read_enable;
    wire        decoded_mem_write_enable;
    wire        decoded_nzp_write_enable;
    wire [1:0]  decoded_reg_input_selector;
    wire [1:0]  decoded_alu_arithmetic_selector;
    wire        decoded_alu_output_selector;
    wire        decoded_pc_mux;
    wire        decoded_ret;

    decoder uut (
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

    // Clock generation: 10ns period (100MHz)
    always #5 clock = ~clock;

    // Pipeline stage
    localparam DECODE = 3'b010;

    // Opcodes
    localparam NOP   = 4'b0000;
    localparam BRnzp = 4'b0001;
    localparam CMP   = 4'b0010;
    localparam ADD   = 4'b0011;
    localparam SUB   = 4'b0100;
    localparam MUL   = 4'b0101;
    localparam DIV   = 4'b0110;
    localparam LDR   = 4'b0111;
    localparam STR   = 4'b1000;
    localparam CONST = 4'b1001;
    localparam RET   = 4'b1111;

    // Register input selector values
    localparam REG_SRC_ARITHMETIC = 2'b00;
    localparam REG_SRC_MEMORY     = 2'b01;
    localparam REG_SRC_CONSTANT   = 2'b10;

    // ALU arithmetic selector values
    localparam ALU_ADD = 2'b00;
    localparam ALU_SUB = 2'b01;
    localparam ALU_MUL = 2'b10;
    localparam ALU_DIV = 2'b11;

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

    initial begin
        $dumpfile("decoder_tb.vcd");
        $dumpvars(0, decoder_tb);

        clock       = 0;
        reset       = 1;
        core_state  = 3'b000;
        instruction = 16'h0;

        $display("\n========================================");
        $display("Decoder Testbench Starting");
        $display("========================================\n");

        // Reset sequence
        #20;
        reset      = 0;
        core_state = DECODE;
        #10;

        // ==========================================
        // Test NOP
        // ==========================================
        $display("--- NOP ---\n");
        instruction = {NOP, 12'h0};
        #10;
        check_signal(decoded_reg_write_enable,        0, "NOP: reg_write_enable = 0");
        check_signal(decoded_mem_read_enable,         0, "NOP: mem_read_enable = 0");
        check_signal(decoded_mem_write_enable,        0, "NOP: mem_write_enable = 0");
        check_signal(decoded_nzp_write_enable,        0, "NOP: nzp_write_enable = 0");
        check_signal(decoded_alu_output_selector,     0, "NOP: alu_output_selector = 0");
        check_signal(decoded_pc_mux,                  0, "NOP: pc_mux = 0");
        check_signal(decoded_ret,                     0, "NOP: ret = 0");

        // ==========================================
        // Test ADD R3, R1, R2
        // ==========================================
        $display("\n--- ADD R3, R1, R2 ---\n");
        instruction = {ADD, 4'd3, 4'd1, 4'd2};
        #10;
        check_signal(decoded_rd_address,              3,                  "ADD: rd_address = 3");
        check_signal(decoded_rs_address,              1,                  "ADD: rs_address = 1");
        check_signal(decoded_rt_address,              2,                  "ADD: rt_address = 2");
        check_signal(decoded_reg_write_enable,        1,                  "ADD: reg_write_enable = 1");
        check_signal(decoded_reg_input_selector,      REG_SRC_ARITHMETIC, "ADD: reg_input_selector = ARITHMETIC");
        check_signal(decoded_alu_arithmetic_selector, ALU_ADD,            "ADD: alu_arithmetic_selector = ADD");
        check_signal(decoded_alu_output_selector,     0,                  "ADD: alu_output_selector = 0 (arithmetic)");
        check_signal(decoded_mem_read_enable,         0,                  "ADD: mem_read_enable = 0");
        check_signal(decoded_pc_mux,                  0,                  "ADD: pc_mux = 0");

        // ==========================================
        // Test SUB R5, R2, R4
        // ==========================================
        $display("\n--- SUB R5, R2, R4 ---\n");
        instruction = {SUB, 4'd5, 4'd2, 4'd4};
        #10;
        check_signal(decoded_alu_arithmetic_selector, ALU_SUB,            "SUB: alu_arithmetic_selector = SUB");
        check_signal(decoded_reg_write_enable,        1,                  "SUB: reg_write_enable = 1");
        check_signal(decoded_reg_input_selector,      REG_SRC_ARITHMETIC, "SUB: reg_input_selector = ARITHMETIC");

        // ==========================================
        // Test MUL R0, R7, R6
        // ==========================================
        $display("\n--- MUL R0, R7, R6 ---\n");
        instruction = {MUL, 4'd0, 4'd7, 4'd6};
        #10;
        check_signal(decoded_alu_arithmetic_selector, ALU_MUL,            "MUL: alu_arithmetic_selector = MUL");
        check_signal(decoded_reg_write_enable,        1,                  "MUL: reg_write_enable = 1");
        check_signal(decoded_reg_input_selector,      REG_SRC_ARITHMETIC, "MUL: reg_input_selector = ARITHMETIC");

        // ==========================================
        // Test DIV R1, R8, R9
        // ==========================================
        $display("\n--- DIV R1, R8, R9 ---\n");
        instruction = {DIV, 4'd1, 4'd8, 4'd9};
        #10;
        check_signal(decoded_alu_arithmetic_selector, ALU_DIV,            "DIV: alu_arithmetic_selector = DIV");
        check_signal(decoded_reg_write_enable,        1,                  "DIV: reg_write_enable = 1");
        check_signal(decoded_reg_input_selector,      REG_SRC_ARITHMETIC, "DIV: reg_input_selector = ARITHMETIC");

        // ==========================================
        // Test CMP R_, R2, R3
        // ==========================================
        $display("\n--- CMP ---\n");
        instruction = {CMP, 4'd0, 4'd2, 4'd3};
        #10;
        check_signal(decoded_alu_output_selector, 1, "CMP: alu_output_selector = 1 (comparison mode)");
        check_signal(decoded_nzp_write_enable,    1, "CMP: nzp_write_enable = 1");
        check_signal(decoded_reg_write_enable,    0, "CMP: reg_write_enable = 0 (no reg write)");

        // ==========================================
        // Test BRnzp  nzp=101, target=0x42
        // [15:12]=BRnzp, [11:9]=nzp, [8]=0, [7:0]=immediate
        // ==========================================
        $display("\n--- BRnzp (nzp=101, target=0x42) ---\n");
        instruction = {BRnzp, 3'b101, 1'b0, 8'h42};
        #10;
        check_signal(decoded_pc_mux,           1,      "BRnzp: pc_mux = 1 (branch)");
        check_signal(decoded_nzp,              3'b101, "BRnzp: nzp = 3'b101");
        check_signal(decoded_immediate,        8'h42,  "BRnzp: immediate = 0x42");
        check_signal(decoded_reg_write_enable, 0,      "BRnzp: reg_write_enable = 0");

        // ==========================================
        // Test LDR R4, R2
        // ==========================================
        $display("\n--- LDR R4, R2 ---\n");
        instruction = {LDR, 4'd4, 4'd2, 4'd0};
        #10;
        check_signal(decoded_reg_write_enable,   1,              "LDR: reg_write_enable = 1");
        check_signal(decoded_mem_read_enable,    1,              "LDR: mem_read_enable = 1");
        check_signal(decoded_reg_input_selector, REG_SRC_MEMORY, "LDR: reg_input_selector = MEMORY");
        check_signal(decoded_rd_address,         4,              "LDR: rd_address = 4");
        check_signal(decoded_rs_address,         2,              "LDR: rs_address = 2 (mem address)");
        check_signal(decoded_mem_write_enable,   0,              "LDR: mem_write_enable = 0");

        // ==========================================
        // Test STR rs=R2 (address), rt=R5 (data)
        // ==========================================
        $display("\n--- STR R2, R5 ---\n");
        instruction = {STR, 4'd0, 4'd2, 4'd5};
        #10;
        check_signal(decoded_mem_write_enable,  1, "STR: mem_write_enable = 1");
        check_signal(decoded_reg_write_enable,  0, "STR: reg_write_enable = 0 (no reg write)");
        check_signal(decoded_rs_address,        2, "STR: rs_address = 2 (address)");
        check_signal(decoded_rt_address,        5, "STR: rt_address = 5 (data)");
        check_signal(decoded_mem_read_enable,   0, "STR: mem_read_enable = 0");

        // ==========================================
        // Test CONST R6, #100
        // ==========================================
        $display("\n--- CONST R6, #100 ---\n");
        instruction = {CONST, 4'd6, 8'd100};
        #10;
        check_signal(decoded_reg_write_enable,   1,                 "CONST: reg_write_enable = 1");
        check_signal(decoded_reg_input_selector, REG_SRC_CONSTANT,  "CONST: reg_input_selector = CONSTANT");
        check_signal(decoded_rd_address,         6,                 "CONST: rd_address = 6");
        check_signal(decoded_immediate,          100,               "CONST: immediate = 100");
        check_signal(decoded_mem_read_enable,    0,                 "CONST: mem_read_enable = 0");

        // ==========================================
        // Test RET
        // ==========================================
        $display("\n--- RET ---\n");
        instruction = {RET, 12'h0};
        #10;
        check_signal(decoded_ret,              1, "RET: decoded_ret = 1");
        check_signal(decoded_reg_write_enable, 0, "RET: reg_write_enable = 0");
        check_signal(decoded_mem_read_enable,  0, "RET: mem_read_enable = 0");

        // ==========================================
        // Test: outputs hold outside DECODE stage
        // (last instruction was RET, decoded_ret = 1)
        // ==========================================
        $display("\n--- Hold outside DECODE stage ---\n");
        core_state  = 3'b000;
        instruction = {NOP, 12'h0};   // NOP presented but ignored (not DECODE)
        #10;
        check_signal(decoded_ret, 1, "Non-DECODE: outputs hold (ret still 1)");

        // Return to DECODE - NOP should clear ret
        core_state = DECODE;
        #10;
        check_signal(decoded_ret,              0, "Back to DECODE: NOP clears ret");
        check_signal(decoded_reg_write_enable, 0, "Back to DECODE: NOP clears reg_write_enable");

        // ==========================================
        // Test Reset
        // ==========================================
        $display("\n--- Reset ---\n");
        instruction = {ADD, 4'd3, 4'd1, 4'd2};
        core_state  = DECODE;
        #10;   // decode the ADD so signals are non-zero
        reset = 1;
        #10;
        check_signal(decoded_reg_write_enable, 0, "Reset: reg_write_enable = 0");
        check_signal(decoded_rd_address,       0, "Reset: rd_address = 0");
        check_signal(decoded_ret,              0, "Reset: ret = 0");
        check_signal(decoded_pc_mux,           0, "Reset: pc_mux = 0");
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
