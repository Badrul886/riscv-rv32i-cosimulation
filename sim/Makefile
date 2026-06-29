# Use Verilator for high-speed processor simulation
SIM ?= verilator
TOPLEVEL_LANG ?= verilog

# Path to the Verilog source file in the rtl directory
VERILOG_SOURCES += $(PWD)/../rtl/mini_riscv.sv

# The name of the top-level Verilog module
TOPLEVEL = mini_riscv

# Tell cocotb to look inside the tb/ folder for Python modules
export PYTHONPATH := $(PWD)/../tb:$(PYTHONPATH)
MODULE = test_mini_riscv

# Tell Verilator to generate waveforms
EXTRA_ARGS += --trace --trace-fst --trace-structs

# Include Cocotb's standard simulation rules
include $(shell cocotb-config --makefiles)/Makefile.sim