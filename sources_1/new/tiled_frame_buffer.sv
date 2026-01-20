`timescale 1ns / 1ps

module tiled_frame_buffer #(
    parameter int DEPTH = 9600,
    parameter int ADDR_WIDTH = 17,
    parameter int DATA_WIDTH = 12
)(
    input wire i_clk,
    input wire i_clk_vga,

    // ============================
    // Write Interface (From Arbiter)
    // ============================
    input wire [ADDR_WIDTH-1:0] i_tile_fb_addr[8],
    input wire i_tile_fb_we[8],
    input wire [DATA_WIDTH-1:0] i_tile_fb_data[8],

    // ============================
    // Read Interface (To VGA)
    // ============================
    // Ideally, pass X and Y. If you only have linear addr, see note below.
    input wire [9:0] i_vga_x, // 0-319
    input wire [9:0] i_vga_y, // 0-239

    output logic [DATA_WIDTH-1:0] o_vga_pixel
);

    logic [2:0] vga_tile_index;
    logic [13:0] vga_local_addr; // 80*120 fits in 14

    logic [2:0] vga_tile_index_d;

    // Optimized coordinate signals
    logic [6:0] local_x;
    logic [6:0] local_y;
    logic [1:0] col_idx;
    logic       row_idx;

    // Combinational Math (Cheaper than doing it inside FF with variables)
    always_comb begin
        // Column Index & Local X Calculation
        if (i_vga_x < 80) begin
            col_idx = 0;
            local_x = i_vga_x[6:0];
        end else if (i_vga_x < 160) begin
            col_idx = 1;
            local_x = (i_vga_x - 80);
        end else if (i_vga_x < 240) begin
            col_idx = 2;
            local_x = (i_vga_x - 160);
        end else begin
            col_idx = 3;
            local_x = (i_vga_x - 240);
        end

        // Row Index & Local Y Calculation
        if (i_vga_y < 120) begin
            row_idx = 0;
            local_y = i_vga_y[6:0];
        end else begin
            row_idx = 1;
            local_y = (i_vga_y - 120);
        end
    end

    // Sequential Pipeline
    always_ff @(posedge i_clk_vga) begin
        // 1. Capture Tile Index
        vga_tile_index <= {row_idx, col_idx};
        
        // 2. Pipeline for BRAM Latency (matches read delay)
        vga_tile_index_d <= vga_tile_index;

        // 3. Calculate Linear Address for the BRAM
        // 80 * local_y + local_x
        // Synthesis handles *80 efficiently (shift+add)
        vga_local_addr <= (local_y * 80) + local_x;
    end

    // ---------------------------------------------------------
    // Instantiate 8 BRAMs
    // ---------------------------------------------------------
    logic [DATA_WIDTH-1:0] bram_dout [8]; 

    genvar t;
    generate
        for (t = 0; t < 8; t = t + 1) begin : gen_tiles
            simple_dual_clk_bram #(
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(14),
                .DEPTH(DEPTH),
                .INIT_FILE("frame_buffer_init.mem")
            ) simple_dual_clk_bram_instance (
                // Port A: Write Port (i_clk)
                .clka(i_clk),
                .we(i_tile_fb_we[t]),
                .waddr(i_tile_fb_addr[t][13:0]), // Use lower 14 bits for local addr
                .din(i_tile_fb_data[t]),

                // Port B: Read Port (i_clk_vga)
                .clkb(i_clk_vga),
                .raddr(vga_local_addr),
                .dout(bram_dout[t])
            );
        end
    endgenerate

    // ---------------------------------------------------------
    // Output MUX
    // ---------------------------------------------------------
    always_comb begin
        o_vga_pixel = bram_dout[vga_tile_index_d];
    end
endmodule
