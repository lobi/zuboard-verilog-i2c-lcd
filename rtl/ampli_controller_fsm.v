`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: ampli_controller_fsm
// Description: Main FSM for digital amplifier controller
//              4 states: IDLE, MENU_VOLUME, MENU_BASS, MENU_TREBLE
//              5-second timeout to return to IDLE
//              Manages Volume (0-100), Bass (-10 to +10), Treble (-10 to +10)
//////////////////////////////////////////////////////////////////////////////////

module ampli_controller_fsm #(
    parameter CLK_FREQ = 100_000_000,           // 100MHz
    parameter TIMEOUT_SEC = 5                    // 5 seconds timeout
)(
    input  wire        clk,
    input  wire        rst_n,
    // Rotary encoder interface
    input  wire        enc_inc,                  // Increment pulse
    input  wire        enc_dec,                  // Decrement pulse
    input  wire        btn_press,                // Button press pulse
    // LCD controller interface
    input  wire        lcd_ready,
    input  wire        lcd_init_done,
    output reg         lcd_cmd_valid,
    output reg [2:0]   lcd_cmd_type,
    output reg [7:0]   lcd_cmd_data,
    // Audio parameter outputs (for future audio processing)
    output reg [6:0]   volume,                   // 0-100
    output reg signed [4:0] bass,                // -10 to +10
    output reg signed [4:0] treble               // -10 to +10
);

    // LCD command types (must match pcf8574_lcd_controller)
    localparam CMD_INIT       = 3'd0;
    localparam CMD_CLEAR      = 3'd1;
    localparam CMD_WRITE_CMD  = 3'd2;
    localparam CMD_WRITE_DATA = 3'd3;
    localparam CMD_SET_CURSOR = 3'd4;
    
    // FSM States
    localparam [1:0]
        STATE_IDLE        = 2'd0,
        STATE_MENU_VOLUME = 2'd1,
        STATE_MENU_BASS   = 2'd2,
        STATE_MENU_TREBLE = 2'd3;
        
    reg [1:0] state, next_state;
    
    // Timeout counter (5 seconds @ 100MHz = 500_000_000 cycles)
    localparam TIMEOUT_CYCLES = CLK_FREQ * TIMEOUT_SEC;
    reg [31:0] timeout_cnt;
    reg timeout_reset;
    
    // Display update control
    reg display_update_req;
    reg display_busy;
    reg [7:0] char_index;
    reg [127:0] line1_buffer;  // 16 characters
    reg [127:0] line2_buffer;  // 16 characters
    
    // Display state machine
    localparam [2:0]
        DISP_IDLE      = 3'd0,
        DISP_CLEAR     = 3'd1,
        DISP_SET_LINE1 = 3'd2,
        DISP_WRITE_L1  = 3'd3,
        DISP_SET_LINE2 = 3'd4,
        DISP_WRITE_L2  = 3'd5,
        DISP_DONE      = 3'd6;
        
    reg [2:0] disp_state;
    
    // ASCII conversion helper
    function [7:0] digit_to_ascii;
        input [3:0] digit;
        begin
            digit_to_ascii = 8'h30 + digit;  // '0' = 0x30
        end
    endfunction
    
    // Convert number to string (decimal)
    function [23:0] num_to_str3;  // 3 digits
        input [6:0] num;
        reg [6:0] temp;
        reg [3:0] d0, d1, d2;
        begin
            temp = num;
            d0 = temp % 10;
            temp = temp / 10;
            d1 = temp % 10;
            d2 = temp / 10;
            num_to_str3 = {digit_to_ascii(d2), digit_to_ascii(d1), digit_to_ascii(d0)};
        end
    endfunction
    
    // Convert signed number to string with sign
    function [31:0] signed_to_str;  // "+10" or "-05" format
        input signed [4:0] num;
        reg [4:0] abs_num;
        reg [3:0] d0, d1;
        reg [7:0] sign;
        begin
            if (num < 0) begin
                sign = 8'h2D;  // '-'
                abs_num = -num;
            end else begin
                sign = 8'h2B;  // '+'
                abs_num = num;
            end
            d0 = abs_num % 10;
            d1 = abs_num / 10;
            signed_to_str = {sign, digit_to_ascii(d1), digit_to_ascii(d0), 8'h20};  // Add space
        end
    endfunction
    
    // Main FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            volume <= 50;         // Default volume
            bass <= 0;            // Default bass
            treble <= 0;          // Default treble
            timeout_cnt <= 0;
            display_update_req <= 0;
        end else begin
            // Timeout counter
            if (timeout_reset || enc_inc || enc_dec || btn_press) begin
                timeout_cnt <= 0;
            end else if (state != STATE_IDLE && timeout_cnt < TIMEOUT_CYCLES) begin
                timeout_cnt <= timeout_cnt + 1;
            end
            
            // State transitions
            state <= next_state;
            
            // Handle button press (cycle through menus)
            if (btn_press && lcd_init_done) begin
                display_update_req <= 1;
                case (state)
                    STATE_IDLE:        next_state <= STATE_MENU_VOLUME;
                    STATE_MENU_VOLUME: next_state <= STATE_MENU_BASS;
                    STATE_MENU_BASS:   next_state <= STATE_MENU_TREBLE;
                    STATE_MENU_TREBLE: next_state <= STATE_MENU_VOLUME;
                endcase
            end
            
            // Handle encoder rotation
            if (enc_inc || enc_dec) begin
                display_update_req <= 1;
                case (state)
                    STATE_MENU_VOLUME: begin
                        if (enc_inc && volume < 100) volume <= volume + 1;
                        if (enc_dec && volume > 0)   volume <= volume - 1;
                    end
                    STATE_MENU_BASS: begin
                        if (enc_inc && bass < 10)  bass <= bass + 1;
                        if (enc_dec && bass > -10) bass <= bass - 1;
                    end
                    STATE_MENU_TREBLE: begin
                        if (enc_inc && treble < 10)  treble <= treble + 1;
                        if (enc_dec && treble > -10) treble <= treble - 1;
                    end
                endcase
            end
            
            // Timeout: return to IDLE
            if (timeout_cnt >= TIMEOUT_CYCLES && state != STATE_IDLE) begin
                next_state <= STATE_IDLE;
                display_update_req <= 1;
            end
            
            // Clear update request when display starts updating
            if (display_update_req && !display_busy && disp_state != DISP_IDLE) begin
                display_update_req <= 0;
            end
        end
    end
    
    // Prepare display buffers based on state
    always @(*) begin
        timeout_reset = 0;
        case (state)
            STATE_IDLE: begin
                // Line 1: "HELLO JETKING   "
                // Line 2: "DIGITAL AMPLIFIER"
                line1_buffer = {"H", "E", "L", "L", "O", " ", "J", "E", "T", "K", "I", "N", "G", " ", " ", " "};
                line2_buffer = {"D", "I", "G", "I", "T", "A", "L", " ", "A", "M", "P", "L", "I", "F", "I", "E"};
                timeout_reset = 1;
            end
            
            STATE_MENU_VOLUME: begin
                // Line 1: "VOLUME: 050     " (example)
                // Line 2: "<Rotate to adjst>"
                line1_buffer = {"V", "O", "L", "U", "M", "E", ":", " ", 
                               num_to_str3(volume), "     "};
                line2_buffer = {"<", "R", "o", "t", "a", "t", "e", " ", "t", "o", " ", "a", "d", "j", "s", "t", ">"};
            end
            
            STATE_MENU_BASS: begin
                // Line 1: "BASS: +05       "
                // Line 2: "<Rotate to adjst>"
                line1_buffer = {"B", "A", "S", "S", ":", " ", 
                               signed_to_str(bass), "        "};
                line2_buffer = {"<", "R", "o", "t", "a", "t", "e", " ", "t", "o", " ", "a", "d", "j", "s", "t", ">"};
            end
            
            STATE_MENU_TREBLE: begin
                // Line 1: "TREBLE: -03     "
                // Line 2: "<Rotate to adjst>"
                line1_buffer = {"T", "R", "E", "B", "L", "E", ":", " ",
                               signed_to_str(treble), "      "};
                line2_buffer = {"<", "R", "o", "t", "a", "t", "e", " ", "t", "o", " ", "a", "d", "j", "s", "t", ">"};
            end
            
            default: begin
                line1_buffer = {16{8'h20}};  // Spaces
                line2_buffer = {16{8'h20}};
            end
        endcase
    end
    
    // Display update state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            disp_state <= DISP_IDLE;
            lcd_cmd_valid <= 0;
            lcd_cmd_type <= 0;
            lcd_cmd_data <= 0;
            char_index <= 0;
            display_busy <= 0;
        end else begin
            lcd_cmd_valid <= 0;  // Default: no command
            
            case (disp_state)
                DISP_IDLE: begin
                    display_busy <= 0;
                    if (display_update_req && lcd_ready && lcd_init_done) begin
                        display_busy <= 1;
                        disp_state <= DISP_CLEAR;
                    end
                end
                
                DISP_CLEAR: begin
                    if (lcd_ready) begin
                        lcd_cmd_valid <= 1;
                        lcd_cmd_type <= CMD_CLEAR;
                        disp_state <= DISP_SET_LINE1;
                    end
                end
                
                DISP_SET_LINE1: begin
                    if (lcd_ready) begin
                        lcd_cmd_valid <= 1;
                        lcd_cmd_type <= CMD_SET_CURSOR;
                        lcd_cmd_data <= 8'h00;  // Line 1, position 0
                        char_index <= 0;
                        disp_state <= DISP_WRITE_L1;
                    end
                end
                
                DISP_WRITE_L1: begin
                    if (lcd_ready) begin
                        if (char_index < 16) begin
                            lcd_cmd_valid <= 1;
                            lcd_cmd_type <= CMD_WRITE_DATA;
                            lcd_cmd_data <= line1_buffer[127 - char_index*8 -: 8];
                            char_index <= char_index + 1;
                        end else begin
                            disp_state <= DISP_SET_LINE2;
                        end
                    end
                end
                
                DISP_SET_LINE2: begin
                    if (lcd_ready) begin
                        lcd_cmd_valid <= 1;
                        lcd_cmd_type <= CMD_SET_CURSOR;
                        lcd_cmd_data <= 8'h40;  // Line 2, position 0
                        char_index <= 0;
                        disp_state <= DISP_WRITE_L2;
                    end
                end
                
                DISP_WRITE_L2: begin
                    if (lcd_ready) begin
                        if (char_index < 16) begin
                            lcd_cmd_valid <= 1;
                            lcd_cmd_type <= CMD_WRITE_DATA;
                            lcd_cmd_data <= line2_buffer[127 - char_index*8 -: 8];
                            char_index <= char_index + 1;
                        end else begin
                            disp_state <= DISP_DONE;
                        end
                    end
                end
                
                DISP_DONE: begin
                    disp_state <= DISP_IDLE;
                    display_busy <= 0;
                end
                
                default: disp_state <= DISP_IDLE;
            endcase
        end
    end

endmodule
