`timescale 1ns / 1ps

module tiled_frame_buffer #(
    parameter int DEPTH = 38400,
    parameter int ADDR_WIDTH = 16, // Needs to be 16 for a depth of 38,400
    parameter int DATA_WIDTH = 12
)(
    input wire i_clk,
    input wire i_clk_vga,

    // Write Interface
    input wire [ADDR_WIDTH-1:0] i_tile_fb_addr[2],
    input wire i_tile_fb_we[2],
    input wire [DATA_WIDTH-1:0] i_tile_fb_data[2],

    // Read Interface
    input wire [ADDR_WIDTH:0] i_vga_addr, 
    output logic [DATA_WIDTH-1:0] o_vga_pixel
);
    // 1. Address Slicing
    // We assume i_vga_addr[0] is the Even/Odd selector (LSB)
    wire [ADDR_WIDTH-1:0] vga_local_addr = i_vga_addr[ADDR_WIDTH:1];
    logic [DATA_WIDTH-1:0] bram_dout [2]; 

    // 2. Latency Compensation
    // Delay the LSB by 1 cycle to match BRAM read latency
    logic vga_bank_sel_q;
    always_ff @(posedge i_clk_vga) begin
        vga_bank_sel_q <= i_vga_addr[0];
    end

    genvar t;
    generate
        for (t = 0; t < 2; t = t + 1) begin : gen_tiles
            simple_dual_clk_bram #(
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(ADDR_WIDTH),
                .DEPTH(DEPTH),
                .INIT_FILE("frame_buffer_init.mem")
            ) simple_dual_clk_bram_instance (
                // Port A: Write
                .clka(i_clk),
                .we(i_tile_fb_we[t]),
                .waddr(i_tile_fb_addr[t]), // Use full local addr width
                .din(i_tile_fb_data[t]),

                // Port B: Read
                .clkb(i_clk_vga),
                .raddr(vga_local_addr),
                .dout(bram_dout[t])
            );
        end
    endgenerate

    // 3. Output MUX (Uses the delayed select signal)
    assign o_vga_pixel = bram_dout[vga_bank_sel_q];

endmodule