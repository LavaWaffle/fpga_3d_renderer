`timescale 1ns / 1ps

module interpolator(
    input wire i_clk,
    input wire i_rst,

    // [TYPE] Q2.30 - Inverse Area (Calculated in setup)
    input wire signed [31:0] i_inv_area, 
    
    // [TYPE] U8.0 - Vertex Z
    input wire [7:0] i_z0, i_z1, i_z2,
    
    // [TYPE] Q16.16 - Vertex UVs
    input wire signed [31:0] i_u0, i_u1, i_u2,
    input wire signed [31:0] i_v0, i_v1, i_v2,

    // [TYPE] S32.0 - Weights (from Edge Engine)
    input wire signed [31:0] i_w0, i_w1, i_w2, // Barycentric Weights in Integer format
    input wire i_inside,
    input wire i_valid,

    // Outputs
    // [TYPE] S32.0 Container holding U8.0 Value
    // Math: (Weight_Int * Z_Int * InvArea_Q2.30) >>> 30 = Integer
    output reg signed [31:0] o_p_z, // Note z is actully just a 8 bit int [0,255]

    // [TYPE] Q16.16 - Interpolated UVs
    // Math: (Weight_Int * UV_Q16.16 * InvArea_Q2.30) >>> 30 = Q16.16
    output reg signed [31:0] o_p_u, 
    output reg signed [31:0] o_p_v,
    
    output reg o_inside,
    output reg o_valid
);
    // Helper for Z expansion (8-bit -> 32-bit signed for math)
    logic signed [31:0] z0_32, z1_32, z2_32;
    assign z0_32 = {24'b0, i_z0};
    assign z1_32 = {24'b0, i_z1};
    assign z2_32 = {24'b0, i_z2};

    // 3 Stages:
    // 1. Weighted Sums (Multiply)
    reg signed [63:0] i_w1_s1 [3]; // i_w1_s1[0] = i_w1 for z, [1] = i_w1 for u, [2] = i_w1 for v
    reg signed [63:0] i_w2_s1 [3];
    reg signed [63:0] i_w0_s1 [3];
    reg i_inside_s1, i_valid_s1;
    reg signed [31:0] i_inv_area_s1;

    // 2. Add Sums
    reg signed [63:0] sum_z_s2;
    reg signed [63:0] sum_u_s2;
    reg signed [63:0] sum_v_s2;
    reg i_inside_s2, i_valid_s2;
    reg signed [31:0] i_inv_area_s2;

    // 3. Normalize by Area (Multiply-Shift)
    reg signed [31:0] p_z_s3;
    reg signed [31:0] p_u_s3;
    reg signed [31:0] p_v_s3;
    reg i_inside_s3, i_valid_s3;

    // Reset Gated Pipeline
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            i_inside_s1 <= 0; i_valid_s1 <= 0;
            i_inside_s2 <= 0; i_valid_s2 <= 0;
            i_inside_s3 <= 0; i_valid_s3 <= 0;
            o_inside    <= 0; o_valid    <= 0;
        end else begin
            i_inside_s1 <= i_inside;
            i_valid_s1 <= i_valid;

            i_inside_s2 <= i_inside_s1;
            i_valid_s2 <= i_valid_s1;

            i_inside_s3 <= i_inside_s2;
            i_valid_s3 <= i_valid_s2;

            o_inside <= i_inside_s3;
            o_valid  <= i_valid_s3;
        end
    end

    // Main Pipeline (No Reset for Better WNS)
    always_ff @(posedge i_clk) begin
        // Stage 1
        i_w1_s1[0] <= i_w1 * z0_32;
        i_w1_s1[1] <= i_w1 * i_u0;
        i_w1_s1[2] <= i_w1 * i_v0;

        i_w2_s1[0] <= i_w2 * z1_32;
        i_w2_s1[1] <= i_w2 * i_u1;
        i_w2_s1[2] <= i_w2 * i_v1;

        i_w0_s1[0] <= i_w0 * z2_32;
        i_w0_s1[1] <= i_w0 * i_u2;
        i_w0_s1[2] <= i_w0 * i_v2;

        i_inv_area_s1 <= i_inv_area;
        
        // Stage 2
        sum_z_s2 <= i_w1_s1[0] + i_w2_s1[0] + i_w0_s1[0];
        sum_u_s2 <= i_w1_s1[1] + i_w2_s1[1] + i_w0_s1[1];
        sum_v_s2 <= i_w1_s1[2] + i_w2_s1[2] + i_w0_s1[2];
        i_inv_area_s2 <= i_inv_area_s1;

        // Stage 3
        p_z_s3 <= (96'(sum_z_s2) * 96'(i_inv_area_s2)) >>> 30;
        p_u_s3 <= (96'(sum_u_s2) * 96'(i_inv_area_s2)) >>> 30;
        p_v_s3 <= (96'(sum_v_s2) * 96'(i_inv_area_s2)) >>> 30;

        // Output
        o_p_z    <= p_z_s3;
        o_p_u    <= p_u_s3;
        o_p_v    <= p_v_s3;
    end
endmodule