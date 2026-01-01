# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "numpy",
#     "pillow",
# ]
# ///

import numpy as np
from PIL import Image, ImageDraw
import math

# ==============================================================================
# 1. SETUP & CONFIGURATION
# ==============================================================================
# --- Hardware Parameters ---
TEXTURE_WIDTH = 64
TEXTURE_HEIGHT = 64
FIXED_POINT_SCALE = 65536.0  # Q16.16 (1 << 16)
SCREEN_WIDTH = 320
SCREEN_HEIGHT = 240

# --- Scene Parameters ---
SCALE = 3.5
CULL_BACKFACES = True
TEX_BG_COLOR = (0, 0, 255)   # Blue
TEX_STAR_COLOR = (255, 255, 0) # Yellow
PREVIEW_BG_COLOR = (10, 10, 10)

# --- Files ---
VERTEX_MEM_FILE = "d20_star_vertex.mem"
TEXTURE_MEM_FILE = "d20_star_texture.mem"
TEXTURE_PREVIEW_FILE = "d20_star_tex_preview.png"
SCENE_PREVIEW_FILE = "d20_star_scene_preview.png"

# --- MVP Matrix ---
mvp_matrix = np.array([
    [ 7.5000000e-01,  0.0000000e+00,  0.0000000e+00,  0.0000000e+00],
    [ 0.0000000e+00,  8.9442718e-01, -4.4721359e-01, -1.1920929e-07],
    [ 0.0000000e+00, -4.9428868e-01, -9.8857737e-01,  1.0251953e+01],
    [ 0.0000000e+00, -4.4721359e-01, -8.9442718e-01,  1.1180340e+01]
], dtype=np.float32)

# --- UV Mapping Configuration ---
# Defines how we map the equilateral triangle face onto the square texture.
# Normalized coords (0.0 - 1.0).
# These map vertices to Bottom-Left, Bottom-Right, and Top-Center regions.
STANDARD_FACE_UVS = [
    (0.1, 0.9), # Vertex 1 (UV indices match face vertex order)
    (0.9, 0.9), # Vertex 2
    (0.5, 0.1)  # Vertex 3
]

# ==============================================================================
# 2. GEOMETRY GENERATION (ICOSAHEDRON)
# ==============================================================================
def generate_icosahedron(scale):
    phi = (1.0 + math.sqrt(5.0)) / 2.0
    verts = [
        (-1,  phi, 0), ( 1,  phi, 0), (-1, -phi, 0), ( 1, -phi, 0),
        ( 0, -1,  phi), ( 0,  1,  phi), ( 0, -1, -phi), ( 0,  1, -phi),
        ( phi, 0, -1), ( phi, 0,  1), (-phi, 0, -1), (-phi, 0,  1)
    ]
    vertices = [np.array(v, dtype=np.float32) * scale for v in verts]
    faces = [
        (0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11),
        (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
        (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9),
        (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)
    ]
    return vertices, faces

# ==============================================================================
# 3. TEXTURE GENERATION (UPDATED: Smaller Stars)
# ==============================================================================
def generate_star_texture():
    """Generates a 64x64 image: Blue background, smaller Yellow star."""
    img = Image.new("RGB", (TEXTURE_WIDTH, TEXTURE_HEIGHT), TEX_BG_COLOR)
    draw = ImageDraw.Draw(img)
    
    cx, cy = TEXTURE_WIDTH / 2, TEXTURE_HEIGHT / 2
    # --- UPDATED: Reduced radii to make star smaller ---
    outer_radius = TEXTURE_WIDTH * 0.25  # Was 0.45
    inner_radius = TEXTURE_WIDTH * 0.1   # Was 0.2
    # ---------------------------------------------------
    points = []
    angle = -math.pi / 2 # Start at top
    step = math.pi / 5   
    
    for i in range(10):
        r = outer_radius if i % 2 == 0 else inner_radius
        x = cx + math.cos(angle) * r
        y = cy + math.sin(angle) * r
        points.append((x,y))
        angle += step
        
    draw.polygon(points, fill=TEX_STAR_COLOR)
    return img

# ==============================================================================
# 4. EXPORTERS
# ==============================================================================
def float_to_q16_16_hex(val):
    fixed_val = int(val * FIXED_POINT_SCALE)
    if fixed_val < 0: fixed_val = (1 << 32) + fixed_val
    return f"{fixed_val & 0xFFFFFFFF:08X}"

def rgb_to_12bit_hex(r, g, b):
    return f"{(r>>4)&0xF:x}{(g>>4)&0xF:x}{(b>>4)&0xF:x}"

def export_texture_mem(img, filename):
    print(f"Exporting Texture to {filename}...")
    width, height = img.size
    with open(filename, 'w') as f:
        for y in range(height):
            for x in range(width):
                r, g, b = img.getpixel((x, y))
                f.write(rgb_to_12bit_hex(r, g, b) + "\n")

def export_vertex_mem(vertices, faces, filename):
    print(f"Exporting Vertices to {filename}...")
    with open(filename, 'w') as f:
        f.write("// D20 Star Map Data\n")
        f.write(f"// Format: X, Y, Z, U, V (Q16.16 Hex)\n")
        
        for face_indices in faces:
            # Loop through the 3 vertices of the face
            for i, v_idx in enumerate(face_indices):
                v = vertices[v_idx]
                # Use the standard UV set, matching vertex index in face (0, 1, or 2)
                uv = STANDARD_FACE_UVS[i] 
                
                lines = []
                lines.append(float_to_q16_16_hex(v[0])) # X
                lines.append(float_to_q16_16_hex(v[1])) # Y
                lines.append(float_to_q16_16_hex(v[2])) # Z
                # UVs are already normalized 0-1 floats here
                lines.append(float_to_q16_16_hex(uv[0])) # U (Normalized)
                lines.append(float_to_q16_16_hex(uv[1])) # V (Normalized)
                
                f.write("\n".join(lines) + "\n")
        
        f.write("// EOS\n")
        for _ in range(5): f.write("FFFFFFFF\n")

# ==============================================================================
# 5. VISUALIZATION PIPELINE (UPDATED: Textured Rasterizer)
# ==============================================================================

def rasterize_textured_triangle(canvas_pixels, tex_pixels, tex_w, tex_h, p0, p1, p2, uv0, uv1, uv2):
    """
    Simple software rasterizer using barycentric coordinates and affine texture mapping.
    Takes normalized UVs (0.0-1.0) and maps them to texture dimensions.
    """
    # 1. Find Bounding Box on screen
    min_x = max(0, int(math.floor(min(p0[0], p1[0], p2[0]))))
    max_x = min(SCREEN_WIDTH - 1, int(math.ceil(max(p0[0], p1[0], p2[0]))))
    min_y = max(0, int(math.floor(min(p0[1], p1[1], p2[1]))))
    max_y = min(SCREEN_HEIGHT - 1, int(math.ceil(max(p0[1], p1[1], p2[1]))))

    # Edge function for barycentric calculation
    def edge_function(a, b, c_x, c_y):
        return (c_x - a[0]) * (b[1] - a[1]) - (c_y - a[1]) * (b[0] - a[0])

    area = edge_function(p0, p1, p2[0], p2[1])
    # Avoid division by zero for degenerate triangles
    if abs(area) < 1e-9: return

    # 2. Iterate over bounding box pixels
    for y in range(min_y, max_y + 1):
        for x in range(min_x, max_x + 1):
            # Calculate barycentric weights
            w0 = edge_function(p1, p2, x, y)
            w1 = edge_function(p2, p0, x, y)
            w2 = edge_function(p0, p1, x, y)

            # Check if pixel is inside triangle (using slightly loose tolerance for edges)
            if w0 >= -1e-9 and w1 >= -1e-9 and w2 >= -1e-9:
                lambda0 = w0 / area
                lambda1 = w1 / area
                lambda2 = w2 / area

                # Interpolate normalized UVs
                u_norm = lambda0 * uv0[0] + lambda1 * uv1[0] + lambda2 * uv2[0]
                v_norm = lambda0 * uv0[1] + lambda1 * uv1[1] + lambda2 * uv2[1]

                # --- CRITICAL: Map Normalized UV (0->1) to Texture Coordinates ---
                # Scale by dimensions and clamp to ensure we don't sample outside image boundaries
                tex_x = max(0, min(tex_w - 1, int(u_norm * tex_w)))
                tex_y = max(0, min(tex_h - 1, int(v_norm * tex_h)))

                # Sample texture and write to canvas
                canvas_pixels[x, y] = tex_pixels[tex_x, tex_y]


def run_preview_pipeline(vertices, faces, mvp_mat, texture_img):
    print("Running Textured Geometry Preview...")
    img = Image.new('RGB', (SCREEN_WIDTH, SCREEN_HEIGHT), PREVIEW_BG_COLOR)
    canvas_pixels = img.load()
    
    # Prepare texture for fast access
    tex_pixels = texture_img.load()
    tex_w, tex_h = texture_img.size

    projected_verts = []
    for v in vertices:
        v4 = np.array([v[0], v[1], v[2], 1.0])
        clip = mvp_mat @ v4
        # Simple w-division guard
        w = clip[3] if abs(clip[3]) > 1e-9 else 1e-9
        # Viewport transform to screen coordinates
        sx = (clip[0]/w + 1.0) * (SCREEN_WIDTH / 2.0)
        sy = (1.0 - clip[1]/w) * (SCREEN_HEIGHT / 2.0) 
        projected_verts.append((sx, sy, w))

    render_list = []
    for face_indices in faces:
        p0 = projected_verts[face_indices[0]]
        p1 = projected_verts[face_indices[1]]
        p2 = projected_verts[face_indices[2]]
        
        # Culling check
        cross_z = (p1[0] - p0[0]) * (p2[1] - p0[1]) - (p1[1] - p0[1]) * (p2[0] - p0[0])
        is_visible = True
        if CULL_BACKFACES and cross_z > 0: is_visible = False
        
        if is_visible:
            avg_depth = (p0[2] + p1[2] + p2[2]) / 3.0
            render_list.append({
                'depth': avg_depth,
                # Store screen coordinates (x,y) tuples
                'screen_verts': [(p0[0], p0[1]), (p1[0], p1[1]), (p2[0], p2[1])],
                # Store corresponding normalized UVs based on standard mapping
                'uvs': [STANDARD_FACE_UVS[0], STANDARD_FACE_UVS[1], STANDARD_FACE_UVS[2]]
            })
            
    # Simple painter's algorithm sort
    render_list.sort(key=lambda x: x['depth'], reverse=True)
    
    print(f"Rasterizing {len(render_list)} visible triangles...")
    for item in render_list:
        sv = item['screen_verts']
        uvs = item['uvs']
        # Call custom software rasterizer
        rasterize_textured_triangle(
            canvas_pixels, tex_pixels, tex_w, tex_h,
            sv[0], sv[1], sv[2], # Screen vertices P0, P1, P2
            uvs[0], uvs[1], uvs[2] # Normalized UVs UV0, UV1, UV2
        )
        
    img.save(SCENE_PREVIEW_FILE)
    print(f"Textured preview saved to {SCENE_PREVIEW_FILE}")

# ==============================================================================
# MAIN
# ==============================================================================
if __name__ == "__main__":
    print("--- D20 Star Texture Exporter & Previewer ---")
    verts, faces = generate_icosahedron(SCALE)
    
    # 1. Generate Texture (Now smaller stars)
    tex_img = generate_star_texture()
    tex_img.save(TEXTURE_PREVIEW_FILE)
    print(f"Texture preview saved to {TEXTURE_PREVIEW_FILE}")

    # 2. Export Hardware Files (using 0->1 UVs translated to Q16.16)
    export_vertex_mem(verts, faces, VERTEX_MEM_FILE)
    export_texture_mem(tex_img, TEXTURE_MEM_FILE)
    
    # 3. Run Textured Preview (using 0->1 UVs and software rasterization)
    run_preview_pipeline(verts, faces, mvp_matrix, tex_img)
    print("\nDone.")