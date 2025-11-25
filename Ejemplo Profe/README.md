# Interfaz de Comunicación JTAG para FPGA (vía puente TCP/IP) - Parametrizada y Bidireccional

## 1. Resumen

Este proyecto proporciona un marco flexible para la comunicación bidireccional y de ancho parametrizado (lectura y escritura) entre un PC host y una FPGA Intel/Altera usando la interfaz Virtual JTAG (vJTAG) a través de un puente TCP/IP. Permite enviar y recibir datos desde el diseño FPGA en tiempo real, soportando varios anchos de dato (p. ej., 8, 16, 32 bits) con configuración consistente en todos los componentes.

El sistema consta de:
1.  **Módulo Verilog parametrizado (`vjtag_interface.sv` [4]):** Módulo hardware con un parámetro de ancho de dato (`DW`) para instanciar dentro del diseño FPGA. Implementa los registros de datos accesibles por JTAG y usa enums para la decodificación de instrucciones.
2.  **Script TCL configurable (`jtag_server.tcl` [2]):** Se ejecuta dentro de `quartus_stp`. Crea un servidor TCP/IP que puentea comandos a operaciones JTAG. El ancho de datos JTAG se pasa como argumento de línea de comandos a este script.
3.  **Script Python configurable (`jtag_fpga.py` [1]):** Cliente de línea de comandos que se conecta al servidor TCL. Proporciona un procesador de comandos interactivo con historial, control de verbosidad y ancho de dato parametrizado.
4.  **Ejemplo de Verilog top-level (`top.sv` [3]):** Demuestra cómo instanciar y conectar el IP Virtual JTAG y el módulo parametrizado `vjtag_interface.sv` dentro de un diseño FPGA mayor.

Este README se basa en los archivos funcionales provistos:
*   `jtag_fpga.py` [1] (Cliente Python)
*   `jtag_server.tcl` [2] (Servidor TCL)
*   `top.sv` [3] (Diseño top-level de ejemplo)
*   `vjtag_interface.sv` [4] (Interfaz JTAG parametrizada en hardware)

## 2. Características

*   **Comunicación Bidireccional:** Soporta tanto escritura hacia la FPGA como lectura desde ella.
*   **Ancho de Dato Parametrizado (`DW`):** El ancho del canal de datos JTAG se puede configurar en Verilog (como se muestra en `vjtag_interface.sv` [4] y su instanciación en `top.sv` [3]) y sincronizar con los scripts de software mediante argumentos de línea de comandos.
*   **Cliente Python Amigable:**
    *   Procesador de comandos interactivo (`write`, `read`).
    *   Historial de comandos (flechas Arriba/Abajo, guardado entre sesiones vía `readline`).
    *   Verbosidad configurable (`quiet`, `normal`, `debug`) vía línea de comandos o comando `verbose` en tiempo de ejecución.
    *   El campo `<address>` en los comandos es actualmente un marcador de posición en software.
*   **Manejo claro de Instrucciones JTAG:** Usa un Registro de Instrucción (IR) de 2 bits para seleccionar BYPASS, WRITE o READ, decodificado mediante enums en Verilog (`vjtag_interface.sv` [4]).
*   **Uso del Máquina de Estados JTAG Estándar:** Utiliza las señales del IP Virtual JTAG (`v_cdr`, `v_sdr`, `udr`) para las fases correctas de captura, desplazamiento y actualización de datos.
*   **Soporte de Depuración:** El módulo Verilog (`vjtag_interface.sv` [4]) incluye salidas `debug_dr1` y `debug_dr2`, demostradas en `top.sv` [3] conectadas a LEDS.

## 3. Requisitos Previos

*   **Intel Quartus Prime (o Quartus II):**
    *   Para síntesis Verilog y programación de la FPGA.
    *   Requiere el core IP "Virtual JTAG".
    *   La utilidad `quartus_stp` (System Console / SignalTap II) es necesaria para ejecutar el script `jtag_server.tcl`.
*   **Python 3.x:**
    *   Para ejecutar el cliente `jtag_fpga.py`.
    *   Librerías estándar: `socket`, `time`, `argparse`, `os`, `readline`, `atexit`.
*   **(Opcional, para historial en Windows):** `pyreadline3`. Instalar con pip:
    ```
    pip install pyreadline3
    ```
*   **Placa de Desarrollo FPGA:** Una placa Intel/Altera con programador JTAG (p. ej., USB-Blaster) reconocida por Quartus.

## 4. Configuración e Instalación

El ancho de dato **DEBE** ser coherente entre:
1.  El valor del parámetro `DW` usado al instanciar `vjtag_interface.sv` en tu diseño top-level (p. ej., `localparam int DW = 16;` en `top.sv` [3]).
2.  La configuración del IP Virtual JTAG en Quartus (anchos de la ruta del registro de datos).
3.  El argumento de línea de comandos pasado a `jtag_server.tcl` [2].
4.  El argumento de línea de comandos (`-dw` o `--data_width`) pasado a `jtag_fpga.py` [1].

### 4.1. Diseño FPGA (Verilog y IP JTAG)

A. `vjtag_interface.sv` Module [4]
1.  Asegúrate de incluir este archivo Verilog en tu proyecto Quartus.
2.  El módulo está parametrizado con `parameter int DW = 8;` (valor por defecto si no se sobreescribe en la instanciación).

B. Configuración del IP Virtual JTAG en Quartus
1.  En tu proyecto Quartus, instancia el IP "Virtual JTAG". La instancia de ejemplo en `top.sv` [3] se llama `u_vjtag`.
2.  Configura el IP con los siguientes parámetros:
    *   **Ancho del Registro de Instrucción (IR):** Ajustar a **`2`** bits. Esto permite:
        *   `IR=0` (`2'b00`): BYPASS (mapea a `BYPASS` enum en `vjtag_interface.sv`)
        *   `IR=1` (`2'b01`): Instrucción de usuario para **WRITE** (mapea a `WRITE` enum, apunta a `DR1`)
        *   `IR=2` (`2'b10`): Instrucción de usuario para **READ** (mapea a `READ` enum, apunta a `DR2`)
    *   **Número de rutas de registros de datos de usuario (virtual JTAG):** Ajustar a **`2`**.
    *   Para **ruta de registro de datos de usuario 0** (corresponde a `IR=1` desde el IP):
        *   **Ancho del registro de datos:** Ajustar a tu `DW` elegido (p. ej., `16` como en `top.sv` [3]).
    *   Para **ruta de registro de datos de usuario 1** (corresponde a `IR=2` desde el IP):
        *   **Ancho del registro de datos:** Ajustar al *mismo* `DW`.
    *   **Señales expuestas desde el IP:** Asegúrate de que el IP esté configurado para exponer las señales de control necesarias. El ejemplo en `top.sv` [3] muestra estas conexiones:
        *   `ir_in` (salida de instrucción del IP, a menudo `ir_out[1:0]` en la GUI del IP)
        *   `virtual_state_cdr`
        *   `virtual_state_sdr`
        *   `virtual_state_udr`
        *   `tck` (reloj JTAG generado por el IP)
        *   `tdi` (TDI para pasar a la lógica de usuario)

C. Diseño top-level (Ejemplo: `top.sv` [3])
1.  Instancia el IP Virtual JTAG (p. ej., `u_vjtag`) y el módulo `vjtag_interface.sv` (p. ej., `u_vjtag_interface`).
2.  **Establece el parámetro `DW` para `vjtag_interface`** al instanciarlo. El archivo `top.sv` [3] usa `localparam int DW = 16;` y luego instancia con `vjtag_interface #(.DW(DW)) u_vjtag_interface (...)`.
3.  Conecta los puertos de salida del IP JTAG a los puertos de entrada correspondientes de `u_vjtag_interface`:
    *   IP JTAG `ir_in` (o su nombre real como `ir_out`) -> `u_vjtag_interface.ir_in`
    *   IP JTAG `virtual_state_cdr` -> `u_vjtag_interface.v_cdr`
    *   IP JTAG `virtual_state_sdr` -> `u_vjtag_interface.v_sdr`
    *   IP JTAG `virtual_state_udr` -> `u_vjtag_interface.udr`
    *   IP JTAG `tdi` (salida del IP hacia la lógica de usuario) -> `u_vjtag_interface.tdi`
    *   `u_vjtag_interface.tdo` -> IP JTAG `tdo` (entrada al IP desde la lógica de usuario)
    *   Conecta `u_vjtag_interface.aclr` a la señal de reset de tu sistema (p. ej., `resetn` en `top.sv`).
    *   Conecta `u_vjtag_interface.tck` a la salida `tck` del IP JTAG.
4.  Conecta las rutas de datos de `u_vjtag_interface`:
    *   `u_vjtag_interface.data_in` debe conectarse a las señales internas de la FPGA (de ancho `DW`) que deseas leer. En `top.sv` [3] esto está conectado a un `counter`.
    *   `u_vjtag_interface.data_out` debe conectarse a señales/registros internos de la FPGA (de ancho `DW`) que desees controlar desde el PC. En `top.sv` [3] esto está conectado a `jtag_data`, que puede cargar el `counter`.
5.  Opcionalmente, conecta los puertos de depuración (`debug_dr1`, `debug_dr2`) a LEDs o SignalTap, como en `top.sv` [3] donde se conectan a `LEDG` y partes de `LEDR`.

D. Compilar y Programar
1.  Añade todos los archivos `.sv` necesarios (incluyendo `top.sv` y `vjtag_interface.sv`) y el archivo `.qip` del IP JTAG a tu proyecto Quartus.
2.  Compila el proyecto.
3.  Programa tu placa FPGA.

### 4.2. Ejecución del Software

A. Iniciar el servidor TCL (`jtag_server.tcl` [2])
1.  Abre una terminal donde `quartus_stp` sea accesible (p. ej., desde un "Embedded Command Shell" o después de cargar los scripts de entorno de Quartus).
2.  Ejecuta el script, pasando el ancho de dato como argumento de línea de comandos. **Este ancho debe coincidir con `DW` usado en Verilog y en el IP JTAG.**
    *   Ejemplo para **16 bits** (para coincidir con `top.sv` [3]):
        ```
        quartus_stp -t /path/to/jtag_server.tcl 16
        ```
    *   Si `<DATA_WIDTH>` se omite, el script por defecto usa 8.
3.  El servidor indicará el ancho de dato usado y el puerto de escucha (por defecto: `2540`). Mantén esta terminal abierta.

B. Ejecutar el cliente Python (`jtag_fpga.py` [1])
1.  Abre otra terminal.
2.  Ejecuta el script, pasando el ancho de dato (`-dw` o `--data_width`) y la verbosidad opcional (`-v` para debug, `-q` para quiet). **Este ancho debe coincidir con el servidor TCL y el hardware.**
    *   Para **16 bits**:
        ```
        python /path/to/jtag_fpga.py -dw 16
        ```
    *   Para **16 bits** con verbosidad debug:
        ```
        python /path/to/jtag_fpga.py -dw 16 -v
        ```
    *   Ayuda: `python /path/to/jtag_fpga.py --help`

3.  Uso del procesador de comandos Python:
    El prompt indicará el ancho de dato activo (p. ej., `JTAG-16bit>`).
    *   `write <address> <value>`
        *   Ejemplo (16-bit): `write 0x10 0xABCD` o `write 16 43981`
        *   El rango de valores depende del `DATA_WIDTH` configurado.
    *   `read <address> <expected_value>`
        *   Ejemplo (16-bit): `read 0x10 0xABCD`
    *   `verbose <quiet|normal|debug>`: Cambia la verbosidad en tiempo de ejecución.
    *   `history`: Ver historial de comandos.
    *   `exit`: Salir del cliente.
    *   Usabilidad: Flechas Arriba/Abajo para historial. Usa el buffer de la terminal para revisar salida (configura el tamaño de historial de terminal si es necesario).

## 5. Resolución de Problemas

*   Lecturas devuelven valores incorrectos/fijos (como `01` hex):
    1.  **Desajuste de ancho de dato:** EL PROBLEMA MÁS COMÚN. Asegúrate de que `DW` en la instanciación de Verilog (`top.sv`), los anchos de las rutas del IP JTAG, el argumento del servidor TCL y el argumento del cliente Python sean TODOS IDENTICOS.
    2.  **Configuración del IP Virtual JTAG:** Confirma que el ancho del Registro de Instrucción sea `2`, que haya **dos** rutas de registro de datos de usuario configuradas, y que **ambas** rutas tengan su "Data register width" correctamente ajustado a `DW`. La segunda ruta (para `IR=2'b10`) debe estar activa para lecturas.
    3.  **Conexiones Verilog en `top.sv`:** Verifica que todas las señales de salida del IP JTAG (`ir_in`, `virtual_state_cdr`, etc.) estén correctamente cableadas a la instancia `u_vjtag_interface`.
    4.  **Lógica Verilog en `vjtag_interface.sv`:** ¿Está `ir_state` decodificando correctamente `ir_in`? ¿Se ejecuta `DR2 <= data_in;` durante `v_cdr` cuando `ir_state == READ`?
    5.  **Usar SignalTap II:** Sondea `ir_in`, `v_cdr`, `v_sdr`, `data_in`, `DR2`, `tdo` dentro de `vjtag_interface`, y las señales `counter` y `jtag_data` en `top.sv`.
*   **"Connection Refused" (Python):** El servidor TCL (`quartus_stp ...`) no está en ejecución o hay un problema de firewall.
*   **"Unknown command" (Servidor TCL, para escrituras):** Desajuste de ancho de dato. La longitud de la cadena binaria enviada desde Python no coincide con `$VJTAG_DATA_WIDTH` usado en el `regexp` del TCL.
