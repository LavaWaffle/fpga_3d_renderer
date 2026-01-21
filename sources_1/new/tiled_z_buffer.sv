`timescale 1ns / 1ps

module tiled_z_buffer #(
    parameter int DEPTH = 38400,
    parameter int ADDR_WIDTH = 16,
    parameter int DATA_WIDTH = 8 // Z depth
)(
    input wire i_clk,

    // Read Interface
    input wire [ADDR_WIDTH-1:0] i_zb_r_addr[2],
    output logic [DATA_WIDTH-1:0] o_zb_r_data[2],

    // Write Interface
    input wire [ADDR_WIDTH-1:0] i_zb_w_addr[2],
    input wire i_zb_w_we[2],
    input wire [DATA_WIDTH-1:0] i_zb_w_data[2]
);
    genvar t;
    generate
        for (t = 0; t < 2; t = t + 1) begin : z_buffer_bram_gen
            simple_dual_port_bram #(
                .DATA_WIDTH(DATA_WIDTH), 
                .ADDR_WIDTH(ADDR_WIDTH), // Log2 of DEPTH (320 * 240 / 2 = 38400)
                .DEPTH(DEPTH),
                .INIT_FILE("z_buffer_init.mem")
            ) simple_dual_port_bram_instance (
                .clk(i_clk),

                .we(i_zb_w_we[t]),
                .waddr(i_zb_w_addr[t]),
                .din(i_zb_w_data[t]),
                
                .raddr(i_zb_r_addr[t]),
                .dout(o_zb_r_data[t])
            );
        end
    endgenerate
endmodule
