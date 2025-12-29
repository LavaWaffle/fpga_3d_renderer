`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/29/2025 12:43:26 AM
// Design Name: 
// Module Name: top_level_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module top_level_tb;
    reg clk;
    reg rst;
    reg start;
    reg increment_frame;

    // Instantiate the DUT
    fpga_top dut (
        .clk(clk),
        .rst_n(!rst),
        .start(start),
        .increment_frame(increment_frame),
        .dummy_led()
    );

    // Clock Generation (100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period
    end

    // Monitors

    // Geometry Engine Output Monitoring
    always @(posedge clk) begin
        if (dut.gem_engine.o_vertex_valid == 1) begin
            $display("\n==========================================");
            $display(" Processing Vertex %0d", vertex_idx);
            $display("==========================================");
            $display(" Output X: %f", fixed_to_real_q16_16(dut.gem_engine.o_x));
            $display(" Output Y: %f", fixed_to_real_q16_16(dut.gem_engine.o_y));
            $display(" Output Z: %0d", dut.gem_engine.o_z);
            $display(" Output U: %f", fixed_to_real_q16_16(dut.gem_engine.o_u));
            $display(" Output V: %f", fixed_to_real_q16_16(dut.gem_engine.o_v));
            @(posedge clk);
        end
    end

    // Format: {x[15:0], y[15:0], z[7:0], u[31:0], v[31:0]}
    //  wire signed [15:0] in_x = i_fifo_data[103:88];
    // wire signed [15:0] in_y = i_fifo_data[87:72];
    // wire [7:0]         in_z = i_fifo_data[71:64];
    // wire [31:0]        in_u = i_fifo_data[63:32];
    // wire [31:0]        in_v = i_fifo_data[31:0];
    // Vertex FIFO Input and Output Monitoring
    always @(posedge clk) begin
        if (dut.fifo_inst.i_we) begin
            $display(" Vertex FIFO Input - X: %0d, Y: %0d, Z: %0d, U: %0d, V: %0d",
                     dut.fifo_inst.i_data[103:88],
                     dut.fifo_inst.i_data[87:72],
                     dut.fifo_inst.i_data[71:64],
                     fixed_to_real_q16_16(dut.fifo_inst.i_data[63:32]),
                     fixed_to_real_q16_16(dut.fifo_inst.i_data[31:0]));
        end
        if (dut.fifo_inst.i_re) begin
            $display(" Vertex FIFO Output - X: %0d, Y: %0d, Z: %0d, U: %0d, V: %0d",
                     dut.fifo_inst.o_data[103:88],
                     dut.fifo_inst.o_data[87:72],
                     dut.fifo_inst.o_data[71:64],
                     fixed_to_real_q16_16(dut.fifo_inst.o_data[63:32]),
                     fixed_to_real_q16_16(dut.fifo_inst.o_data[31:0]));
        end
    end

    // Triangle Assembler Input and Output Monitoring
    always @(posedge clk) begin
        if (!dut.triangle_assembler_instance.i_fifo_empty && dut.triangle_assembler_instance.o_fifo_read) begin
            $display(" Triangle Assembler Input - X0: %0d, Y0: %0d, Z0: %0d, U0: %0d, V0: %0d",
                     dut.triangle_assembler_instance.i_fifo_data[103:88],
                     dut.triangle_assembler_instance.i_fifo_data[87:72],
                     dut.triangle_assembler_instance.i_fifo_data[71:64],
                     fixed_to_real_q16_16(dut.triangle_assembler_instance.i_fifo_data[63:32]),
                     fixed_to_real_q16_16(dut.triangle_assembler_instance.i_fifo_data[31:0]));
        end
        if (dut.triangle_assembler_instance.o_tri_valid) begin
            $display(" Triangle Assembler Output - X0: %0d, Y0: %0d, Z0: %0d, U0: %0d, V0: %0d",
                     dut.triangle_assembler_instance.o_x0,
                     dut.triangle_assembler_instance.o_y0,
                     dut.triangle_assembler_instance.o_z0,
                     fixed_to_real_q16_16(dut.triangle_assembler_instance.o_u0),
                     fixed_to_real_q16_16(dut.triangle_assembler_instance.o_v0));
        end
    end

    // Rasterizer Input Monitoring
    always @(posedge clk) begin
        if (dut.rasterizer_instance.i_tri_valid) begin
            $display(" Rasterizer Input - X0: %0d, Y0: %0d, Z0: %0d, U0: %0d, V0: %0d",
                     dut.rasterizer_instance.i_x0,
                     dut.rasterizer_instance.i_y0,
                     dut.rasterizer_instance.i_z0,
                     dut.rasterizer_instance.i_u0,
                     dut.rasterizer_instance.i_v0);
            // second triangle
            $display(" Rasterizer Input - X1: %0d, Y1: %0d, Z1: %0d, U1: %0d, V1: %0d",
                     dut.rasterizer_instance.i_x1,
                     dut.rasterizer_instance.i_y1,
                     dut.rasterizer_instance.i_z1,
                     dut.rasterizer_instance.i_u1,
                     dut.rasterizer_instance.i_v1);
            $display(" Rasterizer Input - X2: %0d, Y2: %0d, Z2: %0d, U2: %0d, V2: %0d",
                     dut.rasterizer_instance.i_x2,
                     dut.rasterizer_instance.i_y2,
                     dut.rasterizer_instance.i_z2,
                     dut.rasterizer_instance.i_u2,
                     dut.rasterizer_instance.i_v2);
        end
    end

    initial begin
        // This creates a file you can open in GTKWave or Vivado
        $dumpfile("top_level_tb.vcd");
        
        // Level 0 dumps ALL signals in this module and everything inside 'dut'
        $dumpvars(0, top_level_tb);
    end

    // Helpers
    // Converts Q16.16 (32-bit signed) to Real for display
    function real fixed_to_real_q16_16(input signed [31:0] val);
        begin
            fixed_to_real_q16_16 = real'(val) / 65536.0;
        end
    endfunction

    integer vertex_idx;

    // Frame Buffer Interface Rasterizer signals
    // In Pipelined mode: This acts as the WRITE address for both FB and ZB
    wire [16:0] fb_addr;
    wire        fb_we;
    wire [11:0] fb_pixel; // Format: 4R, 4G, 4B

    // Z-Buffer Interface
    // In Pipelined mode: This acts as the READ address (from Stage 1)
    wire [16:0] zb_read_addr; 
    reg  [7:0]  zb_read_data; // Input to DUT
    wire [16:0] zb_w_addr;
    wire        zb_we;
    wire [7:0]  zb_write_data;

    // =========================================================================
    // 2. Memory Models (The "Virtual Screen")
    // =========================================================================
    // 320x240 = 76,800 pixels
    logic [11:0] frame_buffer [0:76799];
    logic [7:0]  z_buffer     [0:76799];
    
    // wire up DUT framebuffer and zbuffer signals
    assign fb_addr       = dut.rasterizer_instance.o_fb_addr;
    assign fb_we         = dut.rasterizer_instance.o_fb_we;
    assign fb_pixel      = dut.rasterizer_instance.o_fb_pixel;
    
    assign zb_read_addr  = dut.rasterizer_instance.o_zb_r_addr;
    assign zb_w_addr     = dut.rasterizer_instance.o_zb_w_addr;
    assign zb_we         = dut.rasterizer_instance.o_zb_w_we;
    assign zb_write_data = dut.rasterizer_instance.o_zb_w_data;
    assign dut.rasterizer_instance.i_zb_r_data = zb_read_data;
    
    always @(posedge clk) begin
        // ---------------------------------------------------------------------
        // PORT A: READ (Stage 1)
        // ---------------------------------------------------------------------
        // The pipeline requests data at 'zb_read_addr'. 
        // We deliver it to 'zb_read_data' on the next edge (Synchronous Read).
        zb_read_data <= z_buffer[zb_read_addr];

        // ---------------------------------------------------------------------
        // PORT B: WRITE (Stage 4)
        // ---------------------------------------------------------------------
        // Frame Buffer Write
        if (fb_we) begin
            frame_buffer[fb_addr] <= fb_pixel;
            
            // --- LOGGING ---
            // Note: Accessed via 'dut.stage4_shader.i_p_u' because signals are inside submodules now
//             $display("[FB WRITE] Time: %0t | Addr: %0d (X:%3d, Y:%3d) | Pixel: %h | zbufdata=%h | P: u=%h, v=%h z=%h", 
//                      $time, 
//                      fb_addr, 
//                      fb_addr % 320, // Extract X
//                      fb_addr / 320, // Extract Y
//                      fb_pixel, 
//                      dut.rasterizer_instance.stage4_shader.i_zb_cur_val,
//                      dut.rasterizer_instance.stage4_shader.i_p_u, 
//                      dut.rasterizer_instance.stage4_shader.i_p_v,
//                      dut.rasterizer_instance.stage4_shader.i_p_z
//             );
        end

        // Z-Buffer Write (Using same WRITE address from Stage 4)
        if (zb_we) begin
            z_buffer[zb_w_addr] <= zb_write_data;
        end
    end

    integer i, fd;
    integer x, y, idx;

    integer frame_count;
    string filename;
    integer fc_i;
    initial begin
        $display("--- SIMULATION START ---");

        // 1. Load Memory
        // Ensure "vertex_data.mem" exists in simulation directory
        if ($fopen("vertex_data.mem", "r") == 0) begin
            $display("ERROR: vertex_data.mem not found!");
            $finish;
        end
        // Load data directly into the BRAM instance inside DUT
        $readmemh("vertex_data.mem", dut.gem_engine.vertex_ram.ram);

        for (frame_count = 0; frame_count < 16; frame_count = frame_count + 1) begin
            $display("\n\n\n---------------------------------");
            $display("FRAME %0d", frame_count);
            $display("---------------------------------\n\n\n");

            // 2. Reset
            rst = 1;
            increment_frame = 0;
            
            // Clear Memory (Black background)
            for (i=0; i<76800; i=i+1) begin
                frame_buffer[i] = 12'h000; 
                z_buffer[i] = 8'hFF; // Far plane
            end

            #100;
            rst = 0;
            #100;

            for (fc_i = 0; fc_i < frame_count; fc_i = fc_i + 1) begin
                increment_frame = 1;
                @(posedge clk);
                @(posedge clk);
                @(posedge clk);
                @(posedge clk);
                increment_frame = 0;
                @(posedge clk);
                @(posedge clk);
                @(posedge clk);
                @(posedge clk);
            end

            start = 1;
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            @(posedge clk);
            start = 0;

            // Name the block so we can target it with disable
            fork : wait_for_rasterizer
                begin
                    // OPTIONAL: Ensure signal is low first to catch a FRESH rising edge
                    // wait(dut.rasterizer_instance.o_busy == 0); 
                    
                    // Wait for it to become busy
                    wait(dut.rasterizer_instance.o_busy == 1);
                    $display("Rasterizer Busy Started at time %t", $time);
                    
                    // Wait for it to finish
                    wait(dut.rasterizer_instance.o_busy == 0);
                    $display("Rasterizer Busy Ended at time %t", $time);
                end
                begin
                    // Corrected to match comment (or change comment to 250)
                    #(500us); 
                    $error("TIMEOUT: Rasterizer took too long to finish!");
                end
            join_any
            
            // CRITICAL: Kill the thread that didn't finish (the zombie)
            disable wait_for_rasterizer;
                

            // Dump Frame Buffer to PPM file
            filename = $sformatf("output_image-%02d.ppm", frame_count);
            fd = $fopen(filename, "w");
            $fwrite(fd, "P3\n320 240\n15\n"); // PPM Header
            
            for (y = 0; y < 240; y = y + 1) begin
                for (x = 0; x < 320; x = x + 1) begin
                    // FLIP Y MODIFICATION:
                    // Instead of y * 320, we read from (239 - y) * 320.
                    // This writes the last row of the buffer to the first row of the file.
                    idx = (239 - y) * 320 + x;
                    
                    $fwrite(fd, "%0d %0d %0d ", 
                            frame_buffer[idx][11:8], 
                            frame_buffer[idx][7:4], 
                            frame_buffer[idx][3:0]);
                end
                $fwrite(fd, "\n");
            end

            $fclose(fd);
            // $display("Output image written to output_image.ppm");
            $display("Output image written to %s", filename);
            #100;

        end

        $display("--- SIMULATION END ---");
        $finish;
    end
endmodule
