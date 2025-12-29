# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "numpy",
# ]
# ///

import numpy as np

# ==============================================================================
# 1. MATHEMATICAL HELPERS
# ==============================================================================

def get_rotation_matrix(axis, radians):
    """Generates a 4x4 rotation matrix for X, Y, or Z axis."""
    c = np.cos(radians)
    s = np.sin(radians)
    
    if axis.upper() == 'X':
        return np.array([
            [1, 0, 0, 0],
            [0, c, -s, 0],
            [0, s, c, 0],
            [0, 0, 0, 1]
        ], dtype=np.float32)
    elif axis.upper() == 'Y':
        return np.array([
            [ c, 0, s, 0],
            [ 0, 1, 0, 0],
            [-s, 0, c, 0],
            [ 0, 0, 0, 1]
        ], dtype=np.float32)
    elif axis.upper() == 'Z':
        return np.array([
            [c, -s, 0, 0],
            [s, c, 0, 0],
            [0, 0, 1, 0],
            [0, 0, 0, 1]
        ], dtype=np.float32)
    else:
        return np.eye(4, dtype=np.float32)

def create_model_matrix(position, scale, rotation_matrix):
    tx, ty, tz = position
    sx, sy, sz = scale
    
    # Scale Matrix
    scale_mat = np.eye(4, dtype=np.float32)
    scale_mat[0,0] = sx
    scale_mat[1,1] = sy
    scale_mat[2,2] = sz
    
    # Translation Matrix
    trans_mat = np.eye(4, dtype=np.float32)
    trans_mat[:3, 3] = [tx, ty, tz]
    
    # Order: T * R * S
    return trans_mat @ rotation_matrix @ scale_mat

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
# 2. OUTPUT FORMATTER (Q16.16)
# ==============================================================================

def float_to_q16_16_hex(val):
    # Scale by 65536 (2^16)
    fixed_val = int(val * 65536.0)
    if fixed_val < 0:
        fixed_val = (1 << 32) + fixed_val
    return f"32'h{fixed_val & 0xFFFFFFFF:08X}"

def print_combined_verilog_array(all_frames_data):
    num_frames = len(all_frames_data)
    
    print(f"\n// ==========================================")
    print(f"// ANIMATION DATA: {num_frames} FRAMES")
    print(f"// Access: MVP_FRAMES[frame_index][matrix_element_index]")
    print(f"// ==========================================")
    
    # Declare 2D array: [Number of Frames][16 Elements per matrix]
    print(f"logic signed [31:0] MVP_FRAMES [0:{num_frames-1}][0:15] = '{{")
    
    for i, frame_hex_list in enumerate(all_frames_data):
        print(f"    // Frame {i}")
        print("    '{")
        
        # Print 4 rows of 4 elements for readability
        for r in range(4):
            row_start = r * 4
            row_end   = row_start + 4
            row_vals  = frame_hex_list[row_start : row_end]
            
            # Formatting
            line_str = ", ".join(row_vals)
            
            # Add comma if this isn't the very last row of the very last frame
            # But inside a SystemVerilog array literal, every element needs a comma except the last
            
            suffix = "," # Comma after every row for internal array structure
            if r == 3: suffix = "" # No comma at end of the 'frame' block internally
            
            print(f"        {line_str}{suffix}")
            
        # Close the frame block
        closer = "},"
        if i == num_frames - 1:
            closer = "}" # No comma after the last frame
            
        print(f"    {closer}")

    print("};")

# ==============================================================================
# 3. MAIN CONFIGURATION & LOOP
# ==============================================================================
if __name__ == "__main__":
    
    # --- ANIMATION SETTINGS ---
    NUM_FRAMES         = 16
    ROTATION_AXIS      = 'Z'   # 'X', 'Y', or 'Z'
    TOTAL_TURN_DEGREES = 360.0

    # --- STANDARD SETTINGS ---
    FOV_DEGREES  = 90.0
    ASPECT_RATIO = 320.0 / 240.0 
    NEAR_PLANE   = 1.0
    FAR_PLANE    = 20.0

    CAM_POS    = [0.0, 0.0, 10.0]
    CAM_TARGET = [0.0, 0.0, 0.0]
    CAM_UP     = [0.0, 1.0, 0.0]

    OBJ_POS    = [0.0, 0.0, 0.0] 
    OBJ_SCALE  = [1.0, 1.0, 1.0]

    # --- PRE-CALCULATE STATIC MATRICES ---
    view_mat = look_at(CAM_POS, CAM_TARGET, CAM_UP)
    proj_mat = perspective(FOV_DEGREES, ASPECT_RATIO, NEAR_PLANE, FAR_PLANE)
    vp_mat   = proj_mat @ view_mat

    # --- STORAGE FOR FINAL PRINT ---
    all_frames_hex = []

    # --- GENERATION LOOP ---
    for i in range(NUM_FRAMES):
        # Calculate angle
        deg = (i / NUM_FRAMES) * TOTAL_TURN_DEGREES
        rad = np.radians(deg)
        
        # Calculate MVP
        rot_mat = get_rotation_matrix(ROTATION_AXIS, rad)
        model_mat = create_model_matrix(OBJ_POS, OBJ_SCALE, rot_mat)
        mvp_mat = vp_mat @ model_mat
        
        # Flatten and Convert to Hex
        frame_hex = []
        for r in range(4):
            for c in range(4):
                frame_hex.append(float_to_q16_16_hex(mvp_mat[r, c]))
        
        all_frames_hex.append(frame_hex)

    # --- FINAL OUTPUT ---
    print_combined_verilog_array(all_frames_hex)