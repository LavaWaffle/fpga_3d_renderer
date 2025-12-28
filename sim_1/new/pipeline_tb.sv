`timescale 1ns / 1ps

module pipeline_tb;

    // =========================================================================
    // 1. Signals
    // =========================================================================
    reg clk;
    reg rst;

    // Interconnect Signals
    // Geometry -> FIFO
    wire        geo_valid;
    wire [31:0] geo_x, geo_y, geo_u, geo_v;
    wire [7:0]  geo_z;
    
    // FIFO -> Assembler
    wire [103:0] fifo_data_out;
    wire         fifo_full, fifo_empty, fifo_read_en;
    
    // Assembler -> Rasterizer (Outputs to check)
    wire        tri_valid;
    reg         raster_busy;
    
    wire signed [15:0] t_x0, t_y0, t_x1, t_y1, t_x2, t_y2;
    wire [7:0]         t_z0, t_z1, t_z2;
    wire [31:0]        t_u0, t_v0, t_u1, t_v1, t_u2, t_v2;

    // =========================================================================
    // 2. Module Instantiations
    // =========================================================================

    // A. Geometry Engine
    geometry_engine geo_inst (
        .i_clk(clk),
        .i_rst(rst),
        .o_vertex_valid(geo_valid),
        .o_x(geo_x), .o_y(geo_y),
        .o_z(geo_z),
        .o_u(geo_u), .o_v(geo_v)
    );

    // B. Vertex FIFO
    vertex_fifo #(
        .DATA_WIDTH(104), 
        .DEPTH(64)
    ) fifo_inst (
        .i_clk(clk),
        .i_rst(rst),
        
        // Write Side
        .i_we(geo_valid), 
        .i_data({geo_x[31:16], geo_y[31:16], geo_z, geo_u, geo_v}), 
        .o_full(fifo_full),
        
        // Read Side
        .i_re(fifo_read_en), 
        .o_data(fifo_data_out),
        .o_empty(fifo_empty)
    );

    // C. Triangle Assembler
    triangle_assembler asm_inst (
        .i_clk(clk),
        .i_rst(rst),
        
        // FIFO Interface
        .i_fifo_data(fifo_data_out),
        .i_fifo_empty(fifo_empty),
        .o_fifo_read(fifo_read_en),
        
        // Rasterizer Interface
        .o_tri_valid(tri_valid),
        .i_raster_busy(raster_busy),
        
        // Outputs
        .o_x0(t_x0), .o_y0(t_y0), .o_x1(t_x1), .o_y1(t_y1), .o_x2(t_x2), .o_y2(t_y2),
        .o_z0(t_z0), .o_z1(t_z1), .o_z2(t_z2),
        .o_u0(t_u0), .o_v0(t_v0), .o_u1(t_u1), .o_v1(t_v1), .o_u2(t_u2), .o_v2(t_v2)
    );

    // =========================================================================
    // 3. Clock & Setup
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz
    end

    initial begin
        $dumpfile("pipeline_wave.vcd");
        $dumpvars(0, pipeline_tb);
        
        // 1. Load Memory
        if ($fopen("vertex_data.mem", "r") == 0) begin
            $display("ERROR: vertex_data.mem not found!");
            $finish;
        end
        $readmemh("vertex_data.mem", geo_inst.vertex_ram.ram);

        $display("--- PIPELINE INTEGRATION TEST ---");

        rst = 1;
        raster_busy = 0;
        #100;
        rst = 0;
        
        $display("Reset Complete. Waiting for Triangle 1 (CCW - Valid)...");

        // ---------------------------------------------------------------------
        // CHECK 1: CCW Triangle (Should be VALID)
        // ---------------------------------------------------------------------
        fork
            begin
                wait(tri_valid == 1);
                $display("\n[PASS] Triangle 1 Assembled and Validated! %t", $time);
                $display("  V0: (x %0d, y %0d, z %0d, u %0d, v %0d)", t_x0, t_y0, t_z0, t_u0, t_v0);
                $display("  V1: (x %0d, y %0d, z %0d, u %0d, v %0d)", t_x1, t_y1, t_z1, t_u1, t_v1);
                $display("  V2: (x %0d, y %0d, z %0d, u %0d, v %0d)", t_x2, t_y2, t_z2, t_u2, t_v2);
                
                // Wait for pulse to finish
                @(posedge clk);
                while(tri_valid) @(posedge clk);
            end
            begin
                #5000;
                $display("\n[FAIL] Timeout waiting for Triangle 1.");
                $finish;
            end
        join_any

        $display("\nWaiting for Triangle 2 (CW - Should be Culled)...");

        // ---------------------------------------------------------------------
        // CHECK 2: CW Triangle (Should be CULLED)
        // ---------------------------------------------------------------------
        // We need to wait enough time for the Geometry Engine to process 3 more vertices.
        // Each vertex takes ~36 cycles (Fetch + Matrix + Div + Map). 
        // 3 * 36 * 10ns = ~1080ns. Let's wait 2000ns to be safe.
        
        fork
            begin
                // If we see tri_valid go high again, that's a FAILURE
                wait(tri_valid == 1);
                $display("\n[FAIL] Triangle 2 was VALID (Should have been culled!) %t", $time);
                $display("  V0: (x %0d, y %0d, z %0d, u %0d, v %0d)", t_x0, t_y0, t_z0, t_u0, t_v0);
                $display("  V1: (x %0d, y %0d, z %0d, u %0d, v %0d)", t_x1, t_y1, t_z1, t_u1, t_v1);
                $display("  V2: (x %0d, y %0d, z %0d, u %0d, v %0d)", t_x2, t_y2, t_z2, t_u2, t_v2);
                
                #1000;
            end
            begin
                #2000;
                $display("\n[PASS] Timer expired. Triangle 2 was correctly culled (No valid pulse seen).");
            end
        join_any
        
        $display("\n--- SIMULATION DONE ---");
        $finish;
    end

endmodule