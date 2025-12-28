`timescale 1ns / 1ps

module simple_bram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10,
    parameter INIT_FILE  = ""
)(
    input wire clk,
    input wire we,
    input wire [ADDR_WIDTH-1:0] addr,
    input wire [DATA_WIDTH-1:0] wdata,
    output reg [DATA_WIDTH-1:0] rdata
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    // Declare the RAM array using the parameters
    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] ram [0:DEPTH-1];

    initial begin
        // If INIT_FILE is not empty, load it
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, ram);
        end
    end

    always @(posedge clk) begin
        if (we) begin
            ram[addr] <= wdata;
        end
        // Read-First behavior: When writing, rdata will show the OLD value
        rdata <= ram[addr]; 
    end

endmodule