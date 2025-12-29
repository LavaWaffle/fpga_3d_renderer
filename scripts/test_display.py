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
TRIANGLE_COLOR = (255, 0, 0) # Red
# Optional: Use a specific outline color to see the wireframe edges clearly
OUTLINE_COLOR = (255, 255, 255) 

# The exact MVP matrix (Unchanged)
mvp_matrix = np.array([
    [   0.750,    0.000,    0.000,    0.000],
    [   0.000,    1.000,    0.000,    0.000],
    [   0.000,    0.000,   -1.105,    8.947],
    [   0.000,    0.000,   -1.000,   10.000]], dtype=np.float32)

# --- CUBE CONFIGURATION ---
CUBE_SIZE = 4.0       # Total length of one side
hs = CUBE_SIZE / 2.0   # Half-Size (distance from origin to face)

# Helper: Define the 8 corners of a cube centered at (0,0,0)
# Naming: F=Front, B=Back, T=Top, Bt=Bottom, L=Left, R=Right
# Coordinates: (X, Y, Z)
c_fbl = [-hs, -hs,  hs] # Front Bottom Left
c_fbr = [ hs, -hs,  hs] # Front Bottom Right
c_ftr = [ hs,  hs,  hs] # Front Top Right
c_ftl = [-hs,  hs,  hs] # Front Top Left
c_bbl = [-hs, -hs, -hs] # Back Bottom Left
c_bbr = [ hs, -hs, -hs] # Back Bottom Right
c_btr = [ hs,  hs, -hs] # Back Top Right
c_btl = [-hs,  hs, -hs] # Back Top Left

# Helper to create a homogenous numpy array (x,y,z,1.0)
def mk_v(arr): return np.array(arr + [1.0], dtype=np.float32)

# 12 Triangles (36 Vertices total), CCW Winding Order
vertices = [
    # --- FRONT FACE (+Z) ---
    mk_v(c_fbl), mk_v(c_fbr), mk_v(c_ftr), # Tri 1
    mk_v(c_fbl), mk_v(c_ftr), mk_v(c_ftl), # Tri 2
    
    # --- RIGHT FACE (+X) ---
    mk_v(c_fbr), mk_v(c_bbr), mk_v(c_btr), # Tri 1
    mk_v(c_fbr), mk_v(c_btr), mk_v(c_ftr), # Tri 2
    
    # --- LEFT FACE (-X) ---
    mk_v(c_bbl), mk_v(c_fbl), mk_v(c_ftl), # Tri 1
    mk_v(c_bbl), mk_v(c_ftl), mk_v(c_btl), # Tri 2

    # --- TOP FACE (+Y) ---
    mk_v(c_ftl), mk_v(c_ftr), mk_v(c_btr), # Tri 1
    mk_v(c_ftl), mk_v(c_btr), mk_v(c_btl), # Tri 2

    # --- BOTTOM FACE (-Y) ---
    mk_v(c_bbl), mk_v(c_bbr), mk_v(c_fbr), # Tri 1
    mk_v(c_bbl), mk_v(c_fbr), mk_v(c_fbl), # Tri 2

    # --- BACK FACE (-Z) ---
    # Note: Winding viewed from outside looks reversed relative to axes, 
    # but strictly CCW around the normal vector pointing AWAY from cube.
    mk_v(c_bbr), mk_v(c_bbl), mk_v(c_btl), # Tri 1
    mk_v(c_bbr), mk_v(c_btl), mk_v(c_btr), # Tri 2
]

# Standard UV mapping (0,0 to 1,1) repeated for every face
# We need 36 UV coordinates to match the 36 vertices
uv_quad = [
    (0.0, 0.0), (1.0, 0.0), (1.0, 1.0), # Tri 1 (BL, BR, TR)
    (0.0, 0.0), (1.0, 1.0), (0.0, 1.0)  # Tri 2 (BL, TR, TL)
]
uvs = uv_quad * 6 # Repeat 6 times for 6 faces

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
    print("// ==========================================")
    print("// VERTEX DATA (Q16.16 HEX FORMAT)")
    print(f"// Total Vertices: {len(verts)} ({len(verts)//3} Triangles)")
    print("// Format: X, Y, Z, U, V")
    print("// ==========================================")
    
    for i, (v, uv) in enumerate(zip(verts, uv_coords)):
        x, y, z = v[0], v[1], v[2]
        u, v_coord = uv
        
        # Add a separator every 3 vertices (every triangle)
        if i % 3 == 0:
            print(f"// --- Triangle {i // 3} ---")

        print(f"// V{i}: ({x:.3f}, {y:.3f}, {z:.3f})")
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
        # Avoid divide by zero if w is 0 (shouldn't happen with this setup)
        w = clip[3] if clip[3] != 0 else 0.00001
        ndc_x = clip[0] / w
        ndc_y = clip[1] / w
        
        # STEP 3: Viewport Map
        math_screen_x = (ndc_x + 1.0) * (SCREEN_WIDTH / 2.0)
        math_screen_y = (ndc_y + 1.0) * (SCREEN_HEIGHT / 2.0)
        
        # DRAW COORDINATES
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

    # MODIFIED DRAWING LOOP:
    # Iterate 3 points at a time to form independent triangles.
    # Note: This is a simple "Painter's Algorithm" based on list order.
    # It does not perform real Z-buffering.
    for i in range(0, len(final_screen_points), 3):
        triangle_verts = final_screen_points[i : i+3]
        draw.polygon(triangle_verts, fill=TRIANGLE_COLOR, outline=OUTLINE_COLOR)

    # 4. Save
    output_filename = "cube_pipeline_output.png"
    img.save(output_filename)
    print(f"\nGenerated image saved to: {output_filename}")