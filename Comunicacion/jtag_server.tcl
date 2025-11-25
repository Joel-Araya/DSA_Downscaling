# ======================================================================
#  SERVIDOR TCL COMPLETO PARA PC <-> FPGA (vJTAG)
#  MODO MOCK (sin FPGA) y MODO HARDWARE (con FPGA real)
# ======================================================================

package require Tcl 8.6
package require base64

# ----------------------------------------------------------------------
# CONFIGURACIÓN
# ----------------------------------------------------------------------
set USE_FPGA 1        ;# 0 = Mock, 1 = FPGA real
set SERVER_PORT 9999  ;# Puerto para el cliente Python
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
        if { [string match "USB-Blaster*" $hardware_name] } {
            set usbblaster_name $hardware_name
            foreach device_name [get_device_names -hardware_name $usbblaster_name] {
                if { [string match "@1*" $device_name] } {
                    set test_device $device_name
                }
            }
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
    device_virtual_ir_shift -instance_index 0 -ir_value 2 -no_captured_ir_value
    set hex_val [device_virtual_dr_shift -instance_index 0 -length $VJTAG_DATA_WIDTH -value_in_hex]
    device_virtual_ir_shift -instance_index 0 -ir_value 0 -no_captured_ir_value
    closeport
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

        SET_PARAMS {
            set WIDTH  [lindex $parts 1]
            set HEIGHT [lindex $parts 2]
            set SCALE  [lindex $parts 3]
            return "OK PARAMS Width $WIDTH, Height $HEIGHT, Scale $SCALE"
        }

        READ_PARAMS {
            return "PARAMS WIDTH $WIDTH, HEIGHT $HEIGHT, SCALE $SCALE"
        }

        SET_SCALE {
            set SCALE [lindex $parts 1]
            return "OK SCALE $SCALE"
        }

        

        WRITE_PIXELS {
            # parts: WRITE_PIXELS <chunk_index> <base64_block>
            set chunk [lindex $parts 1]
            set b64 [lindex $parts 2]
            set bin [binary decode base64 $b64]

            if {!$USE_FPGA} {
                if {$chunk == 0} {
                    # Primer chunk: reiniciar buffer mock
                    set ::MOCK_MEMORY ""
                }

                mock_write_pixels $bin
                #append ::MOCK_MEMORY $bin

            } else {
                if {$chunk == 0} {
                    # Implementar alguna inicialización si es necesario
                }
                # Enviar cada byte como palabra:
                foreach c [split $bin ""] {
                    set byte [scan $c %c]
                    # Convertir byte → binario de N bits
                    set binstr [format "%0*b" $VJTAG_DATA_WIDTH $byte]
                    # fpga_write_word $binstr
                }
            }
            return "OK PIXELS WRITED"
        }

        START {
            if {!$USE_FPGA} {
                mock_start
                return "OK START(MOCK)"
            } else {
                # Aquí llamas a señal de inicio real (si existe)
                return "OK START(FPGA)"
            }
        }

        READ_OUTPUT {
            if {!$USE_FPGA} {
                set out [mock_read_output]
                set b64 [binary encode base64 $out]
                return "DATA $b64"
            } else {
                # Leer palabra por palabra
                set total_bytes [expr {$WIDTH * $HEIGHT}]
                set buf ""

                for {set i 0} {$i < $total_bytes} {incr i} {
                    set hex [fpga_read_word]
                    scan $hex %02x byte_val
                    append buf [binary format c $byte_val]
                }

                set b64 [binary encode base64 $buf]
                return "DATA $b64"
            }
        }

        STEP { 
            #STEP avanza 1 ciclo, STEP <num_cycles> avanza N ciclos
            set num_cycles 1
            if {[llength $parts] > 1} {
                set num_cycles [lindex $parts 1]
            }

            if {!$USE_FPGA} {
                # En modo mock no hay ciclos reales, solo simular
                return "OK STEP MOCK $num_cycles cycles"
            } else {
                # Aquí implementarías el avance de ciclos en FPGA si es posible
                return "OK STEP FPGA $num_cycles cycles"
            }
        }

        READ_REG {
            set reg [lindex $parts 1]
            if {!$USE_FPGA} {
                set value [mock_read_reg $reg]
            } else {
                set value [fpga_read_word]
            }
            return "REG $reg $value"
        }

        READ_REGS {
            if {!$USE_FPGA} {
                set regs [mock_read_regs]
            } else {
                # Aquí podrías implementar la lectura de múltiples registros en FPGA
                set regs ""
            }
            return "REGS $regs"
        }

        WRITE_REG {
            # parts: WRITE_REG <reg> <value>
            set reg [lindex $parts 1]
            set value [lindex $parts 2]

            if {!$USE_FPGA} {
                mock_write_reg $reg $value
            } else {
                # Aquí se definiría cómo se escribe un registro real por vJTAG
                # Por ejemplo se podría enviar un IR específico + DR con el valor
                set binstr [format "%0*b" $VJTAG_DATA_WIDTH $value]
                fpga_write_word $binstr
            }

            return "OK WRITE_REG $reg"
        }

        HELP {
            return "Commands: SET_PARAMS, READ_PARAMS, SET_SCALE, WRITE_PIXELS, START, READ_OUTPUT, STEP, READ_REG, READ_REGS, WRITE_REG"
        }


        default {
            return "ERR Unknown"
        }
    }
}

# ----------------------------------------------------------------------
# TCP SERVER
# ----------------------------------------------------------------------

proc accept {sock addr port} {
    fconfigure $sock -buffering line
    puts "Cliente conectado desde $addr:$port"
    fileevent $sock readable [list handle $sock]
}

proc handle {sock} {
    if {[eof $sock]} {
        close $sock
        return
    }

    gets $sock line
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
