module refresh_strobes #(
    parameter int CLK_HZ = 100_000_000  // Default 100 MHz
)(
    input  logic clk,
    input  logic rst,
    output logic strb_60,  // 1 cycle pulse, 60 times/sec
    output logic strb_30,  // 1 cycle pulse, 30 times/sec
    output logic strb_15,  // 1 cycle pulse, 15 times/sec
    output logic strb_10,  // 1 cycle pulse, 10 times/sec
    output logic strb_5,   // 1 cycle pulse, 5 times/sec
    output logic strb_1    // 1 cycle pulse, 1 time/sec
);

    // Calculate cycles for the fastest rate (60Hz)
    localparam int CYCLES_PER_60HZ = (CLK_HZ / 60) - 1;

    // Main counter for the base 60Hz frequency
    logic [31:0] counter;
    
    // Sub-counter to track 0 to 59 (1 second worth of 60Hz ticks)
    // We need 6 bits to store up to 59.
    logic [5:0] tick_cnt;

    always_ff @(posedge clk) begin
        if (rst) begin
            counter  <= 0;
            tick_cnt <= 0;
            strb_60  <= 1'b0;
            strb_30  <= 1'b0;
            strb_15  <= 1'b0;
            strb_10  <= 1'b0;
            strb_5   <= 1'b0;
            strb_1   <= 1'b0;
        end else begin
            // Default: Strobes are low unless explicitly set high
            strb_60 <= 1'b0;
            strb_30 <= 1'b0;
            strb_15 <= 1'b0;
            strb_10 <= 1'b0;
            strb_5  <= 1'b0;
            strb_1  <= 1'b0;

            if (counter == CYCLES_PER_60HZ) begin
                // --- 60Hz Base Tick ---
                counter <= 0;
                strb_60 <= 1'b1; // Always fires here

                // Manage the 0-59 circular counter
                if (tick_cnt == 59) begin
                    tick_cnt <= 0;
                end else begin
                    tick_cnt <= tick_cnt + 1'b1;
                end

                // --- Derive Dividers ---
                // We check the *current* value of tick_cnt before it increments
                // This ensures everything aligns perfectly at tick_cnt == 0

                // 30Hz: Every 2nd tick (0, 2, 4...)
                if (tick_cnt[0] == 1'b0) begin 
                    strb_30 <= 1'b1;
                end

                // 15Hz: Every 4th tick (0, 4, 8...)
                if (tick_cnt[1:0] == 2'b00) begin
                    strb_15 <= 1'b1;
                end

                // 10Hz: Every 6th tick (0, 6, 12...)
                if (tick_cnt % 6 == 0) begin
                    strb_10 <= 1'b1;
                end

                // 5Hz: Every 12th tick (0, 12, 24...)
                if (tick_cnt % 12 == 0) begin
                    strb_5 <= 1'b1;
                end

                // 1Hz: Every 60th tick (Only at 0)
                if (tick_cnt == 0) begin
                    strb_1 <= 1'b1;
                end

            end else begin
                counter <= counter + 1;
            end
        end
    end

endmodule