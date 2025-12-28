# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "numpy",
# ]
# ///

import numpy as np

# --- (Your Helper Functions: create_model_matrix, look_at, perspective remain exactly the same) ---
def create_model_matrix(position, scale, rotation_euler):
    tx, ty, tz = position
    sx, sy, sz = scale
    rz = rotation_euler[2] 
    c = np.cos(rz)
    s = np.sin(rz)
    rs_mat = np.array([
        [sx*c, -sy*s, 0, 0],
        [sx*s,  sy*c, 0, 0],
        [   0,     0, sz, 0],
        [   0,     0,  0, 1]
    ], dtype=np.float32)
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

# --- NEW: Fixed Point Converter ---
def float_to_q16_16_hex(val):
    # Scale by 65536 (2^16)
    fixed_val = int(val * 65536.0)
    # Handle negative numbers (Two's complement for 32-bit)
    if fixed_val < 0:
        fixed_val = (1 << 32) + fixed_val
    # Return as hex string
    return f"32'h{fixed_val:08X}"

def print_verilog_matrix(mat):
    print("\n// ==========================================")
    print("// SystemVerilog Fixed Point Matrix (Q16.16)")
    print("// ==========================================")
    print("logic signed [31:0] MVP_MATRIX [0:15] = '{")
    
    rows = ["X", "Y", "Z", "W"]
    
    for r in range(4):
        line_vals = []
        for c in range(4):
            line_vals.append(float_to_q16_16_hex(mat[r, c]))
        
        # Formatting specifically to show the dot product relationship
        comment = f"// Row {r} (Calculates {rows[r]}_out): Multiply with {{Vx, Vy, Vz, Vw}}"
        print(f"    {', '.join(line_vals)}, {comment}")

    print("};")
    print("// Access pattern: MVP_MATRIX[row*4 + col]")

def print_mat(name, mat):
    print(f"\n--- {name} Matrix ---")
    # Clean formatting: 3 decimal places, suppress scientific notation, align columns
    with np.printoptions(precision=3, suppress=True, linewidth=100, formatter={'float': '{: 8.3f}'.format}):
        print(mat) 

# ==============================================================================
# CONFIGURATION
# ==============================================================================
if __name__ == "__main__":
    # 1. SCREEN SETTINGS
    FOV_DEGREES  = 90.0
    ASPECT_RATIO = 320.0 / 240.0 # Match your hardware resolution!
    NEAR_PLANE   = 1.0
    FAR_PLANE    = 20.0

    # 2. CAMERA SETTINGS
    CAM_POS    = [0.0, 5.0, 10.0]
    CAM_TARGET = [0.0, 0.0, 0.0]
    CAM_UP     = [0.0, 1.0, 0.0]

    # 3. OBJECT SETTINGS
    OBJ_POS    = [0.0, 0.0, 0.0] # Centered
    OBJ_SCALE  = [1.0, 1.0, 1.0] # No scaling
    # OBJ_ROT    = [0.0, 0.0, np.radians(45)]
    OBJ_ROT    = [0.0, 0.0, 0.0] # No rotation

    # CALCULATION
    model_mat = create_model_matrix(OBJ_POS, OBJ_SCALE, OBJ_ROT)
    view_mat  = look_at(CAM_POS, CAM_TARGET, CAM_UP)
    proj_mat  = perspective(FOV_DEGREES, ASPECT_RATIO, NEAR_PLANE, FAR_PLANE)

    mvp_mat = proj_mat @ view_mat @ model_mat
    
    print_mat("Model", model_mat)

    print_mat("View", view_mat)

    print_mat("Projection", proj_mat)

    print_mat("Final MVP", mvp_mat) 



    # Generate the Verilog code
    print_verilog_matrix(mvp_mat)