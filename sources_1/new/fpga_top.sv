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
    wire  rasterizer_read_enable = 1'b0; 
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

    always_ff @(posedge clk) begin
        dummy_led <= gem_engine.x_screen ^ gem_engine.y_screen;
    end
endmodule
