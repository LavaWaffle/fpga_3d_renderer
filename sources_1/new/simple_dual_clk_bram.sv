`timescale 1ns / 1ps

module simple_dual_clk_bram #(
    parameter DATA_WIDTH = 12,
    parameter ADDR_WIDTH = 17,
    parameter DEPTH = 76800,
    parameter INIT_FILE = "" 
)(
    // Port A: Write Only (Connect to System/Rasterizer Clock)
    input  wire                  clka,
    input  wire                  we,
    input  wire [ADDR_WIDTH-1:0] waddr,
    input  wire [DATA_WIDTH-1:0] din,

    // Port B: Read Only (Connect to Pixel Clock)
    input  wire                  clkb,
    input  wire [ADDR_WIDTH-1:0] raddr,
    output reg  [DATA_WIDTH-1:0] dout
);

    // Infer Block RAM
    (* ram_style = "block" *) 
    reg [DATA_WIDTH-1:0] ram [0:DEPTH-1];

    // Initialization
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, ram);
        end
    end

    // Port A: Synchronous Write on clka
    always_ff @(posedge clka) begin
        if (we) begin
            ram[waddr] <= din;
        end
    end

    // Port B: Synchronous Read on clkb
    always_ff @(posedge clkb) begin
        dout <= ram[raddr];
    end

endmodule