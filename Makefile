# ============================================================
# Verilator Examples - Multi-project, multi-TB Makefile
#
# Usage examples:
#   make run PROJ=mux_2x1     FLOW=cpp
#   make run PROJ=mux_2x1     FLOW=sv
#   make run PROJ=mux_2x1     FLOW=cocotb
#   make run PROJ=mux_2x1     FLOW=pyuvm
#
#   make run PROJ=counter_4bit FLOW=cpp
#   make clean PROJ=mux_2x1
#
# Notes:
# - cocotb/pyuvm flows require a Python venv with cocotb installed.
# ============================================================

SHELL := /bin/bash

# -------- User-selectable knobs --------
PROJ ?= mux_2x1               # mux_2x1 | counter_4bit
FLOW ?= cpp                   # cpp | sv | cocotb | pyuvm
WAVES ?= 1                    # 1 enables VCD (where applicable)
TRACE ?= 0                    # 1 enables Verilator tracing
OPT ?= -O2                    # C++ optimization for native sim
JOBS ?= 0                     # 0 = let verilator decide, else -j N

# Python venv (recommended)
VENV ?= .venv
PYTHON_BIN ?= $(CURDIR)/$(VENV)/bin/python
COCOTB_CONFIG ?= $(CURDIR)/$(VENV)/bin/cocotb-config

# -------- Project mapping --------
# Assumes structure:
#   mux_2x1/rtl/mux_2x1.sv
#   mux_2x1/tb/tb_mux_cpp.cpp, tb_mux_sv.sv, tb_mux_py.py, tb_mux_pyuvm.py
#   counter_4bit/rtl/counter.sv
#   counter_4bit/tb/tb_counter_cpp.cpp, tb_counter_sv.sv, tb_counter_py.py, tb_counter_pyuvm.py

PROJ_DIR := $(CURDIR)/$(PROJ)
RTL_DIR  := $(PROJ_DIR)/rtl
TB_DIR   := $(PROJ_DIR)/tb
BUILD_DIR:= $(PROJ_DIR)/build/$(FLOW)

# -------- Verilator common flags --------
VERILATOR ?= verilator

VFLAGS_COMMON := -Wall --cc --Mdir $(BUILD_DIR) --top-module $(TOPLEVEL) \
                 --timescale 1ns/1ps

# Trace (VCD) options for Verilator (used mainly for C++/SV flows)
ifeq ($(TRACE),1)
  VFLAGS_COMMON += --trace
endif

# Parallel build
ifneq ($(JOBS),0)
  VFLAGS_COMMON += -j $(JOBS)
endif

# -------- Per-project config --------
# Set TOPLEVEL + RTL + TB file names based on PROJ
ifeq ($(PROJ),mux_2x1)
  TOPLEVEL := mux_2x1
  RTL      := $(RTL_DIR)/mux_2x1.sv
  TB_CPP   := $(TB_DIR)/tb_mux_cpp.cpp
  TB_SV    := $(TB_DIR)/tb_mux_sv.sv
  MOD_COCO := tb_mux_py
  MOD_PYUVM:= tb_mux_pyuvm
else ifeq ($(PROJ),counter_4bit)
  TOPLEVEL := counter
  RTL      := $(RTL_DIR)/counter.sv
  TB_CPP   := $(TB_DIR)/tb_counter_cpp.cpp
  TB_SV    := $(TB_DIR)/tb_counter_sv.sv
  MOD_COCO := tb_counter_py
  MOD_PYUVM:= tb_counter_pyuvm
else
  $(error Unknown PROJ='$(PROJ)'. Use PROJ=mux_2x1 or PROJ=counter_4bit)
endif

# -------- Targets --------
.PHONY: help run build clean distclean info check_venv venv

help:
	@echo ""
	@echo "Targets:"
	@echo "  make run   PROJ=<mux_2x1|counter_4bit> FLOW=<cpp|sv|cocotb|pyuvm> [WAVES=1] [TRACE=0|1]"
	@echo "  make build PROJ=... FLOW=..."
	@echo "  make clean PROJ=... [FLOW=...]"
	@echo "  make venv  (create venv + install cocotb/pyuvm)"
	@echo ""
	@echo "Examples:"
	@echo "  make run PROJ=mux_2x1      FLOW=cpp"
	@echo "  make run PROJ=mux_2x1      FLOW=cocotb"
	@echo "  make run PROJ=counter_4bit FLOW=pyuvm"
	@echo ""

info:
	@echo "PROJ      = $(PROJ)"
	@echo "FLOW      = $(FLOW)"
	@echo "TOPLEVEL  = $(TOPLEVEL)"
	@echo "RTL       = $(RTL)"
	@echo "TB_CPP    = $(TB_CPP)"
	@echo "TB_SV     = $(TB_SV)"
	@echo "BUILD_DIR = $(BUILD_DIR)"
	@echo "PYTHON    = $(PYTHON_BIN)"
	@echo "COCOTB_CONFIG = $(COCOTB_CONFIG)"

run: build
ifeq ($(FLOW),cpp)
	@echo ">> Running C++ TB..."
	@$(BUILD_DIR)/V$(TOPLEVEL)
else ifeq ($(FLOW),sv)
	@echo ">> Running SV TB (compiled by Verilator)..."
	@$(BUILD_DIR)/Vtb_top
else ifeq ($(FLOW),cocotb)
	@echo ">> Running cocotb TB..."
	@$(MAKE) -C $(BUILD_DIR) -f Vtop.mk \
		MODULE=$(MOD_COCO) TOPLEVEL=$(TOPLEVEL) TOPLEVEL_LANG=verilog \
		PYTHON_BIN=$(PYTHON_BIN) \
		PYTHONPATH=$(TB_DIR) \
		sim
else ifeq ($(FLOW),pyuvm)
	@echo ">> Running pyuvm TB..."
	@$(MAKE) -C $(BUILD_DIR) -f Vtop.mk \
		MODULE=$(MOD_PYUVM) TOPLEVEL=$(TOPLEVEL) TOPLEVEL_LANG=verilog \
		PYTHON_BIN=$(PYTHON_BIN) \
		PYTHONPATH=$(TB_DIR) \
		sim
else
	$(error Unknown FLOW='$(FLOW)'. Use FLOW=cpp|sv|cocotb|pyuvm)
endif

build:
	@mkdir -p $(BUILD_DIR)
ifeq ($(FLOW),cpp)
	@echo ">> Building (cpp flow)..."
	@$(VERILATOR) $(VFLAGS_COMMON) --exe $(TB_CPP) $(RTL) \
		-CFLAGS "$(OPT)" -LDFLAGS ""
	@$(MAKE) -C $(BUILD_DIR) -f V$(TOPLEVEL).mk -j
else ifeq ($(FLOW),sv)
	@echo ">> Building (sv flow)..."
	@$(VERILATOR) -Wall --cc --Mdir $(BUILD_DIR) \
		--top-module tb_top --exe $(TB_SV) $(RTL) \
		-CFLAGS "$(OPT)" -LDFLAGS ""
	@$(MAKE) -C $(BUILD_DIR) -f Vtb_top.mk -j
else ifeq ($(FLOW),cocotb)
	@$(MAKE) check_venv
	@echo ">> Building (cocotb flow)..."
	@PYTHON_BIN=$(PYTHON_BIN) \
	PYTHONPATH=$(TB_DIR) \
	MODULE=$(MOD_COCO) \
	TOPLEVEL=$(TOPLEVEL) TOPLEVEL_LANG=verilog \
	VERILOG_SOURCES=$(RTL) \
	SIM=verilator \
	$(MAKE) -f $$($(COCOTB_CONFIG) --makefiles)/Makefile.sim \
		BUILD_DIR=$(BUILD_DIR) \
		SIM_BUILD=$(BUILD_DIR) \
		TOPLEVEL=$(TOPLEVEL) \
		TOPLEVEL_LANG=verilog \
		VERILOG_SOURCES="$(RTL)" \
		VERILATOR=$(VERILATOR) \
		EXTRA_ARGS="$(VFLAGS_COMMON)" \
		sim
else ifeq ($(FLOW),pyuvm)
	@$(MAKE) check_venv
	@echo ">> Building (pyuvm flow)..."
	@PYTHON_BIN=$(PYTHON_BIN) \
	PYTHONPATH=$(TB_DIR) \
	MODULE=$(MOD_PYUVM) \
	TOPLEVEL=$(TOPLEVEL) TOPLEVEL_LANG=verilog \
	VERILOG_SOURCES=$(RTL) \
	SIM=verilator \
	$(MAKE) -f $$($(COCOTB_CONFIG) --makefiles)/Makefile.sim \
		BUILD_DIR=$(BUILD_DIR) \
		SIM_BUILD=$(BUILD_DIR) \
		TOPLEVEL=$(TOPLEVEL) \
		TOPLEVEL_LANG=verilog \
		VERILOG_SOURCES="$(RTL)" \
		VERILATOR=$(VERILATOR) \
		EXTRA_ARGS="$(VFLAGS_COMMON)" \
		sim
else
	$(error Unknown FLOW='$(FLOW)'. Use FLOW=cpp|sv|cocotb|pyuvm)
endif

clean:
ifeq ($(FLOW),)
	@echo ">> Cleaning all flows for $(PROJ)..."
	@rm -rf $(PROJ_DIR)/build
else
	@echo ">> Cleaning $(PROJ) flow $(FLOW)..."
	@rm -rf $(BUILD_DIR)
endif

distclean:
	@echo ">> Removing all build artifacts and venv..."
	@rm -rf mux_2x1/build counter_4bit/build $(VENV)

check_venv:
	@if [ ! -x "$(PYTHON_BIN)" ]; then \
		echo "ERROR: Python venv not found at $(PYTHON_BIN)"; \
		echo "Run: make venv"; \
		exit 1; \
	fi
	@if [ ! -x "$(COCOTB_CONFIG)" ]; then \
		echo "ERROR: cocotb-config not found at $(COCOTB_CONFIG)"; \
		echo "Activate venv and install cocotb, or run: make venv"; \
		exit 1; \
	fi

venv:
	@echo ">> Creating venv at $(VENV) ..."
	@python3 -m venv $(VENV)
	@$(PYTHON_BIN) -m pip install -U pip setuptools wheel
	@$(PYTHON_BIN) -m pip install cocotb pyuvm
	@echo ">> Done. Activate with: source $(VENV)/bin/activate"
