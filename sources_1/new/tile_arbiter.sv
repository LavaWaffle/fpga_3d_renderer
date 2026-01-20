`timescale 1ns / 1ps
module tile_arbiter #(
    parameter int NUM_RASTERIZERS = 2,
    parameter int ADDR_WIDTH = 17,
    parameter int COLOR_DATA_WIDTH = 12, // 12 bit color
    parameter int Z_DATA_WIDTH = 8 // 8 bit Z buf
)(
    input wire i_clk,
    input wire i_rst, 
    input wire rasterizer_rq_valid[NUM_RASTERIZERS],
    input wire [2:0] rasterizer_rq[NUM_RASTERIZERS],
    input wire rasterizer_done[NUM_RASTERIZERS], 

    // Virtual Tile Interface (fb)
    input wire [ADDR_WIDTH-1:0] i_rasterizer_fb_addr[NUM_RASTERIZERS],
    input wire i_rasterizer_fb_we[NUM_RASTERIZERS],
    input wire [COLOR_DATA_WIDTH-1:0] i_rasterizer_fb_data[NUM_RASTERIZERS],

    // Virtual Tile Interface (zb)
    input wire [ADDR_WIDTH-1:0] i_rasterizer_zb_r_addr[NUM_RASTERIZERS],
    output logic [Z_DATA_WIDTH-1:0] o_rasterizer_zb_r_data[NUM_RASTERIZERS],
    input wire [ADDR_WIDTH-1:0] i_rasterizer_zb_w_addr[NUM_RASTERIZERS],
    input wire i_rasterizer_zb_w_we[NUM_RASTERIZERS],
    input wire [Z_DATA_WIDTH-1:0] i_rasterizer_zb_w_data[NUM_RASTERIZERS],

    // Virtual Tile Real BRAM Interface 
    output logic [ADDR_WIDTH-1:0] o_tile_fb_addr[8],
    output logic o_tile_fb_we[8],
    output logic [COLOR_DATA_WIDTH-1:0] o_tile_fb_data[8],

    output logic [ADDR_WIDTH-1:0] o_tile_zb_r_addr[8],
    input logic [Z_DATA_WIDTH-1:0] i_tile_zb_r_data[8],
    output logic [ADDR_WIDTH-1:0] o_tile_zb_w_addr[8],
    output logic o_tile_zb_w_we[8],
    output logic [Z_DATA_WIDTH-1:0] o_tile_zb_w_data[8],
    
    output logic o_rasterizer_res[NUM_RASTERIZERS] 
);
    logic signed [$clog2(NUM_RASTERIZERS)+1:0] tile [0:7]; 

    always_comb begin
        // Default Outputs to Rasterizers
        for (int i = 0; i < NUM_RASTERIZERS; i++) begin
            o_rasterizer_res[i] = 1'b0;
            o_rasterizer_zb_r_data[i] = '0;
        end

        // Default Memory Requests to 0
        for (int t = 0; t < 8; t++) begin
            o_tile_fb_addr[t] = '0;
            o_tile_fb_we[t]   = 1'b0;
            o_tile_fb_data[t] = '0;

            o_tile_zb_r_addr[t] = '0;
            o_tile_zb_w_addr[t] = '0;
            o_tile_zb_w_we[t]   = 1'b0;
            o_tile_zb_w_data[t] = '0;
        end

        // Handle Tile Connection
        for (int t = 0; t < 8; t++) begin
            // If the tile is owned (tile[t] is not -1)
            if (tile[t] != -1) begin
                // Connect all Memory Requests from the owning Rasterizer to this tile
                int i = tile[t]; // i = Rasterizer Index that owns tile t

                o_rasterizer_res[i] = 1'b1;

                // Frame Buffer
                o_tile_fb_addr[t] = i_rasterizer_fb_addr[i];
                o_tile_fb_we[t]   = i_rasterizer_fb_we[i];
                o_tile_fb_data[t] = i_rasterizer_fb_data[i];

                // Z Buffer Read
                o_tile_zb_r_addr[t] = i_rasterizer_zb_r_addr[i];
                o_rasterizer_zb_r_data[i] = i_tile_zb_r_data[t];

                // Z Buffer Write
                o_tile_zb_w_addr[t] = i_rasterizer_zb_w_addr[i];
                o_tile_zb_w_we[t]   = i_rasterizer_zb_w_we[i];
                o_tile_zb_w_data[t] = i_rasterizer_zb_w_data[i];
                
            end
        end
    end

    always_ff @(posedge i_clk) begin    
        if (i_rst) begin
            for (int i = 0; i < 8; i++) begin
                tile[i] <= -1; 
            end
        end else begin
           for (int i = 0; i < NUM_RASTERIZERS; i++) begin
                for (int t = 0; t < 8; t++) begin
                     // Check Request
                     if (rasterizer_rq_valid[i] && rasterizer_rq[i] == t[2:0]) begin
                          if (tile[t] == -1) begin
                            tile[t] <= i;
                          end
                     end 
                     
                     // Check Done
                     // Note: We check tile[t] == i to ensure only the owner can free it
                     if (rasterizer_done[i] && tile[t] == i) begin
                          tile[t] <= -1;
                     end
                end
           end 
        end
    end
endmodule