# jtag_server.tcl - Accepts Data Width as a command-line argument
##############################################################################################
############################# Basic vJTAG Interface ##########################################
##############################################################################################

# --- START: Parameter for Data Width from Command Line ---
set VJTAG_DATA_WIDTH 32 ; # Default value
if {$argc > 0} {
    set arg1 [lindex $argv 0]
    if {[string is integer -strict $arg1] && $arg1 > 0} {
        set VJTAG_DATA_WIDTH $arg1
        puts "|INFO| VJTAG_DATA_WIDTH set from command line to $VJTAG_DATA_WIDTH bits."
    } else {
        puts "|WARNING| Invalid command-line argument for data width: '$arg1'. Using default $VJTAG_DATA_WIDTH bits."
    }
} else {
    puts "|INFO| No data width provided on command line, defaulting to $VJTAG_DATA_WIDTH bits."
}
# --- END: Parameter for Data Width ---

global usbblaster_name
global test_device

# ... (rest of your existing usbblaster and device detection logic remains the same) ...
# List all available programming hardwares, and select the USBBlaster.
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

proc openport {} {
    global usbblaster_name
    global test_device
    open_device -hardware_name $usbblaster_name -device_name $test_device
}

proc closeport { } {
    catch {device_unlock}
    catch {close_device}
}

# Procedure to write data to the FPGA (DR1)
proc transmit_to_fpga {send_data_binary_str} {
    global VJTAG_DATA_WIDTH # Access the global variable
    openport
    device_lock -timeout 10000
    puts "|INFO| Sending $VJTAG_DATA_WIDTH-bit Value $send_data_binary_str to FPGA (DR1)"
    device_virtual_ir_shift -instance_index 0 -ir_value 1 -no_captured_ir_value
    device_virtual_dr_shift -dr_value $send_data_binary_str -instance_index 0 -length $VJTAG_DATA_WIDTH -no_captured_dr_value
    device_virtual_ir_shift -instance_index 0 -ir_value 0 -no_captured_ir_value
    closeport
}

# Procedure to read data from the FPGA (DR2)
proc read_from_fpga {} {
    global VJTAG_DATA_WIDTH # Access the global variable
    openport
    device_lock -timeout 10000
    puts "|INFO| Reading $VJTAG_DATA_WIDTH-bit Value from FPGA (DR2)"
    device_virtual_ir_shift -instance_index 0 -ir_value 2 -no_captured_ir_value
    set tdo_hex_value [device_virtual_dr_shift -instance_index 0 -length $VJTAG_DATA_WIDTH -value_in_hex]
    device_virtual_ir_shift -instance_index 0 -ir_value 0 -no_captured_ir_value
    closeport
    puts "|INFO| Read $VJTAG_DATA_WIDTH-bit Hex Value '$tdo_hex_value' from FPGA"
    return "$tdo_hex_value\n"
}


##############################################################################################
################################# TCP/IP Server ##############################################
##############################################################################################

proc Start_Server {port_num} { # Changed parameter name for clarity
    set s [socket -server ConnAccept $port_num]
    puts "Started Socket Server on port - $port_num"
    vwait forever
}

proc ConnAccept {sock addr client_port} { # Changed parameter name
    global conn
    puts "Accept $sock from $addr port $client_port"
    set conn(addr,$sock) [list $addr $client_port]
    fconfigure $sock -buffering line
    fileevent $sock readable [list IncomingData $sock]
}

proc IncomingData {sock} {
    global conn
    global VJTAG_DATA_WIDTH # Access the global variable
    if {[eof $sock] || [catch {gets $sock line}]} {
        close $sock
        puts "Close $conn(addr,$sock)"
        unset conn(addr,$sock)
    } else {
        set trimmed_line [string trim $line]
        puts "|DEBUG| Received command: '$trimmed_line'"
        if {$trimmed_line eq "READ"} {
            set response [read_from_fpga]
            puts -nonewline $sock $response
            flush $sock
            puts "|DEBUG| Sent read response: [string trim $response]"
        } elseif {[string length $trimmed_line] == $VJTAG_DATA_WIDTH && [regexp "^\[01\]\{$VJTAG_DATA_WIDTH\}$" $trimmed_line]} {
            transmit_to_fpga $trimmed_line
            puts "|DEBUG| Executed write command for $trimmed_line"
        } else {
            puts "|WARNING| Received unknown command or invalid data format: '$trimmed_line'. Expected 'READ' or a $VJTAG_DATA_WIDTH-bit binary string."
        }
    }
}

# Define the server port (can also be a command-line argument if needed)
set server_port_number 2540
Start_Server $server_port_number
##############################################################################################
