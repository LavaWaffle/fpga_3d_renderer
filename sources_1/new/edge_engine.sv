`timescale 1ns / 1ps

module edge_engine(
    input wire i_clk,
    input wire i_rst,

    // -------------------------------------------------------------------------
    // 1. Static Triangle Inputs (Held Constant during traversal)
    // -------------------------------------------------------------------------
    // We pass these through to the Interpolator so it has local access
    input wire signed [15:0] i_x0, i_y0, i_x1, i_y1, i_x2, i_y2,

    // -------------------------------------------------------------------------
    // 2. Pipeline Input (From Pixel Iterator)
    // -------------------------------------------------------------------------
    input wire signed [15:0] i_p_x, 
    input wire signed [15:0] i_p_y,
    input wire i_valid, // High if this is a real pixel, Low if bubble

    // -------------------------------------------------------------------------
    // 3. Pipeline Output (To Interpolator)
    // -------------------------------------------------------------------------
    // Weights are signed 32-bit (Result of 16-bit multiplications)
    output reg signed [31:0] o_w0, o_w1, o_w2, // Barycentric Weights in Integer format
    output reg o_inside, // High if pixel is INSIDE triangle
    output reg o_valid   // Forwarded valid signal
);

    // Combinatorial Logic variables
    logic signed [31:0] w0_comb, w1_comb, w2_comb;
    logic inside_comb;

    always_comb begin
        logic all_pos, all_neg;
        // =====================================================================
        // Barycentric Weight Calculation (Cross Product)
        // =====================================================================
        // Force 32-bit math for the multiplication by casting inputs first
        // 1. Calculate Weights (Using the 32-bit cast fix from before)
        w0_comb = (signed'(32'(i_p_x)) - signed'(32'(i_x0))) * (signed'(32'(i_y1)) - signed'(32'(i_y0))) - 
                  (signed'(32'(i_p_y)) - signed'(32'(i_y0))) * (signed'(32'(i_x1)) - signed'(32'(i_x0)));
        
        w1_comb = (signed'(32'(i_p_x)) - signed'(32'(i_x1))) * (signed'(32'(i_y2)) - signed'(32'(i_y1))) - 
                  (signed'(32'(i_p_y)) - signed'(32'(i_y1))) * (signed'(32'(i_x2)) - signed'(32'(i_x1)));
        
        w2_comb = (signed'(32'(i_p_x)) - signed'(32'(i_x2))) * (signed'(32'(i_y0)) - signed'(32'(i_y2))) - 
                  (signed'(32'(i_p_y)) - signed'(32'(i_y2))) * (signed'(32'(i_x0)) - signed'(32'(i_x2)));

        
        all_pos = (w0_comb >= 0) && (w1_comb >= 0) && (w2_comb >= 0);
        all_neg = (w0_comb <= 0) && (w1_comb <= 0) && (w2_comb <= 0);
        
        if (all_pos) begin
            // Front Face: Pass through as is
            o_w0 = w0_comb; o_w1 = w1_comb; o_w2 = w2_comb;
            o_inside = 1'b1;
        end else if (all_neg) begin
            // Back Face: Negate weights to make them Positive
            o_w0 = -w0_comb; o_w1 = -w1_comb; o_w2 = -w2_comb;
            o_inside = 1'b1;
        end else begin
            // Outside
            o_w0 = 0; o_w1 = 0; o_w2 = 0; // or don't care
            o_inside = 1'b0;
        end
    end

    // =========================================================================
    // Pipeline Register (Latch results on clock edge)
    // =========================================================================
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            o_w0     <= 0;
            o_w1     <= 0;
            o_w2     <= 0;
            o_inside <= 0;
            o_valid  <= 0;
        end else begin
            // Pass through the calculation results
            o_w0     <= w0_comb;
            o_w1     <= w1_comb;
            o_w2     <= w2_comb;
            
            // Only flag 'inside' if the input was valid AND geometry passed
            o_inside <= inside_comb && i_valid;
            
            // Pass valid flag along (used to flush pipeline)
            o_valid  <= i_valid; 
        end
    end

endmodule