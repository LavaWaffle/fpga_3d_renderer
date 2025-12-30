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
    output wire [16:0] o_fb_addr,
    output wire        o_fb_we,
    output wire [11:0] o_fb_pixel,
    
    // Z-Buffer
    output wire [16:0] o_zb_r_addr,
    input  wire [7:0]  i_zb_r_data,
    output wire [16:0] o_zb_w_addr,
    output wire        o_zb_w_we,
    output wire [7:0]  o_zb_w_data
);

    // Internal Latches
    reg signed [15:0] x0_i, y0_i, x1_i, y1_i, x2_i, y2_i;
    reg [7:0]         z0_i, z1_i, z2_i;
    reg [31:0]        u0_i, v0_i, u1_i, v1_i, u2_i, v2_i;

    // =========================================================================
    // 1. Internal Signals & Setup Logic
    // =========================================================================
    
    // State Machine
    typedef enum {
        IDLE,
        SETUP_MATH,
        SETUP_DIV,
        RASTER_RUN,
        RASTER_FLUSH
    } rast_state_t;
    
    rast_state_t state;
    
    // Setup Registers
    reg signed [15:0] min_x, max_x, min_y, max_y;
    reg signed [31:0] div_num, div_den;
    reg start_div;
    wire signed [31:0] div_res;
    wire div_done;
    
    // Pipeline Control
    reg iter_start;
    wire iter_done;
    reg [2:0] flush_count; // Wait for pipeline to empty

    // Helper Functions
    function signed [15:0] min3(input signed [15:0] a, b, c);
        min3 = (a < b) ? ((a < c) ? a : c) : ((b < c) ? b : c);
    endfunction
    function signed [15:0] max3(input signed [15:0] a, b, c);
        max3 = (a > b) ? ((a > c) ? a : c) : ((b > c) ? b : c);
    endfunction

    // =========================================================================
    // 2. Setup Phase Logic
    // =========================================================================
    
    // Divider Instance
    q2_30_div setup_div (
        .i_clk(i_clk), .i_rst(i_rst), .i_start(start_div), 
        .i_dividend(div_num), .i_divisor(div_den),
        .o_quotient(div_res), .o_done(div_done)
    );

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            state <= IDLE;
            o_busy <= 0;
            iter_start <= 0;
            flush_count <= 0;
            start_div <= 0;
            x0_i <= 0; y0_i <= 0; x1_i <= 0; y1_i <= 0; x2_i <= 0; y2_i <= 0;
            z0_i <= 0; z1_i <= 0; z2_i <= 0;
            u0_i <= 0; v0_i <= 0; u1_i <= 0; v1_i <= 0; u2_i <= 0; v2_i <= 0;
        end else begin
            // Default Pulses
            iter_start <= 0;

            case (state)
                IDLE: begin
                    if (i_tri_valid) begin
                        o_busy <= 1;
                        
                        // Clamp Bounding Box
                        min_x <= (min3(i_x0, i_x1, i_x2) < 0) ? 0 : min3(i_x0, i_x1, i_x2);
                        max_x <= (max3(i_x0, i_x1, i_x2) > 319) ? 319 : max3(i_x0, i_x1, i_x2);
                        min_y <= (min3(i_y0, i_y1, i_y2) < 0) ? 0 : min3(i_y0, i_y1, i_y2);
                        max_y <= (max3(i_y0, i_y1, i_y2) > 239) ? 239 : max3(i_y0, i_y1, i_y2);

                        x0_i <= i_x0; y0_i <= i_y0; x1_i <= i_x1; y1_i <= i_y1; x2_i <= i_x2; y2_i <= i_y2;
                        z0_i <= i_z0; z1_i <= i_z1; z2_i <= i_z2;
                        u0_i <= i_u0; v0_i <= i_v0; u1_i <= i_u1; v1_i <= i_v1; u2_i <= i_u2; v2_i <= i_v2;

                        state <= SETUP_MATH;
                    end
                end

                SETUP_MATH: begin
                    // Calculate Signed Area (for Divider)
                    div_num <= 32'd1;
                    div_den <= ( signed'(32'(x2_i) - 32'(x0_i)) * signed'(32'(y1_i) - 32'(y0_i)) ) - 
                               ( signed'(32'(x1_i) - 32'(x0_i)) * signed'(32'(y2_i) - 32'(y0_i)) );
                    
                    start_div <= 1;
                    state <= SETUP_DIV;
                end

                SETUP_DIV: begin
                    start_div <= 0; 
                    if (div_done) begin
                        // Divider finished, start the Pipeline!
                        iter_start <= 1; 
                        state <= RASTER_RUN;
                    end
                end

                RASTER_RUN: begin
                    // Wait for the Iterator to say "I have generated the last pixel"
                    if (iter_done) begin
                        flush_count <= 5; // Increased flush count due to deeper pipeline
                        state <= RASTER_FLUSH;
                    end
                end

                RASTER_FLUSH: begin
                    if (flush_count > 0) begin
                        flush_count <= flush_count - 1;
                    end else begin
                        o_busy <= 0;
                        state <= IDLE;
                    end
                end
            endcase
        end
    end

    // =========================================================================
    // 3. The Pipeline Interconnects
    // =========================================================================
    
    // --- Stage 1 -> Stage 2 Wires ---
    wire signed [15:0] s1_x, s1_y;
    wire s1_valid;
    wire [16:0] s1_zb_addr_gen; // The read address generated by Iterator

    // --- Stage 2 -> Stage 3 Wires ---
    wire signed [31:0] s2_w0, s2_w1, s2_w2;
    wire s2_inside, s2_valid;

    // --- Stage 3 -> Stage 3.5 Wires ---
    wire signed [31:0] s3_p_z, s3_p_u, s3_p_v;
    wire s3_inside, s3_valid;
    
    // --- Stage 3.5 -> Stage 4 Wires ---
    // These are the signals DELAYED while we waited for Texture RAM
    reg signed [31:0] s3_p_z_d1;
    reg s3_inside_d1, s3_valid_d1;
    wire [11:0] tex_data_out; // Data coming out of Texture ROM

    // =========================================================================
    // 4. Pipeline Instantiation
    // =========================================================================

    // --- Stage 1: Iterator ---
    pixel_iterator stage1_iter (
        .i_clk(i_clk), .i_rst(i_rst),
        .i_start(iter_start), .o_done(iter_done),
        .i_min_x(min_x), .i_max_x(max_x),
        .i_min_y(min_y), .i_max_y(max_y),
        .o_x(s1_x), .o_y(s1_y), .o_valid(s1_valid),
        .o_zb_addr(s1_zb_addr_gen) // Initiates Read
    );
    
    // Connect Iterator Output directly to ZB Read Port
    assign o_zb_r_addr = s1_zb_addr_gen; 

    // --- Stage 2: Edge Engine ---
    edge_engine stage2_edge (
        .i_clk(i_clk), .i_rst(i_rst),
        .i_x0(x0_i), .i_y0(y0_i), .i_x1(x1_i), .i_y1(y1_i), .i_x2(x2_i), .i_y2(y2_i),
        .i_p_x(s1_x), .i_p_y(s1_y), .i_valid(s1_valid),
        .o_w0(s2_w0), .o_w1(s2_w1), .o_w2(s2_w2),
        .o_inside(s2_inside), .o_valid(s2_valid)
    );

    // --- Stage 3: Interpolator ---
    interpolator stage3_interp (
        .i_clk(i_clk), .i_rst(i_rst),
        .i_inv_area(div_res),
        .i_z0(z0_i), .i_z1(z1_i), .i_z2(z2_i),
        .i_u0(u0_i), .i_u1(u1_i), .i_u2(u2_i),
        .i_v0(v0_i), .i_v1(v1_i), .i_v2(v2_i),
        .i_w0(s2_w0), .i_w1(s2_w1), .i_w2(s2_w2),
        .i_inside(s2_inside), .i_valid(s2_valid),
        .o_p_z(s3_p_z), .o_p_u(s3_p_u), .o_p_v(s3_p_v),
        .o_inside(s3_inside), .o_valid(s3_valid)
    );
    
    // =========================================================================
    // Stage 3.5: Texture Read & Delay Alignment
    // =========================================================================
    
    // 1. Calculate Texture Address (Combinational)
    // Map Q16.16 U/V to 0-63 (6 bits). 
    // We take bits [15:10] of the integer/fraction boundary.
    wire [11:0] tex_addr = { s3_p_v[15:10], s3_p_u[15:10] };
    
    // 2. Instantiate Texture ROM
    texture_rom tex_rom_inst (
        .i_clk(i_clk),
        .i_addr(tex_addr),  
        .o_data(tex_data_out) // Goes to Shader
    );

    // =========================================================================
    // 5. The Delay Line (Timing Alignment)
    // =========================================================================
    // Old Chain: s1 -> addr_d1 -> addr_d2 -> addr_d3 (Target: Shader)
    // New Chain: s1 -> d1 -> d2 -> d3 -> d4 (Target: Shader)
    // We need 1 extra cycle because of the Texture Read Latency
    
    reg [16:0] addr_d1, addr_d2, addr_d3, addr_d4;
    reg [7:0]  zb_data_d1, zb_data_d2;

    always_ff @(posedge i_clk) begin
        // --- 1. Delay Address (Cycle 1 -> Cycle 4) ---
        addr_d1 <= s1_zb_addr_gen;
        addr_d2 <= addr_d1;
        addr_d3 <= addr_d2; 
        addr_d4 <= addr_d3; // <--- To Shader (Matches Texture Data arrival)

        // --- 2. Delay Z-Buffer Read Data (Cycle 2 -> Cycle 4) ---
        // Z-Buffer Read Issued at T0. Data Arrives at T1 (available at i_zb_r_data).
        // Texture Read Issued at T2. Data Arrives at T3.
        // We need to hold Z-buffer data until T3.
        zb_data_d1 <= i_zb_r_data; 
        zb_data_d2 <= zb_data_d1; // <--- To Shader

        // --- 3. Pipeline Interpolator Outputs (Wait for Texture) ---
        // Interpolator finishes at T2.
        // Texture Data ready at T3.
        s3_p_z_d1    <= s3_p_z;
        s3_inside_d1 <= s3_inside;
        s3_valid_d1  <= s3_valid;
    end

    // --- Stage 4: Fragment Shader ---
    fragment_shader stage4_shader (
        .i_clk(i_clk), .i_rst(i_rst),
        
        // NEW: Connect delayed signals (from Stage 3.5)
        .i_p_z(s3_p_z_d1), 
        .i_inside(s3_inside_d1), 
        .i_valid(s3_valid_d1),
        
        // NEW: Texture Input
        .i_tex_pixel(tex_data_out), 

        // Inputs from Delay Line
        .i_pixel_addr(addr_d2), 
        .i_zb_cur_val(zb_data_d1),

        // Outputs
        .o_fb_addr(o_fb_addr),
        .o_fb_we(o_fb_we),
        .o_fb_pixel(o_fb_pixel),
        .o_zb_w_addr(o_zb_w_addr),
        .o_zb_w_we(o_zb_w_we),
        .o_zb_w_new_val(o_zb_w_data)
    );

endmodule