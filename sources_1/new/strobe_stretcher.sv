module strobe_stretcher #(
    parameter int CLK_HZ     = 100_000_000, // Default 100 MHz
    parameter int STRETCH_MS = 10           // Duration to stretch in milliseconds
)(
    input  logic clk,
    input  logic rst,
    input  logic strobe_in,    // The 1-cycle pulse to capture
    output logic stretched_out // Stays high for STRETCH_MS
);

    // Calculate cycles needed. 
    // We use longint for the calculation to prevent overflow before division 
    // (e.g., 100MHz * 500ms would overflow a 32-bit int).
    localparam int CYCLES_TO_WAIT = int'( (longint'(CLK_HZ) * STRETCH_MS) / 1000 );

    // Counter to track remaining time
    int counter;

    always_ff @(posedge clk) begin
        if (rst) begin
            counter       <= 0;
            stretched_out <= 1'b0;
        end else begin
            if (strobe_in) begin
                // Re-trigger: Reset timer to max whenever input fires
                counter       <= CYCLES_TO_WAIT;
                stretched_out <= 1'b1;
            end 
            else if (counter > 0) begin
                // Decrement if active
                counter <= counter - 1;
                // Keep output high
                stretched_out <= 1'b1;
            end 
            else begin
                // Time expired
                stretched_out <= 1'b0;
            end
        end
    end

endmodule