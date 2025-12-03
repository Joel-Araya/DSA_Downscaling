# Makefile for DSA_Downscaling project
# Designed for Windows PowerShell

# Force PowerShell as shell
SHELL := powershell.exe
.SHELLFLAGS := -NoProfile -Command

# Variables
QUARTUS_STP = C:\intelFPGA_lite\22.1std\quartus\bin64\quartus_stp.exe
TCL_SERVER = .\Ejemplo Profe\jtag_server.tcl
PYTHON_CLIENT = .\Ejemplo Profe\jtag_fpga.py
VENV_DIR = venv
PYTHON = python3

# Server command - Run JTAG server
server_ie:
	& "$(QUARTUS_STP)" -t "$(TCL_SERVER)"

# Client command - Run Python JTAG client (uses venv if available)
client_ie:
	if (Test-Path .\$(VENV_DIR)\Scripts\python.exe) { .\$(VENV_DIR)\Scripts\python.exe "$(PYTHON_CLIENT)" } else { $(PYTHON) "$(PYTHON_CLIENT)" }

# Create virtual environment and install dependencies
venv:
	$(PYTHON) -m venv $(VENV_DIR); .\$(VENV_DIR)\Scripts\python.exe -m pip install --upgrade pip; .\$(VENV_DIR)\Scripts\python.exe -m pip install pyreadline3
	@echo "Virtual environment created in $(VENV_DIR)"
	@echo "Dependencies installed: pyreadline3"
	@echo "To activate manually, run: .\$(VENV_DIR)\Scripts\Activate.ps1"
	@echo "Or use venv python directly: .\$(VENV_DIR)\Scripts\python.exe"

# Clean virtual environment
clean_venv:
	powershell -Command "if (Test-Path $(VENV_DIR)) { Remove-Item -Recurse -Force $(VENV_DIR) }"

# Help command
help:
	@echo "Available commands:"
	@echo "  make server_ie       - Start JTAG server"
	@echo "  make client_ie       - Start JTAG Python client (system Python)"
	@echo "  make client_ie_venv  - Start JTAG Python client (venv Python)"
	@echo "  make venv            - Create Python virtual environment"
	@echo "  make clean_venv      - Remove virtual environment"
	@echo "  make help            - Show this help message"

.PHONY: server_ie client_ie client_ie_venv venv clean_venv help
