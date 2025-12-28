# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "numpy",
# ]
# ///

import numpy as np

# ==============================================================================
# 1. SETUP THE EXACT MATRIX FROM YOUR VERILOG
# ==============================================================================
# We reconstruct the matrix columns from your SystemVerilog code
# Note: Your code calculates dot products row by row.
# mvp_matrix = np.array([
# [  0.530,   -0.530,    0.000,    0.000],
#  [   0.632,    0.632,   -0.447,   -0.000],
#  [  -0.317,   -0.317,   -0.896,   11.003],
#  [  -0.316,   -0.316,   -0.894,   11.180]], 
#  dtype=np.float32)


mvp_matrix = np.array([
    [ 0.750,    0.000,    0.000,    0.000],
    [ 0.000,    0.894,   -0.447,   -0.000],
    [ 0.000,   -0.494,   -0.989,   10.252],
    [ 0.000,   -0.447,   -0.894,   11.180]
], dtype=np.float32)

# Re-creating the exact hex values you used to ensure 1:1 match
# 32'h000087C3 = 0.5303...
# 32'hFFFF783D = -0.5303...
# etc...
# For verification, we will use float math, but it will be close enough to check logic.

# ==============================================================================
# 2. DEFINE THE TEST TRIANGLE (From vertex_data.mem)
# ==============================================================================
# (-1, -1, 1), (1, -1, 1), (1, 1, 1)
vertices = [
    np.array([-1.0, -1.0, 1.0, 1.0]),
    np.array([ 1.0, -1.0, 1.0, 1.0]),
    np.array([ 1.0,  1.0, 1.0, 1.0])
]

print("--- GEOMETRY ENGINE VERIFICATION ---")

for i, v in enumerate(vertices):
    print(f"\nProcessing Vertex {i}: {v[:3]}")
    
    # STEP 1: MATRIX TRANSFORM
    # -----------------------------------------------------
    # Clip Coords = Matrix * Vector
    clip = mvp_matrix @ v
    
    print(f"  [1] Clip Space (x_out, y_out, z_out, w_out):")
    print(f"      X: {clip[0]:.4f}")
    print(f"      Y: {clip[1]:.4f}")
    print(f"      Z: {clip[2]:.4f}")
    print(f"      W: {clip[3]:.4f} (Should be > 0.1)")

    # STEP 2: PERSPECTIVE DIVIDE
    # -----------------------------------------------------
    # NDC = Clip / W
    ndc_x = clip[0] / clip[3]
    ndc_y = clip[1] / clip[3]
    ndc_z = clip[2] / clip[3]
    
    print(f"  [2] NDC (x_ndc, y_ndc):")
    print(f"      X: {ndc_x:.4f}")
    print(f"      Y: {ndc_y:.4f}")

    # STEP 3: VIEWPORT MAP
    # -----------------------------------------------------
    # Screen X = (NDC_X + 1.0) * 160
    # Screen Y = (NDC_Y + 1.0) * 120
    screen_x = (ndc_x + 1.0) * 160.0
    screen_y = (ndc_y + 1.0) * 120.0
    screen_z = (ndc_z + 1.0) * 127.5 # [-1,1] to [0,255]
    
    # Convert to Q16.16 Hex for comparison
    def to_hex(val):
        fixed = int(val * 65536.0)
        return f"{fixed:08X}"

    print(f"  [3] FINAL OUTPUT (Compare these to your waveform):")
    print(f"      x register (Dec): {int(screen_x)} (Hex: {to_hex(screen_x)})")
    print(f"      y register (Dec): {int(screen_y)} (Hex: {to_hex(screen_y)})")
    print(f"      z register (Dec): {int(screen_z)} (Hex: {to_hex(screen_z)})")