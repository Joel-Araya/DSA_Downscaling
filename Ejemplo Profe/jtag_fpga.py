# jtag_fpga.py - Modified with verbosity control
import socket
import time
import argparse
import os 
import readline
import atexit 

# --- START: Verbosity Levels ---
VERBOSE_LEVEL_QUIET = 0
VERBOSE_LEVEL_NORMAL = 1 # Default: INFO, RESULT, WARNING, ERROR
VERBOSE_LEVEL_DEBUG = 2  # All messages including DEBUG
# --- END: Verbosity Levels ---

# These will be set in main() after parsing arguments
DATA_WIDTH = 32
MAX_VAL = (1 << DATA_WIDTH) - 1
HEX_PADDING = DATA_WIDTH // 4
VERBOSITY_LEVEL = VERBOSE_LEVEL_NORMAL # Default, will be updated by argparse

HOST = 'localhost'
PORT = 2540
SOCKET_TIMEOUT = 10.0

HISTORY_FILE = os.path.expanduser("~/.jtag_fpga_history")

def load_history():
    if hasattr(readline, "read_history_file"):
        try:
            readline.read_history_file(HISTORY_FILE)
        except FileNotFoundError:
            pass # No history file yet
        except Exception:
            pass # Other error reading history

def save_history():
    if hasattr(readline, "write_history_file"):
        try:
            readline.write_history_file(HISTORY_FILE)
        except Exception:
            pass # Error saving history

atexit.register(save_history)

# --- START: Conditional Print Function ---
def print_message(level, message):
    """Prints a message if the current verbosity level is high enough."""
    global VERBOSITY_LEVEL
    if level <= VERBOSITY_LEVEL:
        print(message)
# --- END: Conditional Print Function ---

def open_connection(host_addr, server_port):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(SOCKET_TIMEOUT)
        s.connect((host_addr, server_port))
        print_message(VERBOSE_LEVEL_NORMAL, f"|INFO| Connected to server {host_addr}:{server_port}")
        return s
    except socket.timeout:
        print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Connection to {host_addr}:{server_port} timed out.") # ERROR always prints
        return None
    except ConnectionRefusedError:
        print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Connection to {host_addr}:{server_port} refused. Is the TCL server running?")
        return None
    except Exception as e:
        print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Could not connect to server: {e}")
        return None

def write_value_to_fpga(conn, int_value_to_write):
    if conn is None:
        print_message(VERBOSE_LEVEL_QUIET, "|ERROR| No connection to server. Cannot write.")
        return
    try:
        binary_string = format(int_value_to_write, f'0{DATA_WIDTH}b')
        request = binary_string + '\n'
        print_message(VERBOSE_LEVEL_DEBUG, f"|DEBUG| Python sending {DATA_WIDTH}-bit write request: {request.strip()}")
        conn.sendall(request.encode())
        print_message(VERBOSE_LEVEL_NORMAL, f"|INFO| Write request for {DATA_WIDTH}-bit value {int_value_to_write} (0x{int_value_to_write:0{HEX_PADDING}x}) sent.")
    except socket.timeout:
        print_message(VERBOSE_LEVEL_QUIET, "|ERROR| Socket timeout during write operation.")
    except Exception as e:
        print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Failed to send data: {e}")

def read_value_from_fpga(conn):
    if conn is None:
        print_message(VERBOSE_LEVEL_QUIET, "|ERROR| No connection to server. Cannot read.")
        return None
    try:
        request = "READ\n"
        print_message(VERBOSE_LEVEL_DEBUG, f"|DEBUG| Python sending read request: {request.strip()}")
        conn.sendall(request.encode())
        
        response_bytes = b''
        conn.settimeout(SOCKET_TIMEOUT) 
        while True:
            try:
                chunk = conn.recv(1) 
                if not chunk: 
                    print_message(VERBOSE_LEVEL_QUIET, "|ERROR| Connection closed by server while waiting for read response.")
                    return None
                response_bytes += chunk
                if chunk == b'\n':
                    break
            except socket.timeout:
                print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Socket timeout while waiting for full {DATA_WIDTH}-bit read response line.")
                if response_bytes:
                    print_message(VERBOSE_LEVEL_NORMAL, "|WARNING| Partial response received before timeout.")
                    break 
                return None
        
        response_hex = response_bytes.decode().strip()
        print_message(VERBOSE_LEVEL_NORMAL, f"|INFO| Python received raw {DATA_WIDTH}-bit hex response: '{response_hex}'")
        if not response_hex:
            print_message(VERBOSE_LEVEL_QUIET, "|ERROR| Received empty or incomplete response from server.")
            return None
        try:
            int_value = int(response_hex, 16)
            return int_value
        except ValueError:
            print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Could not parse {DATA_WIDTH}-bit hex string '{response_hex}' to integer.")
            return None
    except socket.timeout: 
        print_message(VERBOSE_LEVEL_QUIET, "|ERROR| Socket timeout during sending read command.")
        return None
    except Exception as e:
        print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Failed to read data: {e}")
        return None

def parse_integer_argument(arg_str, arg_name="argument"):
    if arg_str is None:
        return None
    try:
        return int(arg_str, 0) 
    except ValueError:
        print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Invalid format for {arg_name}: '{arg_str}'. Must be an integer.")
        return None

def main_loop(conn):
    global VERBOSITY_LEVEL # Allow modification from 'verbose' command

    print_message(VERBOSE_LEVEL_NORMAL, f"\nJTAG Command Processor ({DATA_WIDTH}-bit)")
    print_message(VERBOSE_LEVEL_NORMAL, "Available commands:")
    print_message(VERBOSE_LEVEL_NORMAL, "  write <address> <value>")
    print_message(VERBOSE_LEVEL_NORMAL, "  read <address> <expected_value>")
    print_message(VERBOSE_LEVEL_NORMAL, "  verbose <quiet|normal|debug>")
    print_message(VERBOSE_LEVEL_NORMAL, "  history")
    print_message(VERBOSE_LEVEL_NORMAL, "  exit")
    print_message(VERBOSE_LEVEL_NORMAL, "Note: <address> is parsed but currently ignored by the hardware.")
    print_message(VERBOSE_LEVEL_NORMAL, f"      <value> and <expected_value> should be 0-{MAX_VAL} (or hex equivalent).")
    print_message(VERBOSE_LEVEL_NORMAL, "      Use Up/Down arrow keys for command history.")
    print_message(VERBOSE_LEVEL_NORMAL, "      Configure your terminal for scrollback.\n")

    try:
        while True:
            user_input = input(f"JTAG-{DATA_WIDTH}bit> ").strip()
            parts = user_input.split()

            if not parts:
                continue

            command = parts[0].lower()

            if command == 'exit':
                break
            elif command == 'verbose':
                if len(parts) == 2:
                    level_str = parts[1].lower()
                    if level_str == "quiet":
                        VERBOSITY_LEVEL = VERBOSE_LEVEL_QUIET
                        print_message(VERBOSE_LEVEL_QUIET, "|CONFIG| Verbosity set to QUIET.")
                    elif level_str == "normal":
                        VERBOSITY_LEVEL = VERBOSE_LEVEL_NORMAL
                        print_message(VERBOSE_LEVEL_NORMAL, "|CONFIG| Verbosity set to NORMAL.")
                    elif level_str == "debug":
                        VERBOSITY_LEVEL = VERBOSE_LEVEL_DEBUG
                        print_message(VERBOSE_LEVEL_DEBUG, "|CONFIG| Verbosity set to DEBUG.")
                    else:
                        print_message(VERBOSE_LEVEL_QUIET, "|ERROR| Unknown verbosity level. Use 'quiet', 'normal', or 'debug'.")
                else:
                    current_level_str = "UNKNOWN"
                    if VERBOSITY_LEVEL == VERBOSE_LEVEL_QUIET: current_level_str = "QUIET"
                    elif VERBOSITY_LEVEL == VERBOSE_LEVEL_NORMAL: current_level_str = "NORMAL"
                    elif VERBOSITY_LEVEL == VERBOSE_LEVEL_DEBUG: current_level_str = "DEBUG"
                    print_message(VERBOSE_LEVEL_NORMAL, f"|INFO| Current verbosity: {current_level_str}. Usage: verbose <quiet|normal|debug>")


            elif command == 'write':
                if len(parts) == 3:
                    addr_str, value_str = parts[1], parts[2]
                    address = parse_integer_argument(addr_str, "address")
                    value_to_write = parse_integer_argument(value_str, "value")

                    if address is not None and value_to_write is not None:
                        if 0 <= value_to_write <= MAX_VAL:
                            print_message(VERBOSE_LEVEL_NORMAL, f"|INFO| Executing WRITE: Address=0x{address:X} (ignored), Value={value_to_write} (0x{value_to_write:0{HEX_PADDING}x})")
                            write_value_to_fpga(conn, value_to_write)
                        else:
                            print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Value to write ({value_to_write}) out of {DATA_WIDTH}-bit range (0-{MAX_VAL}).")
                else:
                    print_message(VERBOSE_LEVEL_QUIET, "|ERROR| Usage: write <address> <value>")
            
            elif command == 'read':
                if len(parts) == 3:
                    addr_str, expected_value_str = parts[1], parts[2]
                    address = parse_integer_argument(addr_str, "address")
                    expected_value = parse_integer_argument(expected_value_str, "expected_value")

                    if address is not None and expected_value is not None:
                        if 0 <= expected_value <= MAX_VAL:
                            print_message(VERBOSE_LEVEL_NORMAL, f"|INFO| Executing READ: Address=0x{address:X} (ignored), Expecting=0x{expected_value:0{HEX_PADDING}x}")
                            actual_value = read_value_from_fpga(conn)
                            if actual_value is not None:
                                print_message(VERBOSE_LEVEL_NORMAL, f"|RESULT| Value actually read from FPGA: {actual_value} (0x{actual_value:0{HEX_PADDING}x})")
                                if actual_value == expected_value:
                                    print_message(VERBOSE_LEVEL_NORMAL, "|RESULT| MATCH: Read value matches expected value.")
                                else:
                                    print_message(VERBOSE_LEVEL_NORMAL, f"|RESULT| MISMATCH: Expected 0x{expected_value:0{HEX_PADDING}x}, Got 0x{actual_value:0{HEX_PADDING}x}.")
                            else:
                                print_message(VERBOSE_LEVEL_NORMAL, "|RESULT| Failed to get actual value from FPGA.")
                        else:
                            print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Expected value ({expected_value}) out of {DATA_WIDTH}-bit range (0-{MAX_VAL}).")
                else:
                    print_message(VERBOSE_LEVEL_QUIET, "|ERROR| Usage: read <address> <expected_value>")
            elif command == 'history':
                if hasattr(readline, "get_current_history_length"):
                    print_message(VERBOSE_LEVEL_NORMAL, "Command History:")
                    for i in range(1, readline.get_current_history_length() + 1):
                        item = readline.get_history_item(i)
                        if item: # Ensure item is not None
                           print_message(VERBOSE_LEVEL_NORMAL, f"  {i}: {item}")
                else:
                    print_message(VERBOSE_LEVEL_NORMAL, "|INFO| Readline history not fully available.")
            else:
                print_message(VERBOSE_LEVEL_QUIET, f"|ERROR| Unknown command: '{command}'. Type 'exit' to quit.")
            
            if command != 'verbose': # Avoid double separator after verbose command
                print_message(VERBOSE_LEVEL_NORMAL, "-" * 40) 
    finally:
        if conn:
            conn.close()
            print_message(VERBOSE_LEVEL_NORMAL, "|INFO| Connection closed.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=f"JTAG Client for FPGA communication.")
    parser.add_argument(
        "-dw", "--data_width", 
        type=int, 
        default=32, 
        choices=[8, 16, 32, 64],
        help="Specify the data width in bits for JTAG operations (default: 32)."
    )
    # Add verbosity arguments
    parser.add_argument(
        "-q", "--quiet",
        action="store_const", const=VERBOSE_LEVEL_QUIET, dest="verbosity",
        help="Set verbosity to quiet (only errors)."
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_const", const=VERBOSE_LEVEL_DEBUG, dest="verbosity",
        help="Set verbosity to debug (all messages)."
    )
    parser.set_defaults(verbosity=VERBOSE_LEVEL_NORMAL) # Default if no -q or -v

    args = parser.parse_args()

    DATA_WIDTH = args.data_width
    VERBOSITY_LEVEL = args.verbosity # Set global verbosity from parsed args
    MAX_VAL = (1 << DATA_WIDTH) - 1
    HEX_PADDING = DATA_WIDTH // 4
    
    print_message(VERBOSE_LEVEL_NORMAL, f"|CONFIG| Script configured for {DATA_WIDTH}-bit data width.")
    verbosity_str_map = {VERBOSE_LEVEL_QUIET: "QUIET", VERBOSE_LEVEL_NORMAL: "NORMAL", VERBOSE_LEVEL_DEBUG: "DEBUG"}
    print_message(VERBOSE_LEVEL_NORMAL, f"|CONFIG| Initial verbosity level: {verbosity_str_map.get(VERBOSITY_LEVEL, 'UNKNOWN')}")

    if os.name != 'nt': # readline typically works out-of-box on non-Windows
        print_message(VERBOSE_LEVEL_DEBUG, "|DEBUG| Attempting to load readline history.")
        load_history()
    else:
        print_message(VERBOSE_LEVEL_NORMAL, "|INFO| For command history on Windows, try installing 'pyreadline3' (`pip install pyreadline3`).")
    print_message(VERBOSE_LEVEL_NORMAL, "|INFO| For scrollback, configure your terminal's Screen Buffer Size (e.g., Properties > Layout > Height).")


    conn = open_connection(HOST, PORT)
    if conn is None:
        print_message(VERBOSE_LEVEL_QUIET, "|FATAL| Exiting due to connection failure.")
        exit(1) 
    
    main_loop(conn)
