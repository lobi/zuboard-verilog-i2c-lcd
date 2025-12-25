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
    output reg signed [4:0] treble,              // -10 to +10
    // Debug outputs
    output wire [2:0]  current_state,
    output wire        timeout_flag
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
    reg init_display_done;  // Track if initial display has been shown
    
    // Helper variables for number to ASCII conversion
    reg [7:0] vol_d0, vol_d1, vol_d2;  // Volume digits
    reg [7:0] bass_d0, bass_d1, bass_sign;  // Bass digits and sign
    reg [7:0] treb_d0, treb_d1, treb_sign;  // Treble digits and sign
    
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
    
    // Main FSM
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
            volume <= 50;         // Default volume
            bass <= 0;            // Default bass
            treble <= 0;          // Default treble
            timeout_cnt <= 0;
            display_update_req <= 0;
            init_display_done <= 0;
        end else begin
            // Default: stay in current state
            next_state = state;
            
            // Trigger initial display after LCD init (only once)
            if (lcd_init_done && !init_display_done && lcd_ready && !display_busy) begin
                display_update_req <= 1;
                init_display_done <= 1;
            end
            
            // Timeout counter
            if (timeout_reset || enc_inc || enc_dec || btn_press) begin
                timeout_cnt <= 0;
            end else if (state != STATE_IDLE && timeout_cnt < TIMEOUT_CYCLES) begin
                timeout_cnt <= timeout_cnt + 1;
            end
            
            // Handle button press (cycle through menus)
            if (btn_press && lcd_init_done && !display_busy) begin
                display_update_req <= 1;
                case (state)
                    STATE_IDLE:        next_state = STATE_MENU_VOLUME;
                    STATE_MENU_VOLUME: next_state = STATE_MENU_BASS;
                    STATE_MENU_BASS:   next_state = STATE_MENU_TREBLE;
                    STATE_MENU_TREBLE: next_state = STATE_MENU_VOLUME;
                endcase
            end
            
            // Handle encoder rotation (don't change state, just update value and display)
            // ONLY in menu states - encoder should be ignored in IDLE
            if ((enc_inc || enc_dec) && !display_busy && state != STATE_IDLE) begin
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
                    default: begin
                        // Do nothing - already covered by state != STATE_IDLE check
                    end
                endcase
            end
            
            // Timeout: return to IDLE and update display once
            if (timeout_cnt >= TIMEOUT_CYCLES && state != STATE_IDLE) begin
                next_state = STATE_IDLE;
                // Only update display when transitioning TO idle
                if (!display_update_req) begin
                    display_update_req <= 1;
                end
            end
            
            // Apply state transition
            state <= next_state;
            
            // Clear update request when display starts updating
            if (display_update_req && display_busy) begin
                display_update_req <= 0;
            end
        end
    end
    
    // Prepare display buffers based on state
    always @(*) begin
        timeout_reset = 0;
        
        // Extract volume digits (0-100)
        if (volume >= 100) begin
            vol_d2 = 8'h31;  // '1'
            vol_d1 = 8'h30;  // '0'
            vol_d0 = 8'h30;  // '0'
        end else if (volume >= 90) begin
            vol_d2 = 8'h30; vol_d1 = 8'h39; vol_d0 = 8'h30 + (volume - 90);
        end else if (volume >= 80) begin
            vol_d2 = 8'h30; vol_d1 = 8'h38; vol_d0 = 8'h30 + (volume - 80);
        end else if (volume >= 70) begin
            vol_d2 = 8'h30; vol_d1 = 8'h37; vol_d0 = 8'h30 + (volume - 70);
        end else if (volume >= 60) begin
            vol_d2 = 8'h30; vol_d1 = 8'h36; vol_d0 = 8'h30 + (volume - 60);
        end else if (volume >= 50) begin
            vol_d2 = 8'h30; vol_d1 = 8'h35; vol_d0 = 8'h30 + (volume - 50);
        end else if (volume >= 40) begin
            vol_d2 = 8'h30; vol_d1 = 8'h34; vol_d0 = 8'h30 + (volume - 40);
        end else if (volume >= 30) begin
            vol_d2 = 8'h30; vol_d1 = 8'h33; vol_d0 = 8'h30 + (volume - 30);
        end else if (volume >= 20) begin
            vol_d2 = 8'h30; vol_d1 = 8'h32; vol_d0 = 8'h30 + (volume - 20);
        end else if (volume >= 10) begin
            vol_d2 = 8'h30; vol_d1 = 8'h31; vol_d0 = 8'h30 + (volume - 10);
        end else begin
            vol_d2 = 8'h30; vol_d1 = 8'h30; vol_d0 = 8'h30 + volume;
        end
        
        // Extract bass/treble sign and digits (-10 to +10)
        if (bass == 10) begin
            bass_sign = 8'h2B; bass_d1 = 8'h31; bass_d0 = 8'h30;
        end else if (bass >= 0) begin
            bass_sign = 8'h2B; bass_d1 = 8'h30; bass_d0 = 8'h30 + bass[3:0];
        end else if (bass == -10) begin
            bass_sign = 8'h2D; bass_d1 = 8'h31; bass_d0 = 8'h30;
        end else begin  // bass -9 to -1
            bass_sign = 8'h2D; bass_d1 = 8'h30; bass_d0 = 8'h30 + (-bass);
        end
        
        if (treble == 10) begin
            treb_sign = 8'h2B; treb_d1 = 8'h31; treb_d0 = 8'h30;
        end else if (treble >= 0) begin
            treb_sign = 8'h2B; treb_d1 = 8'h30; treb_d0 = 8'h30 + treble[3:0];
        end else if (treble == -10) begin
            treb_sign = 8'h2D; treb_d1 = 8'h31; treb_d0 = 8'h30;
        end else begin  // treble -9 to -1
            treb_sign = 8'h2D; treb_d1 = 8'h30; treb_d0 = 8'h30 + (-treble);
        end
        
        case (state)
            STATE_IDLE: begin
                // Line 1: "HELLO JETKING   "
                // Line 2: "DIGITAL AMPLIFIE"
                line1_buffer = {8'h48, 8'h45, 8'h4C, 8'h4C, 8'h4F, 8'h20, 8'h4A, 8'h45, 8'h54, 8'h4B, 8'h49, 8'h4E, 8'h47, 8'h20, 8'h20, 8'h20};
                line2_buffer = {8'h44, 8'h49, 8'h47, 8'h49, 8'h54, 8'h41, 8'h4C, 8'h20, 8'h41, 8'h4D, 8'h50, 8'h4C, 8'h49, 8'h46, 8'h49, 8'h45};
                timeout_reset = 1;
            end
            
            STATE_MENU_VOLUME: begin
                // Line 1: "VOLUME: 050     "
                // Line 2: "Press btn/rotate"
                line1_buffer = {8'h56, 8'h4F, 8'h4C, 8'h55, 8'h4D, 8'h45, 8'h3A, 8'h20, vol_d2, vol_d1, vol_d0, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                line2_buffer = {8'h50, 8'h72, 8'h65, 8'h73, 8'h73, 8'h20, 8'h62, 8'h74, 8'h6E, 8'h2F, 8'h72, 8'h6F, 8'h74, 8'h61, 8'h74, 8'h65};
            end
            
            STATE_MENU_BASS: begin
                // Line 1: "BASS: +05       "
                // Line 2: "Press btn/rotate"
                line1_buffer = {8'h42, 8'h41, 8'h53, 8'h53, 8'h3A, 8'h20, bass_sign, bass_d1, bass_d0, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                line2_buffer = {8'h50, 8'h72, 8'h65, 8'h73, 8'h73, 8'h20, 8'h62, 8'h74, 8'h6E, 8'h2F, 8'h72, 8'h6F, 8'h74, 8'h61, 8'h74, 8'h65};
            end
            
            STATE_MENU_TREBLE: begin
                // Line 1: "TREBLE: +05     "
                // Line 2: "Press btn/rotate"
                line1_buffer = {8'h54, 8'h52, 8'h45, 8'h42, 8'h4C, 8'h45, 8'h3A, 8'h20, treb_sign, treb_d1, treb_d0, 8'h20, 8'h20, 8'h20, 8'h20, 8'h20};
                line2_buffer = {8'h50, 8'h72, 8'h65, 8'h73, 8'h73, 8'h20, 8'h62, 8'h74, 8'h6E, 8'h2F, 8'h72, 8'h6F, 8'h74, 8'h61, 8'h74, 8'h65};
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
            char_index <= 0;
            display_busy <= 0;
        end else begin
            // NOTE: lcd_cmd_valid/type/data are driven combinationally below.
            
            case (disp_state)
                DISP_IDLE: begin
                    display_busy <= 0;
                    if (display_update_req && lcd_ready && lcd_init_done) begin
                        display_busy <= 1;
                        disp_state <= DISP_CLEAR;
                    end
                end
                
                DISP_CLEAR: begin
                    // Wait for command completion (ready->busy->ready)
                    if (disp_cmd_done) begin
                        disp_state <= DISP_SET_LINE1;
                    end
                end
                
                DISP_SET_LINE1: begin
                    if (disp_cmd_done) begin
                        char_index <= 0;
                        disp_state <= DISP_WRITE_L1;
                    end
                end
                
                DISP_WRITE_L1: begin
                    if (disp_cmd_done) begin
                        if (char_index < 15) begin
                            char_index <= char_index + 1;
                        end else begin
                            disp_state <= DISP_SET_LINE2;
                        end
                    end
                end
                
                DISP_SET_LINE2: begin
                    if (disp_cmd_done) begin
                        char_index <= 0;
                        disp_state <= DISP_WRITE_L2;
                    end
                end
                
                DISP_WRITE_L2: begin
                    if (disp_cmd_done) begin
                        if (char_index < 15) begin
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

    //---------------------------------------------------------------------------
    // LCD command handshake (one-cycle strobe)
    //---------------------------------------------------------------------------

    // Command lifecycle tracking for the display sequencer:
    // - When lcd_ready=1 and a command is needed, assert lcd_cmd_valid for 1 cycle.
    // - Wait for lcd_ready to go low (busy), then high again (done).
    reg disp_cmd_issued;
    reg disp_cmd_started;
    wire disp_need_cmd;
    wire disp_cmd_strobe;
    wire disp_cmd_done;

    assign disp_need_cmd = (disp_state != DISP_IDLE) && (disp_state != DISP_DONE);
    assign disp_cmd_strobe = disp_need_cmd && lcd_ready && !disp_cmd_issued;
    assign disp_cmd_done = disp_need_cmd && disp_cmd_started && lcd_ready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            disp_cmd_issued <= 1'b0;
            disp_cmd_started <= 1'b0;
        end else begin
            // Reset tracking when entering idle/done
            if (disp_state == DISP_IDLE || disp_state == DISP_DONE) begin
                disp_cmd_issued <= 1'b0;
                disp_cmd_started <= 1'b0;
            end else begin
                // Mark the command as issued (strobe will fire this cycle)
                if (disp_cmd_strobe) begin
                    disp_cmd_issued <= 1'b1;
                end
                // Once the LCD controller goes busy, we know it latched the command
                if (disp_cmd_issued && !lcd_ready) begin
                    disp_cmd_started <= 1'b1;
                end
                // When done, allow next command in next cycle
                if (disp_cmd_done) begin
                    disp_cmd_issued <= 1'b0;
                    disp_cmd_started <= 1'b0;
                end
            end
        end
    end

    // Combinational command mux for current display state
    always @(*) begin
        lcd_cmd_valid = 1'b0;
        lcd_cmd_type  = CMD_WRITE_CMD;
        lcd_cmd_data  = 8'h00;

        if (disp_cmd_strobe) begin
            lcd_cmd_valid = 1'b1;
            case (disp_state)
                DISP_CLEAR: begin
                    lcd_cmd_type = CMD_CLEAR;
                    lcd_cmd_data = 8'h00;
                end
                DISP_SET_LINE1: begin
                    lcd_cmd_type = CMD_SET_CURSOR;
                    lcd_cmd_data = 8'h00;
                end
                DISP_WRITE_L1: begin
                    lcd_cmd_type = CMD_WRITE_DATA;
                    lcd_cmd_data = line1_buffer[127 - char_index*8 -: 8];
                end
                DISP_SET_LINE2: begin
                    lcd_cmd_type = CMD_SET_CURSOR;
                    lcd_cmd_data = 8'h40;
                end
                DISP_WRITE_L2: begin
                    lcd_cmd_type = CMD_WRITE_DATA;
                    lcd_cmd_data = line2_buffer[127 - char_index*8 -: 8];
                end
                default: begin
                    lcd_cmd_type = CMD_WRITE_CMD;
                    lcd_cmd_data = 8'h00;
                end
            endcase
        end
    end
    
    // Debug outputs
    assign current_state = {1'b0, state};
    assign timeout_flag = (timeout_cnt >= TIMEOUT_CYCLES);

endmodule
