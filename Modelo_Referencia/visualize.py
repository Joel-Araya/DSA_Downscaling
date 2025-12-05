import sys
import numpy as np
from PIL import Image
from pathlib import Path

img_dir = Path(sys.argv[1])

# Leer dimensiones de salida
with open(img_dir / "dims_out.txt") as f:
    w, h = map(int, f.read().split())

#========= SERIAL =========
arr_serial = np.fromfile(img_dir / "output_serial.raw", dtype=np.uint8)
arr_serial = arr_serial.reshape((h, w))
Image.fromarray(arr_serial).save(img_dir / "output_serial.png")

#========= SIMD ==========
arr_simd = np.fromfile(img_dir / "output_simd.raw", dtype=np.uint8)
arr_simd = arr_simd.reshape((h, w))
Image.fromarray(arr_simd).save(img_dir / "output_simd.png")

print("visualize.py: imágenes creadas")
