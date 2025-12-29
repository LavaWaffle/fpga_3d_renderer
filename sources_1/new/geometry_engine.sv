`timescale 1ns / 1ps

module geometry_engine (
    input i_clk,
    input i_rst,

    input wire       i_start,
    input wire       i_increment_frame,
    input wire       i_vertex_fifo_full,

    // OUTPUTS TO FIFO
    output reg        o_vertex_valid, 
    output reg [31:0] o_x, o_y,
    output reg [7:0]  o_z, 
    output reg [31:0] o_u, o_v 
);
    // Vertex Memory (Simple BRAM)
    reg  [9:0] vertex_addr_i;
    wire [31:0] vertex_data_i;
    
    simple_bram #(
        .DATA_WIDTH(32),
        .ADDR_WIDTH(10),
        .INIT_FILE("vertex_data.mem")  
    ) vertex_ram (
        .clk    (i_clk),
        .we     (1'b0),
        .addr   (vertex_addr_i),
        .wdata  (32'b0),
        .rdata  (vertex_data_i)
    );

    // Geometry Engine State Machine
    typedef enum {
        S_IDLE,
        S_VERTEX_FETCH,
        S_MATRIX_TRANSFORM,
        S_PERSP_DIVIDE,
        S_VIEWPORT_MAP
    } geom_engine_state_t;

    geom_engine_state_t state_i;

    // Vertex Attributes (from RAM)
    reg [31:0] x_local_i, y_local_i, z_local_i, u_local_i, v_local_i;
    reg [2:0] vertex_count_i;

    assign o_u = u_local_i;
    assign o_v = v_local_i;

    reg [3:0] mvp_frame_count_i;

   // ==========================================
    // ANIMATION DATA: 16 FRAMES
    // Access: MVP_FRAMES[frame_index][matrix_element_index]
    // ==========================================
    logic signed [31:0] MVP_FRAMES [0:15][0:15] = '{
        // Frame 0
        '{
            32'h0000C000, 32'h00000000, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00010000, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00000000, 32'hFFFEE50E, 32'h0008F286,
            32'h00000000, 32'h00000000, 32'hFFFF0000, 32'h000A0000
        },
        // Frame 1
        '{
            32'h0000B162, 32'h00000000, 32'h00004979, 32'h00000000,
            32'h00000000, 32'h00010000, 32'h00000000, 32'h00000000,
            32'h00006C47, 32'h00000000, 32'hFFFEFA98, 32'h0008F286,
            32'h000061F7, 32'h00000000, 32'hFFFF137D, 32'h000A0000
        },
        // Frame 2
        '{
            32'h000087C3, 32'h00000000, 32'h000087C3, 32'h00000000,
            32'h00000000, 32'h00010000, 32'h00000000, 32'h00000000,
            32'h0000C812, 32'h00000000, 32'hFFFF37EE, 32'h0008F286,
            32'h0000B504, 32'h00000000, 32'hFFFF4AFC, 32'h000A0000
        },
        // Frame 3
        '{
            32'h00004979, 32'h00000000, 32'h0000B162, 32'h00000000,
            32'h00000000, 32'h00010000, 32'h00000000, 32'h00000000,
            32'h00010568, 32'h00000000, 32'hFFFF93B9, 32'h0008F286,
            32'h0000EC83, 32'h00000000, 32'hFFFF9E09, 32'h000A0000
        },
        // Frame 4
        '{
            32'h00000000, 32'h00000000, 32'h0000C000, 32'h00000000,
            32'h00000000, 32'h00010000, 32'h00000000, 32'h00000000,
            32'h00011AF2, 32'h00000000, 32'h00000000, 32'h0008F286,
            32'h00010000, 32'h00000000, 32'h00000000, 32'h000A0000
        },
        // Frame 5
        '{
            32'hFFFFB687, 32'h00000000, 32'h0000B162, 32'h00000000,
            32'h00000000, 32'h00010000, 32'h00000000, 32'h00000000,
            32'h00010568, 32'h00000000, 32'h00006C47, 32'h0008F286,
            32'h0000EC83, 32'h00000000, 32'h000061F7, 32'h000A0000
        },
        // Frame 6
        '{
            32'hFFFF783D, 32'h00000000, 32'h000087C3, 32'h00000000,
            32'h00000000, 32'h00010000, 32'h00000000, 32'h00000000,
            32'h0000C812, 32'h00000000, 32'h0000C812, 32'h0008F286,
            32'h0000B504, 32'h00000000, 32'h0000B504, 32'h000A0000
        },
        // Frame 7
        '{
            32'hFFFF4E9E, 32'h00000000, 32'h00004979, 32'h00000000,
            32'h00000000, 32'h00010000, 32'h00000000, 32'h00000000,
            32'h00006C47, 32'h00000000, 32'h00010568, 32'h0008F286,
            32'h000061F7, 32'h00000000, 32'h0000EC83, 32'h000A0000
        },
        // Frame 8
        '{
            32'hFFFF4000, 32'h00000000, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00010000, 32'h00000000, 32'h00000000,
            32'h00000000, 32'h00000000, 32'h00011AF2, 32'h0008F286,
            32'h00000000, 32'h00000000, 32'h00010000, 32'h000A0000
        },
        // Frame 9
        '{
            32'hFFFF4E9E, 32'h00000000, 32'hFFFFB687, 32'h00000000,
            32'h00000000, 32'h00010000, 32'h00000000, 32'h00000000,
            32'hFFFF93B9, 32'h00000000, 32'h00010568, 32'h0008F286,
            32'hFFFF9E09, 32'h00000000, 32'h0000EC83, 32'h000A0000
        },
        // Frame 10
        '{
            32'hFFFF783D, 32'h00000000, 32'hFFFF783D, 32'h00000000,
            32'h00000000, 32'h00010000, 32'h00000000, 32'h00000000,
            32'hFFFF37EE, 32'h00000000, 32'h0000C812, 32'h0008F286,
            32'hFFFF4AFC, 32'h00000000, 32'h0000B504, 32'h000A0000
        },
        // Frame 11
        '{
            32'hFFFFB687, 32'h00000000, 32'hFFFF4E9E, 32'h00000000,
            32'h00000000, 32'h00010000, 32'h00000000, 32'h00000000,
            32'hFFFEFA98, 32'h00000000, 32'h00006C47, 32'h0008F286,
            32'hFFFF137D, 32'h00000000, 32'h000061F7, 32'h000A0000
        },
        // Frame 12
        '{
            32'h00000000, 32'h00000000, 32'hFFFF4000, 32'h00000000,
            32'h00000000, 32'h00010000, 32'h00000000, 32'h00000000,
            32'hFFFEE50E, 32'h00000000, 32'h00000000, 32'h0008F286,
            32'hFFFF0000, 32'h00000000, 32'h00000000, 32'h000A0000
        },
        // Frame 13
        '{
            32'h00004979, 32'h00000000, 32'hFFFF4E9E, 32'h00000000,
            32'h00000000, 32'h00010000, 32'h00000000, 32'h00000000,
            32'hFFFEFA98, 32'h00000000, 32'hFFFF93B9, 32'h0008F286,
            32'hFFFF137D, 32'h00000000, 32'hFFFF9E09, 32'h000A0000
        },
        // Frame 14
        '{
            32'h000087C3, 32'h00000000, 32'hFFFF783D, 32'h00000000,
            32'h00000000, 32'h00010000, 32'h00000000, 32'h00000000,
            32'hFFFF37EE, 32'h00000000, 32'hFFFF37EE, 32'h0008F286,
            32'hFFFF4AFC, 32'h00000000, 32'hFFFF4AFC, 32'h000A0000
        },
        // Frame 15
        '{
            32'h0000B162, 32'h00000000, 32'hFFFFB687, 32'h00000000,
            32'h00000000, 32'h00010000, 32'h00000000, 32'h00000000,
            32'hFFFF93B9, 32'h00000000, 32'hFFFEFA98, 32'h0008F286,
            32'hFFFF9E09, 32'h00000000, 32'hFFFF137D, 32'h000A0000
        }
    };
    
    logic signed [31:0] MVP_MATRIX [0:15];
    assign MVP_MATRIX = MVP_FRAMES[mvp_frame_count_i];
    
    reg signed [31:0] x_clip_i, y_clip_i, z_clip_i, w_clip_i;
    
    function signed [31:0] mul_fix(input signed [31:0] a, input signed [31:0] b);
        logic signed [63:0] temp;
        begin
            temp = a * b;
            mul_fix = temp >>> 16;
        end
    endfunction
    
    // Divider Instances for Perspective Divide
    reg start_div_i;
    wire signed [31:0] x_ndc_i, y_ndc_i, z_ndc_i;
    wire div_x_done_i, div_y_done_i, div_z_done_i;

    q16_16_div div_x_inst (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(start_div_i),
        .i_dividend(x_clip_i),
        .i_divisor(w_clip_i),
        .o_quotient(x_ndc_i),
        .o_done(div_x_done_i)
    );

    q16_16_div div_y_inst (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(start_div_i),
        .i_dividend(y_clip_i),
        .i_divisor(w_clip_i),
        .o_quotient(y_ndc_i),
        .o_done(div_y_done_i)
    );

    q16_16_div div_z_inst (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(start_div_i),
        .i_dividend(z_clip_i),
        .i_divisor(w_clip_i),
        .o_quotient(z_ndc_i),
        .o_done(div_z_done_i)
    );
    
    // Screen Space Coordinates 
    reg [31:0] x_screen, y_screen, z_screen;
    assign o_x = x_screen;
    assign o_y = y_screen;
    assign o_z = z_screen[23:16]; // 8-bit depth

    reg prev_increment_frame_i;

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            state_i <= S_IDLE;
            mvp_frame_count_i <= 0;
            vertex_addr_i <= 0;
            vertex_count_i <= 0;
            o_vertex_valid <= 0;
            x_local_i <= 0;
            y_local_i <= 0;
            z_local_i <= 0;
            u_local_i <= 0;
            v_local_i <= 0;
        end else begin
            // Default to invalid
            o_vertex_valid <= 0;
            prev_increment_frame_i <= i_increment_frame;

            case (state_i)
                S_IDLE: begin
                    // On falling edge of increment frame signal, increment frame count
                    if (prev_increment_frame_i && !i_increment_frame) begin
                        if (mvp_frame_count_i == 15) begin
                            mvp_frame_count_i <= 0;
                        end else begin 
                            mvp_frame_count_i <= mvp_frame_count_i + 1;
                        end
                    end
                    if (i_start && !i_vertex_fifo_full) begin
                        vertex_addr_i <= 0;
                        vertex_count_i <= 0;
                        state_i <= S_VERTEX_FETCH;
                    end
                end
                S_VERTEX_FETCH: begin
                    // Start at 1 to give clk cycle for RAM read
                    if (vertex_count_i == 1) x_local_i <= vertex_data_i;
                    else if (vertex_count_i == 2) y_local_i <= vertex_data_i;
                    else if (vertex_count_i == 3) z_local_i <= vertex_data_i;
                    else if (vertex_count_i == 4) u_local_i <= vertex_data_i;
                    else if (vertex_count_i == 5) begin
                        v_local_i <= vertex_data_i;
                        vertex_count_i <= 0;
                        
                        // Check for End of Stream Signal
                        if (
                            x_local_i == 32'hFFFFFFFF &&
                            y_local_i == 32'hFFFFFFFF &&
                            z_local_i == 32'hFFFFFFFF &&
                            u_local_i == 32'hFFFFFFFF &&
                            vertex_data_i == 32'hFFFFFFFF 
                        ) begin 
                            state_i <= S_IDLE;
                        end else begin 
                            state_i <= S_MATRIX_TRANSFORM;
                        end
                    end
    
                    // Handle Addressing
                    if (vertex_count_i != 5) begin
                        vertex_addr_i <= vertex_addr_i + 1;
                        vertex_count_i <= vertex_count_i + 1;
                    end
                end
                S_MATRIX_TRANSFORM: begin
                    // Perform 4 Dot Products in Parallel
                    // Row 0 calculates new X
                    x_clip_i <= mul_fix(MVP_MATRIX[0], x_local_i) + 
                             mul_fix(MVP_MATRIX[1], y_local_i) + 
                             mul_fix(MVP_MATRIX[2], z_local_i) + 
                             mul_fix(MVP_MATRIX[3], 32'h00010000); // W=1.0

                    // Row 1 calculates new Y
                    y_clip_i <= mul_fix(MVP_MATRIX[4], x_local_i) + 
                             mul_fix(MVP_MATRIX[5], y_local_i) + 
                             mul_fix(MVP_MATRIX[6], z_local_i) + 
                             mul_fix(MVP_MATRIX[7], 32'h00010000);

                    // Row 2 calculates new Z
                    z_clip_i <= mul_fix(MVP_MATRIX[8], x_local_i) + 
                             mul_fix(MVP_MATRIX[9], y_local_i) + 
                             mul_fix(MVP_MATRIX[10], z_local_i) + 
                             mul_fix(MVP_MATRIX[11], 32'h00010000);

                    // Row 3 calculates new W (Crucial for perspective!)
                    w_clip_i <= mul_fix(MVP_MATRIX[12], x_local_i) + 
                             mul_fix(MVP_MATRIX[13], y_local_i) + 
                             mul_fix(MVP_MATRIX[14], z_local_i) + 
                             mul_fix(MVP_MATRIX[15], 32'h00010000);

                    start_div_i <= 1; 
                    state_i <= S_PERSP_DIVIDE;
                end
                S_PERSP_DIVIDE: begin
                    start_div_i <= 0; // Clear start signal
                    
                    // Wait for both dividers to finish (~34 cycles)
                    if (div_x_done_i && div_y_done_i && div_z_done_i) begin
                        // Check Clipping (Simple Near Plane check)
                        // If W < Near_Plane (0.1 in fixed point ~ 6553), point is behind camera
                        if (w_clip_i < 32'h00001999) begin 
                            // Invalid! Skip to next vertex immediately
                            state_i <= S_VERTEX_FETCH;
                            // Note: You need logic to handle "partial" triangles later, 
                            // but for now we just drop bad vertices.
                        end else begin
                            // Valid! Move to Viewport Map
                            state_i <= S_VIEWPORT_MAP;
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
                    x_screen <= mul_fix(x_ndc_i + 32'h00010000, 32'h00A00000); 

                    // Y Calculation: (y_ndc + 1.0) * 120
                    // 120 in Q16.16 = 32'h00780000
                    y_screen <= mul_fix(y_ndc_i + 32'h00010000, 32'h00780000);
                    
                    // Note: 'x' and 'y' registers now hold Screen Coordinates in Q16.16 format.
                    // The integer part (x[31:16]) is the pixel location (0-319).

                    // Logic: (z_ndc + 1.0) * 127.5
                    // 127.5 in Q16.16 is 32'h007F8000
                    z_screen <= mul_fix(z_ndc_i + 32'h00010000, 32'h007F8000);
                    // [-1 to 1] maps to [0 to 255] for depth buffer

                    // Output valid vertex
                    o_vertex_valid <= 1;
                    // Done with this vertex. Go to next.
                    state_i <= S_VERTEX_FETCH;
                end
            endcase
        end
    
    end
    
endmodule
