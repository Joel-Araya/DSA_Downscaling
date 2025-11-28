# ======================================================================
#  SERVIDOR TCL COMPLETO PARA PC <-> FPGA (vJTAG)
#  MODO MOCK (sin FPGA) y MODO HARDWARE (con FPGA real)
# ======================================================================

package require Tcl 8.6
package require base64

# ----------------------------------------------------------------------
# CONFIGURACIÓN
# ----------------------------------------------------------------------
set USE_FPGA 0        ;# 0 = Mock, 1 = FPGA real
set SERVER_PORT 2540  ;# Puerto para el cliente Python
set VJTAG_DATA_WIDTH 8 ;# Ancho de palabra para DR shifts (8,16,32...)

# Buffers para MOCK
set MOCK_MEMORY ""
set MOCK_OUTPUT ""

# Parámetros de imagen
set WIDTH 0
set HEIGHT 0
set SCALE 1


#Otros parámetros
array set MOCK_REGS {
    R0 0
    R1 0
    R2 0
    R3 0
    R4 0
    R5 0
    R6 0
    R7 0
}




# ----------------------------------------------------------------------
# MOCK IMPLEMENTATION (no FPGA)
# ----------------------------------------------------------------------

proc mock_write_pixels {bin_data} {
    global MOCK_MEMORY
    append MOCK_MEMORY $bin_data
}


proc mock_start {} {
    global MOCK_MEMORY MOCK_OUTPUT
    # Simula interpolación: copia entrada a salida
    set MOCK_OUTPUT $MOCK_MEMORY
}

proc mock_read_output {} {
    global MOCK_OUTPUT
    return $MOCK_OUTPUT
}

proc mock_read_reg {reg} {
    global MOCK_REGS

    if {[info exists MOCK_REGS($reg)]} {
        return $MOCK_REGS($reg)
    } else {
        return "0x0000"   ;# valor por defecto
    }
}


# Leer todos los registros mock en orden alfabético
proc mock_read_regs {} {
    global MOCK_REGS

    # Obtener lista de pares clave valor
    set lst [array get MOCK_REGS]

    # Extraer solo claves
    set keys {}
    foreach {k v} $lst {
        lappend keys $k
    }

    # Ordenar claves
    set sorted_keys [lsort -dictionary $keys]

    # Construir lista ordenada
    set result {}
    foreach k $sorted_keys {
        lappend result $k $MOCK_REGS($k)
    }

    return $result
}

# Escribir valor en registro mock
proc mock_write_reg {reg value} {
    global MOCK_REGS
    set MOCK_REGS($reg) $value
    return
}



# ----------------------------------------------------------------------
# FPGA REAL (JTAG vía vJTAG)
# ----------------------------------------------------------------------
set usbblaster_name ""
set test_device ""

# Detectar USB-Blaster
if {$USE_FPGA} {
    foreach hardware_name [get_hardware_names] {
        puts "|DEBUG| hardware_name = $hardware_name|"
        if { [string match "DE-SoC*" $hardware_name] } {
            set usbblaster_name $hardware_name
            puts "|INFO| Select JTAG chain connected to $usbblaster_name";
            foreach device_name [get_device_names -hardware_name $usbblaster_name] {
                puts "|DEBUG-OUT| device name = $device_name|"
                if { [string match "@2*" $device_name] } { # Assumes first device on the chain
                    puts "|DEBUG-IN| device name = $device_name|"
                    set test_device $device_name
                    puts "Selected device: $test_device.\n";
                }
            }
        } else {
            puts "|WARNING| USB-Blaster not found. Available hardware: $hardware_name"
        }
    }
}

proc openport {} {
    global usbblaster_name test_device
    open_device -hardware_name $usbblaster_name -device_name $test_device
}

proc closeport {} {
    catch {device_unlock}
    catch {close_device}
}

# --- FPGA write (DR1) ---
proc fpga_write_word {binary_str} {
    global VJTAG_DATA_WIDTH
    openport
    device_lock -timeout 10000
    puts "|INFO| Sending $VJTAG_DATA_WIDTH-bit Value $binary_str to FPGA (DR1)"
    device_virtual_ir_shift -instance_index 0 -ir_value 1 -no_captured_ir_value
    device_virtual_dr_shift -dr_value $binary_str -instance_index 0 -length $VJTAG_DATA_WIDTH -no_captured_dr_value
    device_virtual_ir_shift -instance_index 0 -ir_value 0 -no_captured_ir_value
    closeport
}



# --- FPGA read (DR2) ---
proc fpga_read_word {} {
    global VJTAG_DATA_WIDTH
    openport
    device_lock -timeout 10000
    puts "|INFO| Reading $VJTAG_DATA_WIDTH-bit Value from FPGA (DR2)"
    device_virtual_ir_shift -instance_index 0 -ir_value 2 -no_captured_ir_value
    set hex_val [device_virtual_dr_shift -instance_index 0 -length $VJTAG_DATA_WIDTH -value_in_hex]
    device_virtual_ir_shift -instance_index 0 -ir_value 0 -no_captured_ir_value
    closeport
    puts "|INFO| Read $VJTAG_DATA_WIDTH-bit Hex Value '$hex_val' from FPGA"
    return $hex_val
}

# ----------------------------------------------------------------------
# COMANDOS DEL SERVIDOR
# ----------------------------------------------------------------------

proc handle_command {line} {
    global USE_FPGA WIDTH HEIGHT SCALE
    global VJTAG_DATA_WIDTH

    set parts [split $line]
    set cmd [lindex $parts 0]

    switch $cmd {

        default {

            if {$USE_FPGA}{
                fpga_write_word $line
            }

            return "Comando recibido: $cmd"
        }
    }
}

# ----------------------------------------------------------------------
# TCP SERVER
# ----------------------------------------------------------------------

proc accept {sock addr port} {
    fconfigure $sock -translation binary -buffering none
    puts "Cliente conectado desde $addr:$port"
    fileevent $sock readable [list handle $sock]
}


proc handle {sock} {
    if {[eof $sock]} {
        close $sock
        return
    }

    gets $sock line
    puts "|DEBUG| Received: $line|"
    if {$line eq "" } {
        # Ignorar líneas vacías
        return
    }

    set response [handle_command $line]
    puts $sock $response
    flush $sock
}

set server [socket -server accept $SERVER_PORT]
puts "Servidor TCL escuchando en puerto $SERVER_PORT"
vwait forever
