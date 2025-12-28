`timescale 1ns / 1ps

module triangle_assembler(
    input wire i_clk,
    input wire i_rst,

    // Interface to Vertex FIFO
    input wire [103:0] i_fifo_data,  // {x[15:0], y[15:0], z[7:0], u[31:0], v[31:0]}
    input wire         i_fifo_empty,
    output reg         o_fifo_read,

    // Interface to Rasterizer
    output reg         o_tri_valid,
    input wire         i_raster_busy, // Feedback from Rasterizer (Stop if busy)
    
    // Triangle Outputs (V0, V1, V2)
    output reg signed [15:0] o_x0, o_y0, o_x1, o_y1, o_x2, o_y2,
    output reg [7:0]         o_z0, o_z1, o_z2,
    output reg [31:0]        o_u0, o_v0, o_u1, o_v1, o_u2, o_v2
);

    // Unpack FIFO Data
    // Format: {x[15:0], y[15:0], z[7:0], u[31:0], v[31:0]}
    wire signed [15:0] in_x = i_fifo_data[103:88];
    wire signed [15:0] in_y = i_fifo_data[87:72];
    wire [7:0]         in_z = i_fifo_data[71:64];
    wire [31:0]        in_u = i_fifo_data[63:32];
    wire [31:0]        in_v = i_fifo_data[31:0];

    // Internal Storage
    reg signed [15:0] v0_x, v0_y, v1_x, v1_y;
    reg [7:0]         v0_z, v1_z;
    reg [31:0]        v0_u, v0_v, v1_u, v1_v;
    
    typedef enum {
        WAIT_V0,
        READ_V0,
        WAIT_V1,
        READ_V1,
        WAIT_V2,
        READ_V2,
        CULL_CHECK,
        OUTPUT_TRI
    } tri_assem_state_t;
    
    tri_assem_state_t state;

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            state <= WAIT_V0;
            o_fifo_read <= 0;
            o_tri_valid <= 0;
        end else begin
            o_fifo_read <= 0;
            o_tri_valid <= 0; // Single pulse

            case (state)
                WAIT_V0: begin
                    if (!i_fifo_empty) begin
                        o_fifo_read <= 1;
                        
                        state <= READ_V0;
                    end
                end

                READ_V0: begin
                    // Capture logic (Latches 'in' signals this cycle)
                    v0_x <= in_x; v0_y <= in_y; v0_z <= in_z;
                    v0_u <= in_u; v0_v <= in_v;

                    state <= WAIT_V1;
                end

                WAIT_V1: begin
                    if (!i_fifo_empty) begin
                        o_fifo_read <= 1;
                        
                        state <= READ_V1;
                    end
                end

                READ_V1: begin
                    // Capture logic (Latches 'in' signals this cycle)
                    v1_x <= in_x; v1_y <= in_y; v1_z <= in_z;
                    v1_u <= in_u; v1_v <= in_v;

                    state <= WAIT_V2;
                end

                WAIT_V2: begin
                    if (!i_fifo_empty) begin
                        o_fifo_read <= 1;       
                        
                        state <= READ_V2;
                    end
                end

                READ_V2: begin
                    // Capture logic for V2
                    o_x0 <= v0_x; o_y0 <= v0_y; o_z0 <= v0_z; o_u0 <= v0_u; o_v0 <= v0_v;
                    o_x1 <= v1_x; o_y1 <= v1_y; o_z1 <= v1_z; o_u1 <= v1_u; o_v1 <= v1_v;
                    o_x2 <= in_x; o_y2 <= in_y; o_z2 <= in_z; o_u2 <= in_u; o_v2 <= in_v;

                    state <= CULL_CHECK;
                end

                CULL_CHECK: begin
                    // Back-Face Culling: Signed Area
                    // (x1-x0)*(y2-y0) - (x2-x0)*(y1-y0)
                    
                    logic signed [31:0] vec0_x, vec0_y, vec1_x, vec1_y;
                    logic signed [31:0] cross_prod;
                    
                    vec0_x = o_x1 - o_x0;
                    vec0_y = o_y1 - o_y0;
                    vec1_x = o_x2 - o_x0;
                    vec1_y = o_y2 - o_y0;
                    
                    cross_prod = (vec0_x * vec1_y) - (vec1_x * vec0_y);

                    // If Positive, it's visible.
                    if (cross_prod > 0) begin
                        state <= OUTPUT_TRI;
                    end else begin
                        // Discard and restart
                        state <= WAIT_V0;
                    end
                end

                OUTPUT_TRI: begin
                    // Wait for Rasterizer to be ready
                    if (!i_raster_busy) begin
                        o_tri_valid <= 1;
                        state <= WAIT_V0;
                    end
                end
            endcase
        end
    end
endmodule