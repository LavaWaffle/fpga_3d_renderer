`timescale 1ns / 1ps

module interpolator(
    input wire i_clk,
    input wire i_rst,

    // -------------------------------------------------------------------------
    // 1. Triangle Attributes (Constant for the whole triangle)
    // -------------------------------------------------------------------------
    // Inverse Area (Q16.16) calculated in Setup
    input wire signed [31:0] i_inv_area, 
    
    // Vertex Z values (8-bit)
    input wire [7:0] i_z0, i_z1, i_z2,
    
    // Vertex U/V values (Q16.16)
    input wire signed [31:0] i_u0, i_u1, i_u2,
    input wire signed [31:0] i_v0, i_v1, i_v2,

    // -------------------------------------------------------------------------
    // 2. Pipeline Input (From Edge Engine)
    // -------------------------------------------------------------------------
    input wire signed [31:0] i_w0, i_w1, i_w2,
    input wire i_inside,
    input wire i_valid,

    // -------------------------------------------------------------------------
    // 3. Pipeline Output (To Fragment Shader)
    // -------------------------------------------------------------------------    
    // Interpolated values in Q16.16 format
    output reg signed [31:0] o_p_z, 
    output reg signed [31:0] o_p_u, 
    output reg signed [31:0] o_p_v,
    
    output reg o_inside,
    output reg o_valid
);

    // -------------------------------------------------------------------------
    // Combinatorial Logic
    // -------------------------------------------------------------------------
    logic signed [63:0] sum_z, sum_u, sum_v;
    logic signed [31:0] p_z_comb, p_u_comb, p_v_comb;

    // Helper for Z expansion (8-bit -> 32-bit signed for math)
    logic signed [31:0] z0_32, z1_32, z2_32;
    assign z0_32 = {24'b0, i_z0};
    assign z1_32 = {24'b0, i_z1};
    assign z2_32 = {24'b0, i_z2};

    always_comb begin
        // Default values
        sum_z = 0; sum_u = 0; sum_v = 0;
        p_z_comb = 0; p_u_comb = 0; p_v_comb = 0;

        // Only compute if pixel is valid AND inside triangle (Gate for Power)
        if (i_valid && i_inside) begin
            
            // 1. Weighted Sums
            // Remapped Weights: w1->V0, w2->V1, w0->V2
            sum_z = (i_w1 * z0_32) + (i_w2 * z1_32) + (i_w0 * z2_32);
            sum_u = (i_w1 * i_u0)  + (i_w2 * i_u1)  + (i_w0 * i_u2);
            sum_v = (i_w1 * i_v0)  + (i_w2 * i_v1)  + (i_w0 * i_v2);

            // 2. Normalize by Area (Multiplication instead of Division)
            // Result is technically Q32.32 before shift, so we shift right by 16 to get Q16.16
            // The DSP blocks usually handle this Multiply-Shift efficiently
            p_z_comb = (sum_z * i_inv_area) >>> 30;
            p_u_comb = (sum_u * i_inv_area) >>> 30;
            p_v_comb = (sum_v * i_inv_area) >>> 30;
        end
    end

    // -------------------------------------------------------------------------
    // Pipeline Register
    // -------------------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            o_p_z    <= 0;
            o_p_u    <= 0;
            o_p_v    <= 0;
            o_inside <= 0;
            o_valid  <= 0;
        end else begin
            o_p_z    <= p_z_comb;
            o_p_u    <= p_u_comb;
            o_p_v    <= p_v_comb;
            o_inside <= i_inside;
            o_valid  <= i_valid;
        end
    end

endmodule