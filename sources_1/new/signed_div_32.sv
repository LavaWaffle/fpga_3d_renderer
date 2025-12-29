module signed_div_32 (
    input wire i_clk,
    input wire i_rst,
    input wire i_start,
    input wire signed [31:0] i_dividend, 
    input wire signed [31:0] i_divisor,  
    output reg signed [31:0] o_quotient, 
    output reg o_done
);
    localparam IDLE = 0;
    localparam DIVIDE = 1;
    localparam SIGN_CORRECT = 2;

    reg [1:0] state;
    reg [5:0] count;
    reg [63:0] reg_working; 
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
                        sign_diff <= i_dividend[31] ^ i_divisor[31];
                        // FIXED: No internal shift here. We trust the input scaling.
                        reg_working <= {32'b0, (i_dividend[31] ? -i_dividend : i_dividend)};
                        reg_divisor <= (i_divisor[31] ? -i_divisor : i_divisor);
                        count <= 32; 
                        state <= DIVIDE;
                    end
                end

                DIVIDE: begin
                    if (count > 0) begin
                        reg_working = reg_working << 1;
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
                    o_quotient <= sign_diff ? -reg_working[31:0] : reg_working[31:0];
                    o_done <= 1;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule