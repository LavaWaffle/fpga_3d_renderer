`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/27/2025 11:55:59 PM
// Design Name: 
// Module Name: fpga_top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module fpga_top(
    input wire clk,
    output reg dummy_led
    );
    
    (* DONT_TOUCH = "true" *)
    geometry_engine gem_engine (
        .i_clk (clk),
        .i_rst (1'b0)
    );
    
    always_ff @(posedge clk) begin
        dummy_led <= gem_engine.x_screen ^ gem_engine.y_screen;
    end
endmodule
