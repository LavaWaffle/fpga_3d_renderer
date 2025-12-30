import os

def generate_mem_files():
    # Configuration based on your SV loop
    DEPTH = 76800
    
    # --- Frame Buffer Settings ---
    # 12'h000 -> 12 bits = 3 hex digits
    FB_FILENAME = "frame_buffer.mem"
    FB_WIDTH_HEX = 3 
    FB_VAL = 0x000 
    
    # --- Z Buffer Settings ---
    # 8'hFF -> 8 bits = 2 hex digits
    ZB_FILENAME = "z_buffer.mem"
    ZB_WIDTH_HEX = 2
    ZB_VAL = 0xFF

    print(f"Generating {FB_FILENAME} with {DEPTH} entries of {FB_WIDTH_HEX}-digit hex...")
    with open(FB_FILENAME, 'w') as f:
        # Format: {:03X} for 3 digits, {:02X} for 2 digits
        # We pre-calculate the string to speed up the loop
        line_str = f"{FB_VAL:0{FB_WIDTH_HEX}X}\n"
        
        for _ in range(DEPTH):
            f.write(line_str)

    print(f"Generating {ZB_FILENAME} with {DEPTH} entries of {ZB_WIDTH_HEX}-digit hex...")
    with open(ZB_FILENAME, 'w') as f:
        line_str = f"{ZB_VAL:0{ZB_WIDTH_HEX}X}\n"
        
        for _ in range(DEPTH):
            f.write(line_str)
            
    print("Done. Files created in current directory.")

if __name__ == "__main__":
    generate_mem_files()