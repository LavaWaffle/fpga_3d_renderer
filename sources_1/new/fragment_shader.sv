`timescale 1ns / 1ps

module fragment_shader(
    input wire i_clk,
    input wire i_rst,

    // -------------------------------------------------------------------------
    // 1. Pipeline Inputs (From Interpolator & Delays)
    // -------------------------------------------------------------------------
    input wire signed [31:0] i_p_z, // 8 bit int [0,255]
    // input wire signed [31:0] i_p_u, // Q16.16
    // input wire signed [31:0] i_p_v, // Q16.16
    input wire i_inside,    // From Interpolator
    input wire i_valid,     // From Interpolator

    input wire [11:0] i_tex_pixel,

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
    logic z_test_pass;

    always_comb begin
        // Defaults
        o_fb_we        = 0;
        o_zb_w_we      = 0;
        o_fb_pixel     = 0;
        o_zb_w_new_val = 0;
        o_fb_addr      = i_pixel_addr; // Pass through address
        o_zb_w_addr    = i_pixel_addr;

        // 1. Convert Z to 8-bit
        z_new_8bit = i_p_z[7:0]; 
        
        // 2. Z-Test Logic
        // Check if valid, inside triangle, AND closer than current Z-buffer value
        // Note: We use < because 0 is near, 255 is far.
        if (i_valid && i_inside && (z_new_8bit < i_zb_cur_val)) begin
            z_test_pass = 1;
        end else begin
            z_test_pass = 0;
        end

        // 3. Output Generation
        if (z_test_pass) begin
            // DIRECT TEXTURE MAPPING
            // We just pass the color we retrieved from the ROM
            o_fb_pixel   = i_tex_pixel;
            o_fb_we      = 1;
            
            o_zb_w_new_val = z_new_8bit;
            o_zb_w_we      = 1;
        end
    end
endmodule