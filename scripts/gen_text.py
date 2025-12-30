# gen_texture.py
# Generates a 64x64 texture (4096 lines) in hex format for Verilog $readmemh

def generate_xor_texture():
    filename = "texture.mem"
    width = 64
    height = 64
    
    print(f"Generating {width}x{height} texture to {filename}...")
    
    with open(filename, "w") as f:
        for y in range(height):
            for x in range(width):
                # XOR Pattern Logic
                # We combine X and Y to create a pattern that changes over the surface
                r = (x ^ y) & 0xF
                g = (x + y) & 0xF
                b = (x & y) & 0xF
                
                # Combine into 12-bit color (0xRGB)
                pixel = (r << 8) | (g << 4) | b
                
                # Write hex string (e.g., "f05")
                f.write(f"{pixel:03x}\n")
                
    print("Done! Texture file created.")

if __name__ == "__main__":
    generate_xor_texture()