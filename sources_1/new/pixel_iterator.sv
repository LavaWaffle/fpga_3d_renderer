`timescale 1ns / 1ps

module pixel_iterator(
    input wire i_clk,
    input wire i_rst,
    
    // Control
    input wire i_start,             // Pulse to start generating pixels
    output reg o_done,              // High for 1 cycle when iteration completes
    
    // Bounding Box (Latched internally on start)
    input wire signed [15:0] i_min_x, i_max_x,
    input wire signed [15:0] i_min_y, i_max_y,
    
    // Pipeline Outputs (To Stage 2: Edge Engine)
    output reg signed [15:0] o_x,
    output reg signed [15:0] o_y,
    output reg o_valid,             // High = Valid Pixel, Low = Bubble/Idle
    
    // Memory Request (To Memory Controller)
    output reg [16:0] o_zb_addr     // Initiates Read for Z-Buffer
);

    typedef enum {
        PIXEL_ITE_IDLE = 0,
        PIXEL_ITE_RUN  = 1,
        PIXEL_ITE_DONE = 2
    } pixel_ite_state_t;

    // Internal State
    pixel_ite_state_t state;

    // Internal counters (Shadow copies of output to avoid feedback loops on outputs)
    reg signed [15:0] r_x, r_y;
    reg signed [15:0] r_max_x, r_max_y, r_min_x; // Latch inputs to ensure stability

    always @(posedge i_clk) begin
        if (i_rst) begin
            state    <= PIXEL_ITE_IDLE;
            o_valid  <= 0;
            o_done   <= 0;
            o_x      <= 0;
            o_y      <= 0;
            o_zb_addr <= 0;
            r_x      <= 0;
            r_y      <= 0;
        end else begin
            // Default pulse resets
            o_done  <= 0;
            o_valid <= 0; // Default to invalid unless we are actively iterating

            case (state)
                PIXEL_ITE_IDLE: begin
                    if (i_start) begin
                        // Latch bounding box to prevent issues if inputs change mid-triangle
                        r_x     <= i_min_x;
                        r_y     <= i_min_y;
                        r_min_x <= i_min_x;
                        r_max_x <= i_max_x;
                        r_max_y <= i_max_y;
                        
                        // Output the very first pixel immediately
                        o_x       <= i_min_x;
                        o_y       <= i_min_y;
                        o_zb_addr <= (i_min_y * 320) + i_min_x;
                        o_valid   <= 1;
                        
                        state   <= PIXEL_ITE_RUN;
                    end
                end

                PIXEL_ITE_RUN: begin
                    // ---------------------------------------------------------
                    // 1. Calculate Next Position
                    // ---------------------------------------------------------
                    if (r_x < r_max_x) begin
                        // Move Right
                        r_x <= r_x + 1;
                        
                        // Pipeline Output
                        o_x       <= r_x + 1;
                        o_y       <= r_y;
                        o_zb_addr <= (r_y * 320) + (r_x + 1);
                        o_valid   <= 1;
                        
                    end else begin
                        // End of Row
                        if (r_y < r_max_y) begin
                            // Move Down, Reset X
                            r_x <= r_min_x;
                            r_y <= r_y + 1;
                            
                            // Pipeline Output
                            o_x       <= r_min_x;
                            o_y       <= r_y + 1;
                            o_zb_addr <= ((r_y + 1) * 320) + r_min_x;
                            o_valid   <= 1;
                            
                        end else begin
                            // End of Box
                            state   <= PIXEL_ITE_DONE;
                            o_valid <= 0; // Stop the pipeline
                        end
                    end
                end

                PIXEL_ITE_DONE: begin
                    o_done <= 1;
                    state  <= PIXEL_ITE_IDLE;
                end
            endcase
        end
    end

endmodule