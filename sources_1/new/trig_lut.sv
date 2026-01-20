module trig_lut (
    input  logic [3:0]  angle_idx, // 0 to 15
    output logic [31:0] sin_out,   // Q16.16
    output logic [31:0] cos_out    // Q16.16
);

    // Force Vivado to use LUTRAM (Distributed ROM)
    (* rom_style = "distributed" *)
    logic signed [17:0] sin_rom [0:15];

    initial begin
        sin_rom[ 0] = 18'h00000; //   0.0 deg | Sin: 0.0000
        sin_rom[ 1] = 18'h061F8; //  22.5 deg | Sin: 0.3827
        sin_rom[ 2] = 18'h0B505; //  45.0 deg | Sin: 0.7071
        sin_rom[ 3] = 18'h0EC83; //  67.5 deg | Sin: 0.9239
        sin_rom[ 4] = 18'h10000; //  90.0 deg | Sin: 1.0000
        sin_rom[ 5] = 18'h0EC83; // 112.5 deg | Sin: 0.9239
        sin_rom[ 6] = 18'h0B505; // 135.0 deg | Sin: 0.7071
        sin_rom[ 7] = 18'h061F8; // 157.5 deg | Sin: 0.3827
        sin_rom[ 8] = 18'h00000; // 180.0 deg | Sin: 0.0000
        sin_rom[ 9] = 18'h39E08; // 202.5 deg | Sin: -0.3827
        sin_rom[10] = 18'h34AFB; // 225.0 deg | Sin: -0.7071
        sin_rom[11] = 18'h3137D; // 247.5 deg | Sin: -0.9239
        sin_rom[12] = 18'h30000; // 270.0 deg | Sin: -1.0000
        sin_rom[13] = 18'h3137D; // 292.5 deg | Sin: -0.9239
        sin_rom[14] = 18'h34AFB; // 315.0 deg | Sin: -0.7071
        sin_rom[15] = 18'h39E08; // 337.5 deg | Sin: -0.3827
    end

    // Logic to derive Cosine from Sine (Offset by +4 steps / 90 deg)
    logic [3:0] cos_addr;
    assign cos_addr = angle_idx + 4'd4;

    always_comb begin
        // Sign extend 18-bit Q2.16 -> 32-bit Q16.16
        // We replicate the sign bit (bit 17) 14 times to fill the upper bits
        sin_out = {{14{sin_rom[angle_idx][17]}}, sin_rom[angle_idx]};
        cos_out = {{14{sin_rom[cos_addr][17]}}, sin_rom[cos_addr]};
    end

endmodule
