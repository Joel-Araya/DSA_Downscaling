import sys
import numpy as np
from PIL import Image
from pathlib import Path

# Recibir ruta absoluta desde C++
img_dir = Path(sys.argv[1])

# Rutas completas
input_png = img_dir / "input.png"
raw_path  = img_dir / "input.raw"
dims_path = img_dir / "dims.txt"

img = Image.open(input_png).convert("L")
arr = np.array(img, dtype=np.uint8)

h, w = arr.shape

arr.tofile(raw_path)

with open(dims_path, "w") as f:
    f.write(f"{w} {h}")

print("generate_raw.py: listo")
