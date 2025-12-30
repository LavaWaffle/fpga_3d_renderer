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
# 1. SETUP & CONFIGURATION
# ==============================================================================
SCREEN_WIDTH = 320
SCREEN_HEIGHT = 240
BACKGROUND_COLOR = (0, 0, 0)
TRIANGLE_COLOR = (255, 0, 0)
OUTLINE_COLOR = (255, 255, 255)

# --- NEW: SUBDIVISION CONTROL ---
# 1 = Original (2 triangles per face)
# 2 = 8 triangles per face
# 4 = 32 triangles per face
SUBDIVISIONS = 1

# Output filename
MEM_FILENAME = "cube_data.mem"

# The exact MVP matrix (Unchanged)
mvp_matrix = np.array([
    [ 7.5000000e-01,  0.0000000e+00,  0.0000000e+00,  0.0000000e+00],
    [ 0.0000000e+00,  8.9442718e-01, -4.4721359e-01, -1.1920929e-07],
    [ 0.0000000e+00, -4.9428868e-01, -9.8857737e-01,  1.0251953e+01],
    [ 0.0000000e+00, -4.4721359e-01, -8.9442718e-01,  1.1180340e+01]
], dtype=np.float32)

# --- CUBE GEOMETRY ---
CUBE_SIZE = 5.5
hs = CUBE_SIZE / 2.0

# Define the 8 Master Corners
# (Left/Right, Bottom/Top, Back/Front)
c_fbl = np.array([-hs, -hs,  hs])
c_fbr = np.array([ hs, -hs,  hs])
c_ftr = np.array([ hs,  hs,  hs])
c_ftl = np.array([-hs,  hs,  hs])
c_bbl = np.array([-hs, -hs, -hs])
c_bbr = np.array([ hs, -hs, -hs])
c_btr = np.array([ hs,  hs, -hs])
c_btl = np.array([-hs,  hs, -hs])

# ==============================================================================
# 2. SUBDIVISION LOGIC
# ==============================================================================

def lerp(a, b, t):
    """Linear interpolation between a and b by t (0.0 to 1.0)."""
    return a + (b - a) * t

def generate_subdivided_face(bl, br, tr, tl, uv_bl, uv_br, uv_tr, uv_tl, steps):
    """
    Generates vertices and UVs for a subdivided quad.
    Input: 4 Corners (3D) and 4 UVs (2D).
    Output: List of vertices (X,Y,Z) and list of UVs (U,V).
    """
    out_verts = []
    out_uvs = []

    for r in range(steps):       # Rows
        for c in range(steps):   # Columns
            
            # Calculate ratios for the current cell
            # We need 4 points: Bottom-Left (00), Bottom-Right (10), Top-Right (11), Top-Left (01)
            # relative to this specific grid cell.
            
            # r_f = row float (0.0 to 1.0)
            r0 = r / steps
            r1 = (r + 1) / steps
            c0 = c / steps
            c1 = (c + 1) / steps

            # Helper to get interpolated pos and uv for a specific (row_ratio, col_ratio)
            def get_interp(rr, cr):
                # Interpolate left and right edges vertically
                pos_l = lerp(bl, tl, rr)
                pos_r = lerp(br, tr, rr)
                uv_l  = lerp(uv_bl, uv_tl, rr)
                uv_r  = lerp(uv_br, uv_tr, rr)
                
                # Interpolate horizontally
                pos = lerp(pos_l, pos_r, cr)
                uv  = lerp(uv_l, uv_r, cr)
                return pos, uv

            # Calculate the 4 corners of this sub-quad
            p00, t00 = get_interp(r0, c0) # BL
            p10, t10 = get_interp(r0, c1) # BR
            p11, t11 = get_interp(r1, c1) # TR
            p01, t01 = get_interp(r1, c0) # TL

            # --- Triangle 1 (BL -> BR -> TR) ---
            out_verts.extend([p00, p10, p11])
            out_uvs.extend([t00, t10, t11])

            # --- Triangle 2 (BL -> TR -> TL) ---
            out_verts.extend([p00, p11, p01])
            out_uvs.extend([t00, t11, t01])

    return out_verts, out_uvs

# ==============================================================================
# 3. MESH GENERATION
# ==============================================================================

# UV Offset Definitions
# We define the corners manually to ensure rotation/flipping is correct
# Format: (U, V)
# Reminder from original script: V=1.0 is bottom, V=0.0 is top.
# Atlas is 2x2.
# Side (Top-Left):   u:0.0-0.5, v:0.0-0.5
# Top (Top-Right):   u:0.5-1.0, v:0.0-0.5
# Bottom (Bot-Left): u:0.0-0.5, v:0.5-1.0

# UV Corners for "Side" (Front, Right, Left, Back)
uv_s_bl = np.array([0.0, 0.5])
uv_s_br = np.array([0.5, 0.5])
uv_s_tr = np.array([0.5, 0.0])
uv_s_tl = np.array([0.0, 0.0])

# UV Corners for "Top"
uv_t_bl = np.array([0.5, 0.5])
uv_t_br = np.array([1.0, 0.5])
uv_t_tr = np.array([1.0, 0.0])
uv_t_tl = np.array([0.5, 0.0])

# UV Corners for "Bottom"
uv_b_bl = np.array([0.0, 1.0])
uv_b_br = np.array([0.5, 1.0])
uv_b_tr = np.array([0.5, 0.5])
uv_b_tl = np.array([0.0, 0.5])

all_vertices = []
all_uvs = []

def add_face(c_bl, c_br, c_tr, c_tl, uv_bl, uv_br, uv_tr, uv_tl):
    v, u = generate_subdivided_face(c_bl, c_br, c_tr, c_tl, uv_bl, uv_br, uv_tr, uv_tl, SUBDIVISIONS)
    all_vertices.extend(v)
    all_uvs.extend(u)

# 1. Front Face (+Z) -> Uses Side UVs
add_face(c_fbl, c_fbr, c_ftr, c_ftl, uv_s_bl, uv_s_br, uv_s_tr, uv_s_tl)

# 2. Right Face (+X) -> Uses Side UVs
add_face(c_fbr, c_bbr, c_btr, c_ftr, uv_s_bl, uv_s_br, uv_s_tr, uv_s_tl)

# 3. Left Face (-X) -> Uses Side UVs
add_face(c_bbl, c_fbl, c_ftl, c_btl, uv_s_bl, uv_s_br, uv_s_tr, uv_s_tl)

# 4. Top Face (+Y) -> Uses Top UVs
add_face(c_ftl, c_ftr, c_btr, c_btl, uv_t_bl, uv_t_br, uv_t_tr, uv_t_tl)

# 5. Bottom Face (-Y) -> Uses Bottom UVs
add_face(c_bbl, c_bbr, c_fbr, c_fbl, uv_b_bl, uv_b_br, uv_b_tr, uv_b_tl)

# 6. Back Face (-Z) -> Uses Side UVs
add_face(c_bbr, c_bbl, c_btl, c_btr, uv_s_bl, uv_s_br, uv_s_tr, uv_s_tl)

# Convert to list of vec4 for pipeline compatibility
final_vertices_vec4 = [np.array([v[0], v[1], v[2], 1.0], dtype=np.float32) for v in all_vertices]

# ==============================================================================
# 4. MEM FILE & HEX HELPERS
# ==============================================================================
def float_to_hex(val):
    """Converts a float to a 32-bit Q16.16 hex string."""
    fixed_val = int(val * 65536.0)
    if fixed_val < 0:
        fixed_val = (1 << 32) + fixed_val
    return f"{fixed_val & 0xFFFFFFFF:08X}"

def generate_mem_file(verts, uv_coords, filename):
    print(f"Generating {filename}...")
    with open(filename, "w") as f:
        f.write(f"// Generated Cube with {SUBDIVISIONS}x{SUBDIVISIONS} subdivisions per face\n")
        f.write(f"// Total Vertices: {len(verts)}\n")
        
        for i, (v, uv) in enumerate(zip(verts, uv_coords)):
            # V is vec4, we need x,y,z. UV is vec2
            lines = []
            lines.append(float_to_hex(v[0])) # X
            lines.append(float_to_hex(v[1])) # Y
            lines.append(float_to_hex(v[2])) # Z
            lines.append(float_to_hex(uv[0])) # U
            lines.append(float_to_hex(uv[1])) # V
            
            # Join with newlines and write
            f.write("\n".join(lines) + "\n")
        
        # EOS SIGNAL
        f.write("// END OF STREAM SIGNAL\n")
        for _ in range(5):
            f.write("FFFFFFFF\n")
            
    print("Done.")

# ==============================================================================
# 5. VISUALIZATION PIPELINE (UNCHANGED logic)
# ==============================================================================
def run_pipeline(verts, mvp_mat):
    screen_points = []
    
    for i, v in enumerate(verts):
        # Matrix Transform
        clip = mvp_mat @ v
        
        # Perspective Divide
        w = clip[3] if clip[3] != 0 else 0.00001
        ndc_x = clip[0] / w
        ndc_y = clip[1] / w
        
        # Viewport Map
        math_screen_x = (ndc_x + 1.0) * (SCREEN_WIDTH / 2.0)
        math_screen_y = (ndc_y + 1.0) * (SCREEN_HEIGHT / 2.0)
        
        draw_x = math_screen_x
        draw_y = SCREEN_HEIGHT - math_screen_y
        
        screen_points.append((int(draw_x), int(draw_y)))

    return screen_points

# ==============================================================================
# 6. MAIN EXECUTION
# ==============================================================================
if __name__ == "__main__":
    # 1. Generate MEM File
    generate_mem_file(final_vertices_vec4, all_uvs, MEM_FILENAME)

    # 2. Run Visualization Pipeline to prove it works
    final_screen_points = run_pipeline(final_vertices_vec4, mvp_matrix)
    
    # 3. Draw Image
    img = Image.new('RGB', (SCREEN_WIDTH, SCREEN_HEIGHT), BACKGROUND_COLOR)
    draw = ImageDraw.Draw(img)

    for i in range(0, len(final_screen_points), 3):
        triangle_verts = final_screen_points[i : i+3]
        draw.polygon(triangle_verts, fill=TRIANGLE_COLOR, outline=OUTLINE_COLOR)

    # 4. Save Image
    output_filename = "cube_subdivided_preview.png"
    img.save(output_filename)
    print(f"Preview image saved to: {output_filename}")