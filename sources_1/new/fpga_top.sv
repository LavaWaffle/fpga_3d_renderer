`timescale 1ns / 1ps

module fpga_top(
    input wire clk,
    input wire rst_n,
    output reg dummy_led
    );

    wire rst = !rst_n;

    wire [31:0] geo_x, geo_y, geo_u, geo_v;
    wire [7:0]  geo_z;
    wire        geo_valid;
    wire        fifo_full;
    
    geometry_engine gem_engine (
        .i_clk (clk),
        .i_rst (rst),

        .o_vertex_valid(geo_valid),
        .o_x(geo_x), .o_y(geo_y),
        .o_z(geo_z),
        .o_u(geo_u), .o_v(geo_v)
    );

    wire [103:0] rasterizer_data_in;
    wire  rasterizer_fifo_empty;
    wire  rasterizer_read_enable; 
    vertex_fifo #(
        .DATA_WIDTH(104), // 32+32+8+16+16
        .DEPTH(64)
    ) fifo_inst (
        .i_clk(clk),
        .i_rst(rst),
        
        // Write Side (From Geometry)
        .i_we(geo_valid), 
        .i_data({geo_x[31:16], geo_y[31:16], geo_z, geo_u, geo_v}), // Packing
        .o_full(fifo_full),
        
        // Read Side (To Rasterizer/Assembler)
        .i_re(rasterizer_read_enable), 
        .o_data(rasterizer_data_in),
        .o_empty(rasterizer_fifo_empty)
    );

    wire triangle_assembler_data_valid;
    wire rasterizer_busy;

    wire signed [15:0] x0, y0, x1, y1, x2, y2;
    wire [7:0]         z0, z1, z2;
    wire [31:0]        u0, v0, u1, v1, u2, v2;

    triangle_assembler triangle_assembler_instance (
        .i_clk(clk),
        .i_rst(rst),

        // FIFO Interface
        .i_fifo_data(rasterizer_data_in),
        .i_fifo_empty(rasterizer_fifo_empty),
        .o_fifo_read(rasterizer_read_enable),
        
        // Assembler to Rasterizer Interface
        .o_tri_valid(triangle_assembler_data_valid),
        .i_raster_busy(rasterizer_busy),
        
        // Triangle Outputs
        .o_x0(x0), .o_y0(y0), .o_z0(z0),
        .o_x1(x1), .o_y1(y1), .o_z1(z1),
        .o_x2(x2), .o_y2(y2), .o_z2(z2),
        
        .o_u0(u0), .o_v0(v0),
        .o_u1(u1), .o_v1(v1),
        .o_u2(u2), .o_v2(v2)
    );

    wire [16:0] rast_fb_addr; // 320x240 = 76,800 addrs (17 bits)
    wire        rast_fb_we;   // Write Enable for Framebuffer
    wire [11:0] rast_fb_pixel; // 12-bit Color 

    wire [16:0] rast_zb_addr;
    wire        rast_zb_we;
    wire [7:0]  rast_o_zb_i_data;
    wire [7:0]  rast_i_zb_o_data;

    rasterizer rasterizer_instance (
        .i_clk(clk),
        .i_rst(rst),
        
        // Assembler Interface
        .i_tri_valid(triangle_assembler_data_valid),
        .o_busy(rasterizer_busy),
        
        // Triangle Inputs
        .i_x0(x0), .i_y0(y0), .i_z0(z0),
        .i_x1(x1), .i_y1(y1), .i_z1(z1),
        .i_x2(x2), .i_y2(y2), .i_z2(z2),
        
        .i_u0(u0), .i_v0(v0),
        .i_u1(u1), .i_v1(v1),
        .i_u2(u2), .i_v2(v2),

        // Framebuffer Interface
        .o_fb_addr(rast_fb_addr),
        .o_fb_we(rast_fb_we),
        .o_fb_pixel(rast_fb_pixel),
        
        // Z-Buffer Interface
        .o_zb_r_addr(rast_zb_addr),
        .i_zb_r_data(rast_i_zb_o_data),
        .o_zb_w_addr(),
        .o_zb_w_we(rast_zb_we),
        .o_zb_w_data(rast_o_zb_i_data)
    );

    always_ff @(posedge clk) begin
        // Unary XOR (^) before a vector reduces all its bits to 1 bit.
        // We include EVERYTHING: Pixel color, Write Enables, Addresses, and Z-data.
        dummy_led <= x0[0] 
                     ^ (^rast_fb_pixel)   // Vital: Keeps Interpolator alive
                     ^ (^rast_fb_addr)    // Vital: Keeps Address generator alive
                     ^ rast_fb_we         
                     ^ rast_zb_we 
                     ^ (^rasterizer_instance.stage4_shader.b_val); // Vital: Checks ALL bits of Z, not just LSB
    end
endmodule
