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
        for (vertex_idx = 0; vertex_idx < 3; vertex_idx += 1) begin
            $display("\n==========================================");
            $display(" Processing Vertex %0d", vertex_idx);
            $display("==========================================");

            // -----------------------------------------------------------------
            // A. Log INPUTS (Model Space)
            // -----------------------------------------------------------------
            // Wait for Fetch to complete and Transform to start.
            // At this point, registers x_local/y_local/etc should contain the fetched data.
            wait(dut.state == dut.S_MATRIX_TRANSFORM);
            
            // NOTE: Ensure 'x_local', 'u', 'v' match the register names in your DUT
            $display("  [0] Input Data (Model Space - from RAM):");
            $display("      X: %0.4f (Hex: %h)", fixed_to_real(dut.x), dut.x);
            $display("      Y: %0.4f (Hex: %h)", fixed_to_real(dut.y), dut.y);
            $display("      Z: %0.4f (Hex: %h)", fixed_to_real(dut.z), dut.z);
            // Assuming U/V are just passed through registers
            $display("      U: %0.4f (Hex: %h)", fixed_to_real(dut.u), dut.u);
            $display("      V: %0.4f (Hex: %h)", fixed_to_real(dut.v), dut.v);

            // Wait for the transition out of Transform
            @(posedge clk); 
            while (dut.state == dut.S_MATRIX_TRANSFORM) @(posedge clk);
            
            // -----------------------------------------------------------------
            // B. Log CLIP SPACE (After Matrix Mult)
            // -----------------------------------------------------------------
            // Now in S_PERSP_DIVIDE, but regs hold Matrix result
            $display("  [1] Clip Space (Post-Matrix):");
            $display("      X: %0.4f (Hex: %h)", fixed_to_real(dut.x_out), dut.x_out);
            $display("      Y: %0.4f (Hex: %h)", fixed_to_real(dut.y_out), dut.y_out);
            $display("      Z: %0.4f (Hex: %h)", fixed_to_real(dut.z_out), dut.z_out);
            $display("      W: %0.4f (Hex: %h)", fixed_to_real(dut.w_out), dut.w_out);

            // -----------------------------------------------------------------
            // C. Log NDC (Normalized Device Coordinates)
            // -----------------------------------------------------------------
            // Wait for Division to finish
            wait(dut.state == dut.S_VIEWPORT_MAP);
            
            $display("  [2] NDC (Perspective Divide):");
            $display("      X: %0.4f", fixed_to_real(dut.x_ndc));
            $display("      Y: %0.4f", fixed_to_real(dut.y_ndc));

            // -----------------------------------------------------------------
            // D. Log FINAL OUTPUT (Screen Space)
            // -----------------------------------------------------------------
            // Wait until state goes back to Fetch
            wait(dut.state == dut.S_VERTEX_FETCH);
            @(posedge clk); // Settle final assignment

            $display("  [3] FINAL OUTPUT (Screen Coords):");
            $display("      x:%0.4f (Hex: %h)", fixed_to_real(dut.x_screen), dut.x_screen);
            $display("      y:%0.4f (Hex: %h)", fixed_to_real(dut.y_screen), dut.y_screen);
            
            // Small delay to separate outputs visually
            #10;
        end

        $display("\n--- SIMULATION DONE ---");
        $finish;
    end

endmodule