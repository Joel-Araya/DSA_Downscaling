from PIL import Image
import numpy as np
import time
from typing import Tuple
from pathlib import Path

# -------------------------
# Utilidades: carga/guardado, banco de pruebas, etc.
# -------------------------

def load_grayscale(path: str) -> np.ndarray:
    im = Image.open(path).convert('L')
    return np.array(im, dtype=np.uint8)


def save_grayscale(arr: np.ndarray, path: str):
    Image.fromarray(arr).save(path)


def benchmark_and_compare(img: np.ndarray, scale: float):
    print(f"Dimensiones de entrada: {img.shape}, escala={scale}")
    t0 = time.time()
    out_seq = downscale_sequential(img, scale)
    t1 = time.time()
    out_vec = downscale_vectorized(img, scale)
    t2 = time.time()
    print(f"\nTiempo secuencial: {t1-t0:.3f}s, Tiempo vectorizado: {t2-t1:.3f}s")
    equal = np.array_equal(out_seq, out_vec)
    mismatches = None
    if not equal:
        # mostrar algunos diagnósticos
        diff = out_seq.astype(np.int16) - out_vec.astype(np.int16)
        mismatches = np.count_nonzero(diff)
        maxdiff = diff.max()
        mindiff = diff.min()
        print(f"¡Las salidas difieren! diferencias={mismatches}, rango de diferencia {mindiff}..{maxdiff}")
    else:
        print("Salidas idénticas (bit a bit).")
    return out_seq, out_vec, equal, mismatches


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def scale_to_steps(scale: float) -> float:
    """Ajusta y redondea la escala a pasos permitidos (0.50..1.00 paso 0.05)."""
    s = round(scale * 100) / 100.0
    if s < 0.50: s = 0.50
    if s > 1.00: s = 1.00
    # redondear al 0.05 más cercano
    step = round(s / 0.05) * 0.05
    return round(step, 2)


def get_output_size(w: int, h: int, scale: float) -> Tuple[int,int]:
    scale = scale_to_steps(scale)
    ow = max(1, int(np.floor(w * scale))) # ancho de salida
    oh = max(1, int(np.floor(h * scale))) # alto de salida
    return ow, oh


# -------------------------
# Interpolación bilineal de punto fijo
# -------------------------
def downscale_sequential(img: np.ndarray, scale: float) -> np.ndarray:
    """
    Reduce la escala de una imagen en escala de grises (numpy 2D uint8) usando interpolación bilineal
    con matemática de enteros. Implementación secuencial: bucles sobre los píxeles de salida.
    """
    in_h, in_w = img.shape
    scale = scale_to_steps(scale)
    out_w, out_h = get_output_size(in_w, in_h, scale)
    out = np.zeros((out_h, out_w), dtype=np.uint8)

    for oy in range(out_h):
        for ox in range(out_w):
            # mapear a coordenada fuente (conceptualmente flotante)
            src_x = (ox + 0.0) / scale
            src_y = (oy + 0.0) / scale

            ix = int(np.floor(src_x))
            iy = int(np.floor(src_y))

            # ajustar coordenadas enteras al rango válido para leer vecinos
            ix = clamp(ix, 0, in_w - 2)
            iy = clamp(iy, 0, in_h - 2)

            fx = src_x - ix
            fy = src_y - iy

            # parte fraccionaria en [0..255]
            fx_q = int(round(fx * 256))  # 0..256 (pero fx<1 así que normalmente 0..255)
            fy_q = int(round(fy * 256))

            # asegurar límites 0..255
            fx_q = clamp(fx_q, 0, 255)
            fy_q = clamp(fy_q, 0, 255)

            # pesos como producto de números Q0.8 -> rango 0..65536
            w00 = (256 - fx_q) * (256 - fy_q)
            w10 = fx_q * (256 - fy_q)
            w01 = (256 - fx_q) * fy_q
            w11 = fx_q * fy_q

            p00 = int(img[iy, ix])
            p10 = int(img[iy, ix + 1])
            p01 = int(img[iy + 1, ix])
            p11 = int(img[iy + 1, ix + 1])

            acc = p00 * w00 + p10 * w10 + p01 * w01 + p11 * w11
            # redondeo
            out_pix = (acc + (1 << 15)) >> 16  # equivalente a (acc/65536) redondeado
            out[oy, ox] = clamp(out_pix, 0, 255)

    return out


def downscale_vectorized(img: np.ndarray, scale: float) -> np.ndarray:
    """
    Implementación vectorizada (NumPy) del mismo algoritmo de reducción de escala bilineal de punto fijo.
    Calcula todas las coordenadas de mapeo a la vez y usa indexación avanzada y operaciones elemento a elemento.
    Es un buen modelo de procesamiento SIMD
    """
    in_h, in_w = img.shape
    scale = scale_to_steps(scale)
    out_w, out_h = get_output_size(in_w, in_h, scale)

    # crear cuadrícula de coordenadas de salida
    oy = np.arange(out_h)
    ox = np.arange(out_w)
    grid_y, grid_x = np.meshgrid(oy, ox, indexing='xy')  # forma (out_h,out_w) si xy

    # pero por simplicidad producir arreglos con forma (out_h, out_w)
    grid_x = grid_x.T
    grid_y = grid_y.T

    # calcular coordenadas fuente
    src_x = grid_x.astype(np.float64) / scale
    src_y = grid_y.astype(np.float64) / scale

    # calcular componentes enteras y fraccionarias
    ix = np.floor(src_x).astype(np.int32)
    iy = np.floor(src_y).astype(np.int32)
    ix = np.clip(ix, 0, in_w - 2)
    iy = np.clip(iy, 0, in_h - 2)

    # calcular partes fraccionarias
    fx = src_x - ix
    fy = src_y - iy
    fx_q = np.round(fx * 256).astype(np.int32)
    fy_q = np.round(fy * 256).astype(np.int32)
    fx_q = np.clip(fx_q, 0, 255)
    fy_q = np.clip(fy_q, 0, 255)

    # calcular pesos
    w00 = (256 - fx_q) * (256 - fy_q)  # int arrays
    w10 = fx_q * (256 - fy_q)
    w01 = (256 - fx_q) * fy_q
    w11 = fx_q * fy_q

    # recopilar píxeles con indexación vectorizada
    p00 = img[iy, ix].astype(np.int32)
    p10 = img[iy, ix + 1].astype(np.int32)
    p01 = img[iy + 1, ix].astype(np.int32)
    p11 = img[iy + 1, ix + 1].astype(np.int32)

    # combinar todo
    acc = p00 * w00 + p10 * w10 + p01 * w01 + p11 * w11
    out = ((acc + (1 << 15)) >> 16).astype(np.int32)
    out = np.clip(out, 0, 255).astype(np.uint8)
    return out


if __name__ == "__main__":
    print("\n--- Downscaling bilineal punto fijo: referencia secuencial vs vectorizada ---\n")

    # Cargar imagen original (convertida a escala de grises)
    path_in = Path("Imagenes/fpga.jpg")
    img = load_grayscale(path_in)

    # Definir factor de escala
    scale = 0.75

    # Ejecutar versión secuencial y SIMD (vectorizada)
    out_seq, out_vec, eq, mismatches = benchmark_and_compare(img, scale)

    # Guardar resultados
    output_path = Path("Avance_1/Resultados")
    output_path.mkdir(exist_ok=True)
    save_grayscale(out_seq, output_path / "fpga_downscaled_seq.png")
    save_grayscale(out_vec, output_path / "fpga_downscaled_vec.png")

    print("Imágenes generadas en la carpeta Resultados/")
    if eq:
        print("Ambas versiones son idénticas (bit a bit).\n")
    else:
        print(f"Diferencias detectadas en {mismatches} píxeles.\n")
