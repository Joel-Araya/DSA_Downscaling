import socket
import base64
import numpy as np
from PIL import Image
import tkinter as tk
from tkinter import filedialog

regs = {
    "REG_STATUS": "00000000",
    "REG_IMG_WIDTH": "00000001",
    "REG_IMG_HEIGHT": "00000010",
    "REG_SCALE": "00000011",
    "REG_MODE": "00000100",
    "PERF_CYCLES": "00010000",
    "PERF_FLOPS": "00010001",
    "PERF_MEM_READ": "00010010",
    "PERF_MEM_WRITE": "00010011",
    "DBG_FSM_STATE": "00100000",
    "DBG_CURR_X": "00100001",
    "DBG_CURR_Y": "00100010",
    "DBG_MEM_ADDR": "00100011",
    "DBG_PIXEL_OUT_0": "00110000",
    "DBG_PIXEL_OUT_1": "00110001",
    "DBG_PIXEL_OUT_2": "00110010",
    "DBG_PIXEL_OUT_3": "00110011",
    "DBG_NEIGHBORS": "00110100"}


class TCLClient:
    def __init__(self, host="127.0.0.1", port=2540):
        self.s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.s.connect((host, port))
        self.f = self.s.makefile("rwb")  # lectura/escritura en modo binario
        self.image = None
        self.width = 0
        self.height = 0
        self.scale = 1
        self.mode = 0 # Secuencial por defecto, 1 SIMD
        self.debug = 0
        self.N_simd = 0 # No usado en modo secuencial

    # ------------------
    # Funciones de texto
    # ------------------
    def send(self, cmd):
        self.f.write((cmd+"\n").encode())
        self.f.flush()
        resp = self.f.readline().decode().strip()
        return resp


    # -------------------------
    # Cargar imagen desde disco
    # -------------------------
    def load_image(self, filepath="Imagenes/input.png"):
        if filepath is None:
            root = tk.Tk()
            root.withdraw()
            filepath = filedialog.askopenfilename(
                title="Selecciona una imagen",
                filetypes=[("Image files", "*.png;*.jpg;*.jpeg;*.bmp;*.gif")]
            )

        print("Cargando imagen:", filepath)

        self.image = Image.open(filepath).convert("L")  # gris 8 bits

        # Guardar versión en gris
        self.image.save("Imagenes/gray_image.png")

        self.width, self.height = self.image.size
        arr = np.array(self.image, dtype=np.uint8)

        return arr.tobytes(), self.width, self.height



    def process_image_config_command(self, cmd:str) -> str:
        #Bit31 1, Bit30 0/1 (secuencial/SIMD), Bit29 0/1 (debug off/on), Bits[28-20] width, Bits[19-11] height, Bits[10-8] N SIMD, Bits[7-0] scale 
        cmd_parts = cmd.split()
        if len(cmd_parts) == 7: #IMAGE_CONFIG <width> <height> <scale> <mode> <debug>, <N_SIMD> 
            #Convertir el string que trae width a binario con 9 bits
            width_bin = format(int(cmd_parts[1]), '09b')  # Bits [28-20]
            height_bin = format(int(cmd_parts[2]), '09b') # Bits [19-11]
            N_simd_bin = format(int(cmd_parts[6]), '03b') #Bits [10-8]
            #Lo mismo con la escala, pero no es int, es un float entre 0.5 y 1.0
            scale_bin = format(int(float(cmd_parts[3])*100), '08b')  # Escala entre 0.5 y 1.0


            cmd_binary = "1" + cmd_parts[4] + cmd_parts[5] + width_bin + height_bin + N_simd_bin + scale_bin
            return cmd_binary
        else:
            print("[ERROR] Formato incorrecto para IMAGE_CONFIG. Uso: IMAGE_CONFIG <width> <height> <scale> <mode> <debug> <N_SIMD>")
            return None
    
    def write_pixels(self):
        """
        Divide la imagen cargada (self.image) en chunks de 4 pixeles.
        Cada chunk se convierte a un string de 32 bits.
        """
        if self.image is None:
            print("[ERROR] No hay imagen cargada.")
            return None

        arr = np.array(self.image, dtype=np.uint8).flatten()

        pixels_bin = []

        # Procesar en pasos de 4 bytes
        for i in range(0, len(arr), 4):
            chunk = arr[i:i+4]

            # Rellenar el chunk si es necesario (solo ocurre en el último bloque)
            if len(chunk) < 4:
                padded = np.zeros(4, dtype=np.uint8)
                padded[:len(chunk)] = chunk
                chunk = padded

            # Convertir 4 bytes → string de 32 bits
            chunk_bin = ''.join(f"{byte:08b}" for byte in chunk)

            pixels_bin.append(chunk_bin)

        
        for binary in pixels_bin:
            response = self.send(f"WRITE_PIXELS {binary}")
            # print(f"Enviado: {binary}, Respuesta del servidor: {response}")

        return pixels_bin
    
    
    # Metodo para confirmar que los datos de la imagen han sido leídos correctamente
    def dato_leido(self):
        cmd = "0" + "1"*31  # Bit 31 = 0, Bits [30-0] = 1
        response = self.send(cmd)
        return response
            


    def convert_command_to_binary(self, command:str) -> str:
        """
        Convierte un comando textual en su representación binaria (en string).
        """
        parts = command.split()

        # Suponiendo 32 bits por instrucción
        cmd_bin = "0"*32
        if parts[0] in ["START", "STEP"]: #1000 0000 0000 0000 0000 0000 0000 0000
            #Cambiar bit 28 a 1
            cmd_bin = "1" + cmd_bin[1:] #Bit 31 cambiado a 1
            return cmd_bin
        
        elif parts[0] == "IMAGE_CONFIG": #Bit31 1, Bit30 0/1 (secuencial/SIMD), Bit29 0/1 (debug off/on), Bits[28-20] width, Bits[19-11] height, Bits[10-8] N SIMD, Bits[7-0] scale 
            cmd_bin = self.process_image_config_command(command)
            return cmd_bin


        elif parts[0] == "WRITE_PIXELS": #Se envían 4 pixeles de la imagen guardada en la variable self.image
            if len(parts) != 1:
                print("[ERROR] Formato incorrecto para WRITE_PIXELS. Uso: WRITE_PIXELS")
                return None
            #De momento no se hace nada aquí, se envían los pixeles en la función write_pixels()
            return None 
        
        elif parts[0] == "READ_REG":
            #Dos casos, si escribe READ_REG <reg_name> o READ_REG <reg_address>
            if len(parts) != 2:
                print("[ERROR] Formato incorrecto para READ_REG. Uso: READ_REG <reg_name/reg_address>")
                return None
            
            reg = parts[1]
            if reg in regs:
                reg_addr_bin = regs[reg]
            else:
                
                direcciones = regs.values()
                if reg not in direcciones:
                    print("[ERROR] Registro no reconocido.")
                    return None
                reg_addr_bin = reg  # Ya es binario
                    


            cmd_bin = "01" + "0"*22 + reg_addr_bin  # Bits [31-30]=01, Bits [29-8]=0, Bits [7-0]=reg_addr_bin

            return cmd_bin
        
        elif parts[0] == "READ_IMAGE":
            cmd_bin = "0001" + "0"*28  # Bits [31-28]=0001, Bits [27-0]=0
            response = self.send(cmd_bin)

            print(response)

            width_downscaled = int(self.width * self.scale)
            height_downscaled = int(self.height * self.scale)
            num_pixels = width_downscaled * height_downscaled

            contador = 0

            imagen_generada = [] 
            
            pixel0 = int(response[0:8], 2)
            pixel1 = int(response[8:16], 2)
            pixel2 = int(response[16:24], 2)
            pixel3 = int(response[24:32], 2)

            imagen_generada.extend([pixel0, pixel1, pixel2, pixel3])
            contador +=4


            while contador < num_pixels:
                
                response = self.send(cmd_bin)

                pixel0 = int(response[0:8], 2)
                pixel1 = int(response[8:16], 2)
                pixel2 = int(response[16:24], 2)
                pixel3 = int(response[24:32], 2)

                imagen_generada.extend([pixel0, pixel1, pixel2, pixel3])
                contador +=4

            #Recortar la imagen generada al tamaño correcto
            imagen_generada = imagen_generada[:num_pixels]

            #Guardar la imagen generada como PNG
            img_array = np.array(imagen_generada, dtype=np.uint8).reshape((height_downscaled, width_downscaled))
            img = Image.fromarray(img_array, mode='L')
            img.save("Imagenes/imagen_generada.png")

            
            return None

        
        else:
            print("[ERROR] Comando no reconocido o formato incorrecto.")
            return None
        return cmd_bin

    def help(self):
        print(""" Comandos disponibles:
        START                                                           - Inicia el procesamiento de la imagen.
        STEP                                                            - Procesa un paso de la imagen (modo debug).
        IMAGE_CONFIG <width> <height> <scale> <mode> <debug> <N_SIMD>   - Configura los parámetros de la imagen.
        WRITE_PIXELS                                                    - Envía los datos de la imagen cargada.
        READ_REG <reg_name/reg_address>                                 - Lee el valor de un registro específico.
        READ_IMAGE                                                      - Lee la imagen procesada y la guarda como PNG.
        EXIT                                                            - Salir del programa.
        HELP                                                            - Muestra esta ayuda.
        """
        )


# ============================================================
#                       MAIN PROGRAM
# ============================================================
if __name__ == "__main__":
    t = TCLClient()

    # # Cargar imagen real
    img_data, width, height = t.load_image(None)
    # scale = 1

    # Enviar configuración de imagen
    t.scale = 0.5
    t.mode = 0  # Secuencial
    t.debug = 0
    t.N_simd = 0  # No usado en modo secuencial
    image_config_cmd = f"IMAGE_CONFIG {t.width} {t.height} {t.scale} {t.mode} {t.debug} {t.N_simd}"
    converted_cmd = t.convert_command_to_binary(image_config_cmd)
    t.send(converted_cmd)

    # Enviar datos de la imagen
    t.write_pixels()





    # ------------------
    # Loop de comandos manuales
    # ------------------
    command = input("Comando TCL: ").upper()

    while command != "EXIT":
        if command == "" or command=="HELP":
            if command == "HELP":
                t.help()
            command = input("Comando TCL: ").upper()
            continue
    
        
        converted_to_binary = t.convert_command_to_binary(command)
        if converted_to_binary is None:
            command = input("Comando TCL: ").upper()
            continue
        
        print("Enviando comando:", command)
        response = t.send(converted_to_binary)
        print("Respuesta:", response)

        command = input("Comando TCL: ").upper()
