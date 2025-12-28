`timescale 1ns / 1ps

module fpga_top(
    input wire clk,
    input wire rst,
    output reg dummy_led
    );

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
        .i_fifo_data(rasterizer_data_in),
        .i_fifo_empty(rasterizer_fifo_empty),
        .o_fifo_read(rasterizer_read_enable),
        
        .o_tri_valid(triangle_assembler_data_valid),
        .i_raster_busy(rasterizer_busy),
        
        .o_x0(x0), .o_y0(y0), .o_z0(z0),
        .o_x1(x1), .o_y1(y1), .o_z1(z1),
        .o_x2(x2), .o_y2(y2), .o_z2(z2),
        
        .o_u0(u0), .o_v0(v0),
        .o_u1(u1), .o_v1(v1),
        .o_u2(u2), .o_v2(v2)
    );

    always_ff @(posedge clk) begin
        dummy_led <= x0[0] ^ x1[0] ^ x2[0];
    end
endmodule
