`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module: i2c_master_writer
// Description: I2C master - based on working reference implementation
//              Counter-based timing for reliable I2C communication
//////////////////////////////////////////////////////////////////////////////////

module i2c_master_writer(
    input  wire       clk,          // 1MHz clock
    input  wire       rst_n,
    input  wire       start,        // Pulse to start transmission
    input  wire [6:0] slave_addr,   // 7-bit slave address
    input  wire [7:0] data_byte,    // Data byte to send (for PCF8574)
    output reg        busy,
    output reg        done,         // Pulse when complete
    inout  wire       sda,
    output reg        scl
);

    // State machine
    localparam IDLE       = 4'd0;
    localparam START_BIT  = 4'd1;
    localparam ADDR_BITS  = 4'd2;
    localparam ACK_ADDR   = 4'd3;
    localparam DATA_BITS  = 4'd4;
    localparam ACK_DATA   = 4'd5;
    localparam STOP_BIT   = 4'd6;
    
    reg [3:0] state;
    reg [3:0] counter;
    reg [2:0] bit_index;
    reg       sda_out;
    reg       sda_oe;   // Output enable
    reg [7:0] shift_reg;
    
    assign sda = sda_oe ? sda_out : 1'bz;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            scl <= 1'b1;
            sda_out <= 1'b1;
            sda_oe <= 1'b1;
            busy <= 1'b0;
            done <= 1'b0;
            counter <= 0;
            bit_index <= 0;
        end else begin
            done <= 1'b0;  // Single-cycle pulse
            
            case (state)
                IDLE: begin
                    scl <= 1'b1;
                    sda_out <= 1'b1;
                    sda_oe <= 1'b1;
                    busy <= 1'b0;
                    counter <= 0;
                    
                    if (start) begin
                        busy <= 1'b1;
                        shift_reg <= {slave_addr, 1'b0};  // Write operation
                        state <= START_BIT;
                    end
                end
                
                START_BIT: begin
                    counter <= counter + 1;
                    case (counter)
                        0: begin
                            sda_out <= 1'b1;
                            scl <= 1'b1;
                        end
                        5: begin
                            sda_out <= 1'b0;  // START: SDA falls while SCL high
                        end
                        10: begin
                            scl <= 1'b0;
                            counter <= 0;
                            bit_index <= 7;
                            state <= ADDR_BITS;
                        end
                    endcase
                end
                
                ADDR_BITS: begin
                    counter <= counter + 1;
                    case (counter)
                        0: begin
                            sda_out <= shift_reg[7];
                            scl <= 1'b0;
                        end
                        5: begin
                            scl <= 1'b1;  // Clock high - slave reads
                        end
                        10: begin
                            scl <= 1'b0;
                            shift_reg <= {shift_reg[6:0], 1'b0};
                            counter <= 0;
                            
                            if (bit_index == 0) begin
                                state <= ACK_ADDR;
                            end else begin
                                bit_index <= bit_index - 1;
                            end
                        end
                    endcase
                end
                
                ACK_ADDR: begin
                    counter <= counter + 1;
                    case (counter)
                        0: begin
                            sda_oe <= 1'b0;  // Release SDA for ACK
                            scl <= 1'b0;
                        end
                        5: begin
                            scl <= 1'b1;  // Slave pulls SDA low
                        end
                        10: begin
                            scl <= 1'b0;
                            sda_oe <= 1'b1;
                            counter <= 0;
                            bit_index <= 7;
                            shift_reg <= data_byte;
                            state <= DATA_BITS;
                        end
                    endcase
                end
                
                DATA_BITS: begin
                    counter <= counter + 1;
                    case (counter)
                        0: begin
                            sda_out <= shift_reg[7];
                            scl <= 1'b0;
                        end
                        5: begin
                            scl <= 1'b1;
                        end
                        10: begin
                            scl <= 1'b0;
                            shift_reg <= {shift_reg[6:0], 1'b0};
                            counter <= 0;
                            
                            if (bit_index == 0) begin
                                state <= ACK_DATA;
                            end else begin
                                bit_index <= bit_index - 1;
                            end
                        end
                    endcase
                end
                
                ACK_DATA: begin
                    counter <= counter + 1;
                    case (counter)
                        0: begin
                            sda_oe <= 1'b0;  // Release for ACK
                            scl <= 1'b0;
                        end
                        5: begin
                            scl <= 1'b1;
                        end
                        10: begin
                            scl <= 1'b0;
                            sda_oe <= 1'b1;
                            counter <= 0;
                            state <= STOP_BIT;
                        end
                    endcase
                end
                
                STOP_BIT: begin
                    counter <= counter + 1;
                    case (counter)
                        0: begin
                            sda_out <= 1'b0;
                            scl <= 1'b0;
                        end
                        5: begin
                            scl <= 1'b1;
                        end
                        10: begin
                            sda_out <= 1'b1;  // STOP: SDA rises while SCL high
                        end
                        15: begin
                            done <= 1'b1;
                            busy <= 1'b0;
                            counter <= 0;
                            state <= IDLE;
                        end
                    endcase
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
