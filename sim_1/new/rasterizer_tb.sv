`timescale 1ns / 1ps

module rasterizer_tb;

    // =========================================================================
    // 1. Signals
    // =========================================================================
    reg clk;
    reg rst;

    // Triangle Input
    reg        tri_valid;
    wire       busy;
    reg signed [15:0] x0, y0, x1, y1, x2, y2;
    reg [7:0]         z0, z1, z2;
    reg [31:0]        u0, v0, u1, v1, u2, v2;

    // Frame Buffer Interface (Outputs from DUT)
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

    // =========================================================================
    // 3. DUT Instantiation
    // =========================================================================
    rasterizer dut (
        .i_clk(clk),
        .i_rst(rst),
        
        .i_tri_valid(tri_valid),
        .o_busy(busy),
        
        .i_x0(x0), .i_y0(y0), 
        .i_x1(x1), .i_y1(y1), 
        .i_x2(x2), .i_y2(y2),
        
        .i_z0(z0), .i_z1(z1), .i_z2(z2),
        .i_u0(u0), .i_v0(v0), 
        .i_u1(u1), .i_v1(v1), 
        .i_u2(u2), .i_v2(v2),

        // Write Port (Stage 4)
        .o_fb_addr(fb_addr),
        .o_fb_we(fb_we),
        .o_fb_pixel(fb_pixel),

        // Read Port (Stage 1) & Write Data
        // Note: We connect the DUT's 'o_zb_addr' to our 'zb_read_addr' wire
        // because in the new design, o_zb_addr is driven by the Iterator (Stage 1).
        .o_zb_r_addr(zb_read_addr),
        .i_zb_r_data(zb_read_data),
        .o_zb_w_addr(zb_w_addr),
        .o_zb_w_we(zb_we),
        .o_zb_w_data(zb_write_data)
    );

    // =========================================================================
    // 4. Memory Logic (Dual Port Simulation) & LOGGING
    // =========================================================================
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
             $display("[FB WRITE] Time: %0t | Addr: %0d (X:%3d, Y:%3d) | Pixel: %h | zbufdata=%h | P: u=%h, v=%h z=%h", 
                      $time, 
                      fb_addr, 
                      fb_addr % 320, // Extract X
                      fb_addr / 320, // Extract Y
                      fb_pixel, 
                      dut.stage4_shader.i_zb_cur_val,
                      dut.stage4_shader.i_p_u, 
                      dut.stage4_shader.i_p_v,
                      dut.stage4_shader.i_p_z
             );
        end

        // Z-Buffer Write (Using same WRITE address from Stage 4)
        if (zb_we) begin
            z_buffer[zb_w_addr] <= zb_write_data;
        end
    end

    // =========================================================================
    // 5. Clock Generation
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz
    end

    // =========================================================================
    // 6. Stimulus & Image Export
    // =========================================================================
    integer i, fd;
    integer x, y, idx;
    
    initial begin
        $dumpfile("rasterizer_wave.vcd");
        $dumpvars(0, rasterizer_tb);
        
        // --- Init ---
        rst = 1;
        tri_valid = 0;
        
        // Clear Memory (Black background)
        for (i=0; i<76800; i=i+1) begin
            frame_buffer[i] = 12'h000; 
             z_buffer[i] = 8'hFF; // Far plane
//            z_buffer[i] = 8'h83; // Gradient for testing
        end
        
        #100;
        rst = 0;
        #20;

        // --- Send Triangle ---
//        // Vertex 0 (Top) -> RED
//        x0 = 160; y0 = 110; z0 = 50; 
//        u0 = 32'h00010000; v0 = 0;       

//        // Vertex 1 (Bottom Left) -> GREEN
//        x1 = 150; y1 = 130; z1 = 50; 
//        u1 = 0; v1 = 32'h00010000;       

//        // Vertex 2 (Bottom Right) -> BLUE
//        x2 = 170; y2 = 130; z2 = 50; 
//        u2 = 0; v2 = 0;           
               
//         // Vertex 0 (Top Center) -> RED (U=1, V=0)
//         // Vertex 0 (Top Center) -> RED (U=1, V=0)
//            x0 = 173; y0 = 93;  z0 = 248;
//            u0 = 0; v0 = 0;
    
//            // SWAPPED Vertex 2 into Slot 1
//            // Vertex 1 (Bottom Right)
//            x1 = 130; y1 = 62; z1 = 225;
//            u1 = 32'h00010000; v1 = 0;

//            // SWAPPED Vertex 1 into Slot 2
//            // Vertex 2 (Top Right - originally V1)
//            x2 = 160;  y2 = 155; z2 = 241; 
////            u2 = 32'h00010000; v2 = 0;
//            u2 = 0; v2 = 32'h00010000;  

// Vertex 0 (Top Center) -> RED (U=1, V=0)
         // Vertex 0 (Top Center) -> RED (U=1, V=0)
            x0 = 121; y0 = 88;  z0 = 245;
            u0 = 0; v0 = 0;
    
            // SWAPPED Vertex 2 into Slot 1
            // Vertex 1 (Bottom Right)
            x1 = 160; y1 = 155; z1 = 241;
//            u1 = 32'h00010000; v1 = 0;
            u1 = 0; v1 = 32'h00010000;  

            // SWAPPED Vertex 1 into Slot 2
            // Vertex 2 (Top Right - originally V1)
            x2 = 212;  y2 = 77; z2 = 236; 
            u2 = 32'h00010000; v2 = 0;
//            u2 = 0; v2 = 32'h00010000;  

             

        $display("Sending Triangle...");
        
        tri_valid = 1;
        @(posedge clk);
                @(posedge clk);

        tri_valid = 0;

        // --- Wait for Completion ---
        @(posedge clk);
        wait(busy == 1); // Started
        $display("Rasterizer Busy...");
        
        wait(busy == 0); // Finished
        $display("Rasterizer Done!");
        #100;

        // --- Export to PPM Image ---
        $display("Writing output.ppm...");
        fd = $fopen("output.ppm", "w");
        
        // PPM Header (P3 = Text RGB, Width, Height, Max Color)
        $fwrite(fd, "P3\n320 240\n15\n"); 

        for (y=0; y<240; y=y+1) begin
            for (x=0; x<320; x=x+1) begin
                idx = y*320 + x;
                
                // Extract RGB from 12-bit (4R 4G 4B)
                $fwrite(fd, "%0d %0d %0d  ", 
                    frame_buffer[idx][11:8], 
                    frame_buffer[idx][7:4], 
                    frame_buffer[idx][3:0]);
            end
            $fwrite(fd, "\n");
        end
        
        $fclose(fd);
        $display("Image saved to output.ppm");
        $display("Min x: %0d, Max x: %0d", dut.min_x, dut.max_x);
        $display("Min y: %0d, Max y: %0d", dut.min_y, dut.max_y);
        $finish;
    end

endmodule