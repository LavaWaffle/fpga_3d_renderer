`timescale 1ns / 1ps

module top_level_tb_complete;

    // -------------------------------------------------------------------------
    // 1. Signals & DUT Instantiation
    // -------------------------------------------------------------------------
    reg clk;
    reg rst;
    reg start;
    reg increment_frame;
    reg skip_reset_buffers;

    // Instantiate the DUT
    fpga_top #(
        .PIXEL_RESET_COUNT(10)
    ) dut (
        .clk(clk),
        .rst_n(!rst),
        .start(start),
        .increment_frame(increment_frame),
        .skip_reset_buffers(skip_reset_buffers),
        .dummy_led(),
        .hdmi_tmds_clk_n(), .hdmi_tmds_clk_p(),
        .hdmi_tmds_data_n(), .hdmi_tmds_data_p()
    );

    // Clock Generation (100 MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    // -------------------------------------------------------------------------
    // 2. Constants & Variables
    // -------------------------------------------------------------------------
    localparam BMP_WIDTH  = 640;
    localparam BMP_HEIGHT = 480;

    // Array to hold the "Snooped" VGA output
    logic [11:0] vga_capture_data [BMP_WIDTH][BMP_HEIGHT];
    
    // -------------------------------------------------------------------------
    // 3. VGA Snooping Process with Error Detection
    // -------------------------------------------------------------------------
    always @(posedge dut.clk_25MHz) begin
        if (dut.vde) begin
            // Safety check to prevent out of bounds
            if (dut.drawX < BMP_WIDTH && dut.drawY < BMP_HEIGHT) begin
                
                logic [11:0] current_pixel;
                current_pixel = {dut.red, dut.green, dut.blue};

                // Check for 'X' (Unknown) or 'Z' (High Z) values
                if (^current_pixel === 1'bx) begin
                    // Force to Hot Pink so it stands out in the image
                    current_pixel = 12'hF0F; 
                    // Log error once per unique coordinate if needed, or just let the image show it
                end

                vga_capture_data[dut.drawX][dut.drawY] <= current_pixel;
            end
        end
    end

    integer i, j;

    // -------------------------------------------------------------------------
    // 4. Main Test Procedure
    // -------------------------------------------------------------------------
    initial begin
        $display("--- SIMULATION START ---");

        // Initialize capture array to Black to remove X's
        for (i = 0; i < BMP_WIDTH; i = i + 1) begin
            for (j = 0; j < BMP_HEIGHT; j = j + 1) begin
                vga_capture_data[i][j] = 12'h000;
            end
        end

        // --- Load Memory ---
        if ($fopen("vertex_data.mem", "r") == 0) begin
            $display("ERROR: vertex_data.mem not found!");
            $finish;
        end
        $readmemh("vertex_data.mem", dut.gem_engine.vertex_ram.ram);

        // --- Reset Sequence ---
        rst = 1;
        start = 0;
        increment_frame = 0;
        skip_reset_buffers = 0; 
        #100;
        rst = 0;
        
        // Wait for Clock Lock
        wait (dut.locked == 1);
        #100;

        // --- Wait for DUT Initialization ---
        wait (dut.state == dut.T_IDLE);
        $display("DUT Initialized and Idle.");

        // --- Trigger Render ---
        start = 1;
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        @(posedge clk);
        start = 0;
        $display("Render Started...");

        // --- Wait for Render Completion ---
        wait (dut.state == dut.T_RENDERING);
        wait (dut.state == dut.T_IDLE);
        
        $display("Render Complete! Starting Phase 1: Internal Memory Dump... (At T= %0t)", $time);

        // =====================================================================
        // PHASE 1: Internal Memory Dump (PPM)
        // =====================================================================
        save_internal_ppm("output_internal_mem.ppm");
        
        $display("Phase 1 Complete. Internal BRAM saved to disk.");
        $display("Starting Phase 2: Waiting for VSync to capture VGA output...");

        // =====================================================================
        // PHASE 2: External VGA Capture (PPM)
        // =====================================================================
        
        // Reset VGA Controller
        start = 0;
        skip_reset_buffers = 1;
        rst = 1;
        @(posedge clk);
        rst = 0;
        
//        $display("Waiting for Clock Lock...");
//        wait (dut.locked == 1);
//        $display("Clock Locked. Waiting for Frame Sync...");



        // 1. Wait for Start of Frame
        wait (dut.vsync == 0); 
        wait (dut.vsync == 1);
        $display("VSync Detected (Start of Frame). Recording VGA signals...");

        // 2. Wait for End of Frame
        wait (dut.vsync == 0);
        $display("VSync Detected (End of Frame). Saving Capture... (At T= %0t)", $time);

        // 3. Write the captured array to PPM
        save_vga_ppm("output_vga_signal.ppm");

        $display("Phase 2 Complete. VGA Output saved to disk.");
        $display("--- SIMULATION END ---");
        $finish;
    end


    // -------------------------------------------------------------------------
    // Task: Save Internal BRAM to PPM
    // -------------------------------------------------------------------------
    task save_internal_ppm(string ppm_file_name);
        integer fd;
        integer x, y;
        integer bram_addr;
        integer scaled_x, scaled_y;
        logic [11:0] pixel;

        begin
            fd = $fopen(ppm_file_name, "w");
            if (fd == 0) begin
                $display("Error opening %s", ppm_file_name);
                $stop;
            end

            // PPM Header
            // P3 = ASCII RGB, Width=640, Height=480, MaxVal=15
            $fwrite(fd, "P3\n%0d %0d\n15\n", BMP_WIDTH, BMP_HEIGHT);

            // PPM writes Top-to-Bottom (y=0 is top of image).
            // We replicate the logic the VGA controller uses:
            // Screen Y=0 (Top) maps to BRAM Row 239 (Last Row)
            // Screen Y=479 (Bottom) maps to BRAM Row 0 (First Row)
            for (y = 0; y < BMP_HEIGHT; y = y + 1) begin
                for (x = 0; x < BMP_WIDTH; x = x + 1) begin
                    scaled_x = x / 2;
                    scaled_y = y / 2;
                    
                    // Logic mimics "vga_fb_r_addr" in top level
                    // If y=0 (top), scaled_y=0 -> (239-0) = 239.
                    if (scaled_x >= 320 || scaled_y >= 240) begin
                         bram_addr = 0; // Out of bounds safety
                    end else begin
                         bram_addr = (239 - scaled_y) * 320 + scaled_x;
                    end

                    if (bram_addr > 76799) bram_addr = 0;

                    pixel = dut.frame_buffer.ram[bram_addr];

                    // Write RGB values separated by spaces
                    $fwrite(fd, "%0d %0d %0d ", pixel[11:8], pixel[7:4], pixel[3:0]);
                end
                $fwrite(fd, "\n");
            end
            $fclose(fd);
        end
    endtask

    // -------------------------------------------------------------------------
    // Task: Save VGA Capture Array to PPM
    // -------------------------------------------------------------------------
    task save_vga_ppm(string ppm_file_name);
        integer fd;
        integer x, y;
        logic [11:0] pixel;
        
        begin
            fd = $fopen(ppm_file_name, "w"); 
            if (fd == 0) begin
                $display("Error opening %s", ppm_file_name);
                $stop;
            end

            // PPM Header
            $fwrite(fd, "P3\n%0d %0d\n15\n", BMP_WIDTH, BMP_HEIGHT);

            // VGA Capture array is [x][y] where y=0 is Top of screen.
            // PPM expects Top-to-Bottom, so we iterate normally.
            for (y = 0; y < BMP_HEIGHT; y = y + 1) begin
                for (x = 0; x < BMP_WIDTH; x = x + 1) begin
                    pixel = vga_capture_data[x][y];

                    // Error Check for X or Z
                    if (^pixel === 1'bx) begin
                        pixel = 12'hF0F; // Hot Pink
                        $display("ERROR: Writing 'X' pixel to file at (%0d, %0d)", x, y);
                    end else if (^pixel === 1'bz) begin
                        pixel = 12'h000; // Black
                    end

                    $fwrite(fd, "%0d %0d %0d ", pixel[11:8], pixel[7:4], pixel[3:0]);
                end
                $fwrite(fd, "\n");
            end
            $fclose(fd);
        end
    endtask

endmodule