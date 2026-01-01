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

# Model Filename
OBJ_FILENAME = "star.obj"
MTL_FILENAME = "star.mtl"

# --- TRANSFORMATIONS ---
SCALE = 2.5  # Adjust if star is too small/big
# Rotation in Degrees (X, Y, Z). 
ROTATION = (0, 0, 0)

# --- CULLING CONTROL ---
FLIP_CULLING = False # Toggle if faces look inside-out

# --- HARDWARE SPECS ---
MAX_BRAM_LINES = 1024
TEXTURE_SIZE = 64     # 64x64 Atlas
ATLAS_SLOT_H = 32     # We will split vertically: 64x32 per texture

# --- MVP MATRIX (Standard View for Preview) ---
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
        self.materials = {} 
        # Structure:
        # name -> { 
        #   'texture_file': 'eye.png', 
        #   'uv_offset': (u_add, v_add), 
        #   'uv_scale': (u_scale, v_scale) 
        # }
        self.atlas_image = None

    def parse_mtl(self, mtl_path):
        """Parses the .mtl file to find texture maps."""
        print(f"Parsing materials from {mtl_path}...")
        current_mat = None
        
        # We need to assign slots. 
        # Slot 0 (Top) -> First material found
        # Slot 1 (Bottom) -> Second material found
        slot_index = 0
        
        if not os.path.exists(mtl_path):
            print("WARNING: MTL file not found. Using defaults.")
            return

        with open(mtl_path, 'r') as f:
            for line in f:
                line = line.strip()
                parts = line.split()
                if not parts: continue
                
                if parts[0] == 'newmtl':
                    current_mat = parts[1]
                    self.materials[current_mat] = {'texture_file': None, 'slot': slot_index}
                    slot_index += 1
                elif parts[0] in ['map_Kd', 'map_Ka'] and current_mat:
                    # Found a texture file definition
                    # Handle cases where path has spaces or backslashes
                    tex_file = parts[-1].split('\\')[-1].split('/')[-1]
                    self.materials[current_mat]['texture_file'] = tex_file

    def generate_atlas(self):
        """Stitches images into a 64x64 atlas."""
        self.atlas_image = Image.new("RGB", (TEXTURE_SIZE, TEXTURE_SIZE), (255, 0, 255))
        
        for mat_name, data in self.materials.items():
            tex_file = data['texture_file']
            slot = data['slot']
            
            if not tex_file: 
                continue
                
            path = os.path.join(INPUT_DIR, tex_file)
            if os.path.exists(path):
                img = Image.open(path).convert("RGB")
                # Resize to fill the slot (64 width, 32 height)
                img = img.resize((TEXTURE_SIZE, ATLAS_SLOT_H))
                
                # Calculate paste position (Top or Bottom)
                y_offset = slot * ATLAS_SLOT_H
                
                # Paste
                self.atlas_image.paste(img, (0, y_offset))
                
                # Store UV transform info
                # If slot 0 (Top): V range is 0.0 to 0.5
                # If slot 1 (Bot): V range is 0.5 to 1.0
                # (Assuming UV (0,0) is Top-Left for the texture memory)
                data['uv_scale'] = (1.0, 0.5)
                data['uv_offset'] = (0.0, float(slot) * 0.5)
            else:
                print(f" [!] Missing texture: {tex_file}")

        return self.atlas_image

    def get_transformed_uv(self, mat_name, u, v):
        """Remaps 0-1 UVs to the specific atlas slot."""
        if mat_name not in self.materials:
            return (u, v) # Fallback
            
        data = self.materials[mat_name]
        if 'uv_scale' not in data:
            return (u, v)
            
        su, sv = data['uv_scale']
        ou, ov = data['uv_offset']
        
        # Apply transform
        new_u = (u * su) + ou
        new_v = (v * sv) + ov
        return new_u, new_v


# ==============================================================================
# 3. OBJ PARSER
# ==============================================================================
def parse_obj(filepath, mat_mgr):
    print(f"Parsing {filepath}...")
    
    vertices = []    # v
    tex_coords = []  # vt
    faces = []       # {verts: [], uvs: [], mat: str}
    
    current_mat = None
    
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'): continue
            
            parts = line.split()
            cmd = parts[0]
            
            if cmd == 'v':
                vertices.append([float(parts[1]), float(parts[2]), float(parts[3])])
            
            elif cmd == 'vt':
                # OBJ UVs often have V inverted compared to image coords.
                # Standard OBJ: (0,0) bottom-left.
                # Images/Memory: (0,0) top-left.
                # We usually flip V here: 1.0 - v
                u = float(parts[1])
                v = float(parts[2]) % 1.0 
                tex_coords.append([u, 1.0 - v]) 
                
            elif cmd == 'usemtl':
                current_mat = parts[1]
                
            elif cmd == 'f':
                # f v/vt/vn v/vt/vn ...
                v_indices = []
                vt_indices = []
                
                for p in parts[1:]:
                    vals = p.split('/')
                    # Vertex Index (1-based)
                    v_idx = int(vals[0]) - 1
                    v_indices.append(v_idx)
                    
                    # Texture Index (1-based), handles "v//vn" case
                    if len(vals) > 1 and vals[1]:
                        vt_idx = int(vals[1]) - 1
                        vt_indices.append(vt_idx)
                    else:
                        vt_indices.append(0) # Default to 0 if missing

                if FLIP_CULLING:
                    v_indices.reverse()
                    vt_indices.reverse()
                
                # Triangulate
                if len(v_indices) == 3:
                    faces.append({'verts': v_indices, 'uvs': vt_indices, 'mat': current_mat})
                elif len(v_indices) == 4:
                    faces.append({'verts': [v_indices[0], v_indices[1], v_indices[2]], 
                                  'uvs': [vt_indices[0], vt_indices[1], vt_indices[2]], 
                                  'mat': current_mat})
                    faces.append({'verts': [v_indices[0], v_indices[2], v_indices[3]], 
                                  'uvs': [vt_indices[0], vt_indices[2], vt_indices[3]], 
                                  'mat': current_mat})
                    
    return np.array(vertices), np.array(tex_coords), faces

# ==============================================================================
# 4. TRANSFORMS (Geometry)
# ==============================================================================
def process_geometry(verts, rotation_deg, scale_factor):
    # Center
    center = verts.mean(axis=0)
    verts -= center
    
    # Scale
    verts *= scale_factor
    
    # Rotate
    rx, ry, rz = np.radians(rotation_deg)
    mat_x = np.array([[1,0,0],[0,np.cos(rx),-np.sin(rx)],[0,np.sin(rx),np.cos(rx)]])
    mat_y = np.array([[np.cos(ry),0,np.sin(ry)],[0,1,0],[-np.sin(ry),0,np.cos(ry)]])
    mat_z = np.array([[np.cos(rz),-np.sin(rz),0],[np.sin(rz),np.cos(rz),0],[0,0,1]])
    
    rot_mat = mat_z @ mat_y @ mat_x
    verts = (rot_mat @ verts.T).T
    
    return verts

# ==============================================================================
# 5. HEX EXPORTERS
# ==============================================================================
def to_q16_16(val):
    scaled = int(val * 65536.0)
    if scaled < 0: scaled = (1 << 32) + scaled
    return f"{scaled & 0xFFFFFFFF:08X}"

def to_rgb_444(r, g, b):
    return f"{(r>>4):X}{(g>>4):X}{(b>>4):X}"

def write_outputs(verts, tex_coords, faces, mat_mgr, atlas_img):
    # 1. Texture MEM
    tex_path = os.path.join(OUTPUT_DIR, "texture.mem")
    with open(tex_path, 'w') as f:
        pixels = atlas_img.load()
        for y in range(TEXTURE_SIZE):
            for x in range(TEXTURE_SIZE):
                r, g, b = pixels[x, y]
                f.write(to_rgb_444(r, g, b) + "\n")
    print(f"Saved {tex_path}")

    # 2. Vertex MEM
    vert_path = os.path.join(OUTPUT_DIR, "vertex_data.mem")
    lines_needed = len(faces) * 3 * 5 
    print(f"Memory Usage: {lines_needed} lines.")

    with open(vert_path, 'w') as f:
        f.write("// Star Data\n// X, Y, Z, U, V (Q16.16)\n")
        
        for face in faces:
            mat_name = face['mat']
            
            # Write 3 vertices
            for i in range(3):
                v_idx = face['verts'][i]
                vt_idx = face['uvs'][i]
                
                # Geometry
                vert = verts[v_idx]
                
                # UVs
                if len(tex_coords) > 0:
                    raw_u, raw_v = tex_coords[vt_idx]
                    final_u, final_v = mat_mgr.get_transformed_uv(mat_name, raw_u, raw_v)
                else:
                    final_u, final_v = (0.0, 0.0)

                f.write(to_q16_16(vert[0]) + "\n") # X
                f.write(to_q16_16(vert[1]) + "\n") # Y
                f.write(to_q16_16(vert[2]) + "\n") # Z
                f.write(to_q16_16(final_u) + "\n") # U
                f.write(to_q16_16(final_v) + "\n") # V
        
        f.write("// EOS\n")
        f.write("FFFFFFFF\n" * 5)
        
    print(f"Saved {vert_path}")

# ==============================================================================
# 6. VISUALIZATION
# ==============================================================================
def generate_preview(verts, tex_coords, faces, mat_mgr, atlas_img):
    w, h = 320, 240
    img = Image.new("RGB", (w, h), (20, 20, 30))
    draw = ImageDraw.Draw(img)
    
    screen_polys = []
    
    for face in faces:
        mat_name = face['mat']
        poly_verts = []
        avg_z = 0
        
        # Get UV of first vertex just for color sampling (Simple flat shading approx)
        vt_idx_0 = face['uvs'][0]
        raw_u, raw_v = tex_coords[vt_idx_0]
        fu, fv = mat_mgr.get_transformed_uv(mat_name, raw_u, raw_v)
        
        cx, cy = int(fu * TEXTURE_SIZE), int(fv * TEXTURE_SIZE)
        # Clamp
        cx = max(0, min(cx, TEXTURE_SIZE-1))
        cy = max(0, min(cy, TEXTURE_SIZE-1))
        color = atlas_img.getpixel((cx, cy))

        for v_idx in face['verts']:
            v = verts[v_idx]
            v4 = np.array([v[0], v[1], v[2], 1.0])
            clip = mvp_matrix @ v4
            we = clip[3] if clip[3] != 0 else 0.0001
            ndc = clip / we
            sx = (ndc[0] + 1) * (w/2)
            sy = (1 - ndc[1]) * (h/2)
            poly_verts.append((sx, sy))
            avg_z += we 
            
        screen_polys.append((avg_z, poly_verts, color))
        
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
    if not os.path.exists(OUTPUT_DIR): os.makedirs(OUTPUT_DIR)
    
    # Paths
    obj_path = os.path.join(INPUT_DIR, OBJ_FILENAME)
    mtl_path = os.path.join(INPUT_DIR, MTL_FILENAME)

    if not os.path.exists(obj_path):
        print(f"Error: {obj_path} not found.")
        sys.exit(1)

    # 1. Setup Material Manager & Parse MTL
    mat_mgr = MaterialManager()
    mat_mgr.parse_mtl(mtl_path)
    
    # 2. Generate Atlas (Load images)
    print("Generating Atlas...")
    atlas_img = mat_mgr.generate_atlas()
    atlas_img.save(os.path.join(OUTPUT_DIR, "preview_texture.png"))

    # 3. Parse OBJ (Geometry + UVs)
    raw_verts, raw_uvs, raw_faces = parse_obj(obj_path, mat_mgr)
    print(f"Loaded {len(raw_verts)} verts, {len(raw_faces)} faces.")
    
    # 4. Transform Geometry
    final_verts = process_geometry(raw_verts, ROTATION, SCALE)
    
    # 5. Export
    write_outputs(final_verts, raw_uvs, raw_faces, mat_mgr, atlas_img)
    
    # 6. Preview
    generate_preview(final_verts, raw_uvs, raw_faces, mat_mgr, atlas_img)
    
    print("--- Done ---")