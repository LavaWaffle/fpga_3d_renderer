# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "numpy",
#     "pillow",
# ]
# ///

import numpy as np
from PIL import Image, ImageDraw

# ==============================================================================
# 1. SETUP
# ==============================================================================
SCREEN_WIDTH = 320
SCREEN_HEIGHT = 240
BACKGROUND_COLOR = (0, 0, 0)
TRIANGLE_COLOR = (255, 0, 0)

# The exact MVP matrix
mvp_matrix = np.array([
    [   0.750,    0.000,    0.000,    0.000],
    [   0.000,    1.000,    0.000,    0.000],
    [   0.000,    0.000,   -1.105,    8.947],
    [   0.000,    0.000,   -1.000,   10.000]], dtype=np.float32)

TRI_SCALE = 0.5  # 0.5 = Half Size
base_h = 10.0
base_w = 13.333

# Vertex Data (X, Y, Z, W)
# Standard 3D Coordinates: Positive Y is UP
vertices = [
    # V0: Bottom Left (Y is Negative)
    np.array([-base_w * TRI_SCALE, -base_h * TRI_SCALE, 0.0, 1.0]),
    
    # V1: Bottom Right (Y is Negative)
    np.array([ base_w * TRI_SCALE, -base_h * TRI_SCALE, 0.0, 1.0]),
    
    # V2: Top Center (Y is Positive)
    np.array([ 0.000,               base_h * TRI_SCALE, 0.0, 1.0])
]

# UV Coordinates
uvs = [
    (0.0, 0.0), # V0
    (1.0, 0.0), # V1
    (0.0, 1.0)  # V2
]

# ==============================================================================
# 2. HELPER: Q16.16 HEX CONVERTER
# ==============================================================================
def float_to_hex(val):
    """Converts a float to a 32-bit Q16.16 hex string."""
    fixed_val = int(val * 65536.0)
    if fixed_val < 0:
        fixed_val = (1 << 32) + fixed_val
    return f"{fixed_val & 0xFFFFFFFF:08X}"

def print_hex_data(verts, uv_coords):
    names = ["Bottom-Left", "Bottom-Right", "Top-Center"]
    print("// ==========================================")
    print("// VERTEX DATA (Q16.16 HEX FORMAT)")
    print("// Format: X, Y, Z, U, V")
    print("// ==========================================")
    
    for i, (v, uv) in enumerate(zip(verts, uv_coords)):
        x, y, z = v[0], v[1], v[2]
        u, v_coord = uv
        
        print(f"// V{i}: ({x:.3f}, {y:.3f}, {z:.3f}) {names[i]}")
        print(float_to_hex(x)) # X
        print(float_to_hex(y)) # Y
        print(float_to_hex(z)) # Z
        print(float_to_hex(u)) # U
        print(float_to_hex(v_coord)) # V
        print("")

# ==============================================================================
# 3. GEOMETRY PIPELINE
# ==============================================================================
def run_pipeline(verts, mvp_mat):
    screen_points = []
    print("\n--- PIPELINE EXECUTION LOG ---")
    
    for i, v in enumerate(verts):
        # STEP 1: Matrix Transform
        clip = mvp_mat @ v
        
        # STEP 2: Perspective Divide
        ndc_x = clip[0] / clip[3]
        ndc_y = clip[1] / clip[3]
        
        # STEP 3: Viewport Map (ORIGINAL METHOD)
        # We use (ndc_y + 1.0), which maps -1 to 0 and +1 to Height.
        # This implies 0 is "bottom" in math terms.
        math_screen_x = (ndc_x + 1.0) * (SCREEN_WIDTH / 2.0)
        math_screen_y = (ndc_y + 1.0) * (SCREEN_HEIGHT / 2.0)
        
        print(f"Vertex {i} Math Screen: ({math_screen_x:.2f}, {math_screen_y:.2f})")
        
        # DRAW COORDINATES (ORIGINAL METHOD)
        # We manually subtract from SCREEN_HEIGHT to flip it for the image file.
        draw_x = math_screen_x
        draw_y = SCREEN_HEIGHT - math_screen_y
        
        screen_points.append((int(draw_x), int(draw_y)))

    return screen_points

# ==============================================================================
# 4. MAIN EXECUTION
# ==============================================================================
if __name__ == "__main__":
    # 1. Print Hex
    print_hex_data(vertices, uvs)

    # 2. Run Pipeline
    final_screen_points = run_pipeline(vertices, mvp_matrix)
    
    # 3. Draw
    img = Image.new('RGB', (SCREEN_WIDTH, SCREEN_HEIGHT), BACKGROUND_COLOR)
    draw = ImageDraw.Draw(img)
    draw.polygon(final_screen_points, fill=TRIANGLE_COLOR)

    # 4. Save
    output_filename = "pipeline_output.png"
    img.save(output_filename)
    print(f"\nGenerated image saved to: {output_filename}")