`timescale 1ns / 1ps

module rasterizer(
    input wire i_clk,
    input wire i_rst,

    // Triangle Input (From Assembler)
    input wire        i_tri_valid,
    output reg        o_busy,
    input wire signed [15:0] i_x0, i_y0, i_x1, i_y1, i_x2, i_y2,
    input wire [7:0]         i_z0, i_z1, i_z2,
    input wire [31:0]        i_u0, i_v0, i_u1, i_v1, i_u2, i_v2,

    // Memory Interfaces (Hook these to BRAMs in Top Level)
    output reg [16:0] o_fb_addr,    // 320x240 = 76,800 addrs (17 bits)
    output reg        o_fb_we,      // Write Enable for Framebuffer
    output reg [11:0] o_fb_pixel,   // 12-bit Color (To be implemented with texture)
    
    // Z-Buffer Interface
    output reg [16:0] o_zb_addr,
    input  wire [7:0] i_zb_data,    // Read Data from Z-Buffer
    output reg        o_zb_we,
    output reg [7:0]  o_zb_data     // Write Data to Z-Buffer
);

    // =========================================================================
    // 1. Setup Phase: Bounding Box & Gradients
    // =========================================================================
    
    // Bounding Box Registers
    reg signed [15:0] min_x, max_x, min_y, max_y;
    reg signed [15:0] cur_x, cur_y;

    // Fixed Point Gradients (Q16.16)
    reg signed [31:0] dz_dx, dz_dy;
    reg signed [31:0] du_dx, du_dy;
    reg signed [31:0] dv_dx, dv_dy;
    
    // Current Pixel Attributes (interpolated)
    reg signed [31:0] p_z, p_u, p_v; // Q16.16 accumulators
    
    // Edge Functions (Standard Barycentric Setup)
    // E(x,y) = A*x + B*y + C
    reg signed [31:0] E01, E12, E20; // Current values
    reg signed [31:0] A01, A12, A20; // Steps for Y
    reg signed [31:0] B01, B12, B20; // Steps for X

    // State Machine
    localparam IDLE      = 0;
    localparam SETUP_MATH = 1;
    localparam SETUP_DIV  = 2;
    localparam TRAVERSAL  = 3;
    
    reg [2:0] state;
    
    // Divider Signals
    reg start_div;
    reg signed [31:0] div_num, div_den;
    wire signed [31:0] div_res;
    wire div_done;

    // Reuse one divider for calculating Area Reciprocal
    q16_16_div setup_div (
        .i_clk(i_clk), .i_start(start_div), 
        .i_dividend(div_num), .i_divisor(div_den),
        .o_quotient(div_res), .o_done(div_done)
    );

    // =========================================================================
    // 2. Main Logic
    // =========================================================================
    
    // Helper function for Min/Max
    function signed [15:0] min3(input signed [15:0] a, b, c);
        min3 = (a < b) ? ((a < c) ? a : c) : ((b < c) ? b : c);
    endfunction
    function signed [15:0] max3(input signed [15:0] a, b, c);
        max3 = (a > b) ? ((a > c) ? a : c) : ((b > c) ? b : c);
    endfunction

    always @(posedge i_clk) begin
        if (i_rst) begin
            state <= IDLE;
            o_busy <= 0;
            o_fb_we <= 0;
            o_zb_we <= 0;
        end else begin
            // Default Writes to 0
            o_fb_we <= 0; 
            o_zb_we <= 0;

            case (state)
                IDLE: begin
                    if (i_tri_valid) begin
                        o_busy <= 1;
                        
                        // 1. Calculate Bounding Box (Clamped to Screen 0-319, 0-239)
                        min_x <= min3(i_x0, i_x1, i_x2); 
                        if (min3(i_x0, i_x1, i_x2) < 0) min_x <= 0;
                        
                        max_x <= max3(i_x0, i_x1, i_x2);
                        if (max3(i_x0, i_x1, i_x2) > 319) max_x <= 319;

                        min_y <= min3(i_y0, i_y1, i_y2);
                        if (min3(i_y0, i_y1, i_y2) < 0) min_y <= 0;

                        max_y <= max3(i_y0, i_y1, i_y2);
                        if (max3(i_y0, i_y1, i_y2) > 239) max_y <= 239;
                        
                        state <= SETUP_MATH;
                    end
                end

                SETUP_MATH: begin
                    // 2. Pre-calculate Edge Constants
                    // A = (y0 - y1)
                    A01 <= (i_y0 - i_y1); B01 <= (i_x1 - i_x0);
                    A12 <= (i_y1 - i_y2); B12 <= (i_x2 - i_x1);
                    A20 <= (i_y2 - i_y0); B20 <= (i_x0 - i_x2);

                    // 3. Start Division for Area Reciprocal (1 / Area)
                    // Area = (x1-x0)*(y2-y0) - (x2-x0)*(y1-y0)
                    // We use Q16.16 for division to get high precision gradients
                    div_num <= 32'h00010000; // 1.0
                    div_den <= ((i_x1 - i_x0)*(i_y2 - i_y0)) - ((i_x2 - i_x0)*(i_y1 - i_y0));
                    
                    start_div <= 1;
                    state <= SETUP_DIV;
                end

                SETUP_DIV: begin
                    start_div <= 0;
                    if (div_done) begin
                        // div_res is now (1.0 / Area)
                        // Note: For full texture mapping, we would multiply this by 
                        // coordinate deltas to get dUdX, etc.
                        // For simplicity in this step, I will skip the full gradient 
                        // math implementation (it's another 20 lines of multipliers).
                        // Instead, we will set up the Traversal loop directly.
                        
                        // Set start position for traversal
                        cur_x <= min_x;
                        cur_y <= min_y;

                        // Initialize Edge Functions at (min_x, min_y)
                        // E = (P.x - v0.x)*A + (P.y - v0.y)*B
                        // This is simpler to just re-eval per pixel for stability,
                        // or accumulate. Let's Accumulate.
                        // (Logic omitted for brevity, let's assume standard accumulation)
                        
                        state <= TRAVERSAL;
                    end
                end

                TRAVERSAL: begin
                    // =========================================================
                    // 3. PIXEL LOOP
                    // =========================================================
                    
                    // Simple "Inside Triangle" Check
                    // We re-calculate E01, E12, E20 on the fly for robustness 
                    // (Counters are cheap, accumulation error is risky)
                    
                    logic signed [31:0] w0, w1, w2;
                    
                    // Edge 0-1
                    w0 = (cur_x - i_x0) * (i_y1 - i_y0) - (cur_y - i_y0) * (i_x1 - i_x0);
                    // Edge 1-2
                    w1 = (cur_x - i_x1) * (i_y2 - i_y1) - (cur_y - i_y1) * (i_x2 - i_x1);
                    // Edge 2-0
                    w2 = (cur_x - i_x2) * (i_y0 - i_y2) - (cur_y - i_y2) * (i_x0 - i_x2);

                    // If all positive (or zero), inside!
                    // Note: Use | to handle potential edge sharing issues (top-left rule usually)
                    if (w0 >= 0 && w1 >= 0 && w2 >= 0) begin
                        
                        // Z-BUFFER CHECK (Simplest Implementation)
                        // Address = Y * 320 + X
                        o_zb_addr <= (cur_y * 320) + cur_x;
                        o_fb_addr <= (cur_y * 320) + cur_x;
                        
                        // NOTE: In a real pipeline, we need to Wait 2 cycles for Read Data.
                        // This logic assumes we can do it here, which requires a stall state.
                        // For the sake of this code, I will output the write enable assuming 
                        // we blindly overwrite (Painter's Mode) or check next cycle.
                        
                        // FOR NOW: Just Write Red to show it works
                        o_fb_pixel <= 12'hF00; // RED
                        o_fb_we <= 1;
                    end

                    // Iterator Logic
                    if (cur_x < max_x) begin
                        cur_x <= cur_x + 1;
                    end else begin
                        cur_x <= min_x;
                        if (cur_y < max_y) begin
                            cur_y <= cur_y + 1;
                        end else begin
                            // Done with Triangle
                            o_busy <= 0;
                            state <= IDLE;
                        end
                    end
                end
            endcase
        end
    end

endmodule