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
OUTLINE_COLOR = (255, 255, 255) 

# The exact MVP matrix (Unchanged)
mvp_matrix = np.array([
    [ 7.5000000e-01,  0.0000000e+00,  0.0000000e+00,  0.0000000e+00],
    [ 0.0000000e+00,  8.9442718e-01, -4.4721359e-01, -1.1920929e-07],
    [ 0.0000000e+00, -4.9428868e-01, -9.8857737e-01,  1.0251953e+01],
    [ 0.0000000e+00, -4.4721359e-01, -8.9442718e-01,  1.1180340e+01]
], dtype=np.float32)

# --- CUBE CONFIGURATION ---
CUBE_SIZE = 4.5       
hs = CUBE_SIZE / 2.0  

# Corners
c_fbl = [-hs, -hs,  hs] 
c_fbr = [ hs, -hs,  hs] 
c_ftr = [ hs,  hs,  hs] 
c_ftl = [-hs,  hs,  hs] 
c_bbl = [-hs, -hs, -hs] 
c_bbr = [ hs, -hs, -hs] 
c_btr = [ hs,  hs, -hs] 
c_btl = [-hs,  hs, -hs] 

def mk_v(arr): return np.array(arr + [1.0], dtype=np.float32)

# 12 Triangles (36 Vertices total), Order is specific:
# 1. Front, 2. Right, 3. Left, 4. Top, 5. Bottom, 6. Back
vertices = [
    # --- FRONT FACE (+Z) ---
    mk_v(c_fbl), mk_v(c_fbr), mk_v(c_ftr), 
    mk_v(c_fbl), mk_v(c_ftr), mk_v(c_ftl), 
    
    # --- RIGHT FACE (+X) ---
    mk_v(c_fbr), mk_v(c_bbr), mk_v(c_btr), 
    mk_v(c_fbr), mk_v(c_btr), mk_v(c_ftr), 
    
    # --- LEFT FACE (-X) ---
    mk_v(c_bbl), mk_v(c_fbl), mk_v(c_ftl), 
    mk_v(c_bbl), mk_v(c_ftl), mk_v(c_btl), 

    # --- TOP FACE (+Y) ---
    mk_v(c_ftl), mk_v(c_ftr), mk_v(c_btr), 
    mk_v(c_ftl), mk_v(c_btr), mk_v(c_btl), 

    # --- BOTTOM FACE (-Y) ---
    mk_v(c_bbl), mk_v(c_bbr), mk_v(c_fbr), 
    mk_v(c_bbl), mk_v(c_fbr), mk_v(c_fbl), 

    # --- BACK FACE (-Z) ---
    mk_v(c_bbr), mk_v(c_bbl), mk_v(c_btl), 
    mk_v(c_bbr), mk_v(c_btl), mk_v(c_btr), 
]

# ==============================================================================
# UPDATED UV MAPPING LOGIC (Vertically Flipped)
# ==============================================================================

# Base coordinates for a single square face (0.0 to 1.0 relative)
# CHANGED: V coordinates are swapped (1.0 for bottom verts, 0.0 for top verts)
# This ensures the image is not upside down.
base_uv_quad = [
    # Tri 1: BL, BR, TR
    (0.0, 1.0), (1.0, 1.0), (1.0, 0.0), 
    # Tri 2: BL, TR, TL
    (0.0, 1.0), (1.0, 0.0), (0.0, 0.0)  
]

def generate_face_uvs(u_offset, v_offset):
    """
    Scales the base quad to 0.5 (since it's a 2x2 grid)
    and adds the specific quadrant offset.
    """
    face_uvs = []
    for u, v in base_uv_quad:
        # Scale by 0.5 for the atlas size, then add offset
        final_u = u_offset + (u * 0.5)
        final_v = v_offset + (v * 0.5)
        face_uvs.append((final_u, final_v))
    return face_uvs

# Defines for the 2x2 Grid offsets
# Grid Layout:
# (0.0, 0.0) [SIDE]  | (0.5, 0.0) [TOP]
# -------------------|-------------------
# (0.0, 0.5) [BOTT]  | (0.5, 0.5) [UNUSED]

uv_side   = generate_face_uvs(0.0, 0.0) # Top-Left
uv_top    = generate_face_uvs(0.5, 0.0) # Top-Right
uv_bottom = generate_face_uvs(0.0, 0.5) # Bottom-Left

# Assign UVs matching the order of 'vertices' list above
uvs = []
uvs += uv_side   # Front Face
uvs += uv_side   # Right Face
uvs += uv_side   # Left Face
uvs += uv_top    # Top Face   (Top Right of Atlas)
uvs += uv_bottom # Bottom Face (Bottom Left of Atlas)
uvs += uv_side   # Back Face

# ==============================================================================
# 2. HELPER: Q16.16 HEX CONVERTER
# ==============================================================================
def float_to_hex(val):
    """Converts a float to a 32-bit Q16.16 hex string."""
    # Q16.16 scaling
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
        
        if i % 3 == 0:
            print(f"// --- Triangle {i // 3} ---")

        print(f"// V{i}: ({x:.3f}, {y:.3f}, {z:.3f}) UV:({u:.3f}, {v_coord:.3f})")
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

    for i in range(0, len(final_screen_points), 3):
        triangle_verts = final_screen_points[i : i+3]
        draw.polygon(triangle_verts, fill=TRIANGLE_COLOR, outline=OUTLINE_COLOR)

    # 4. Save
    output_filename = "cube_pipeline_output.png"
    img.save(output_filename)
    print(f"\nGenerated image saved to: {output_filename}")