`timescale 1ns / 1ps

module tb_rotary_decoder;

    localparam integer CLK_PERIOD_NS = 10; // 100MHz

    reg clk;
    reg rst_n;
    reg enc_a;
    reg enc_b;
    wire inc_pulse;
    wire dec_pulse;

    integer inc_count;
    integer dec_count;

    // Instantiate DUT with small debounce to speed simulation
    rotary_decoder #(
        .DEBOUNCE_TIME(3)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .enc_a(enc_a),
        .enc_b(enc_b),
        .inc_pulse(inc_pulse),
        .dec_pulse(dec_pulse)
    );

    // Clock
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD_NS/2) clk = ~clk;
    end

    // Count pulses
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inc_count <= 0;
            dec_count <= 0;
        end else begin
            if (inc_pulse) inc_count <= inc_count + 1;
            if (dec_pulse) dec_count <= dec_count + 1;
        end
    end

    // Hold A/B stable long enough to pass sync + debounce
    task automatic hold_ab;
        input a;
        input b;
        integer k;
        begin
            enc_a <= a;
            enc_b <= b;
            // 2 FF sync + debounce(3) + margin
            for (k = 0; k < 12; k = k + 1) @(posedge clk);
        end
    endtask

    task automatic step_cw;
        begin
            // CW sequence: 00 -> 10 -> 11 -> 01 -> 00 (A leads B)
            hold_ab(0,0);
            hold_ab(1,0);
            hold_ab(1,1);
            hold_ab(0,1);
            hold_ab(0,0);
        end
    endtask

    task automatic step_ccw;
        begin
            // CCW sequence: 00 -> 01 -> 11 -> 10 -> 00 (B leads A)
            hold_ab(0,0);
            hold_ab(0,1);
            hold_ab(1,1);
            hold_ab(1,0);
            hold_ab(0,0);
        end
    endtask

    initial begin
        enc_a = 1'b0;
        enc_b = 1'b0;
        rst_n = 1'b0;

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // 1 CW step should generate at least one inc pulse and no dec pulses
        step_cw();
        repeat (20) @(posedge clk);

        if (inc_count < 1) begin
            $display("ERROR: expected inc_pulse for CW step, got inc_count=%0d", inc_count);
            $fatal;
        end
        if (dec_count != 0) begin
            $display("ERROR: expected no dec_pulse for CW step, got dec_count=%0d", dec_count);
            $fatal;
        end

        // Reset counters for clarity
        inc_count = 0;
        dec_count = 0;

        // 1 CCW step should generate at least one dec pulse and no inc pulses
        step_ccw();
        repeat (20) @(posedge clk);

        if (dec_count < 1) begin
            $display("ERROR: expected dec_pulse for CCW step, got dec_count=%0d", dec_count);
            $fatal;
        end
        if (inc_count != 0) begin
            $display("ERROR: expected no inc_pulse for CCW step, got inc_count=%0d", inc_count);
            $fatal;
        end

        $display("tb_rotary_decoder: PASS");
        #100;
        $finish;
    end

endmodule
