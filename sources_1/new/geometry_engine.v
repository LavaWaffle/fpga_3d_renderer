`timescale 1ns / 1ps

module geometry_engine(
        input i_clk,
        input i_rst
    );
    
    reg  [9:0] vertex_addr;
    wire [31:0] vertex_data_i;
    
    simple_bram (
        .DATA_WIDTH(32),
        .ADDR_WIDTH(10),
        .INIT_FILE("")  // "vertex_data.mem"
    ) vertex_ram (
        .clk    (i_clk),
        .we     (1'b0),
        .addr   (vertex_addr),
        .wdata  (32'b0),
        .rdata  (vertex_data_i)
    );

    localparam  S_VERTEX_FETCH = 0;
    localparam  S_MATRIX_TRANSFORM = 1;
    localparam  S_PERSP_DIVIDE = 2;
    localparam  S_VIEWPORT_MAP = 3;

    localparam NUM_STATES = 4;
    
    reg [$clog2(NUM_STATES)-1:0] state;

    reg [31:0] x, y, z, u, v;
    reg [2:0] vertex_count;

    always @(posedge i_clk) begin
        if (i_rst) begin
            state <= S_VERTEX_FETCH;
            vertex_addr <= 0;
            vertex_count <= 0;
            x <= 0;
            y <= 0;
            z <= 0;
            u <= 0;
            v <= 0;
        end else begin
            case (state)
                S_VERTEX_FETCH: begin
                    vertex_count <= vertex_count + 1;
                    if (vertex_count == 0) begin
                        x <= vertex_data_i;
                    end else if (vertex_count == 1) begin
                        y <= vertex_data_i;
                    end else if (vertex_count == 2) begin
                        z <= vertex_data_i;
                    end else if (vertex_count == 3) begin
                        u <= vertex_data_i;
                    end else if (vertex_count == 4) begin
                        v <= vertex_data_i;
                        vertex_count <= 0;
                        state <= S_MATRIX_TRANSFORM;
                    end
                end
                S_MATRIX_TRANSFORM: begin
                    // Placeholder for matrix transformation logic
                    state <= S_PERSP_DIVIDE;
                end
                S_PERSP_DIVIDE: begin
                    // Placeholder for perspective division logic
                    state <= S_VIEWPORT_MAP;
                end
                S_VIEWPORT_MAP: begin
                    // Placeholder for viewport mapping logic   
                    state <= S_VERTEX_FETCH;
                    vertex_addr <= vertex_addr + 1;
                end
            endcase
        end
    
    end
    
endmodule
