`timescale 1ns / 1ps

module simple_dual_port_bram #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 17,
    parameter DEPTH = 76800,
    parameter INIT_FILE = "" 
)(
    input  wire                  clk,

    // Port A: Write Only (Used by Reset Logic or Rasterizer Write-Back)
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] waddr,
    input  wire [DATA_WIDTH-1:0] din,

    // Port B: Read Only (Used by Rasterizer Depth Check or Display Controller)
    input  wire [ADDR_WIDTH-1:0] raddr,
    output reg  [DATA_WIDTH-1:0] dout
);

    // Infer Block RAM
    // "ram_style" attribute helps guide Vivado to use BRAM instead of LUTRAM
    (* ram_style = "block" *) 
    reg [DATA_WIDTH-1:0] ram [0:DEPTH-1];

    // Initialization
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, ram);
        end
    end

    // Port A: Synchronous Write
    always_ff @(posedge clk) begin
        if (we) begin
            ram[waddr] <= din;
        end
    end

    // Port B: Synchronous Read
    always_ff @(posedge clk) begin
        dout <= ram[raddr];
    end

endmodule