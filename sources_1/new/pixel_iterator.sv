`timescale 1ns / 1ps

module pixel_iterator #(
    parameter int TILE_ID = 0 // 0 to 1, 0 = Evens, 1 = Odds
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
    output reg [15:0] o_zb_addr     
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
            if ((r_x + 2) <= r_max_x) begin
                // Move Right
                next_x = r_x + 2;
                move_success = 1;
            end else if (r_y < r_max_y) begin
                // Move Down, Reset X
                next_x = (r_min_x[0] == TILE_ID) ? r_min_x : r_min_x + 1;
                next_y = r_y + 1;
                move_success = 1;
            end else begin
                // Finished
                last_pixel = 1;
            end
        end
    end

    logic [16:0] next_addr;
    always_comb begin
        // (y * (SCREEN_WIDTH/2)) + (x/2)
        // 320/2 = 160.
        next_addr = ($unsigned(next_y) * 160) + ($unsigned(next_x) >> 1);
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

                        // Set r_x to the starting point, but SUBTRACT 2
                        // so that the first 'next_x' calculation in RUN hits the actual start.
                        if ((i_min_x[0]) != TILE_ID) begin
                            r_x <= i_min_x + 1 - 2; 
                        end else begin
                            r_x <= i_min_x - 2;
                        end
                        r_y         <= i_min_y;
                        
                        state       <= PIXEL_ITE_RUN;
                        o_valid     <= 0;
                    end
                end

                PIXEL_ITE_RUN: begin
                    
                    if (move_success) begin
                        r_x         <= next_x;
                        r_y         <= next_y;
                        
                        o_x         <= next_x;
                        o_y         <= next_y;
                        o_zb_addr   <= next_addr; // Uses the clean logic
                        o_valid     <= 1;
                    end else if (last_pixel) begin
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