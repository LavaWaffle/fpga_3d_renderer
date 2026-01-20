`timescale 1ns / 1ps

module tiled_rasterizer(
    input wire i_clk,
    input wire i_rst,

    // Triangle Assembler Interface
    input wire i_tri_valid,
    output wire o_busy,

    // Triangle Vertex Inputs
    // [TYPE] S16.0 (Signed 16-bit Integer) - Screen Coordinates
    input wire signed [15:0] i_x0, i_y0, i_x1, i_y1, i_x2, i_y2,
    // [TYPE] U8.0 (Unsigned 8-bit Integer) - Depth (Lower is Closer)
    input wire [7:0] i_z0, i_z1, i_z2,
    // [TYPE] Q16.16 (Fixed Point) - Texture Coordinates Normalized (0.0 to 1.0)
    input wire [31:0] i_u0, i_v0, i_u1, i_v1, i_u2, i_v2,

    // Frame Buffer Interface
    output wire [16:0] o_fb_addr[8],
    output wire o_fb_we[8],
    output wire [11:0] o_fb_pixel[8],

    // Z Buffer Interface
    output wire [16:0] o_zb_r_addr[8],
    input  wire [7:0] i_zb_r_data[8],
    output wire [16:0] o_zb_w_addr[8],
    output wire o_zb_w_we[8],
    output wire [7:0] o_zb_w_data[8]
);
    wire [7:0] rast_t_busy;
    assign o_busy = |rast_t_busy; // Wait until all tiles are free

    reg i_tri_valid_prev, i_tri_valid_int;

    always_ff @(posedge i_clk) begin
       if (i_rst) begin
              i_tri_valid_prev <= 0;
              i_tri_valid_int  <= 0;
         end else begin
              i_tri_valid_prev <= i_tri_valid;
              // Rising edge detection
              i_tri_valid_int  <= i_tri_valid & ~i_tri_valid_prev;
       end 
    end

    genvar t;
    generate
        for (t = 0; t < 8; t = t + 1) begin : rast_tile_gen
            // if (t != 2 && t != 1) begin : skip_tiles
            //     assign o_fb_addr[t]    = 17'd0;
            //     assign o_fb_we[t]      = 1'b0;
            //     assign o_fb_pixel[t]   = 12'd0;
            //     assign o_zb_r_addr[t]  = 17'd0;
            //     assign o_zb_w_addr[t]  = 17'd0;
            //     assign o_zb_w_we[t]    = 1'b0;
            //     assign o_zb_w_data[t]  = 8'd0;
            //     assign rast_t_busy[t]  = 1'b0;
            // end else begin : inst_tiles

            rasterizer #(
                .TILE_ID(t)
            ) rasterizer_instance (
                .i_clk(i_clk), .i_rst(i_rst),

                // Triangle Assembler Interface
                .i_tri_valid(i_tri_valid_int), .o_busy(rast_t_busy[t]),
                
                // Triangle Vertex Inputs
                .i_x0(i_x0), .i_y0(i_y0),
                .i_x1(i_x1), .i_y1(i_y1),
                .i_x2(i_x2), .i_y2(i_y2),
                
                .i_z0(i_z0), .i_z1(i_z1), .i_z2(i_z2),
                
                .i_u0(i_u0), .i_v0(i_v0),
                .i_u1(i_u1), .i_v1(i_v1),
                .i_u2(i_u2), .i_v2(i_v2),
                
                // Tiled Buffer Interfaces
                .o_fb_addr(o_fb_addr[t]),
                .o_fb_we(o_fb_we[t]),
                .o_fb_pixel(o_fb_pixel[t]),
                .o_zb_r_addr(o_zb_r_addr[t]),
                .i_zb_r_data(i_zb_r_data[t]),
                .o_zb_w_addr(o_zb_w_addr[t]),
                .o_zb_w_we(o_zb_w_we[t]),
                .o_zb_w_data(o_zb_w_data[t])
            );
            // end
        end
    endgenerate
    
endmodule
