`timescale 1ns / 1ps

module fpga_top #(
    parameter PIXEL_RESET_COUNT = 76800
)(
    input wire clk,
    input wire rst_n,
    
    input wire start,
    input wire increment_frame,
    input wire skip_reset_buffers,

    output reg dummy_led,
    
    //HDMI
    output logic hdmi_tmds_clk_n,
    output logic hdmi_tmds_clk_p,
    output logic [2:0]hdmi_tmds_data_n,
    output logic [2:0]hdmi_tmds_data_p
);
    wire rst = !rst_n;

    typedef enum {
        T_IDLE,
        T_RENDERING,
        T_RESETING_BUFFERS
    } top_state_t;

    top_state_t state;
    reg render_modules_enabled;
    reg [16:0] fb_zb_reset_addr;
    reg [3:0] min_rendering_time;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= skip_reset_buffers ? T_IDLE : T_RESETING_BUFFERS;
            render_modules_enabled <= 0;
            fb_zb_reset_addr <= 0;
            min_rendering_time <= 0;
        end else begin
            render_modules_enabled <= 0;
            case (state)
                T_RESETING_BUFFERS: begin
                    render_modules_enabled <= 0;

                    if (fb_zb_reset_addr == PIXEL_RESET_COUNT - 1) begin
                        state <= T_IDLE;
                    end else begin
                        fb_zb_reset_addr <= fb_zb_reset_addr + 1;
                    end
                end
                T_IDLE: begin
                    if (start) begin
                        state <= T_RENDERING;
                        render_modules_enabled <= 1;
                        min_rendering_time <= 0;
                    end
                end
                T_RENDERING: begin
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
                        state <= T_IDLE;
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
        .i_start(start),
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

    rasterizer rasterizer_instance (
        .i_clk(clk),
        .i_rst(rst),
        
        // Assembler Interface
        .i_tri_valid(triangle_assembler_data_valid),
        .o_busy(rasterizer_busy),
        
        // Triangle Inputs
        .i_x0(x0), .i_y0(y0), .i_z0(z0),
        .i_x1(x1), .i_y1(y1), .i_z1(z1),
        .i_x2(x2), .i_y2(y2), .i_z2(z2),
        
        .i_u0(u0), .i_v0(v0),
        .i_u1(u1), .i_v1(v1),
        .i_u2(u2), .i_v2(v2),

        // Framebuffer Interface
        .o_fb_addr(rast_fb_addr),
        .o_fb_we(rast_fb_we),
        .o_fb_pixel(rast_fb_pixel),
        
        // Z-Buffer Interface
        .o_zb_r_addr(rast_zb_r_addr),
        .i_zb_r_data(rast_i_zb_o_data),
        .o_zb_w_addr(rast_zb_w_addr),
        .o_zb_w_we(rast_zb_we),
        .o_zb_w_data(rast_o_zb_i_data)
    );

    // Frame Buffer Muxing (Reset vs Rasterizer)
    wire [16:0] fb_addr  = state == T_RESETING_BUFFERS ? fb_zb_reset_addr : rast_fb_addr;
    wire fb_we           = state == T_RESETING_BUFFERS ? 1 : rast_fb_we;
    wire [11:0] fb_pixel = state == T_RESETING_BUFFERS ? 12'h000 : rast_fb_pixel;

    parameter DEPTH = 76800; // 320x240

    wire [16:0] vga_fb_r_addr;
    wire [11:0] vga_fb_pixel;

    // Framebuffer BRAM (Simple Dual-Port RAM)
    // 320x240 = 76,800 pixels (17 bits)
    simple_dual_clk_bram #(
        .DATA_WIDTH(12),
        .ADDR_WIDTH(17),
        .DEPTH(DEPTH),
        .INIT_FILE("frame_buffer_init.mem")
    ) frame_buffer (
        .clka(clk),
        .we(fb_we),
        .waddr(fb_addr),
        .din(fb_pixel),
        
        .clkb(clk_25MHz),
        .raddr(vga_fb_r_addr), 
        .dout(vga_fb_pixel)
    );

    // ---------------------------------------------------------
    // Z-BUFFER WIRING
    // ---------------------------------------------------------

    // 1. Create the Write Address Mux
    // If resetting: use the reset counter.
    // If rendering: use the Rasterizer's WRITE address (where it wants to save the new Z).
    wire [16:0] zb_w_addr = (state == T_RESETING_BUFFERS) ? fb_zb_reset_addr : rast_zb_w_addr;

    // 2. Create the Write Data/Enable Mux (Same as before)
    wire zb_we            = (state == T_RESETING_BUFFERS) ? 1'b1 : rast_zb_we;
    wire [7:0] zb_w_data  = (state == T_RESETING_BUFFERS) ? 8'hFF : rast_o_zb_i_data;

    // 3. Create the Read Address Mux
    // The reset logic doesn't strictly need to read, but we can tie it to the reset addr.
    // The Rasterizer needs to read to check depth (rast_zb_r_addr).
    wire [16:0] zb_r_addr = (state == T_RESETING_BUFFERS) ? fb_zb_reset_addr : rast_zb_r_addr;

    // 4. Instantiate the Dual Port RAM
    simple_dual_port_bram #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(17),
        .DEPTH(76800),
        .INIT_FILE("z_buffer_init.mem") // The file generated by the python script
    ) z_buffer (
        .clk(clk),
        
        // Write Port
        .we(zb_we),
        .waddr(zb_w_addr),
        .din(zb_w_data),
        
        // Read Port
        .raddr(zb_r_addr),
        .dout(rast_i_zb_o_data) // Data going back into Rasterizer for checking
    );

    wire clk_25MHz, clk_125MHz;
    wire locked;

    //clock wizard configured with a 1x and 5x clock for HDMI
    clk_wiz_0 clk_wiz (
        .clk_out1(clk_25MHz),
        .clk_out2(clk_125MHz),
        .reset(rst),
        .locked(locked),
        .clk_in1(clk)
    );
    
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
    vga_controller vga (
        .pixel_clk(clk_25MHz),
        .reset(rst),
        .hs(hsync),
        .vs(vsync),
        .active_nblank(vde),
        .drawX(drawX),
        .drawY(drawY)
    );    

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
   

//    always_ff @(posedge clk) begin
//        // Unary XOR (^) before a vector reduces all its bits to 1 bit.
//        // We include EVERYTHING: Pixel color, Write Enables, Addresses, and Z-data.
//        dummy_led <= x0[0] 
//                     ^ (^rast_fb_pixel)   // Vital: Keeps Interpolator alive
//                     ^ (^rast_fb_addr)    // Vital: Keeps Address generator alive
//                     ^ rast_fb_we         
//                     ^ rast_zb_we 
//                     ^ (^rast_o_zb_i_data) // Please don't optimize this :pray:
//                     ; // Vital: Checks ALL bits of Z, not just LSB
//    end
endmodule
