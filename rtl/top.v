`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: top
// Description: Top-level module for Digital Amplifier Controller
//              Integrates rotary encoder, button debouncer, I2C master,
//              LCD controller, and main FSM
//              Target: Zynq UltraScale+ (ZUBoard-1CG)
//////////////////////////////////////////////////////////////////////////////////

module top (
    // Clock and reset from PS
    input  wire        clk,              // 100MHz from pl_clk0
    input  wire        rst_n,            // Active-low reset
    
    // Rotary encoder inputs
    input  wire        enc_a,
    input  wire        enc_b,
    input  wire        enc_sw,           // Encoder switch (active low)
    
    // I2C interface to PCF8574/LCD
    inout  wire        i2c_sda,
    output wire        i2c_scl,
    
    // Debug outputs (optional - connect to LEDs)
    output wire [2:0]  debug_state,      // Current menu state
    output wire        debug_timeout     // Timeout indicator
);

    // Internal signals
    // Encoder signals
    wire enc_inc_pulse, enc_dec_pulse;
    wire btn_press_pulse;
    
    // Clock divider - generate 1MHz from 100MHz
    reg [6:0] clk_div_cnt;
    reg clk_1MHz;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_div_cnt <= 0;
            clk_1MHz <= 0;
        end else begin
            if (clk_div_cnt >= 49) begin  // 100MHz / 100 = 1MHz
                clk_div_cnt <= 0;
                clk_1MHz <= ~clk_1MHz;
            end else begin
                clk_div_cnt <= clk_div_cnt + 1;
            end
        end
    end
    
    // I2C master signals
    wire i2c_start;
    wire [6:0] i2c_addr;
    wire [7:0] i2c_data;
    wire i2c_busy, i2c_done;
    
    // LCD controller signals
    wire lcd_cmd_valid;
    wire [2:0] lcd_cmd_type;
    wire [7:0] lcd_cmd_data;
    wire lcd_ready, lcd_init_done;
    
    // Audio parameters (can be connected to audio processing modules)
    wire [6:0] volume;
    wire signed [4:0] bass;
    wire signed [4:0] treble;
    
    //==========================================================================
    // Module Instantiations
    //==========================================================================
    
    // Rotary encoder decoder
    rotary_decoder #(
        .DEBOUNCE_TIME(1000)             // 10us @ 100MHz
    ) u_rotary_decoder (
        .clk        (clk),
        .rst_n      (rst_n),
        .enc_a      (enc_a),
        .enc_b      (enc_b),
        .inc_pulse  (enc_inc_pulse),
        .dec_pulse  (enc_dec_pulse)
    );
    
    // Button debouncer for encoder switch
    button_debounce #(
        .DEBOUNCE_TIME(2_000_000)        // 20ms @ 100MHz
    ) u_button_debounce (
        .clk          (clk),
        .rst_n        (rst_n),
        .button_in    (enc_sw),
        .button_pulse (btn_press_pulse)
    );
    
    // I2C master writer
    i2c_master_writer u_i2c_master (
        .clk        (clk_1MHz),
        .rst_n      (rst_n),
        .start      (i2c_start),
        .slave_addr (i2c_addr),
        .data_byte  (i2c_data),
        .busy       (i2c_busy),
        .done       (i2c_done),
        .scl        (i2c_scl),
        .sda        (i2c_sda)
    );
    
    // PCF8574 LCD controller
    pcf8574_lcd_controller #(
        .PCF8574_ADDR(7'h27)             // Adjust if your PCF8574 has different address
    ) u_lcd_controller (
        .clk          (clk_1MHz),
        .rst_n        (rst_n),
        .cmd_valid    (lcd_cmd_valid),
        .cmd_type     (lcd_cmd_type),
        .cmd_data     (lcd_cmd_data),
        .cmd_ready    (lcd_ready),
        .init_done    (lcd_init_done),
        .i2c_start    (i2c_start),
        .i2c_addr     (i2c_addr),
        .i2c_data     (i2c_data),
        .i2c_busy     (i2c_busy),
        .i2c_done     (i2c_done)
    );
    
    // Amplifier controller FSM
    ampli_controller_fsm #(
        .TIMEOUT_CYCLES(5_000_000)       // 5 seconds @ 1MHz
    ) u_ampli_fsm (
        .clk           (clk_1MHz),
        .rst_n         (rst_n),
        .enc_inc       (enc_inc_pulse),
        .enc_dec       (enc_dec_pulse),
        .btn_press     (btn_press_pulse),
        .lcd_init_done (lcd_init_done),
        .lcd_ready     (lcd_ready),
        .lcd_cmd_valid (lcd_cmd_valid),
        .lcd_cmd_type  (lcd_cmd_type),
        .lcd_cmd_data  (lcd_cmd_data),
        .volume        (volume),
        .bass          (bass),
        .treble        (treble),
        .current_state (debug_state),
        .timeout_flag  (debug_timeout)
    );
    
    //==========================================================================
    // Debug outputs
    //==========================================================================
    
    // Debug outputs connected to FSM outputs (already assigned above)
    // debug_state shows current menu state from FSM
    // debug_timeout shows timeout flag from FSM
    
endmodule
