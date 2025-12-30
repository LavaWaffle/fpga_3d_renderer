# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "pillow",
# ]
# ///

from PIL import Image, ImageOps

# --- CONFIGURATION ---
# Set to True to dye the gray grass texture green. 
# Set to False to keep the original grayscale file.
COLORIZE_GRASS = True 

# The color to apply (Standard Minecraft "Plains" Biome Green)
# Feel free to change this hex code to a different biome color.
GRASS_GREEN_HEX = "#91bd59" 

def combine_textures():
    # 1. Define dimensions
    target_canvas_size = (64, 64)
    target_quadrant_size = (32, 32) # We scale 16x16 -> 32x32
    
    canvas = Image.new('RGBA', target_canvas_size, (0, 0, 0, 0))

    try:
        # 2. Load the source images
        grass_side = Image.open("grass_block_side.png").convert("RGBA")
        grass_top = Image.open("grass_block_top.png").convert("RGBA")
        dirt = Image.open("dirt.png").convert("RGBA")
        
        # 3. Handle the Grass Top Colorization
        if COLORIZE_GRASS:
            # We convert the hex string to an RGB tuple
            color_rgb = tuple(int(GRASS_GREEN_HEX.lstrip('#')[i:i+2], 16) for i in (0, 2, 4))
            
            # Create a solid color layer
            color_layer = Image.new("RGB", grass_top.size, color_rgb)
            
            # Multiply the grayscale texture by the color
            # We must handle the alpha channel separately to avoid turning transparent pixels green
            grayscale_rgb = grass_top.convert("RGB")
            mask = grass_top.split()[3] # Get the alpha channel
            
            tinted_rgb = ImageChops.multiply(grayscale_rgb, color_layer)
            grass_top = Image.merge("RGBA", (*tinted_rgb.split(), mask))
            print(f"Applied tint {GRASS_GREEN_HEX} to grass top.")

        # 4. Scale images (16x16 -> 32x32)
        # We use NEAREST to preserve the 'pixel art' look (no blurring)
        grass_side = grass_side.resize(target_quadrant_size, resample=Image.Resampling.NEAREST)
        grass_top = grass_top.resize(target_quadrant_size, resample=Image.Resampling.NEAREST)
        dirt = dirt.resize(target_quadrant_size, resample=Image.Resampling.NEAREST)
        
        # Create the White Square (already scaled size)
        white_square = Image.new('RGBA', target_quadrant_size, "white")

        # 5. Paste into quadrants
        # Top Left: (0, 0) -> Grass Side
        canvas.paste(grass_side, (0, 0))
        
        # Top Right: (32, 0) -> Grass Top
        canvas.paste(grass_top, (32, 0))
        
        # Bottom Left: (0, 32) -> Dirt
        canvas.paste(dirt, (0, 32))
        
        # Bottom Right: (32, 32) -> White Square
        canvas.paste(white_square, (32, 32))

        # 6. Save
        output_filename = "combined_block_64.png"
        canvas.save(output_filename)
        print(f"Success! Saved as {output_filename}")

    except FileNotFoundError as e:
        print(f"Error: {e}")
        print("Ensure 'grass_block_side.png', 'grass_block_top.png', and 'dirt.png' are present.")
    except Exception as e:
        print(f"An unexpected error occurred: {e}")

# Helper import for the math blending
from PIL import ImageChops

if __name__ == "__main__":
    combine_textures()