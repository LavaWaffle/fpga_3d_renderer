`timescale 1ns / 1ps

module geometry_engine_tb;

    // =========================================================================
    // 1. Inputs and Outputs
    // =========================================================================
    reg clk;
    reg rst;

    // =========================================================================
    // 2. Instantiate the DUT (Device Under Test)
    // =========================================================================
    geometry_engine dut (
        .i_clk(clk),
        .i_rst(rst)
        // Note: Outputs (o_x, o_y, etc.) are internal wires we will snoop directly
        // via the hierarchy in this testbench style.
    );

    // =========================================================================
    // 3. Clock Generation (100 MHz)
    // =========================================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 10ns period
    end

    // =========================================================================
    // 4. Waveform Generation (VCD)
    // =========================================================================
    initial begin
        // This creates a file you can open in GTKWave or Vivado
        $dumpfile("geometry_engine_wave.vcd");
        
        // Level 0 dumps ALL signals in this module and everything inside 'dut'
        $dumpvars(0, geometry_engine_tb);
    end

    // =========================================================================
    // 5. Helper Task: Print Fixed Point as Float
    // =========================================================================
    // Converts Q16.16 (32-bit signed) to Real for display
    function real fixed_to_real(input signed [31:0] val);
        begin
            fixed_to_real = real'(val) / 65536.0;
        end
    endfunction

    // =========================================================================
    // 6. Test Stimulus & Monitoring
    // =========================================================================
    integer vertex_idx;

    initial begin
        // --- Setup ---
        $display("--- SIMULATION START ---");
        
        // 1. Load Memory
        // Ensure "vertex_data.mem" exists in simulation directory
        if ($fopen("vertex_data.mem", "r") == 0) begin
            $display("ERROR: vertex_data.mem not found!");
            $finish;
        end
        // Load data directly into the BRAM instance inside DUT
        $readmemh("vertex_data.mem", dut.vertex_ram.ram);

        // 2. Reset
        rst = 1;
        #100;
        rst = 0;
        
        // 3. Monitor Loop for 3 Vertices
        for (vertex_idx = 0; vertex_idx < 6; vertex_idx += 1) begin
            $display("\n==========================================");
            $display(" Processing Vertex %0d", vertex_idx);
            $display("==========================================");

            // -----------------------------------------------------------------
            // A. Log INPUTS (Model Space)
            // -----------------------------------------------------------------
            // Wait for Fetch to complete and Transform to start.
            // At this point, registers x_local/y_local/etc should contain the fetched data.
            wait(dut.state_i == dut.S_MATRIX_TRANSFORM);
            
            // NOTE: Ensure 'x_local', 'u', 'v' match the register names in your DUT
//            $display("  [0] Input Data (Model Space - from RAM):");
//            $display("      X: %0.4f (Hex: %h)", fixed_to_real(dut.x_local_i), dut.x_local_i);
//            $display("      Y: %0.4f (Hex: %h)", fixed_to_real(dut.y_local_i), dut.y_local_i);
//            $display("      Z: %0.4f (Hex: %h)", fixed_to_real(dut.z_local_i), dut.z_local_i);
//            // Assuming U/V are just passed through registers
//            $display("      U: %0.4f (Hex: %h)", fixed_to_real(dut.u_local_i), dut.u_local_i);
//            $display("      V: %0.4f (Hex: %h)", fixed_to_real(dut.v_local_i), dut.v_local_i);

            // Wait for the transition out of Transform
            @(posedge clk); 
            while (dut.state_i == dut.S_MATRIX_TRANSFORM) @(posedge clk);
            

            // -----------------------------------------------------------------
            // B. Log CLIP SPACE (After Matrix Mult)
            // -----------------------------------------------------------------
            // Now in S_PERSP_DIVIDE, but regs hold Matrix result
//            $display("  [1] Clip Space (Post-Matrix):");
//            $display("      X: %0.4f (Hex: %h)", fixed_to_real(dut.x_clip_i), dut.x_clip_i);
//            $display("      Y: %0.4f (Hex: %h)", fixed_to_real(dut.y_clip_i), dut.y_clip_i);
//            $display("      Z: %0.4f (Hex: %h)", fixed_to_real(dut.z_clip_i), dut.z_clip_i);
//            $display("      W: %0.4f (Hex: %h)", fixed_to_real(dut.w_clip_i), dut.w_clip_i);

            // -----------------------------------------------------------------
            // C. Log NDC (Normalized Device Coordinates)
            // -----------------------------------------------------------------
            // Wait for Division to finish
            wait(dut.state_i == dut.S_VIEWPORT_MAP);
            
//            $display("  [2] NDC (Perspective Divide):");
//            $display("      X: %0.4f", fixed_to_real(dut.x_ndc_i));
//            $display("      Y: %0.4f", fixed_to_real(dut.y_ndc_i));
//            // New Z Logic Check
//            $display("      Z: %0.4f", fixed_to_real(dut.z_ndc_i));

            // -----------------------------------------------------------------
            // D. Log FINAL OUTPUT (Screen Space)
            // -----------------------------------------------------------------
            // Wait until state goes back to Fetch
            wait(dut.state_i == dut.S_VERTEX_FETCH);
            @(posedge clk); // Settle final assignment

            $display("  [3] FINAL OUTPUT (Screen Coords): %t", $time);
            $display("      x: %0.4f (Hex: %h)", fixed_to_real(dut.o_x), dut.o_x);
            $display("      y: %0.4f (Hex: %h)", fixed_to_real(dut.o_y), dut.o_y);
            $display("      z: %0d   (Hex: %h)", dut.o_z, dut.o_z); // Z is 8-bit int now
            
            // Small delay to separate outputs visually
            #10;
        end

        $display("\n--- SIMULATION DONE ---");
        $finish;
    end

endmodule