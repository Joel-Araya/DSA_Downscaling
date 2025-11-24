import socket
import base64
import numpy as np
from PIL import Image
import tkinter as tk
from tkinter import filedialog

class TCLClient:
    def __init__(self, host="127.0.0.1", port=9999):
        self.s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.s.connect((host, port))
        self.f = self.s.makefile("rwb")  # lectura/escritura con buffering

    def send(self, cmd):
        self.f.write((cmd+"\n").encode())
        self.f.flush()
        resp = self.f.readline().decode().strip()
        return resp

    def set_params(self, w, h, scale):
        return self.send(f"SET_PARAMS {w} {h} {scale}")

    def write_pixels_full(self, data): # Versión para enviar toda la imagen de una vez
        b64 = base64.b64encode(data).decode()
        return self.send(f"WRITE_PIXELS {len(data)} {b64}")
    
    def write_pixels(self, chunk_index, data): # Versión para enviar en bloques
        b64 = base64.b64encode(data).decode()
        return self.send(f"WRITE_PIXELS {chunk_index} {b64}")

    def start(self):
        return self.send("START")

    def read_output(self):
        resp = self.send("READ_OUTPUT")
        _, b64 = resp.split(" ", 1)
        return base64.b64decode(b64)

    def step(self):
        return self.send("STEP")

    def read_reg(self, reg):
        return self.send(f"READ_REG {reg}")

    def load_image(self, filepath="Imagenes/input.png"):
        """Carga una imagen real, la convierte a gris y la retorna como bytes."""
        if filepath == None:
            # Abrir un dialog para seleccionar la imagen
            root = tk.Tk()
            root.withdraw()  # Ocultar la ventana principal
            filepath = filedialog.askopenfilename(title="Selecciona una imagen", filetypes=[("Image files", "*.png;*.jpg;*.jpeg;*.bmp;*.gif")])

        print("Cargando imagen:", filepath)

        img = Image.open(filepath).convert("L")  # escala de grises (8 bits)
        #Guardar versión en gris
        img.save("Imagenes/gray_image.png")
        w, h = img.size
        arr = np.array(img, dtype=np.uint8)
        return arr.tobytes(), w, h



def procesar_data_response(response, width, height, output_file="Imagenes/resultado.png"):
    """
    Procesa una respuesta DATA <base64>, reconstruye la imagen y la guarda en disco.
    
    Params:
        response (str): Respuesta recibida del servidor TCL.
        width (int): Ancho de la imagen.
        height (int): Alto de la imagen.
        output_file (str): Nombre del archivo de salida.
        
    Returns:
        bool: True si la imagen fue generada, False si no era un DATA válido.
    """

    if not response.startswith("DATA "):
        return False  # no es una respuesta con datos de imagen

    try:
        # Extraer la parte base64
        b64 = response[5:]
        img_bytes = base64.b64decode(b64)

        # Convertir bytes a imagen (formato L porque es grayscale)
        img = Image.frombytes("L", (width, height), img_bytes)

        # Guardar a archivo
        img.save(output_file)
        print(f"[OK] Imagen guardada como {output_file}")

        return True

    except Exception as e:
        print("[ERROR] Falló al reconstruir la imagen:", e)
        return False

if __name__ == "__main__":
    t = TCLClient()

    #image_path = "Imagenes/jolly_roger.png"  # Ruta a la imagen de prueba
    #img_data, width, height = t.load_image(image_path)

    img_data, width, height = t.load_image(None)
    scale = 1  # Factor de escala

    print(f"Server: {t.set_params(width, height, scale)}")
    
    
    CHUNK = 1000  # Tamaño del bloque en bytes
    chunk_index = 0
    # Escribir la imagen en bloques
    for i in range(0, len(img_data), CHUNK):
        block = img_data[i:i+CHUNK]
        t.write_pixels(chunk_index, block)
        chunk_index += 1
    
    command = input("Comando TCL: ").upper()
    while command.lower() != "exit":
        if command == "":
            # No enviar nada, seguir esperando
            command = input("Comando TCL: ").upper()
            continue

        response = t.send(command)
        if response.startswith("DATA "):
            #print(f"Respuesta, {response}")  # Mostrar solo los primeros 50 caracteres para no saturar la consola
            procesar_data_response(response, width, height)
        else:
            print("Respuesta:", response)
        command = input("Comando TCL: ").upper()
