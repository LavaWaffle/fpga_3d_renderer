`timescale 1ns / 1ps

module q2_30_div (
    input wire i_clk,
    input wire i_rst,
    input wire i_start,
    input wire signed [31:0] i_dividend, // Numerator in Integer format (ex: 1'd1 for finding inverse area)
    input wire signed [31:0] i_divisor,  // The Area in Integer format 
    output reg signed [31:0] o_quotient, // Result in Q2.30 format
    output reg o_done
);
    // State definitions
    localparam IDLE = 0;
    localparam DIVIDE = 1;
    localparam SIGN_CORRECT = 2;

    reg [1:0] state;
    reg [5:0] count;
    reg [63:0] reg_working; // 64-bit working register
    reg [31:0] reg_divisor;
    reg sign_diff;

    always @(posedge i_clk) begin
        if (i_rst) begin
            state <= IDLE;
            o_done <= 0;
            o_quotient <= 0;
            reg_working <= 0;
            reg_divisor <= 0;
            count <= 0;
            sign_diff <= 0;
        end else begin
            case (state)
                IDLE: begin
                    o_done <= 0;
                    if (i_start) begin
                        // 1. Determine Output Sign
                        sign_diff <= i_dividend[31] ^ i_divisor[31];
                        
                        // 2. Take Absolute Values
                        reg_divisor <= (i_divisor[31] ? -i_divisor : i_divisor);
                        
                        // 3. Shift Dividend Left by 30 (The "Precision Boost")
                        // Previous: << 16 (Q16.16)
                        // Current:  << 30 (Q2.30)
                        // This scales the result so that 1 / 48000 becomes a usable number
                        reg_working <= {32'b0, (i_dividend[31] ? -i_dividend : i_dividend)} << 30;
                        
                        count <= 32; // 32 Iterations for 32-bit resolution
                        state <= DIVIDE;
                    end
                end

                DIVIDE: begin
                    if (count > 0) begin
                        reg_working = reg_working << 1;
                        // Compare top 32 bits of working reg with divisor
                        if (reg_working[63:32] >= reg_divisor) begin
                            reg_working[63:32] = reg_working[63:32] - reg_divisor;
                            reg_working[0] = 1;
                        end
                        count <= count - 1;
                    end else begin
                        state <= SIGN_CORRECT;
                    end
                end

                SIGN_CORRECT: begin
                    // Apply correct sign and output
                    o_quotient <= sign_diff ? -reg_working[31:0] : reg_working[31:0];
                    o_done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule