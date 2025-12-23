`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: button_debounce
// Description: Button debouncer with single-pulse output
//              Eliminates mechanical bounce and generates clean single pulse
//              per button press
//////////////////////////////////////////////////////////////////////////////////

module button_debounce #(
    parameter DEBOUNCE_TIME = 2000000  // 20ms @ 100MHz
)(
    input  wire clk,
    input  wire rst_n,
    input  wire button_in,
    output reg  button_pulse        // Single pulse on button press
);

    reg [23:0] debounce_cnt;
    reg button_sync1, button_sync2, button_stable;
    reg button_prev;
    
    // Synchronize input to clock domain
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            button_sync1 <= 1'b1;  // Assume pull-up (active low)
            button_sync2 <= 1'b1;
        end else begin
            button_sync1 <= button_in;
            button_sync2 <= button_sync1;
        end
    end
    
    // Debounce logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            debounce_cnt <= 0;
            button_stable <= 1'b1;
        end else begin
            if (button_sync2 == button_stable) begin
                debounce_cnt <= 0;
            end else begin
                debounce_cnt <= debounce_cnt + 1;
                if (debounce_cnt >= DEBOUNCE_TIME) begin
                    button_stable <= button_sync2;
                    debounce_cnt <= 0;
                end
            end
        end
    end
    
    // Edge detection for falling edge (button press, assuming active low)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            button_prev <= 1'b1;
            button_pulse <= 1'b0;
        end else begin
            button_prev <= button_stable;
            // Generate pulse on falling edge (press)
            button_pulse <= (!button_stable && button_prev);
        end
    end

endmodule
