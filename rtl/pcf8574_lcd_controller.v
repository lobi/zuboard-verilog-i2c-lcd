`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: pcf8574_lcd_controller
// Description: HD44780 LCD in 4-bit mode via PCF8574 - simplified init sequence
//              Following reference implementation from working LCD code
//////////////////////////////////////////////////////////////////////////////////

module pcf8574_lcd_controller #(
    parameter PCF8574_ADDR = 7'h27
)(
    input  wire       clk,              // 1MHz clock
    input  wire       rst_n,
    // Command interface
    input  wire       cmd_valid,
    input  wire [2:0] cmd_type,
    input  wire [7:0] cmd_data,
    output reg        cmd_ready,
    output reg        init_done,
    // I2C master interface
    output reg        i2c_start,
    output reg [6:0]  i2c_addr,
    output reg [7:0]  i2c_data,
    input  wire       i2c_busy,
    input  wire       i2c_done
);

    // Command types
    localparam CMD_INIT      = 3'd0;
    localparam CMD_CLEAR     = 3'd1;
    localparam CMD_WRITE_CMD = 3'd2;
    localparam CMD_WRITE_DATA= 3'd3;
    localparam CMD_SET_CURSOR= 3'd4;
    
    // LCD commands - matching reference
    localparam LCD_4BIT_MODE   = 8'h02;  // 4 bit mode
    localparam LCD_FUNCTION_SET= 8'h28;  // 4-bit, 2 lines, 5x8
    localparam LCD_DISPLAY_ON  = 8'h0C;  // Display on, cursor off
    localparam LCD_ENTRY_MODE  = 8'h06;  // Auto increment cursor
    localparam LCD_CLEAR       = 8'h01;  // Clear display
    localparam LCD_LINE1       = 8'h80;  // Cursor at first line
    localparam LCD_LINE2       = 8'hC0;  // Cursor at second line
    
    // Timing parameters (in microseconds @ 1MHz)
    localparam DELAY_15MS  = 24'd15_000;
    localparam DELAY_2MS   = 24'd2_000;
    localparam DELAY_50US  = 24'd50;
    
    // State machine
    localparam [3:0]
        IDLE         = 4'd0,
        INIT_START   = 4'd1,
        INIT_WAIT    = 4'd2,
        SEND_CMD     = 4'd3,
        SEND_HI_EN1  = 4'd4,
        WAIT_HI_EN1  = 4'd5,
        SEND_HI_EN0  = 4'd6,
        WAIT_HI_EN0  = 4'd7,
        SEND_LO_EN1  = 4'd8,
        WAIT_LO_EN1  = 4'd9,
        SEND_LO_EN0  = 4'd10,
        WAIT_LO_EN0  = 4'd11,
        CMD_DONE     = 4'd12,
        DELAY        = 4'd13;
        
    reg [3:0] state;
    reg [3:0] init_step;
    reg [7:0] cmd_byte;
    reg       cmd_rs;  // 0=command, 1=data
    reg [23:0] delay_cnt;
    reg [23:0] delay_target;
    
    // I2C byte builder: {D7,D6,D5,D4,BL,EN,RW,RS}
    function [7:0] build_byte;
        input [3:0] nibble;
        input rs;
        input en;
        begin
            build_byte = {nibble, 1'b1, en, 1'b0, rs};  // BL=1, RW=0
        end
    endfunction
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= INIT_START;
            init_step <= 0;
            cmd_ready <= 0;
            init_done <= 0;
            i2c_start <= 0;
            i2c_addr <= PCF8574_ADDR;
            i2c_data <= 0;
            cmd_byte <= 0;
            cmd_rs <= 0;
            delay_cnt <= 0;
            delay_target <= 0;
        end else begin
            i2c_start <= 0;  // Default
            
            case (state)
                INIT_START: begin
                    delay_target <= DELAY_15MS;
                    delay_cnt <= 0;
                    state <= INIT_WAIT;
                end
                
                INIT_WAIT: begin
                    if (delay_cnt >= delay_target) begin
                        delay_cnt <= 0;
                        init_step <= 0;
                        state <= SEND_CMD;
                    end else begin
                        delay_cnt <= delay_cnt + 1;
                    end
                end
                
                SEND_CMD: begin
                    // Select command based on init_step
                    case (init_step)
                        0: begin cmd_byte <= LCD_4BIT_MODE;   cmd_rs <= 0; end
                        1: begin cmd_byte <= LCD_FUNCTION_SET; cmd_rs <= 0; end
                        2: begin cmd_byte <= LCD_DISPLAY_ON;  cmd_rs <= 0; end
                        3: begin cmd_byte <= LCD_ENTRY_MODE;  cmd_rs <= 0; end
                        4: begin cmd_byte <= LCD_CLEAR;       cmd_rs <= 0; delay_target <= DELAY_2MS; end
                        default: begin
                            init_done <= 1;
                            cmd_ready <= 1;
                            state <= IDLE;
                        end
                    endcase
                    
                    if (init_step < 5) begin
                        state <= SEND_HI_EN1;
                    end
                end
                
                // High nibble with EN=1
                SEND_HI_EN1: begin
                    i2c_data <= build_byte(cmd_byte[7:4], cmd_rs, 1'b1);
                    i2c_start <= 1;
                    state <= WAIT_HI_EN1;
                end
                
                WAIT_HI_EN1: begin
                    if (i2c_done) state <= SEND_HI_EN0;
                end
                
                // High nibble with EN=0
                SEND_HI_EN0: begin
                    i2c_data <= build_byte(cmd_byte[7:4], cmd_rs, 1'b0);
                    i2c_start <= 1;
                    state <= WAIT_HI_EN0;
                end
                
                WAIT_HI_EN0: begin
                    if (i2c_done) state <= SEND_LO_EN1;
                end
                
                // Low nibble with EN=1
                SEND_LO_EN1: begin
                    i2c_data <= build_byte(cmd_byte[3:0], cmd_rs, 1'b1);
                    i2c_start <= 1;
                    state <= WAIT_LO_EN1;
                end
                
                WAIT_LO_EN1: begin
                    if (i2c_done) state <= SEND_LO_EN0;
                end
                
                // Low nibble with EN=0
                SEND_LO_EN0: begin
                    i2c_data <= build_byte(cmd_byte[3:0], cmd_rs, 1'b0);
                    i2c_start <= 1;
                    state <= WAIT_LO_EN0;
                end
                
                WAIT_LO_EN0: begin
                    if (i2c_done) begin
                        delay_cnt <= 0;
                        if (init_step == 4) begin
                            // Clear needs 2ms delay
                            state <= DELAY;
                        end else begin
                            delay_target <= DELAY_50US;
                            state <= DELAY;
                        end
                    end
                end
                
                DELAY: begin
                    if (delay_cnt >= delay_target) begin
                        delay_cnt <= 0;
                        if (init_step < 5) begin
                            init_step <= init_step + 1;
                            state <= SEND_CMD;
                        end else begin
                            state <= CMD_DONE;
                        end
                    end else begin
                        delay_cnt <= delay_cnt + 1;
                    end
                end
                
                CMD_DONE: begin
                    if (!init_done) begin
                        // Init sequence complete
                        init_done <= 1;
                        cmd_ready <= 1;
                        state <= IDLE;
                    end else begin
                        // User command complete
                        cmd_ready <= 1;
                        state <= IDLE;
                    end
                end
                
                IDLE: begin
                    cmd_ready <= 1;
                    if (cmd_valid && !i2c_busy) begin
                        cmd_ready <= 0;
                        delay_target <= DELAY_50US;
                        
                        case (cmd_type)
                            CMD_CLEAR: begin
                                cmd_byte <= LCD_CLEAR;
                                cmd_rs <= 0;
                                delay_target <= DELAY_2MS;
                                state <= SEND_HI_EN1;
                            end
                            
                            CMD_WRITE_CMD: begin
                                cmd_byte <= cmd_data;
                                cmd_rs <= 0;
                                state <= SEND_HI_EN1;
                            end
                            
                            CMD_WRITE_DATA: begin
                                cmd_byte <= cmd_data;
                                cmd_rs <= 1;
                                state <= SEND_HI_EN1;
                            end
                            
                            CMD_SET_CURSOR: begin
                                cmd_byte <= {1'b1, cmd_data[6:0]};
                                cmd_rs <= 0;
                                state <= SEND_HI_EN1;
                            end
                            
                            default: state <= IDLE;
                        endcase
                    end
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
