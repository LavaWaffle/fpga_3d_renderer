# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "numpy",
#     "pillow",
# ]
# ///

import os
import sys
import numpy as np
from PIL import Image, ImageDraw

# ==============================================================================
# 1. CONFIGURATION
# ==============================================================================
INPUT_DIR = "input"
OUTPUT_DIR = "output"

# Model Filename (Must be inside input/)
OBJ_FILENAME = "B4BC 66001.obj"

# --- TRANSFORMATIONS ---
# Adjust these to fit the Arwing on your screen
SCALE = 1.75
# Rotation in Degrees (X, Y, Z). 
# Example: (-90, 0, 180) often fixes standard Blender exports.
ROTATION = (0, 0, 0)

# --- CULLING CONTROL ---
# Set to True to flip the winding order (reverse culling)
FLIP_CULLING = True

# --- HARDWARE SPECS ---
MAX_BRAM_LINES = 1024
TEXTURE_SIZE = 64
ATLAS_GRID = 8  # 8x8 grid = 64 slots
SLOT_SIZE = TEXTURE_SIZE // ATLAS_GRID # 8 pixels

# --- MVP MATRIX (Standard View) ---
mvp_matrix = np.array([
    [ 7.5000000e-01,  0.0000000e+00,  0.0000000e+00,  0.0000000e+00],
    [ 0.0000000e+00,  8.9442718e-01, -4.4721359e-01, -1.1920929e-07],
    [ 0.0000000e+00, -4.9428868e-01, -9.8857737e-01,  1.0251953e+01],
    [ 0.0000000e+00, -4.4721359e-01, -8.9442718e-01,  1.1180340e+01]
], dtype=np.float32)

# ==============================================================================
# 2. HELPER CLASSES
# ==============================================================================
class MaterialManager:
    def __init__(self):
        self.materials = {} # Name -> { 'id': int, 'color': (r,g,b) }
        self.next_id = 0
        self.max_ids = ATLAS_GRID * ATLAS_GRID
        self.missing_color = (255, 0, 255) # Hot Pink

    def get_material_id(self, mat_name):
        # 1. Check if exists
        if mat_name in self.materials:
            return self.materials[mat_name]['id']
        
        # 2. Create new
        if self.next_id >= self.max_ids:
            print(f"WARNING: Too many materials! Clamping {mat_name} to ID 0.")
            return 0
            
        color = self._load_color_from_file(mat_name)
        new_id = self.next_id
        self.materials[mat_name] = { 'id': new_id, 'color': color }
        self.next_id += 1
        return new_id

    def _load_color_from_file(self, mat_name):
        # Try finding the png. mat_name might be "color_EE"
        # We look for "color_EE.png" in input dir
        filename = f"{mat_name}.png"
        path = os.path.join(INPUT_DIR, filename)
        
        if not os.path.exists(path):
            print(f"  [!] Missing Texture: {filename} -> Using Pink.")
            return self.missing_color
            
        try:
            with Image.open(path) as img:
                img = img.convert("RGB")
                return img.getpixel((0, 0)) # Read top-left pixel
        except Exception as e:
            print(f"  [!] Error reading {filename}: {e}")
            return self.missing_color

    def generate_atlas(self):
        # Create 64x64 Image
        img = Image.new("RGB", (TEXTURE_SIZE, TEXTURE_SIZE), (0,0,0))
        draw = ImageDraw.Draw(img)
        
        for name, data in self.materials.items():
            idx = data['id']
            color = data['color']
            
            # Calc Grid Pos
            row = idx // ATLAS_GRID
            col = idx % ATLAS_GRID
            
            x0 = col * SLOT_SIZE
            y0 = row * SLOT_SIZE
            x1 = x0 + SLOT_SIZE
            y1 = y0 + SLOT_SIZE
            
            draw.rectangle([x0, y0, x1-1, y1-1], fill=color)
            
        return img

    def get_uv_center_normalized(self, mat_id):
        # Returns (u, v) 0.0-1.0 pointing to center of slot
        row = mat_id // ATLAS_GRID
        col = mat_id % ATLAS_GRID
        
        center_x_px = (col * SLOT_SIZE) + (SLOT_SIZE / 2.0)
        center_y_px = (row * SLOT_SIZE) + (SLOT_SIZE / 2.0)
        
        return (center_x_px / TEXTURE_SIZE, center_y_px / TEXTURE_SIZE)


# ==============================================================================
# 3. OBJ PARSER
# ==============================================================================
def parse_obj(filepath, mat_mgr):
    print(f"Parsing {filepath}...")
    
    vertices = [] # List of [x, y, z]
    faces = []    # List of { 'verts': [i1, i2, i3], 'mat_id': int }
    
    current_mat_id = 0
    
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
                
            parts = line.split()
            cmd = parts[0]
            
            if cmd == 'v':
                # Vertex: v x y z
                v = [float(parts[1]), float(parts[2]), float(parts[3])]
                vertices.append(v)
                
            elif cmd == 'usemtl':
                # Material Switch: usemtl color_EE
                mat_name = parts[1]
                current_mat_id = mat_mgr.get_material_id(mat_name)
                
            elif cmd == 'f':
                # Face: f v1/vt1/vn1 v2...
                # We handle triangles (3) and quads (4)
                # OBJ indices are 1-based string "v_idx/vt_idx/vn_idx"
                
                # Extract just vertex indices
                v_indices = []
                for p in parts[1:]:
                    # split "9/37/37" -> take "9"
                    v_str = p.split('/')[0] 
                    v_idx = int(v_str) - 1 # Convert to 0-based
                    v_indices.append(v_idx)

                # --- NEW: Flip Culling Logic ---
                if FLIP_CULLING:
                    v_indices.reverse()
                # -------------------------------
                
                # Triangulate if Quad (0,1,2,3) -> (0,1,2) & (0,2,3)
                if len(v_indices) == 3:
                    faces.append({ 'verts': v_indices, 'mat_id': current_mat_id })
                elif len(v_indices) == 4:
                    faces.append({ 'verts': [v_indices[0], v_indices[1], v_indices[2]], 'mat_id': current_mat_id })
                    faces.append({ 'verts': [v_indices[0], v_indices[2], v_indices[3]], 'mat_id': current_mat_id })
                    
    return np.array(vertices), faces

# ==============================================================================
# 4. TRANSFORMS
# ==============================================================================
def process_geometry(verts, rotation_deg, scale_factor):
    # 1. Center at (0,0,0)
    # Find center of mass
    center = verts.mean(axis=0)
    verts -= center
    
    # 2. Scale
    verts *= scale_factor
    
    # 3. Rotate
    # Convert deg to rad
    rx, ry, rz = np.radians(rotation_deg)
    
    # Rotation Matrices
    mat_x = np.array([[1, 0, 0], [0, np.cos(rx), -np.sin(rx)], [0, np.sin(rx), np.cos(rx)]])
    mat_y = np.array([[np.cos(ry), 0, np.sin(ry)], [0, 1, 0], [-np.sin(ry), 0, np.cos(ry)]])
    mat_z = np.array([[np.cos(rz), -np.sin(rz), 0], [np.sin(rz), np.cos(rz), 0], [0, 0, 1]])
    
    # Apply Rz * Ry * Rx
    rot_mat = mat_z @ mat_y @ mat_x
    
    # Apply to all vertices
    # Transpose for multiplication (3xN) then transpose back
    verts = (rot_mat @ verts.T).T
    
    return verts

# ==============================================================================
# 5. HEX EXPORTERS
# ==============================================================================
def to_q16_16(val):
    scaled = int(val * 65536.0)
    if scaled < 0:
        scaled = (1 << 32) + scaled
    return f"{scaled & 0xFFFFFFFF:08X}"

def to_rgb_444(r, g, b):
    return f"{(r>>4):X}{(g>>4):X}{(b>>4):X}"

def write_outputs(verts, faces, mat_mgr, atlas_img):
    # --- 1. Texture MEM ---
    tex_path = os.path.join(OUTPUT_DIR, "texture.mem")
    with open(tex_path, 'w') as f:
        pixels = atlas_img.load()
        for y in range(TEXTURE_SIZE):
            for x in range(TEXTURE_SIZE):
                r, g, b = pixels[x, y]
                f.write(to_rgb_444(r, g, b) + "\n")
    print(f"Saved {tex_path}")

    # --- 2. Vertex MEM ---
    vert_path = os.path.join(OUTPUT_DIR, "vertex_data.mem")
    
    lines_needed = len(faces) * 3 * 5 # 3 verts per face, 5 lines per vert
    print(f"Memory Usage: {lines_needed} / {MAX_BRAM_LINES} lines.")
    
    if lines_needed > MAX_BRAM_LINES:
        print(f"!!! ERROR: Model too big! ({lines_needed} lines). Reduce geometry.")
        # We will write anyway, but warn heavily
    
    with open(vert_path, 'w') as f:
        f.write("// Arwing Data\n// X, Y, Z, U, V (Q16.16)\n")
        
        for face in faces:
            mat_id = face['mat_id']
            # Get UV center for this material
            u, v = mat_mgr.get_uv_center_normalized(mat_id)
            
            # Write 3 vertices
            for v_idx in face['verts']:
                vert = verts[v_idx]
                
                f.write(to_q16_16(vert[0]) + "\n") # X
                f.write(to_q16_16(vert[1]) + "\n") # Y
                f.write(to_q16_16(vert[2]) + "\n") # Z
                f.write(to_q16_16(u) + "\n")       # U
                f.write(to_q16_16(v) + "\n")       # V
        
        # EOS
        f.write("// EOS\n")
        f.write("FFFFFFFF\n" * 5)
        
    print(f"Saved {vert_path}")

# ==============================================================================
# 6. VISUALIZATION
# ==============================================================================
def generate_preview(verts, faces, mat_mgr, atlas_img):
    w, h = 320, 240
    img = Image.new("RGB", (w, h), (10, 10, 10))
    draw = ImageDraw.Draw(img)
    
    # Simple Pipeline
    screen_polys = []
    
    for face in faces:
        mat_id = face['mat_id']
        poly_verts = []
        avg_z = 0
        
        for v_idx in face['verts']:
            v = verts[v_idx]
            v4 = np.array([v[0], v[1], v[2], 1.0])
            
            clip = mvp_matrix @ v4
            we = clip[3] if clip[3] != 0 else 0.0001
            ndc = clip / we
            
            sx = (ndc[0] + 1) * (w/2)
            sy = (1 - ndc[1]) * (h/2)
            
            poly_verts.append((sx, sy))
            avg_z += we # Use W for depth approx
            
        # Get Color
        u, v = mat_mgr.get_uv_center_normalized(mat_id)
        cx, cy = int(u * TEXTURE_SIZE), int(v * TEXTURE_SIZE)
        color = atlas_img.getpixel((cx, cy))
        
        screen_polys.append((avg_z, poly_verts, color))
        
    # Sort Back-to-Front
    screen_polys.sort(key=lambda x: x[0], reverse=True)
    
    for _, pts, color in screen_polys:
        draw.polygon(pts, fill=color, outline=(255,255,255))
        
    prev_path = os.path.join(OUTPUT_DIR, "preview_scene.png")
    img.save(prev_path)
    print(f"Saved {prev_path}")

# ==============================================================================
# MAIN
# ==============================================================================
if __name__ == "__main__":
    # Create output dir
    if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)
        
    path_to_obj = os.path.join(INPUT_DIR, OBJ_FILENAME)
    if not os.path.exists(path_to_obj):
        print(f"Error: {path_to_obj} not found.")
        sys.exit(1)
        
    # 1. Setup Material Manager
    mat_mgr = MaterialManager()
    
    # 2. Parse OBJ (Builds material list dynamically)
    raw_verts, raw_faces = parse_obj(path_to_obj, mat_mgr)
    print(f"Loaded {len(raw_verts)} vertices, {len(raw_faces)} faces.")
    
    # 3. Generate Atlas
    print(f"Found {len(mat_mgr.materials)} unique materials.")
    atlas_img = mat_mgr.generate_atlas()
    atlas_img.save(os.path.join(OUTPUT_DIR, "preview_texture.png"))
    
    # 4. Transform Geometry
    final_verts = process_geometry(raw_verts, ROTATION, SCALE)
    
    # 5. Export Hardware Files
    write_outputs(final_verts, raw_faces, mat_mgr, atlas_img)
    
    # 6. Preview
    generate_preview(final_verts, raw_faces, mat_mgr, atlas_img)
    
    print("--- Done ---")