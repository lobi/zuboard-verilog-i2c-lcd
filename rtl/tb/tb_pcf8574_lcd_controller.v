`timescale 1ns / 1ps

module tb_pcf8574_lcd_controller;

    // Testbench clocking
    // Run faster than "1MHz" to shorten the built-in delays.
    // The DUT delay counters are cycle-based, so a faster clock speeds up sim.
    localparam integer CLK_PERIOD_NS = 100; // 10MHz

    reg clk;
    reg rst_n;

    // Command interface
    reg        cmd_valid;
    reg [2:0]  cmd_type;
    reg [7:0]  cmd_data;
    wire       cmd_ready;
    wire       init_done;

    // I2C master interface (to external i2c master)
    wire       i2c_start;
    wire [6:0] i2c_addr;
    wire [7:0] i2c_data;
    reg        i2c_busy;
    reg        i2c_done;

    // Command types (match DUT)
    localparam CMD_INIT       = 3'd0;
    localparam CMD_CLEAR      = 3'd1;
    localparam CMD_WRITE_CMD  = 3'd2;
    localparam CMD_WRITE_DATA = 3'd3;
    localparam CMD_SET_CURSOR = 3'd4;

    // Instantiate DUT
    pcf8574_lcd_controller dut (
        .clk(clk),
        .rst_n(rst_n),
        .cmd_valid(cmd_valid),
        .cmd_type(cmd_type),
        .cmd_data(cmd_data),
        .cmd_ready(cmd_ready),
        .init_done(init_done),
        .i2c_start(i2c_start),
        .i2c_addr(i2c_addr),
        .i2c_data(i2c_data),
        .i2c_busy(i2c_busy),
        .i2c_done(i2c_done)
    );

    // Clock
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS/2) clk = ~clk;
    end

    // ------------------------------------------------------------------------
    // Fake I2C completion model
    // ------------------------------------------------------------------------
    // Whenever DUT asserts i2c_start, pretend the external I2C writer becomes
    // busy for a few cycles, then produces a 1-cycle i2c_done pulse.
    integer i2c_countdown;

    always @(posedge clk) begin
        if (!rst_n) begin
            i2c_busy <= 1'b0;
            i2c_done <= 1'b0;
            i2c_countdown <= 0;
        end else begin
            i2c_done <= 1'b0;

            // Detect new transfer
            if (i2c_start && !i2c_busy) begin
                i2c_busy <= 1'b1;
                // Small fixed latency
                i2c_countdown <= 3;
            end

            if (i2c_busy) begin
                if (i2c_countdown > 0) begin
                    i2c_countdown <= i2c_countdown - 1;
                end else begin
                    i2c_busy <= 1'b0;
                    i2c_done <= 1'b1;
                end
            end
        end
    end

    // ------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------
    task automatic send_cmd;
        input [2:0] t;
        input [7:0] d;
        begin
            // Wait until the DUT is ready to accept a command
            while (!cmd_ready) @(posedge clk);

            cmd_type  <= t;
            cmd_data  <= d;
            cmd_valid <= 1'b1;
            @(posedge clk);
            cmd_valid <= 1'b0;

            // The DUT should go busy (cmd_ready low) and then return ready high
            // after completing 4 I2C writes + delay.
            // Wait for completion.
            while (!cmd_ready) @(posedge clk);
        end
    endtask

    // ------------------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------------------
    initial begin
        cmd_valid = 1'b0;
        cmd_type  = 3'd0;
        cmd_data  = 8'h00;
        i2c_busy  = 1'b0;
        i2c_done  = 1'b0;

        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        // Wait for init_done
        while (!init_done) @(posedge clk);
        if (!cmd_ready) begin
            $display("ERROR: cmd_ready not high after init_done");
            $fatal;
        end

        // Basic command smoke test
        // Clear
        send_cmd(CMD_CLEAR, 8'h00);

        // Set cursor to line 2 offset 0x40 (DUT expects cmd_data[6:0])
        send_cmd(CMD_SET_CURSOR, 8'h40);

        // Write 'A'
        send_cmd(CMD_WRITE_DATA, 8'h41);

        // Write 'B'
        send_cmd(CMD_WRITE_DATA, 8'h42);

        // Raw LCD command: display ON
        send_cmd(CMD_WRITE_CMD, 8'h0C);

        $display("tb_pcf8574_lcd_controller: PASS");
        #1000;
        $finish;
    end

endmodule
