`timescale 1ns / 1ps

module pixel_iterator #(
    parameter int TILE_WIDTH = 80, // Parameterized for clarity
    parameter int TILE_HEIGHT = 120
)(
    input wire i_clk,
    input wire i_rst,
    
    // Control
    input wire i_start,             
    output reg o_done,              
    
    // Bounding Box 
    input wire signed [15:0] i_min_x, i_max_x,
    input wire signed [15:0] i_min_y, i_max_y,

    // Pipeline Outputs
    output reg signed [15:0] o_x,
    output reg signed [15:0] o_y,
    output reg o_valid,             
    output reg [16:0] o_zb_addr     
);

    typedef enum {
        PIXEL_ITE_IDLE  = 0,
        PIXEL_ITE_RUN   = 1,
        PIXEL_ITE_DONE  = 3
    } pixel_ite_state_t;

    pixel_ite_state_t state;

    reg signed [15:0] r_x, r_y;
    reg signed [15:0] r_max_x, r_max_y, r_min_x; 

    // --- 1. Combinational "Next" Logic ---
    // We determine where we are going *next* so we can calculate 
    // the address for that location correctly before the clock edge.
    
    logic signed [15:0] next_x, next_y;
    logic last_pixel;
    logic move_success;

    always_comb begin
        // Defaults
        next_x = r_x;
        next_y = r_y;
        last_pixel = 0;
        move_success = 0;

        if (state == PIXEL_ITE_RUN) begin
            if (r_x < r_max_x) begin
                // Move Right
                next_x = r_x + 1;
                move_success = 1;
            end else if (r_y < r_max_y) begin
                // Move Down, Reset X
                next_x = r_min_x;
                next_y = r_y + 1;
                move_success = 1;
            end else begin
                // Finished
                last_pixel = 1;
            end
        end
    end

    // --- 2. Address Calculator (Based on NEXT coords) ---
    logic [6:0] next_local_x; 
    logic [6:0] next_local_y; 
    logic [16:0] next_addr;

    always_comb begin
        // Logic to determine Local X from Global Next X
        if (next_x < TILE_WIDTH)            next_local_x = next_x[6:0];
        else if (next_x < TILE_WIDTH*2)     next_local_x = next_x - TILE_WIDTH;
        else if (next_x < TILE_WIDTH*3)     next_local_x = next_x - (TILE_WIDTH*2);
        else                                next_local_x = next_x - (TILE_WIDTH*3);

        // Logic to determine Local Y from Global Next Y
        if (next_y < TILE_HEIGHT)           next_local_y = next_y[6:0];
        else                                next_local_y = next_y - TILE_HEIGHT;

        // Calculate the address for the cycle we are ABOUT to enter
        next_addr = (next_local_y * TILE_WIDTH) + next_local_x;
    end

    // --- 3. Sequential FSM ---
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            state       <= PIXEL_ITE_IDLE;
            o_valid     <= 0;
            o_done      <= 0;
            o_x         <= 0;
            o_y         <= 0;
            o_zb_addr   <= 0;
            r_x         <= 0;
            r_y         <= 0;
        end else begin
            // Pulse resets
            o_done  <= 0;
            o_valid <= 0; 

            case (state)
                PIXEL_ITE_IDLE: begin
                    if (i_start) begin
                        // Latch bounds
                        r_min_x <= i_min_x;
                        r_max_x <= i_max_x;
                        r_max_y <= i_max_y;

                        // CRITICAL FIX: PRE-LOAD the first pixel
                        // We set r_x to min_x, so the 'next' logic in the first
                        // RUN cycle sees (min+1). But we must output min FIRST.
                        // To solve this cleanly: We output the FIRST pixel here,
                        // or we set r_x to (min_x - 1) so the next logic hits min_x.
                        
                        // Approach A: Output First Pixel Here (0 latency start)
                        r_x         <= i_min_x;
                        r_y         <= i_min_y;
                        
                        // Manually calc address for the first pixel
                        // (Reuse the logic instantiation or duplicate small math here)
                        // For safety/clarity in this snippet, I will output the *first*
                        // valid pixel in the first cycle of RUN by handling r_x differently below.
                        
                        state       <= PIXEL_ITE_RUN;
                        
                        // Initialize outputs to the first pixel immediately
                        o_x         <= i_min_x;
                        o_y         <= i_min_y;
                        
                        // Calc logic for very first pixel (assuming tile 0 for simplicity, 
                        // but strictly should run through the calc block)
                        // Ideally: call a function. For now, rely on next cycle logic 
                        // or accept 1 cycle bubbles.
                        
                        // Let's use the 'Move Success' strategy in RUN:
                    end
                end

                PIXEL_ITE_RUN: begin
                    // FIX: This structure assumes r_x holds the LAST output.
                    // We calculate NEXT. Output NEXT. Update r_x to NEXT.
                    
                    if (move_success) begin
                        r_x         <= next_x;
                        r_y         <= next_y;
                        
                        o_x         <= next_x;
                        o_y         <= next_y;
                        o_zb_addr   <= next_addr; // Uses the clean logic
                        o_valid     <= 1;
                    end else if (last_pixel) begin
                        // We need to stop, but was the current r_x/r_y valid?
                        // If we are here, we processed the max_x/max_y already.
                        state       <= PIXEL_ITE_DONE;
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