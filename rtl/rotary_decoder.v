`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: rotary_decoder
// Description: Quadrature decoder for rotary encoder with debouncing
//              Detects clockwise/counter-clockwise rotation
//              Outputs single pulse (+1/-1) per detent
//////////////////////////////////////////////////////////////////////////////////

module rotary_decoder #(
    parameter DEBOUNCE_TIME = 1000  // Debounce cycles (10us @ 100MHz)
)(
    input  wire clk,
    input  wire rst_n,
    input  wire enc_a,
    input  wire enc_b,
    output reg  inc_pulse,          // Pulse when rotating CW
    output reg  dec_pulse           // Pulse when rotating CCW
);

    // Debounce registers for A and B
    reg [15:0] debounce_a_cnt;
    reg [15:0] debounce_b_cnt;
    reg enc_a_sync1, enc_a_sync2, enc_a_stable;
    reg enc_b_sync1, enc_b_sync2, enc_b_stable;
    
    // Edge detection
    reg enc_a_prev, enc_b_prev;
    wire enc_a_rising, enc_a_falling;
    wire enc_b_rising, enc_b_falling;
    
    // Synchronize inputs to clock domain
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enc_a_sync1 <= 1'b0;
            enc_a_sync2 <= 1'b0;
            enc_b_sync1 <= 1'b0;
            enc_b_sync2 <= 1'b0;
        end else begin
            enc_a_sync1 <= enc_a;
            enc_a_sync2 <= enc_a_sync1;
            enc_b_sync1 <= enc_b;
            enc_b_sync2 <= enc_b_sync1;
        end
    end
    
    // Debounce A signal
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            debounce_a_cnt <= 0;
            enc_a_stable <= 1'b0;
        end else begin
            if (enc_a_sync2 == enc_a_stable) begin
                debounce_a_cnt <= 0;
            end else begin
                debounce_a_cnt <= debounce_a_cnt + 1;
                if (debounce_a_cnt >= DEBOUNCE_TIME) begin
                    enc_a_stable <= enc_a_sync2;
                    debounce_a_cnt <= 0;
                end
            end
        end
    end
    
    // Debounce B signal
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            debounce_b_cnt <= 0;
            enc_b_stable <= 1'b0;
        end else begin
            if (enc_b_sync2 == enc_b_stable) begin
                debounce_b_cnt <= 0;
            end else begin
                debounce_b_cnt <= debounce_b_cnt + 1;
                if (debounce_b_cnt >= DEBOUNCE_TIME) begin
                    enc_b_stable <= enc_b_sync2;
                    debounce_b_cnt <= 0;
                end
            end
        end
    end
    
    // Edge detection on stable signals
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enc_a_prev <= 1'b0;
            enc_b_prev <= 1'b0;
        end else begin
            enc_a_prev <= enc_a_stable;
            enc_b_prev <= enc_b_stable;
        end
    end
    
    assign enc_a_rising  = enc_a_stable && !enc_a_prev;
    assign enc_a_falling = !enc_a_stable && enc_a_prev;
    assign enc_b_rising  = enc_b_stable && !enc_b_prev;
    assign enc_b_falling = !enc_b_stable && enc_b_prev;
    
    // Quadrature decode logic
    // CW:  A leads B  (A rises while B=0, or A falls while B=1)
    // CCW: B leads A  (A rises while B=1, or A falls while B=0)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            inc_pulse <= 1'b0;
            dec_pulse <= 1'b0;
        end else begin
            inc_pulse <= 1'b0;
            dec_pulse <= 1'b0;
            
            // Clockwise detection
            if (enc_a_rising && !enc_b_stable) begin
                inc_pulse <= 1'b1;
            end else if (enc_a_falling && enc_b_stable) begin
                inc_pulse <= 1'b1;
            end
            
            // Counter-clockwise detection
            if (enc_a_rising && enc_b_stable) begin
                dec_pulse <= 1'b1;
            end else if (enc_a_falling && !enc_b_stable) begin
                dec_pulse <= 1'b1;
            end
        end
    end

endmodule
