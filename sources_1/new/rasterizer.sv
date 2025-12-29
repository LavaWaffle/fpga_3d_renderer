`timescale 1ns / 1ps

module rasterizer(
    input wire i_clk,
    input wire i_rst,

    // Triangle Input
    input wire        i_tri_valid,
    output reg        o_busy,
    input wire signed [15:0] i_x0, i_y0, i_x1, i_y1, i_x2, i_y2,
    input wire [7:0]         i_z0, i_z1, i_z2,
    input wire [31:0]        i_u0, i_v0, i_u1, i_v1, i_u2, i_v2,

    // Frame Buffer
    output reg [16:0] o_fb_addr,
    output reg        o_fb_we,
    output reg [11:0] o_fb_pixel,
    
    // Z-Buffer
    output reg [16:0] o_zb_addr,
    input  wire [7:0] i_zb_data,
    output reg        o_zb_we,
    output reg [7:0]  o_zb_data
);

    // =========================================================================
    // 1. Setup Phase: Bounding Box
    // =========================================================================
    reg signed [15:0] min_x, max_x, min_y, max_y;
    reg signed [15:0] cur_x, cur_y;

    // State Machine
    typedef enum {
        IDLE,
        SETUP_MATH,
        SETUP_DIV,
        TRAVERSAL
    } rast_state_t;
    
    rast_state_t state;
    
    // Divider
    reg start_div;
    reg signed [31:0] div_num, div_den;
    wire signed [31:0] div_res; // Result is 1.0 / Area (Q16.16)
    wire div_done;

                    logic signed [31:0] p_z, p_u, p_v, p_w;


    q16_16_div setup_div (
        .i_clk(i_clk), .i_rst(i_rst), .i_start(start_div), 
        .i_dividend(div_num), .i_divisor(div_den),
        .o_quotient(div_res), .o_done(div_done)
    );
    
    // Multiplier Helper (Q16.16)
    function signed [31:0] mul_fix(input signed [31:0] a, input signed [31:0] b);
        logic signed [63:0] temp;
        begin
            temp = a * b;
            mul_fix = temp >>> 16;
        end
    endfunction
    
    // Min/Max Helpers
    function signed [15:0] min3(input signed [15:0] a, b, c);
        min3 = (a < b) ? ((a < c) ? a : c) : ((b < c) ? b : c);
    endfunction
    function signed [15:0] max3(input signed [15:0] a, b, c);
        max3 = (a > b) ? ((a > c) ? a : c) : ((b > c) ? b : c);
    endfunction

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            state <= IDLE;
            o_busy <= 0;
            o_fb_we <= 0;
            o_zb_we <= 0;
        end else begin
            o_fb_we <= 0; 
            o_zb_we <= 0;

            case (state)
                IDLE: begin
                    if (i_tri_valid) begin
                        o_busy <= 1;
                        
                        // Clamp Bounding Box
                        min_x <= (min3(i_x0, i_x1, i_x2) < 0) ? 0 : min3(i_x0, i_x1, i_x2);
                        max_x <= (max3(i_x0, i_x1, i_x2) > 319) ? 319 : max3(i_x0, i_x1, i_x2);
                        min_y <= (min3(i_y0, i_y1, i_y2) < 0) ? 0 : min3(i_y0, i_y1, i_y2);
                        max_y <= (max3(i_y0, i_y1, i_y2) > 239) ? 239 : max3(i_y0, i_y1, i_y2);
                        
                        state <= SETUP_MATH;
                    end
                end

                SETUP_MATH: begin
                    // 1. Calculate Signed Area
                    // FIX 1: Swapped terms here to ensure Area sign matches Edge Function sign
                    // If your edge functions produce positive weights for inside pixels, 
                    // this area calculation must also be positive.
                    div_num <= 32'd1;
                    div_den <= (signed'(i_x2 - i_x0) * signed'(i_y1 - i_y0)) - 
                               (signed'(i_x1 - i_x0) * signed'(i_y2 - i_y0));
                    
                    start_div <= 1;
                    state <= SETUP_DIV;
                end

                SETUP_DIV: begin
                    start_div <= 0;
                    if (div_done) begin
                        // Initialize loop variables
                        cur_x <= min_x;
                        cur_y <= min_y;
                        state <= TRAVERSAL;
                    end
                end

                TRAVERSAL: begin
                    // =========================================================
                    // PIXEL LOOP
                    // =========================================================
                    logic signed [31:0] w0, w1, w2;
                    logic signed [63:0] sum_z, sum_u, sum_v;
                    logic [7:0] current_z_8bit;

                    o_zb_addr <= (cur_y * 320) + cur_x;
                    o_fb_addr <= (cur_y * 320) + cur_x;

                    // Calculate Weights (Edge Functions)
                    // w0 corresponds to Edge 0-1 (Opposite V2)
                    // w1 corresponds to Edge 1-2 (Opposite V0)
                    // w2 corresponds to Edge 2-0 (Opposite V1)
                    w0 = (cur_x - i_x0) * (i_y1 - i_y0) - (cur_y - i_y0) * (i_x1 - i_x0);
                    w1 = (cur_x - i_x1) * (i_y2 - i_y1) - (cur_y - i_y1) * (i_x2 - i_x1);
                    w2 = (cur_x - i_x2) * (i_y0 - i_y2) - (cur_y - i_y2) * (i_x0 - i_x2);

                    if (w0 >= 0 && w1 >= 0 && w2 >= 0) begin
                        
                        // FIX 2: Correct Weight Mapping
                        // w1 is the weight for Vertex 0
                        // w2 is the weight for Vertex 1
                        // w0 is the weight for Vertex 2
                        
                        // Z Interpolation
                        sum_z = (w1 * signed'({24'b0, i_z0})) + 
                                (w2 * signed'({24'b0, i_z1})) + 
                                (w0 * signed'({24'b0, i_z2}));
                        
                        p_z = (sum_z * div_res) >>> 16;
                        current_z_8bit = p_z[7:0]; 

                        // U Interpolation
                        sum_u = (w1 * i_u0) + (w2 * i_u1) + (w0 * i_u2);
                        p_u   = (sum_u * div_res) >>> 16;

                        // V Interpolation
                        sum_v = (w1 * i_v0) + (w2 * i_v1) + (w0 * i_v2);
                        p_v   = (sum_v * div_res) >>> 16;

                        if (current_z_8bit < i_zb_data) begin
                            logic [3:0] r_val, g_val, b_val;
                            
                            // Reconstruct W
                            p_w = 32'h00010000 - p_u - p_v;
                            
                            // Red Channel (U)
                            if (p_u[31]) r_val = 0;
                            else if (|p_u[30:16]) r_val = 4'hF;
                            else r_val = p_u[15:12];

                            // Green Channel (V)
                            if (p_v[31]) g_val = 0;
                            else if (|p_v[30:16]) g_val = 4'hF;
                            else g_val = p_v[15:12];

                            // Blue Channel (W)
                            if (p_w[31]) b_val = 0;
                            else if (|p_w[30:16]) b_val = 4'hF;
                            else b_val = p_w[15:12];
                            
                            o_fb_pixel <= {r_val, g_val, b_val}; 
                            o_fb_we    <= 1;
                            
                            o_zb_data  <= current_z_8bit;
                            o_zb_we    <= 1;
                        end
                    end

                    // Iterator Logic
                    if (cur_x < max_x) begin
                        cur_x <= cur_x + 1;
                    end else begin
                        cur_x <= min_x;
                        if (cur_y < max_y) begin
                            cur_y <= cur_y + 1;
                        end else begin
                            o_busy <= 0;
                            state <= IDLE;
                        end
                    end
                end
            endcase
        end
    end

endmodule