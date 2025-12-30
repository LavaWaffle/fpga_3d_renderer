module texture_rom (
    input wire i_clk,
    input wire [11:0] i_addr, // 64x64 = 4096 pixels
    output reg [11:0] o_data
);
    (* ram_style = "block" *)
    reg [11:0] rom [0:4095];

    initial begin
        $readmemh("texture.mem", rom);
    end

    always @(posedge i_clk) begin
        o_data <= rom[i_addr];
    end
endmodule