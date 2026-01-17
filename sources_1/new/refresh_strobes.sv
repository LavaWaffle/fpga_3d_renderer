module refresh_strobes #(
    parameter int CLK_HZ = 100_000_000  // Default 100 MHz
)(
    input  logic clk,
    input  logic rst,      // Always good practice to include a reset
    output logic strb_60,  // Pulses high for 1 cycle, 60 times/sec
    output logic strb_30,  // Pulses high for 1 cycle, 30 times/sec
    output logic strb_15   // Pulses high for 1 cycle, 15 times/sec
);

    // Calculate the number of cycles for the fastest rate (60Hz)
    // We use -1 because the counter starts at 0
    localparam int CYCLES_PER_60HZ = (CLK_HZ / 60) - 1;

    // Main counter for the base 60Hz frequency
    reg [31:0] counter;
    
    // 2-bit sub-counter to derive 30Hz and 15Hz from the 60Hz signal
    // 00 -> Fire all (15, 30, 60)
    // 01 -> Fire 60
    // 10 -> Fire 30, 60
    // 11 -> Fire 60
    logic [1:0] sub_counter;

    always_ff @(posedge clk) begin
        if (rst) begin
            counter     <= 0;
            sub_counter <= 0;
            strb_60     <= 1'b0;
            strb_30     <= 1'b0;
            strb_15     <= 1'b0;
        end else begin
            // Default: Strobes are low unless explicitly set high
            strb_60 <= 1'b0;
            strb_30 <= 1'b0;
            strb_15 <= 1'b0;

            if (counter == CYCLES_PER_60HZ) begin
                // 1. Base 60Hz Strobe always fires here
                counter <= 0;
                strb_60 <= 1'b1;

                // 2. Handle sub-divisions
                sub_counter <= sub_counter + 1'b1;

                // Fire 30Hz every other time (when LSB is 0)
                if (sub_counter[0] == 1'b0) begin
                    strb_30 <= 1'b1;
                end

                // Fire 15Hz every fourth time (when both bits are 0)
                if (sub_counter == 2'b00) begin
                    strb_15 <= 1'b1;
                end

            end else begin
                counter <= counter + 1;
            end
        end
    end

endmodule