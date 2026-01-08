<p align="center">
  <img src="/images/logo.png" width="200">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/SystemVerilog-RTL-blue">
  <img src="https://img.shields.io/badge/C++-Testbench-orange">
  <img src="https://img.shields.io/badge/Python-cocotb-green">
  <img src="https://img.shields.io/badge/Python-pyuvm-purple">
  <img src="https://img.shields.io/badge/Simulator-Verilator-red">
</p>

<p align="center">
  <b>Exploring Verilator as a Simulation Engine Across Verification Flows</b><br>
  SystemVerilog • C++ • cocotb • pyuvm
</p>


<!-- # Verilator Examples: Multiple Testbench Flows for RTL Verification -->

This repository demonstrates how **Verilator** can be used as a **common simulation engine** across multiple verification styles and languages.

Using two simple designs—a **2×1 multiplexer** and a **4-bit counter**—we show how the *same RTL* can be verified using:

* SystemVerilog testbenches
* Native C++ testbenches
* Python-based verification with **cocotb**
* UVM-style verification in Python using **pyuvm**

The goal is not to compare languages stylistically, but to **illustrate how Verilator handles each flow internally** and where the verification logic actually runs.

---

## Repository Structure

```text
Verilator_examples/
├── Makefile
├── mux_2x1/
│   ├── rtl/
│   │   └── mux_2x1.sv
│   └── tb/
│       ├── tb_mux_cpp.cpp
│       ├── tb_mux_sv.sv
│       ├── tb_mux_py.py
│       └── tb_mux_pyuvm.py
│
└── counter_4bit/
    ├── rtl/
    │   └── counter.sv
    └── tb/
        ├── tb_counter_cpp.cpp
        ├── tb_counter_sv.sv
        ├── tb_counter_py.py
        └── tb_counter_pyuvm.py
```

Each design supports **four verification flows** with identical functional intent.

---

## Verification Flows Overview

### 1. SystemVerilog Testbench (SV)

* Lightweight SV testbench compiled by Verilator
* RTL + TB are converted to C++ and built into a native executable
* Suitable for simple, procedural testbenches

<!-- > **Diagram placeholder** -->
![SV Flow](/Verilator_examples/images/LP1_basic_SV.png)

---

### 2. Native C++ Testbench

* RTL is translated into a C++ class (e.g., `Vmux_2x1`, `Vcounter`)
* User-written `main()` drives inputs and calls `eval()`
* The compiled binary is the simulator

This is one of the most Verilator-native and performance-oriented flows.

<!-- > **Diagram placeholder** -->
![C++ Flow](/Verilator_examples/images/LP1_c++.png)

---

### 3. Python Testbench with cocotb

* Verification logic runs **outside** the simulator in Python
* Verilator executes the RTL as C++
* cocotb interacts with the DUT through VPI callbacks
* Enables rapid scripting, assertions, and reuse

<!-- > **Diagram placeholder** -->
![Python Flow](/Verilator_examples/images/LP1_py.png)

---

### 4. Python UVM-style Testbench with pyuvm

* Builds on cocotb
* Implements UVM-like concepts (env, monitor, scoreboard, sequences) in Python
* Verification structure scales without relying on SystemVerilog classes
* Demonstrates how UVM-style methodology can coexist with Verilator

<!-- > **Diagram placeholder** -->
![PyUVM Flow](/Verilator_examples/images/LP1_pyuvm.png)

---

## Build & Run Instructions

### Prerequisites

#### macOS

```bash
brew install verilator python@3.13
```

#### Ubuntu / Debian

```bash
sudo apt update
sudo apt install -y verilator python3 python3-venv build-essential
```

---

### Python Environment (required for cocotb / pyuvm)

From the repository root:

```bash
make venv
source .venv/bin/activate
```

This installs:

* cocotb
* pyuvm
* required Python build tools

---

### Running Examples

The Makefile is **shared across all designs**.

#### MUX (2×1)

```bash
make run PROJ=mux_2x1 FLOW=cpp
make run PROJ=mux_2x1 FLOW=sv
make run PROJ=mux_2x1 FLOW=cocotb
make run PROJ=mux_2x1 FLOW=pyuvm
```

#### Counter (4-bit)

```bash
make run PROJ=counter_4bit FLOW=cpp
make run PROJ=counter_4bit FLOW=sv
make run PROJ=counter_4bit FLOW=cocotb
make run PROJ=counter_4bit FLOW=pyuvm
```

To clean build artifacts:

```bash
make clean PROJ=mux_2x1
make clean PROJ=counter_4bit
```

---

## Key Takeaways

* Verilator is not just a simulator—it is a **compiler-driven execution model**
* Verification logic can live in:

  * SystemVerilog
  * C++
  * Python (via VPI)
* cocotb and pyuvm enable **modern, scriptable verification** while keeping Verilator as the simulation engine
* The same RTL can be reused across all flows with minimal changes

---

## References

* Verilator Documentation:
  [https://verilator.org/guide/latest/](https://verilator.org/guide/latest/)
* cocotb Documentation:
  [https://docs.cocotb.org/](https://docs.cocotb.org/)
* pyuvm Documentation:
  [https://pyuvm.readthedocs.io/](https://pyuvm.readthedocs.io/)

