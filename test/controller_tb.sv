`default_nettype none
`timescale 1ns/1ns

// CONTROLLER TESTBENCH
// Drives several consumer request channels at a single physical memory channel
// and checks the controller relays each request/response correctly and
// serializes simultaneous requests through the one channel.
//
// Buses are flattened: consumer k lives in [k*W +: W] of each packed vector.
module controller_tb;
    localparam ADDR_BITS     = 8;
    localparam DATA_BITS     = 8;
    localparam NUM_CONSUMERS = 4;
    localparam NUM_CHANNELS  = 1;

    reg clock;
    reg reset;

    // Consumer side (driven by the test)
    reg  [NUM_CONSUMERS-1:0]           consumer_read_valid;
    reg  [NUM_CONSUMERS*ADDR_BITS-1:0] consumer_read_address;
    wire [NUM_CONSUMERS-1:0]           consumer_read_ready;
    wire [NUM_CONSUMERS*DATA_BITS-1:0] consumer_read_data;
    reg  [NUM_CONSUMERS-1:0]           consumer_write_valid;
    reg  [NUM_CONSUMERS*ADDR_BITS-1:0] consumer_write_address;
    reg  [NUM_CONSUMERS*DATA_BITS-1:0] consumer_write_data;
    wire [NUM_CONSUMERS-1:0]           consumer_write_ready;

    // Memory side (answered by the mock memory)
    wire [NUM_CHANNELS-1:0]           mem_read_valid;
    wire [NUM_CHANNELS*ADDR_BITS-1:0] mem_read_address;
    reg  [NUM_CHANNELS-1:0]           mem_read_ready;
    reg  [NUM_CHANNELS*DATA_BITS-1:0] mem_read_data;
    wire [NUM_CHANNELS-1:0]           mem_write_valid;
    wire [NUM_CHANNELS*ADDR_BITS-1:0] mem_write_address;
    wire [NUM_CHANNELS*DATA_BITS-1:0] mem_write_data;
    reg  [NUM_CHANNELS-1:0]           mem_write_ready;

    controller #(
        .ADDR_BITS     (ADDR_BITS),
        .DATA_BITS     (DATA_BITS),
        .NUM_CONSUMERS (NUM_CONSUMERS),
        .NUM_CHANNELS  (NUM_CHANNELS)
    ) uut (
        .clock                  (clock),
        .reset                  (reset),
        .consumer_read_valid    (consumer_read_valid),
        .consumer_read_address  (consumer_read_address),
        .consumer_read_ready    (consumer_read_ready),
        .consumer_read_data     (consumer_read_data),
        .consumer_write_valid   (consumer_write_valid),
        .consumer_write_address (consumer_write_address),
        .consumer_write_data    (consumer_write_data),
        .consumer_write_ready   (consumer_write_ready),
        .mem_read_valid         (mem_read_valid),
        .mem_read_address       (mem_read_address),
        .mem_read_ready         (mem_read_ready),
        .mem_read_data          (mem_read_data),
        .mem_write_valid        (mem_write_valid),
        .mem_write_address      (mem_write_address),
        .mem_write_data         (mem_write_data),
        .mem_write_ready        (mem_write_ready)
    );

    always #5 clock = ~clock;

    // ----- Mock memory (single channel, 1-cycle latency) -----
    reg [7:0] data_mem [0:255];
    integer rcnt = 0;
    integer wcnt = 0;
    always @(posedge clock) begin
        if (reset) begin
            mem_read_ready[0]  <= 0; mem_read_data[0*DATA_BITS +: DATA_BITS] <= 0; rcnt <= 0;
            mem_write_ready[0] <= 0; wcnt <= 0;
        end else begin
            if (mem_read_valid[0] && !mem_read_ready[0]) begin
                if (rcnt >= 1) begin
                    mem_read_ready[0] <= 1;
                    mem_read_data[0*DATA_BITS +: DATA_BITS]
                        <= data_mem[mem_read_address[0*ADDR_BITS +: ADDR_BITS]];
                    rcnt <= 0;
                end else rcnt <= rcnt + 1;
            end else begin
                mem_read_ready[0] <= 0; rcnt <= 0;
            end

            if (mem_write_valid[0] && !mem_write_ready[0]) begin
                if (wcnt >= 1) begin
                    mem_write_ready[0] <= 1;
                    data_mem[mem_write_address[0*ADDR_BITS +: ADDR_BITS]]
                        <= mem_write_data[0*DATA_BITS +: DATA_BITS];
                    wcnt <= 0;
                end else wcnt <= wcnt + 1;
            end else begin
                mem_write_ready[0] <= 0; wcnt <= 0;
            end
        end
    end

    integer tests_passed = 0;
    integer tests_failed = 0;
    integer k, guard, served;
    reg [7:0] captured [NUM_CONSUMERS-1:0];

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
        $dumpfile("controller_tb.vcd");
        $dumpvars(0, controller_tb);

        // Preload memory
        data_mem[8'h10] = 8'h42;
        data_mem[8'h20] = 8'hA0;
        data_mem[8'h21] = 8'hA1;
        data_mem[8'h22] = 8'hA2;
        data_mem[8'h23] = 8'hA3;

        clock = 0;
        reset = 1;
        consumer_read_valid    = {NUM_CONSUMERS{1'b0}};
        consumer_write_valid   = {NUM_CONSUMERS{1'b0}};
        consumer_read_address  = 0;
        consumer_write_address = 0;
        consumer_write_data    = 0;
        mem_read_ready  = 0;
        mem_write_ready = 0;
        for (k = 0; k < NUM_CONSUMERS; k = k + 1) captured[k] = 8'hxx;

        $display("\n========================================");
        $display("Controller Testbench Starting");
        $display("========================================\n");

        #20;
        check_signal(consumer_read_ready,  0, "Reset: consumer_read_ready = 0");
        check_signal(consumer_write_ready, 0, "Reset: consumer_write_ready = 0");
        check_signal(mem_read_valid,       0, "Reset: mem_read_valid = 0");
        reset = 0;
        #10;

        // ==========================================
        // Single consumer read
        // ==========================================
        $display("\n--- Single consumer read ---\n");

        consumer_read_address[0*ADDR_BITS +: ADDR_BITS] = 8'h10;
        consumer_read_valid[0]                          = 1;
        guard = 0;
        while (!consumer_read_ready[0] && guard < 100) begin #10; guard = guard + 1; end
        check_signal(consumer_read_data[0*DATA_BITS +: DATA_BITS], data_mem[8'h10],
                     "consumer 0 read [0x10] = 0x42");
        consumer_read_valid[0] = 0;     // acknowledge
        #20;

        // ==========================================
        // All consumers request at once -> serialized through 1 channel
        // ==========================================
        $display("\n--- Simultaneous reads (arbitration) ---\n");

        for (k = 0; k < NUM_CONSUMERS; k = k + 1) begin
            consumer_read_address[k*ADDR_BITS +: ADDR_BITS] = 8'h20 + k[7:0];
            consumer_read_valid[k]                          = 1;
        end

        served = 0;
        guard  = 0;
        while (served < NUM_CONSUMERS && guard < 400) begin
            for (k = 0; k < NUM_CONSUMERS; k = k + 1) begin
                if (consumer_read_valid[k] && consumer_read_ready[k]) begin
                    captured[k]            = consumer_read_data[k*DATA_BITS +: DATA_BITS];
                    consumer_read_valid[k] = 0;     // ack, freeing the channel
                    served                 = served + 1;
                end
            end
            #10; guard = guard + 1;
        end

        check_signal(served,      NUM_CONSUMERS, "all 4 consumers served");
        check_signal(captured[0], 8'hA0, "consumer 0 got [0x20] = 0xA0");
        check_signal(captured[1], 8'hA1, "consumer 1 got [0x21] = 0xA1");
        check_signal(captured[2], 8'hA2, "consumer 2 got [0x22] = 0xA2");
        check_signal(captured[3], 8'hA3, "consumer 3 got [0x23] = 0xA3");
        #20;

        // ==========================================
        // A consumer write
        // ==========================================
        $display("\n--- Consumer write ---\n");

        consumer_write_address[1*ADDR_BITS +: ADDR_BITS] = 8'h30;
        consumer_write_data[1*DATA_BITS +: DATA_BITS]    = 8'h77;
        consumer_write_valid[1]                          = 1;
        guard = 0;
        while (!consumer_write_ready[1] && guard < 100) begin #10; guard = guard + 1; end
        consumer_write_valid[1] = 0;
        #20;
        check_signal(data_mem[8'h30], 8'h77, "consumer 1 wrote 0x77 -> [0x30]");

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
