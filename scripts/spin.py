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
# 1. MATRIX MATH HELPERS (From your generation script)
# ==============================================================================
def create_model_matrix(position, scale, rotation_euler):
   tx, ty, tz = position
   sx, sy, sz = scale
   rz = rotation_euler[2] 
   c = np.cos(rz)
   s = np.sin(rz)
   
   # Rotation around Z (and scaling)
   rs_mat = np.array([
       [sx*c, -sy*s, 0, 0],
       [sx*s,  sy*c, 0, 0],
       [   0,     0, sz, 0],
       [   0,     0,  0, 1]
   ], dtype=np.float32)
   
   # Translation
   t_mat = np.eye(4, dtype=np.float32)
   t_mat[:3, 3] = [tx, ty, tz]
   
   return t_mat @ rs_mat

def look_at(eye, target, up):
   eye = np.array(eye, dtype=np.float32)
   target = np.array(target, dtype=np.float32)
   up = np.array(up, dtype=np.float32)
   fwd = eye - target
   fwd /= np.linalg.norm(fwd)
   right = np.cross(up, fwd)
   right /= np.linalg.norm(right)
   true_up = np.cross(fwd, right)
   rot = np.array([
       [right[0],   right[1],   right[2],   0],
       [true_up[0], true_up[1], true_up[2], 0],
       [fwd[0],     fwd[1],     fwd[2],     0],
       [0,          0,          0,          1]
   ], dtype=np.float32)
   trans = np.eye(4, dtype=np.float32)
   trans[:3, 3] = -eye
   return rot @ trans

def perspective(fov_degrees, aspect_ratio, near, far):
   fov_rad = np.radians(fov_degrees)
   f = 1.0 / np.tan(fov_rad / 2.0)
   return np.array([
       [f / aspect_ratio, 0, 0, 0],
       [0, f, 0, 0],
       [0, 0, (far + near) / (near - far), (2 * far * near) / (near - far)],
       [0, 0, -1, 0]
   ], dtype=np.float32)

# ==============================================================================
# 2. RENDERING PIPELINE (Hardware Simulation)
# ==============================================================================
SCREEN_WIDTH = 320
SCREEN_HEIGHT = 240
BACKGROUND_COLOR = (0, 0, 0) # Black
TRIANGLE_COLOR = (255, 0, 0) # Red

def run_pipeline(verts, mvp_mat):
   screen_points = []
   
   for v in verts:
       # 1. Matrix Transform
       clip = mvp_mat @ v
       
       # 2. Perspective Divide
       # Avoid div by zero for safety in this script, though hardware might glitch
       w = clip[3] if clip[3] != 0 else 0.0001
       ndc_x = clip[0] / w
       ndc_y = clip[1] / w
       
       # 3. Viewport Map
       math_screen_x = (ndc_x + 1.0) * (SCREEN_WIDTH / 2.0)
       math_screen_y = (ndc_y + 1.0) * (SCREEN_HEIGHT / 2.0)
       
       # 4. Flip Y for Image Coordinate System
       draw_x = math_screen_x
       draw_y = SCREEN_HEIGHT - math_screen_y
       
       screen_points.append((int(draw_x), int(draw_y)))

   return screen_points

# ==============================================================================
# 3. MAIN ANIMATION LOOP
# ==============================================================================
if __name__ == "__main__":
   # --- CONFIGURATION (Matches your "working" setup) ---
   FOV_DEGREES  = 90.0
   ASPECT_RATIO = 320.0 / 240.0
   NEAR_PLANE   = 1.0
   FAR_PLANE    = 20.0
   
   CAM_POS    = [0.0, 0.0, 10.0] # Looking from Z=10
   CAM_TARGET = [0.0, 0.0, 0.0]
   CAM_UP     = [0.0, 1.0, 0.0]
   
   OBJ_POS    = [0.0, 0.0, 0.0] 
   OBJ_SCALE  = [1.0, 1.0, 1.0]
   
   # Input Vertices (Homogeneous)
   vertices = [
       np.array([-1.0, -1.0, 1.0, 1.0]),
       np.array([ 1.0, -1.0, 1.0, 1.0]),
       np.array([ 1.0,  1.0, 1.0, 1.0])
   ]

   # Pre-calculate Projection and View (Camera doesn't move)
   view_mat = look_at(CAM_POS, CAM_TARGET, CAM_UP)
   proj_mat = perspective(FOV_DEGREES, ASPECT_RATIO, NEAR_PLANE, FAR_PLANE)
   
   frames = []
   num_frames = 12  # 30 degrees per frame
   
   print(f"Generating {num_frames} frames...")

   for i in range(num_frames):
       # Calculate Angle (0 to 360)
       angle_deg = i * (360.0 / num_frames)
       angle_rad = np.radians(angle_deg)
       
       # 1. Update Model Matrix (Rotate around Z)
       # Note: Your script defined rotation as [x, y, z] euler angles
       obj_rot = [0.0, 0.0, angle_rad] 
       model_mat = create_model_matrix(OBJ_POS, OBJ_SCALE, obj_rot)
       
       # 2. Calculate MVP
       mvp_mat = proj_mat @ view_mat @ model_mat
       
       # 3. Run Pipeline
       final_points = run_pipeline(vertices, mvp_mat)
       
       # 4. Draw Frame
       img = Image.new('RGB', (SCREEN_WIDTH, SCREEN_HEIGHT), BACKGROUND_COLOR)
       draw = ImageDraw.Draw(img)
       draw.polygon(final_points, fill=TRIANGLE_COLOR)
       
       # Optional: Draw text or frame number to help debug
       # draw.text((10, 10), f"Frame {i}", fill=(255, 255, 255))
       
       frames.append(img)
       print(f"  Frame {i}: Rotation {angle_deg:.1f}°")

   # 5. Save as GIF
   output_filename = "triangle_spin.gif"
   frames[0].save(
       output_filename,
       save_all=True,
       append_images=frames[1:],
       duration=100, # ms per frame
       loop=0
   )
   print(f"\nAnimation saved to: {output_filename}")