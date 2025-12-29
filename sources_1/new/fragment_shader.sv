`timescale 1ns / 1ps

module fragment_shader(
    input wire i_clk,
    input wire i_rst,

    // -------------------------------------------------------------------------
    // 1. Pipeline Inputs (From Interpolator & Delays)
    // -------------------------------------------------------------------------
    input wire signed [31:0] i_p_z, 
    input wire signed [31:0] i_p_u, 
    input wire signed [31:0] i_p_v,
    input wire i_inside,    // From Interpolator
    input wire i_valid,     // From Interpolator

    // Delayed Address info (Must be pipelined 3 cycles from Stage 1)
    input wire [16:0] i_pixel_addr, 

    // -------------------------------------------------------------------------
    // 2. Memory Inputs
    // -------------------------------------------------------------------------
    // The value read from Z-buffer (Latency must match pipeline depth)
    input wire [7:0] i_zb_cur_val, 

    // -------------------------------------------------------------------------
    // 3. Outputs (To Memory Controller / BRAM)
    // -------------------------------------------------------------------------
    output reg [16:0] o_fb_addr,
    output reg        o_fb_we,
    output reg [11:0] o_fb_pixel,
    
    output reg [16:0] o_zb_w_addr,
    output reg        o_zb_w_we,
    output reg [7:0]  o_zb_w_new_val
);

    // Logic Variables
    logic [7:0] z_new_8bit;
    logic signed [31:0] p_w;
    logic [3:0] r_val, g_val, b_val;
    logic z_test_pass;

    always_comb begin
        // Defaults
        o_fb_we      = 0;
        o_zb_w_we      = 0;
        o_fb_pixel   = 0;
        o_zb_w_new_val = 0;
        o_fb_addr    = i_pixel_addr; // Pass through address
        o_zb_w_addr    = i_pixel_addr;

        // 1. Convert Z to 8-bit
        z_new_8bit = i_p_z[7:0]; //i_p_z[7:0]; // Q16.16 scaled, taking integer part approx
        // (If p_z is negative, clamp to 0 handled implicitly by unsigned cast or check)
        
        // 2. Z-Test Logic
        // Check if valid, inside triangle, AND closer than current Z-buffer value
        // Note: Standard Z-buffering usually uses < (less than). 
        // 0 is usually "near", 255 is "far".
        if (i_valid && i_inside && (z_new_8bit < i_zb_cur_val)) begin
            z_test_pass = 1;
        end else begin
            z_test_pass = 0;
        end

        // 3. Color Calculation (Only do this if Z-Test passed to save power?)
        // Actually, for timing, it's often better to calc in parallel and MUX result.
        
        // Calculate W (1.0 - U - V)
        // 1.0 in Q16.16 is 65536 (0x10000)
        p_w = 32'h00010000 - i_p_u - i_p_v;
        
        // --- Red (U) ---
        if (i_p_u[31])           r_val = 0;      // Negative
        else if (|i_p_u[30:16])  r_val = 4'hF;   // Overflow (> 1.0)
        else                     r_val = i_p_u[15:12];

        // --- Green (V) ---
        if (i_p_v[31])           g_val = 0;
        else if (|i_p_v[30:16])  g_val = 4'hF;
        else                     g_val = i_p_v[15:12];

        // --- Blue (W) ---
        if (p_w[31])             b_val = 0;
        else if (|p_w[30:16])    b_val = 4'hF;
        else                     b_val = p_w[15:12];

        // 4. Output Generation
        if (z_test_pass) begin
            o_fb_pixel   = {r_val, g_val, b_val};
            o_fb_we      = 1;
            
            o_zb_w_new_val = z_new_8bit;
            o_zb_w_we      = 1;
        end
    end
endmodule