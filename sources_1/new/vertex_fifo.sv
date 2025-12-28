`timescale 1ns / 1ps

module vertex_fifo #(
    parameter DATA_WIDTH = 104, // {x[15:0], y[15:0], z[7:0], u[31:0], v[31:0]}
    parameter DEPTH = 64        // Store up to 64 vertices (~20 triangles)
)(
    input  wire                  i_clk,
    input  wire                  i_rst,
    
    // Write Interface (From Geometry Engine)
    input  wire                  i_we,    // Write Enable
    input  wire [DATA_WIDTH-1:0] i_data,  // Data In
    output wire                  o_full,  // Stop writing if full
    
    // Read Interface (To Triangle Assembler)
    input  wire                  i_re,    // Read Enable
    output wire [DATA_WIDTH-1:0] o_data,  // Data Out
    output wire                  o_empty  // Stop reading if empty
);

    // Pointer Logic
    localparam PTR_WIDTH = $clog2(DEPTH);
    reg [PTR_WIDTH-1:0] wr_ptr, rd_ptr;
    reg [PTR_WIDTH:0]   count; // Extra bit to track full/empty distinction

    // Memory Array
    // Vivado will infer Block RAM for this
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Status Flags
    assign o_full  = (count == DEPTH);
    assign o_empty = (count == 0);
    
    // Read Logic (Fall-through behavior for ease of use)
    assign o_data = mem[rd_ptr];

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
        end else begin
            // WRITE OPERATION
            if (i_we && !o_full) begin
                mem[wr_ptr] <= i_data;
                wr_ptr      <= (wr_ptr == DEPTH-1) ? 0 : wr_ptr + 1;
            end

            // READ OPERATION
            if (i_re && !o_empty) begin
                rd_ptr <= (rd_ptr == DEPTH-1) ? 0 : rd_ptr + 1;
            end

            // COUNT UPDATE
            if (i_we && !o_full && !(i_re && !o_empty)) begin
                count <= count + 1;
            end else if (i_re && !o_empty && !(i_we && !o_full)) begin
                count <= count - 1;
            end
        end
    end

endmodule