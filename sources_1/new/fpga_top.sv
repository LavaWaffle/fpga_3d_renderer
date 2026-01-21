`timescale 1ns / 1ps

module fpga_top #(
    parameter PIXEL_RESET_COUNT = 76800,
    parameter SKIP_VGA_MODULE = 0
)(
    input wire clk,

    // Basic I/O
    input wire [3:0] btn,
    input logic [15:0] sw_i,
    output reg [15:0] led,
    
    //HEX displays
    output logic [7:0] hex_segA,
    output logic [3:0] hex_gridA,
    output logic [7:0] hex_segB,
    output logic [3:0] hex_gridB,

    //HDMI
    output logic hdmi_tmds_clk_n,
    output logic hdmi_tmds_clk_p,
    output logic [2:0]hdmi_tmds_data_n,
    output logic [2:0]hdmi_tmds_data_p

);

    // Input debouncing
    wire [3:0] btn_sync;
    sync_debounce button_sync [3:0] (
        .clk (clk),
        .d   (btn),
        .q   (btn_sync)
    );

    wire [15:0] switch;
    sync_flop sw_sync [15:0] (
        .clk	(clk),
        .d		(sw_i),
    
        .q		(switch)
    );	

    // Main Btn Inputs
    wire rst = btn_sync[0];
    wire pause = btn_sync[1];
    reg prev_pause;
    reg pause_reg;
    assign led[14] = pause_reg;
    assign led[15] = rst;


    wire strb_60, strb_30, strb_15, strb_10, strb_5, strb_1;
    refresh_strobes #(
        .CLK_HZ(100_000_000)
    ) refresh_strobes_inst (
        .clk(clk),
        .rst(rst),
        .strb_60(strb_60),
        .strb_30(strb_30),
        .strb_15(strb_15),
        .strb_10(strb_10),
        .strb_5(strb_5),
        .strb_1(strb_1)
    );
    
    // Priority Mux for frame strobe based on switches
    wire frame_strobe = 
        (switch[0] == 1'b1) ? strb_1 :
        (switch[1] == 1'b1) ? strb_5 :
        (switch[2] == 1'b1) ? strb_10 :
        (switch[3] == 1'b1) ? strb_15 :
        (switch[4] == 1'b1) ? strb_30 :
                             strb_60 ;

    wire stretch_frame_strobe;
    strobe_stretcher #(
        .CLK_HZ(100_000_000),
        .STRETCH_MS(1)
    ) frame_strobe_stretcher (
        .clk(clk),
        .rst(rst),
        .strobe_in(frame_strobe),
        .stretched_out(stretch_frame_strobe)
    );

    assign led[10] = stretch_frame_strobe;

    wire [5:0] current_frame = gem_engine.mvp_frame_count_i[5:0];

    hex_driver frame_display (
        .clk(clk),
        .reset(rst),
        .in({4'b0, 4'b0, {2'b0, current_frame[5:4]}, current_frame[3:0]}), // Display frame count in hex
        .hex_seg(hex_segB),
        .hex_grid(hex_gridB)
    );

    typedef enum {
        T_INIT_RST_BUFFERS,
        T_CLEAR_IDLE,
        T_CLR_BUFFERS,
        T_RENDER_IDLE,
        T_RENDERING
    } top_state_t;

    top_state_t top_state;
    reg render_modules_enabled;
    reg [16:0] fb_zb_reset_addr;
    reg [3:0] min_rendering_time;

    hex_driver state_display (
        .clk(clk),
        .reset(rst),
        .in({4'b0, 4'b0, 4'b0, top_state[3:0]}), 
        .hex_seg(hex_segA),
        .hex_grid(hex_gridA)
    );
    
    // Debug Signals
    reg start_rendering_frame;
    wire start_rendering_frame_stretched;
    reg increment_frame; 
    wire increment_frame_stretched;
    
    strobe_stretcher #(
        .CLK_HZ(100_000_000),
        .STRETCH_MS(5)
    ) start_rendering_frame_stretcher (
        .clk(clk),
        .rst(rst),
        .strobe_in(start_rendering_frame),
        .stretched_out(start_rendering_frame_stretched)
    );

    strobe_stretcher #(
        .CLK_HZ(100_000_000),
        .STRETCH_MS(5)
    ) increment_frame_stretcher (
        .clk(clk),
        .rst(rst),
        .strobe_in(increment_frame),
        .stretched_out(increment_frame_stretched)
    );

    assign led[12] = start_rendering_frame_stretched;
    assign led[13] = increment_frame_stretched;

    always_ff @(posedge clk) begin
        led[0] <= 1'b0;
        led[1] <= 1'b0;
        led[2] <= 1'b0;
        led[3] <= 1'b0;
        prev_pause <= pause;
        if (rst) begin
//            state <= skip_reset_buffers ? T_IDLE : T_RESETING_BUFFERS;
            top_state <= T_INIT_RST_BUFFERS;
            render_modules_enabled <= 0;
            fb_zb_reset_addr <= 0;
            min_rendering_time <= 0;
            pause_reg <= 0;
        end else begin
            // Latch pause button
            if (pause && !prev_pause) begin
                pause_reg <= ~pause_reg;
            end
            
            start_rendering_frame <= 0;
            render_modules_enabled <= 0;
            increment_frame <= 0;

            case (top_state)
                T_INIT_RST_BUFFERS: begin
                    render_modules_enabled <= 0;

                    if (fb_zb_reset_addr == PIXEL_RESET_COUNT - 1) begin
                        top_state <= T_CLEAR_IDLE;
                    end else begin
                        fb_zb_reset_addr <= fb_zb_reset_addr + 1;
                    end
                end

                // Clear previous frame's data before rendering a new one
                T_CLEAR_IDLE: begin
                    led[3] <= 1'b1;

                    // In simulation, proceed immediately for faster testing
                    `ifdef SYNTHESIS
                    if (frame_strobe && !pause_reg) 
                    `else
                    if (!pause_reg)
                    `endif
                    begin
                        top_state <= T_CLR_BUFFERS;
                        render_modules_enabled <= 1;
                        start_rendering_frame <= 1;
                        min_rendering_time <= 0;
                    end
                end
                T_CLR_BUFFERS: begin
                    render_modules_enabled <= 1;
                    if (min_rendering_time != 4'b1111) begin
                        min_rendering_time <= min_rendering_time + 1;
                    end

                    if (rasterizer_busy == 0 && 
                        rasterizer_fifo_empty == 1 &&
                        triangle_assembler_data_valid == 0 &&
                        min_rendering_time == 4'b1111 &&
                        gem_busy == 0
                    ) begin
                        increment_frame <= 1; // Advance frame count after clearing
                        top_state <= T_RENDER_IDLE;
                    end
                end

                // In between state to init real rendering
                T_RENDER_IDLE: begin
                    led[1] <= 1'b1;

                    begin
                        top_state <= T_RENDERING;
                        render_modules_enabled <= 1;
                        start_rendering_frame <= 1;
                        min_rendering_time <= 0;
                    end
                end
                T_RENDERING: begin
                    led[0] <= 1'b1;
                    render_modules_enabled <= 1;
                    if (min_rendering_time != 4'b1111) begin
                        min_rendering_time <= min_rendering_time + 1;
                    end

                    // Wait for the entire render pipeline to finish
                    if (rasterizer_busy == 0 && 
                        rasterizer_fifo_empty == 1 &&
                        triangle_assembler_data_valid == 0 &&
                        min_rendering_time == 4'b1111 &&
                        gem_busy == 0
                    ) begin
                        top_state <= T_CLEAR_IDLE;
                    end
                end
                
            endcase
        end
    end


    wire [31:0] geo_x, geo_y, geo_u, geo_v;
    wire [7:0]  geo_z;
    wire        geo_valid;
    wire        fifo_full;
    wire        gem_busy;
    
    geometry_engine gem_engine (
        .i_clk (clk),
        .i_rst (rst),

        .i_enabled(render_modules_enabled),
        .i_start(start_rendering_frame),
        .i_increment_frame(increment_frame),
        .i_vertex_fifo_full(fifo_full),

        .o_busy(gem_busy),
        .o_vertex_valid(geo_valid),
        .o_x(geo_x), .o_y(geo_y),
        .o_z(geo_z),
        .o_u(geo_u), .o_v(geo_v)
    );

    wire [103:0] rasterizer_data_in;
    wire  rasterizer_fifo_empty;
    wire  rasterizer_read_enable; 
    vertex_fifo #(
        .DATA_WIDTH(104), // 32+32+8+16+16
        .DEPTH(64)
    ) fifo_inst (
        .i_clk(clk),
        .i_rst(rst),
        
        // Write Side (From Geometry)
        .i_we(geo_valid), 
        .i_data({geo_x[31:16], geo_y[31:16], geo_z, geo_u, geo_v}), // Packing
        .o_full(fifo_full),
        
        // Read Side (To Rasterizer/Assembler)
        .i_re(rasterizer_read_enable), 
        .o_data(rasterizer_data_in),
        .o_empty(rasterizer_fifo_empty)
    );

    wire triangle_assembler_data_valid;
    wire rasterizer_busy;

    wire signed [15:0] x0, y0, x1, y1, x2, y2;
    wire [7:0]         z0, z1, z2;
    wire [31:0]        u0, v0, u1, v1, u2, v2;

    triangle_assembler triangle_assembler_instance (
        .i_clk(clk),
        .i_rst(rst),

        // FIFO Interface
        .i_fifo_data(rasterizer_data_in),
        .i_fifo_empty(rasterizer_fifo_empty),
        .o_fifo_read(rasterizer_read_enable),
        
        // Assembler to Rasterizer Interface
        .o_tri_valid(triangle_assembler_data_valid),
        .i_raster_busy(rasterizer_busy),
        
        // Triangle Outputs
        .o_x0(x0), .o_y0(y0), .o_z0(z0),
        .o_x1(x1), .o_y1(y1), .o_z1(z1),
        .o_x2(x2), .o_y2(y2), .o_z2(z2),
        
        .o_u0(u0), .o_v0(v0),
        .o_u1(u1), .o_v1(v1),
        .o_u2(u2), .o_v2(v2)
    );

    wire [16:0] rast_fb_addr; // 320x240 = 76,800 addrs (17 bits)
    wire        rast_fb_we;   // Write Enable for Framebuffer
    wire [11:0] rast_fb_pixel; // 12-bit Color 

    wire [16:0] rast_zb_r_addr;
    wire [16:0] rast_zb_w_addr;
    wire        rast_zb_we;
    wire [7:0]  rast_o_zb_i_data;
    wire [7:0]  rast_i_zb_o_data;

    wire rasterizer_arbiter_rq_valid;
    wire [2:0] rasterizer_rq_tile;
    wire arbiter_request_grant;
    wire rasterizer_tile_done;

    wire [15:0] rast_o_fb_i_fb_addr [2];
    wire        rast_o_fb_i_fb_we   [2];
    wire [11:0] rast_o_fb_i_fb_data [2];

    wire [15:0] rast_o_zb_i_zb_r_addr [2];
    wire [7:0]  rast_i_zb_o_zb_r_data [2];
    wire [15:0] rast_o_zb_i_zb_w_addr [2];
    wire        rast_o_zb_i_zb_w_we   [2];
    wire [7:0]  rast_o_zb_i_zb_w_data [2];

    tiled_rasterizer tiled_rasterizer_instance (
        .i_clk(clk), .i_rst(rst),
        // Triangle Assembler Interface
        .i_tri_valid(triangle_assembler_data_valid),
        .o_busy(rasterizer_busy),
        
        .i_x0(x0), .i_y0(y0),
        .i_x1(x1), .i_y1(y1),
        .i_x2(x2), .i_y2(y2),
        .i_z0(z0), .i_z1(z1), .i_z2(z2),
        .i_u0(u0), .i_v0(v0),
        .i_u1(u1), .i_v1(v1),
        .i_u2(u2), .i_v2(v2),

        .o_fb_addr(rast_o_fb_i_fb_addr),
        .o_fb_we(rast_o_fb_i_fb_we),
        .o_fb_pixel(rast_o_fb_i_fb_data),

        .o_zb_r_addr(rast_o_zb_i_zb_r_addr),
        .i_zb_r_data(rast_i_zb_o_zb_r_data),
        .o_zb_w_addr(rast_o_zb_i_zb_w_addr),
        .o_zb_w_we(rast_o_zb_i_zb_w_we),
        .o_zb_w_data(rast_o_zb_i_zb_w_data)
    );

    // rasterizer rasterizer_instance (
    //     .i_clk(clk),
    //     .i_rst(rst),
        
    //     // Assembler Interface
    //     .i_tri_valid(triangle_assembler_data_valid),
    //     .o_busy(rasterizer_busy),
        
    //     // Triangle Inputs
    //     .i_x0(x0), .i_y0(y0), .i_z0(z0),
    //     .i_x1(x1), .i_y1(y1), .i_z1(z1),
    //     .i_x2(x2), .i_y2(y2), .i_z2(z2),
        
    //     .i_u0(u0), .i_v0(v0),
    //     .i_u1(u1), .i_v1(v1),
    //     .i_u2(u2), .i_v2(v2),

    //     // // Tile Arbiter Interface
    //     // .o_arbiter_rq_valid(rasterizer_arbiter_rq_valid),
    //     // .o_arbiter_rq_tile(rasterizer_rq_tile),
    //     // .i_arbiter_grant(arbiter_request_grant),
    //     // .o_arbiter_tile_done(rasterizer_tile_done),

    //     // Framebuffer Interface
    //     .o_fb_addr(rast_fb_addr),
    //     .o_fb_we(rast_fb_we),
    //     .o_fb_pixel(rast_fb_pixel),
        
    //     // Z-Buffer Interface
    //     .o_zb_r_addr(rast_zb_r_addr),
    //     .i_zb_r_data(tile_i_zb_o_zb_r_data[1]), // TILE_ID = 1
    //     .o_zb_w_addr(rast_zb_w_addr),
    //     .o_zb_w_we(rast_zb_we),
    //     .o_zb_w_data(rast_o_zb_i_data)
    // );

    // wire [16:0] tile_o_fb_i_fb_addr [2];
    // wire        tile_o_fb_i_fb_we   [2];
    // wire [11:0] tile_o_fb_i_fb_data [2];
    // wire [16:0] tile_o_zb_i_zb_r_addr [2];
    // wire [7:0]  tile_i_zb_o_zb_r_data [2];
    // wire [16:0] tile_o_zb_i_zb_w_addr [2];
    // wire        tile_o_zb_i_zb_w_we   [2];
    // wire [7:0]  tile_o_zb_i_zb_w_data [2];
    // wire        tile_o_rasterizer_res [1];
    // tile_arbiter #(
    //     .NUM_RASTERIZERS(1),
    //     .ADDR_WIDTH(17),
    //     .COLOR_DATA_WIDTH(12),
    //     .Z_DATA_WIDTH(8)
    // ) tile_arbiter_instance (
    //     .i_clk(clk), .i_rst(rst),

    //     .rasterizer_rq_valid('{rasterizer_arbiter_rq_valid}),
    //     .rasterizer_rq('{rasterizer_rq_tile}),
    //     .rasterizer_done('{rasterizer_tile_done}),

    //     .i_rasterizer_fb_addr('{rast_fb_addr}),
    //     .i_rasterizer_fb_we('{rast_fb_we}),
    //     .i_rasterizer_fb_data('{rast_fb_pixel}),

    //     .i_rasterizer_zb_r_addr('{rast_zb_r_addr}),
    //     .o_rasterizer_zb_r_data('{rast_i_zb_o_data}),
    //     .i_rasterizer_zb_w_addr('{rast_zb_w_addr}),
    //     .i_rasterizer_zb_w_we('{rast_zb_we}),
    //     .i_rasterizer_zb_w_data('{rast_o_zb_i_data}),

    //     .o_tile_fb_addr(tile_o_fb_i_fb_addr),
    //     .o_tile_fb_we(tile_o_fb_i_fb_we),
    //     .o_tile_fb_data(tile_o_fb_i_fb_data),
    //     .o_tile_zb_r_addr(tile_o_zb_i_zb_r_addr),
    //     .i_tile_zb_r_data(tile_i_zb_o_zb_r_data),
    //     .o_tile_zb_w_addr(tile_o_zb_i_zb_w_addr),
    //     .o_tile_zb_w_we(tile_o_zb_i_zb_w_we),
    //     .o_tile_zb_w_data(tile_o_zb_i_zb_w_data),
    //     .o_rasterizer_res('{arbiter_request_grant})
    // );

    // Frame Buffer Muxing (Reset vs Rasterizer)
    wire [15:0] fb_addr  [2] = (top_state == T_INIT_RST_BUFFERS) 
        ? '{default: fb_zb_reset_addr}
        : rast_o_fb_i_fb_addr;
    wire fb_we           [2] = ((top_state == T_INIT_RST_BUFFERS) || (top_state == T_CLR_BUFFERS)) 
        ? '{default: 1} 
        : rast_o_fb_i_fb_we;
    wire [11:0] fb_pixel [2] = ((top_state == T_INIT_RST_BUFFERS) || (top_state == T_CLR_BUFFERS)) 
        ? '{default: 12'h000} 
        : rast_o_fb_i_fb_data;

    parameter DEPTH = 76800; // 320x240

    wire [16:0] vga_fb_r_addr;
    wire [11:0] vga_fb_pixel;

    tiled_frame_buffer tiled_frame_buffer_instance (
        .i_clk(clk), .i_clk_vga(clk_25MHz),

        .i_tile_fb_addr(fb_addr),
        .i_tile_fb_we(fb_we),
        .i_tile_fb_data(fb_pixel),
        
        .i_vga_addr(vga_fb_r_addr),
        .o_vga_pixel(vga_fb_pixel)
    );

    wire [15:0] zb_w_addr [2] = (top_state == T_INIT_RST_BUFFERS) 
        ? '{default: fb_zb_reset_addr}
        : rast_o_zb_i_zb_w_addr;
    wire zb_we            [2] = (top_state == T_INIT_RST_BUFFERS || top_state == T_CLR_BUFFERS) 
        ? '{default: 1} 
        : rast_o_zb_i_zb_w_we;
    wire [7:0] zb_w_data  [2] = (top_state == T_INIT_RST_BUFFERS || top_state == T_CLR_BUFFERS) 
        ? '{default: 8'hFF} 
        : rast_o_zb_i_zb_w_data;

    wire [15:0] zb_r_addr [2] = (top_state == T_INIT_RST_BUFFERS) 
        ? '{default: fb_zb_reset_addr}
        : rast_o_zb_i_zb_r_addr;

    tiled_z_buffer tiled_z_buffer_instance (
        .i_clk(clk),

        .i_zb_r_addr(zb_r_addr),
        .o_zb_r_data(rast_i_zb_o_zb_r_data),

        .i_zb_w_addr(zb_w_addr),
        .i_zb_w_we(zb_we),
        .i_zb_w_data(zb_w_data)
    );

    wire clk_25MHz, clk_125MHz;
    wire locked;

    if (SKIP_VGA_MODULE == 0) begin
        //clock wizard configured with a 1x and 5x clock for HDMI
        clk_wiz_0 clk_wiz (
            .clk_out1(clk_25MHz),
            .clk_out2(clk_125MHz),
            .reset(rst),
            .locked(locked),
            .clk_in1(clk)
        );
    end else begin
        // Bypass clock wizard for simulation when skipping VGA module
        assign clk_25MHz  = clk;
        assign clk_125MHz = clk;
        assign locked     = 1;
    end
    
    // Hsync pulses once per line
    // Vsync pulses once per frame
    wire hsync, vsync;
    wire [9:0] drawX;
    wire [9:0] drawY;
    wire vde; //video data enable signal

    // Note fb is 320x240 but VGA is 640x480, so we scale accordingly
    wire active_read = (drawX < 640) && (drawY < 480);

    // 2. Calculate Scaled Y safely
    wire [8:0] dy_scaled = drawY[9:1];
    
    // 3. Assign address with protection
    //    If active: perform your flip/scale logic.
    //    If blanking: force address to 0 (Safe).
    assign vga_fb_r_addr = active_read ? 
                        ((239 - dy_scaled) * 320 + (drawX[9:1])) : 
                        17'd0;
    //VGA Sync signal generator (for 640x480 @60Hz)
    if (SKIP_VGA_MODULE == 0) begin
        vga_controller vga (
            .pixel_clk(clk_25MHz),
            .reset(rst),
            .hs(hsync),
            .vs(vsync),
            .active_nblank(vde),
            .drawX(drawX),
            .drawY(drawY)
        );    
    end else begin
        // Dummy VGA signals for simulation when skipping VGA module
        assign hsync = 0;
        assign vsync = 0;
        assign vde   = 1;
        assign drawX = 0;
        assign drawY = 0;
    end  

    wire [3:0] red, green, blue;
    // Utilize frame buffer and drawX/drawY to get pixel data
    assign red  = vga_fb_pixel[11:8];
    assign green= vga_fb_pixel[7:4];
    assign blue = vga_fb_pixel[3:0];
    
    `ifdef SYNTHESIS
        //Real Digital VGA to HDMI converter
        hdmi_tx_0 vga_to_hdmi (
            //Clocking and Reset
            .pix_clk(clk_25MHz),
            .pix_clkx5(clk_125MHz),
            .pix_clk_locked(locked),
            .rst(rst),
    
            //Color and Sync Signals (12 bit color)
            .red(red),
            .green(green),
            .blue(blue),
            .hsync(hsync),
            .vsync(vsync),
            .vde(vde),
            
            //aux Data (unused)
            .aux0_din(4'b0),
            .aux1_din(4'b0),
            .aux2_din(4'b0),
            .ade(1'b0),
            
            //Differential outputs
            .TMDS_CLK_P(hdmi_tmds_clk_p),          
            .TMDS_CLK_N(hdmi_tmds_clk_n),          
            .TMDS_DATA_P(hdmi_tmds_data_p),         
            .TMDS_DATA_N(hdmi_tmds_data_n)          
        );
    `else
        initial begin
            $display("HDMI Output is disabled in simulation.");
        end
    `endif
endmodule
