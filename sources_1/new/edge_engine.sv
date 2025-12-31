`timescale 1ns / 1ps

module edge_engine(
    input wire i_clk,
    input wire i_rst,

    // [TYPE] S16.0 - Triangle Vertices
    input wire signed [15:0] i_x0, i_y0, i_x1, i_y1, i_x2, i_y2,

    // [TYPE] S16.0 - Current Pixel
    input wire signed [15:0] i_p_x, 
    input wire signed [15:0] i_p_y,
    input wire i_valid, // High if this is a real pixel, Low if bubble

    // [TYPE] S32.0 (Signed Integer) - Output Weights
    // These represent the area of the sub-triangles. 
    // Range roughly: -Wait_Screen_Size to +Max_Screen_Size^2
    output reg signed [31:0] o_w0, o_w1, o_w2, // Barycentric Weights in Integer format
    output reg o_inside, // High if pixel is INSIDE triangle
    output reg o_valid   // Forwarded valid signal
);
    logic signed [31:0] w0_raw, w1_raw, w2_raw;
    logic signed [31:0] w0_next, w1_next, w2_next;
    logic inside_next;

    always_comb begin
        logic all_pos, all_neg;
        
        // =====================================================================
        // Barycentric Weight Calculation (Cross Product)
        // =====================================================================
        // Force 32-bit math for the multiplication by casting inputs first
        // 1. Calculate Weights (Using the 32-bit cast fix from before)
        w0_raw = (signed'(32'(i_p_x)) - signed'(32'(i_x0))) * (signed'(32'(i_y1)) - signed'(32'(i_y0))) - 
                  (signed'(32'(i_p_y)) - signed'(32'(i_y0))) * (signed'(32'(i_x1)) - signed'(32'(i_x0)));
        
        w1_raw = (signed'(32'(i_p_x)) - signed'(32'(i_x1))) * (signed'(32'(i_y2)) - signed'(32'(i_y1))) - 
                  (signed'(32'(i_p_y)) - signed'(32'(i_y1))) * (signed'(32'(i_x2)) - signed'(32'(i_x1)));
        
        w2_raw = (signed'(32'(i_p_x)) - signed'(32'(i_x2))) * (signed'(32'(i_y0)) - signed'(32'(i_y2))) - 
                  (signed'(32'(i_p_y)) - signed'(32'(i_y2))) * (signed'(32'(i_x0)) - signed'(32'(i_x2)));

        
        all_pos = (w0_raw >= 0) && (w1_raw >= 0) && (w2_raw >= 0);
        all_neg = (w0_raw <= 0) && (w1_raw <= 0) && (w2_raw <= 0);
        
        if (all_pos) begin
            // Front Face: Pass through as is
            w0_next = w0_raw; w1_next = w1_raw; w2_next = w2_raw;
            inside_next = 1'b1;
        end else if (all_neg) begin
            // Back Face: Negate weights to make them Positive
            w0_next = -w0_raw; w1_next = -w1_raw; w2_next = -w2_raw;
            inside_next = 1'b1;
        end else begin
            // Outside
            w0_next = 0; w1_next = 0; w2_next = 0; // or don't care
            inside_next = 1'b0;
        end
    end

    // =========================================================================
    // Pipeline Register (Latch results on clock edge)
    // =========================================================================
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            // o_w0     <= 0;
            // o_w1     <= 0;
            // o_w2     <= 0;
            o_inside <= 0;
            o_valid  <= 0;
        end else begin
            // Latch the calculated "next" values
            o_w0     <= w0_next;
            o_w1     <= w1_next;
            o_w2     <= w2_next;
            
            // Qualify the inside check with the valid flag
            o_inside <= inside_next && i_valid;
            
            // Pass the pipeline valid flag
            o_valid  <= i_valid;
        end
    end

endmodule