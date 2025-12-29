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
    // 1. Setup Phase: Bounding Box & Gradients
    // =========================================================================
    reg signed [15:0] min_x, max_x, min_y, max_y;
    reg signed [15:0] cur_x, cur_y;

    // Fixed Point Gradients (Q16.16)
    reg signed [31:0] dz_dx, dz_dy;
    reg signed [31:0] du_dx, du_dy;
    reg signed [31:0] dv_dx, dv_dy;
    
    // Current Pixel Attributes (Accumulators)
    reg signed [31:0] p_z, p_u, p_v;      // Current Pixel values
    reg signed [31:0] row_z, row_u, row_v; // Start-of-Row values
    
    // Edge Functions
    reg signed [31:0] A01, A12, A20; // Y-steps
    reg signed [31:0] B01, B12, B20; // X-steps

    // State Machine
    typedef enum {
        IDLE,
        SETUP_MATH,
        SETUP_DIV,
        SETUP_GRADIENTS, // <--- New State for calculating slopes
        TRAVERSAL
    } rast_state_t;
    
    rast_state_t state;
    
    // Divider
    reg start_div;
    reg signed [31:0] div_num, div_den;
    wire signed [31:0] div_res; // Result is 1.0 / Area (Q2.32)
    wire div_done;

    signed_div_32 setup_div (
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
    
    function signed [31:0] mul_q30(input signed [31:0] a, input signed [31:0] b);
        logic signed [63:0] temp;
        begin
            temp = a * b;
            mul_q30 = temp >>> 30; // Shift down by 30 to restore Q2.30 format
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
                    // 1. Edge Constants (A = dY, B = -dX)
                    A01 <= i_y0 - i_y1; B01 <= i_x1 - i_x0;
                    A12 <= i_y1 - i_y2; B12 <= i_x2 - i_x1;
                    A20 <= i_y2 - i_y0; B20 <= i_x0 - i_x2;

                    // 2. Start Division (1.0 / Area)
                    div_num <= 32'd1 << 30;
                    div_den <=  (signed'(i_x1 - i_x0) * signed'(i_y2 - i_y0)) - 
                                (signed'(i_x2 - i_x0) * signed'(i_y1 - i_y0));
                    
                    start_div <= 1;
                    state <= SETUP_DIV;
                end

                SETUP_DIV: begin
                    start_div <= 0;
                    if (div_done) begin
                        state <= SETUP_GRADIENTS;
                    end
                end

                SETUP_GRADIENTS: begin
                    // ---------------------------------------------------------
                    // 1. Calculate Gradients (Slopes)
                    // ---------------------------------------------------------
                    // Formula: dAttr/dX = (Attr0*A12 + Attr1*A20 + Attr2*A01) / Area
                    
                    logic signed [31:0] z0_fix, z1_fix, z2_fix;
                    logic signed [31:0] start_dx, start_dy;
                    logic signed [31:0] gz_x, gz_y;
                    logic signed [31:0] gu_x, gu_y;
                    logic signed [31:0] gv_x, gv_y;

                    logic signed [63:0] dot_z, dot_u, dot_v;
                    
                    // Temporary variables for inputs
                    logic signed [31:0] z0_f, z1_f, z2_f;
                    logic signed [31:0] u0_f, u1_f, u2_f;
                    logic signed [31:0] v0_f, v1_f, v2_f;
                    
                    // Z Setup: Shift to [23:16] for Integer alignment
                    // FIXED: Was {16'b0, i_z0, 8'b0} -> This was wrong!
                    z0_f = {8'b0, i_z0, 16'b0}; 
                    z1_f = {8'b0, i_z1, 16'b0};
                    z2_f = {8'b0, i_z2, 16'b0};

                    // U/V Setup: Q2.30
                    u0_f = i_u0 <<< 30; 
                    u1_f = i_u1 <<< 30;
                    u2_f = i_u2 <<< 30;
                    
                    v0_f = i_v0 <<< 30;
                    v1_f = i_v1 <<< 30;
                    v2_f = i_v2 <<< 30;

                    // --- Z Gradient Calculation ---
                    // 1. Calculate Dot Product in 64-bit (Input * Edge)
                    dot_z = signed'(z0_f)*A12 + signed'(z1_f)*A20 + signed'(z2_f)*A01;
                    // 2. Multiply by 1/Area (div_res) and shift down Q2.30
                    // dot_z is approx Q16.16 * Integer = Q32.16
                    // div_res is Q2.30
                    // Result: Q34.46. We need Q16.16 (dz_dx).
                    // This multiplication is complex. Let's stick to mul_q30 logic but 64-bit.
                    // Actually, for Z (Q16.16), mul_q30 is too aggressive. 
                    // Let's use standard mul_fix logic (shift 16) for Z terms.
                    dz_dx <= (dot_z * div_res) >>> 30; // Treat div_res as the scaler
                    dz_dy <= (signed'(signed'(z0_f)*B12 + signed'(z1_f)*B20 + signed'(z2_f)*B01) * div_res) >>> 30;

                    // --- U/V Gradient Calculation (The Critical Fix) ---
                    // 1. Dot Product in 64-bit
                    dot_u = signed'(u0_f)*A12 + signed'(u1_f)*A20 + signed'(u2_f)*A01;
                    dot_v = signed'(v0_f)*A12 + signed'(v1_f)*A20 + signed'(v2_f)*A01;
                    
                    // 2. Multiply by Inverse Area (div_res is Q2.30)
                    // dot_u is Q2.30 * Integer = Q32.30 (Massive!)
                    // div_res is Q2.30
                    // Result = Q34.60. 
                    // To get Q2.30 result, we shift right by 30.
                    du_dx <= (dot_u * div_res) >>> 30; 
                    
                    dot_u = signed'(u0_f)*B12 + signed'(u1_f)*B20 + signed'(u2_f)*B01;
                    du_dy <= (dot_u * div_res) >>> 30;

                    dv_dx <= (dot_v * div_res) >>> 30;
                    dot_v = signed'(v0_f)*B12 + signed'(v1_f)*B20 + signed'(v2_f)*B01;
                    dv_dy <= (dot_v * div_res) >>> 30;

                    // ---------------------------------------------------------
                    // 2. Calculate Start Values
                    // ---------------------------------------------------------
                    
                    start_dx = signed'(min_x - i_x0) <<< 16; 
                    start_dy = signed'(min_y - i_y0) <<< 16;

                    // Recalculate slopes locally for immediate use (Copy logic from above)
                    // Note: We can rely on the registers dz_dx etc in TRAVERSAL, 
                    // but for 'row_z' init, we need the values NOW.
                    
                    // Simplify: Use the 'dot' logic again implies huge combinatorial logic.
                    // Optimization: Wait 1 clock cycle? 
                    // For now, let's just copy the 64-bit logic to be safe.
                    
                    // Z Slopes
                    dot_z = signed'(z0_f)*A12 + signed'(z1_f)*A20 + signed'(z2_f)*A01;
                    gz_x = (dot_z * div_res) >>> 30;
                    dot_z = signed'(z0_f)*B12 + signed'(z1_f)*B20 + signed'(z2_f)*B01;
                    gz_y = (dot_z * div_res) >>> 30;
                    
                    row_z <= z0_f + mul_fix(gz_x, start_dx) + mul_fix(gz_y, start_dy);
                    p_z   <= z0_f + mul_fix(gz_x, start_dx) + mul_fix(gz_y, start_dy);

                    // U Slopes
                    dot_u = signed'(u0_f)*A12 + signed'(u1_f)*A20 + signed'(u2_f)*A01;
                    gu_x = (dot_u * div_res) >>> 30;
                    dot_u = signed'(u0_f)*B12 + signed'(u1_f)*B20 + signed'(u2_f)*B01;
                    gu_y = (dot_u * div_res) >>> 30;
                    
                    // Apply Slope (Slope is Q2.30, Dist is Q16.16)
                    // mul_fix shifts by 16. Q2.30 * Q16.16 >> 16 = Q2.30. Correct.
                    row_u <= u0_f + mul_fix(gu_x, start_dx) + mul_fix(gu_y, start_dy);
                    p_u   <= u0_f + mul_fix(gu_x, start_dx) + mul_fix(gu_y, start_dy);

                    // V Slopes
                    dot_v = signed'(v0_f)*A12 + signed'(v1_f)*A20 + signed'(v2_f)*A01;
                    gv_x = (dot_v * div_res) >>> 30;
                    dot_v = signed'(v0_f)*B12 + signed'(v1_f)*B20 + signed'(v2_f)*B01;
                    gv_y = (dot_v * div_res) >>> 30;

                    row_v <= v0_f + mul_fix(gv_x, start_dx) + mul_fix(gv_y, start_dy);
                    p_v   <= v0_f + mul_fix(gv_x, start_dx) + mul_fix(gv_y, start_dy);

                    // Setup Loop
                    cur_x <= min_x;
                    cur_y <= min_y;
                    
                    state <= TRAVERSAL;
                end

                TRAVERSAL: begin
                    // =========================================================
                    // 3. PIXEL LOOP
                    // =========================================================
                    logic signed [31:0] w0, w1, w2;
                    // Set Address for THIS pixel
                    o_zb_addr <= (cur_y * 320) + cur_x;
                    o_fb_addr <= (cur_y * 320) + cur_x;

                    // "Inside" Check (Barycentric)
                    
                    w0 = (cur_x - i_x0) * (i_y1 - i_y0) - (cur_y - i_y0) * (i_x1 - i_x0);
                    w1 = (cur_x - i_x1) * (i_y2 - i_y1) - (cur_y - i_y1) * (i_x2 - i_x1);
                    w2 = (cur_x - i_x2) * (i_y0 - i_y2) - (cur_y - i_y2) * (i_x0 - i_x2);

                    if (w0 >= 0 && w1 >= 0 && w2 >= 0) begin
                        // Z-TEST
                        // Compare current calculated Z (p_z) vs Z-Buffer (i_zb_data)
                        // Note: p_z is Q16.16 (scaled). We need top 8 bits [23:16] approx.
                        // Or since we shifted input by 8, take [23:16]?
                        // Input was 8 bit -> shifted 8 bits -> Q8.16 essentially.
                        // So integer part is bits [23:16].
                        logic [7:0] current_z_8bit;
                        current_z_8bit = (p_z < 0) ? 0 : p_z[23:16]; // Clamp
                        
                        // Check: Is new pixel closer? (Smaller Z is closer usually 0..255)
                        if (current_z_8bit < i_zb_data) begin
                            logic [3:0] r_val, g_val, b_val;
                            logic signed [31:0] p_w;
                            
                            p_w = 32'h40000000 - p_u - p_v; // Q2.30 W = 1.0 - U - V
                            
                            if (p_u[31]) begin                 // Negative?
                                r_val = 0;
                            end else if (p_u[30]) begin        // Integer bit set? (>= 1.0)
                                r_val = 4'hF;                  // Clamp to Max
                            end else begin
                                r_val = p_u[29:26];            // Take top 4 fraction bits
                            end

                            // 2. Green Channel (from V)
                            if (p_v[31]) begin
                                g_val = 0;
                            end else if (p_v[30]) begin
                                g_val = 4'hF;
                            end else begin
                                g_val = p_v[29:26];
                            end

                            // 3. Blue Channel (from W)
                            if (p_w[31]) begin
                                b_val = 0;
                            end else if (p_w[30]) begin
                                b_val = 4'hF;
                            end else begin
                                b_val = p_w[29:26];
                            end
                            
                            // Write Gradient Pixel
                            o_fb_pixel <= {r_val, g_val, b_val}; 
                            o_fb_we    <= 1;
                            
                            o_zb_data  <= current_z_8bit;
                            o_zb_we    <= 1;
                        end
                    end

                    // Iterator Logic
                    if (cur_x < max_x) begin
                        cur_x <= cur_x + 1;
                        p_z   <= p_z + dz_dx; // Step Z
                        p_u   <= p_u + du_dx; // Step U 
                        p_v   <= p_v + dv_dx; // Step V 
                        // Step U/V here too
                    end else begin
                        cur_x <= min_x;
                        
                        // Row Step
                        if (cur_y < max_y) begin
                            cur_y <= cur_y + 1;

                            // Step Row Start Values (Y-Gradient)
                            row_z <= row_z + dz_dy;
                            row_u <= row_u + du_dy;
                            row_v <= row_v + dv_dy; 
                            
                            // Reset Pixel Values to start of new row
                            p_z   <= row_z + dz_dy;
                            p_u   <= row_u + du_dy;
                            p_v   <= row_v + dv_dy;
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