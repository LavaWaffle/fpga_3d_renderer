`timescale 1ns / 1ps

module geometry_engine(
        input i_clk,
        input i_rst
    );
    
    reg  [9:0] vertex_addr;
    wire [31:0] vertex_data_i;
    
    simple_bram #(
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

    logic signed [31:0] MVP_MATRIX [0:15] = '{
        32'h000087C3, 32'hFFFF783D, 32'h00000000, 32'h00000000,
        32'h0000A1E8, 32'h0000A1E8, 32'hFFFF8D84, 32'h00000000,
        32'hFFFFAEE3, 32'hFFFFAEE3, 32'hFFFF1A92, 32'h000B00A5,
        32'hFFFFAF0C, 32'hFFFFAF0C, 32'hFFFF1B07, 32'h000B2E2A
    };
    
    reg signed [31:0] x_out, y_out, z_out, w_out;
    
    function signed [31:0] mul_fix(input signed [31:0] a, input signed [31:0] b);
        logic signed [63:0] temp;
        begin
            temp = a * b;
            mul_fix = temp >>> 16;
        end
    endfunction
    
    reg start_div;
    wire signed [31:0] x_ndc, y_ndc;
    wire div_x_done, div_y_done;

    // Instantiate Divider for X
    q16_16_div div_x_inst (
        .i_clk(i_clk),
        .i_start(start_div),
        .i_dividend(x_out),
        .i_divisor(w_out),
        .o_quotient(x_ndc),
        .o_done(div_x_done)
    );

    // Instantiate Divider for Y
    q16_16_div div_y_inst (
        .i_clk(i_clk),
        .i_start(start_div),
        .i_dividend(y_out),
        .i_divisor(w_out),
        .o_quotient(y_ndc),
        .o_done(div_y_done)
    );
    
    reg [31:0] x_screen, y_screen;

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
                    // Start at 1 to give clk cycle for RAM read
                    if (vertex_count == 1) x <= vertex_data_i;
                    else if (vertex_count == 2) y <= vertex_data_i;
                    else if (vertex_count == 3) z <= vertex_data_i;
                    else if (vertex_count == 4) u <= vertex_data_i;
                    else if (vertex_count == 5) begin
                        v <= vertex_data_i;
                        vertex_count <= 0;
                        state <= S_MATRIX_TRANSFORM;
                    end
    
                    // 2. Prepare address for the NEXT cycle
                    // Only increment if we aren't done yet
                    if (vertex_count != 5) begin
                        vertex_addr <= vertex_addr + 1;
                        vertex_count <= vertex_count + 1;
                    end
                end
                S_MATRIX_TRANSFORM: begin
                    // Perform 4 Dot Products in Parallel
                    // Row 0 calculates new X
                    x_out <= mul_fix(MVP_MATRIX[0], x) + 
                             mul_fix(MVP_MATRIX[1], y) + 
                             mul_fix(MVP_MATRIX[2], z) + 
                             mul_fix(MVP_MATRIX[3], 32'h00010000); // W=1.0

                    // Row 1 calculates new Y
                    y_out <= mul_fix(MVP_MATRIX[4], x) + 
                             mul_fix(MVP_MATRIX[5], y) + 
                             mul_fix(MVP_MATRIX[6], z) + 
                             mul_fix(MVP_MATRIX[7], 32'h00010000);

                    // Row 2 calculates new Z
                    z_out <= mul_fix(MVP_MATRIX[8], x) + 
                             mul_fix(MVP_MATRIX[9], y) + 
                             mul_fix(MVP_MATRIX[10], z) + 
                             mul_fix(MVP_MATRIX[11], 32'h00010000);

                    // Row 3 calculates new W (Crucial for perspective!)
                    w_out <= mul_fix(MVP_MATRIX[12], x) + 
                             mul_fix(MVP_MATRIX[13], y) + 
                             mul_fix(MVP_MATRIX[14], z) + 
                             mul_fix(MVP_MATRIX[15], 32'h00010000);

                    start_div <= 1; 
                    state <= S_PERSP_DIVIDE;
                end
                S_PERSP_DIVIDE: begin
                    start_div <= 0; // Clear start signal
                    
                    // Wait for both dividers to finish (~34 cycles)
                    if (div_x_done && div_y_done) begin
                        // Check Clipping (Simple Near Plane check)
                        // If W < Near_Plane (0.1 in fixed point ~ 6553), point is behind camera
                        if (w_out < 32'h00001999) begin 
                            // Invalid! Skip to next vertex immediately
                            state <= S_VERTEX_FETCH;
//                            vertex_addr <= vertex_addr + 1;
                            // Note: You need logic to handle "partial" triangles later, 
                            // but for now we just drop bad vertices.
                        end else begin
                            // Valid! Move to Viewport Map
                            state <= S_VIEWPORT_MAP;
                        end
                    end
                end
                S_VIEWPORT_MAP: begin
                    // Math: Screen = (NDC + 1.0) * (ScreenDim / 2)
                    // 1. Add 1.0 (Q16.16 is 0x10000)
                    // 2. Multiply by Half Dimension (160 for X, 120 for Y)
                    // 3. Shift right 16 to get Integer
                    
                    // X Calculation: (x_ndc + 1.0) * 160
                    // 160 in Q16.16 = 32'h00A00000
                    x_screen <= mul_fix(x_ndc + 32'h00010000, 32'h00A00000); 

                    // Y Calculation: (y_ndc + 1.0) * 120
                    // 120 in Q16.16 = 32'h00780000
                    y_screen <= mul_fix(y_ndc + 32'h00010000, 32'h00780000);

                    // Note: 'x' and 'y' registers now hold Screen Coordinates in Q16.16 format.
                    // The integer part (x[31:16]) is the pixel location (0-319).
                    
                    // Done with this vertex. Go to next.
                    state <= S_VERTEX_FETCH;
                    // vertex_addr <= vertex_addr + 1;
                end
            endcase
        end
    
    end
    
endmodule
