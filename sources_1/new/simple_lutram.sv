`timescale 1ns / 1ps

module simple_lutram #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 6,     // LUTRAM is typically used for smaller depths (e.g., 64 words)
    parameter INIT_FILE  = ""
)(
    input wire clk,
    input wire we,
    input wire [ADDR_WIDTH-1:0] addr,
    input wire [DATA_WIDTH-1:0] wdata,
    output wire [DATA_WIDTH-1:0] rdata // Changed to wire for asynchronous read
);

    localparam DEPTH = 1 << ADDR_WIDTH;

    // Attribute to force synthesis to Distributed RAM (LUTs)
    (* ram_style = "distributed" *)
    reg [DATA_WIDTH-1:0] ram [0:DEPTH-1];

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, ram);
        end
    end

    // Synchronous Write
    always @(posedge clk) begin
        if (we) begin
            ram[addr] <= wdata;
        end
    end

    // Asynchronous Read (Combinational)
    // This is the defining characteristic of LUTRAM in most FPGAs
    assign rdata = ram[addr];

endmodule