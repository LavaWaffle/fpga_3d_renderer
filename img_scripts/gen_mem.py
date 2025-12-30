# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "pillow",
# ]
# ///

import sys
from pathlib import Path
from PIL import Image

def main():
    input_filename = "combined_block_64.png"
    output_filename = "texture.mem"
    
    # Check if input exists
    input_path = Path(input_filename)
    if not input_path.exists():
        print(f"Error: '{input_filename}' not found in the current directory.")
        sys.exit(1)

    print(f"Processing {input_filename}...")

    try:
        with Image.open(input_path) as img:
            # Ensure image is in RGB mode
            img = img.convert("RGB")
            
            # Verify dimensions
            if img.size != (64, 64):
                print(f"Warning: Input is {img.size}, resizing to (64, 64).")
                img = img.resize((64, 64))

            width, height = img.size
            
            with open(output_filename, 'w') as f:
                # Loop row by row (y), then column by column (x)
                # This ensures standard raster order for FPGA memory initialization
                for y in range(height):
                    for x in range(width):
                        r, g, b = img.getpixel((x, y))
                        
                        # Convert 8-bit (0-255) to 4-bit (0-15)
                        # Shift right by 4 bits
                        r_4 = r >> 4
                        g_4 = g >> 4
                        b_4 = b >> 4
                        
                        # Format as 3-digit hex string (e.g., f0a)
                        hex_val = f"{r_4:x}{g_4:x}{b_4:x}"
                        
                        f.write(hex_val + '\n')
            
            print(f"Success! Generated '{output_filename}' with {width * height} lines.")

    except Exception as e:
        print(f"An error occurred: {e}")

if __name__ == "__main__":
    main()