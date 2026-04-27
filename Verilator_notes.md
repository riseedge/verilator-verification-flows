# Verilator 5.x Guidebook — From Design to Verification

> **Version target:** Verilator 5.x (latest devel: 5.047, April 2026)

---

## Table of Contents

1. [What Verilator Is (and Isn't)](#1-what-verilator-is-and-isnt)
2. [Installation Quick Reference](#2-installation-quick-reference)
3. [Core Workflow — From RTL to Simulation](#3-core-workflow--from-rtl-to-simulation)
4. [Design Coding Style for Verilator](#4-design-coding-style-for-verilator)
5. [Build System & Tool Flow](#5-build-system--tool-flow)
6. [Testbench & Verification (C++/SystemC/DPI)](#6-testbench--verification-csystemcdpi)
7. [Waveform Tracing](#7-waveform-tracing)
8. [Coverage](#8-coverage)
9. [Linting](#9-linting)
10. [Multithreading](#10-multithreading)
11. [Performance Tuning](#11-performance-tuning)
12. [Hierarchical Verilation](#12-hierarchical-verilation)
13. [Verilator Metacomments Cheat Sheet](#13-verilator-metacomments-cheat-sheet)
14. [Warnings & Errors Troubleshooting](#14-warnings--errors-troubleshooting)
15. [Verilator vs. Commercial Simulators — What to Expect](#15-verilator-vs-commercial-simulators--what-to-expect)
16. [Project Structure Template](#16-project-structure-template)

---

## 1. What Verilator Is (and Isn't)

| Verilator IS                                      | Verilator IS NOT                                   |
|---------------------------------------------------|-----------------------------------------------------|
| A **compiler**: Verilog/SV → optimized C++/SystemC | An event-driven simulator (no intra-cycle timing)    |
| **2-state** simulation (0/1, no X/Z propagation)  | A 4-state simulator (limited X handling)             |
| Cycle-accurate                                     | Timing-accurate (delays are scheduling hints only)   |
| 10–1000× faster than interpreted simulators        | A full IEEE 1800 implementation                      |
| Free, open-source (LGPL v3 / Artistic v2)          | A replacement for formal verification                |
| Excellent linter (`--lint-only`)                   | A synthesizer                                        |

**Key mental model:** Verilator flattens your design into a single-threaded (or multi-threaded) C++ evaluation loop. Think "software compile" not "simulation."

---

## 2. Installation Quick Reference

| Method                | Command                                                          | Notes                              |
|-----------------------|------------------------------------------------------------------|------------------------------------|
| **Ubuntu/Debian apt** | `sudo apt install verilator`                                     | Often outdated; check version      |
| **Git (recommended)** | `git clone https://github.com/verilator/verilator`               | Most flexibility; see below        |
| **Docker**            | `docker run -ti verilator/verilator:latest --version`            | Zero setup; good for CI            |
| **conda-forge**       | `conda install -c conda-forge verilator`                         | Cross-platform                     |

**Git build steps (abbreviated):**

```
cd verilator && git checkout stable
autoconf && ./configure --prefix=/opt/verilator
make -j$(nproc) && make install
export PATH=/opt/verilator/bin:$PATH
```

**Verify:** `verilator --version` → expect `Verilator 5.0xx ...`

---

## 3. Core Workflow — From RTL to Simulation

The entire Verilator flow in one picture:

```
RTL (.v/.sv)  →  verilator --cc/--sc  →  C++ model (Vxxx.h/.cpp)
                                              ↓
                                     sim_main.cpp (your TB)
                                              ↓
                                     g++/clang++ compile & link
                                              ↓
                                     ./Vxxx (native binary)
                                              ↓
                                     waveform.vcd / coverage.dat
```

**Fastest path (--binary mode, Verilator 5.x):**

```
verilator --binary -j 0 -Wall top.sv
./obj_dir/Vtop
```

`--binary` = `--main --exe --build --timing` in one flag. Generates a self-contained executable with a default `main()`.

---

## 4. Design Coding Style for Verilator

### 4.1 Golden Rules

| Rule                                   | Why                                                        |
|----------------------------------------|------------------------------------------------------------|
| Use `always_ff`, `always_comb`, `always_latch` | Required for proper scheduling; `always @*` is legacy |
| Use 2-state types (`logic`, `bit`)     | Verilator is 2-state; `reg`/`wire` work but `logic` is cleaner |
| No latches from gate primitives        | Verilator cannot model gate-level latches; use `always_latch` |
| Avoid `#delay` in synthesizable code   | Delays are ignored in `--no-timing` mode                   |
| Explicit widths everywhere             | Prevents WIDTH/WIDTHTRUNC/WIDTHEXPAND warnings             |
| One signal — one driver                | Prevents MULTIDRIVEN; split buses if needed                |
| No `initial` blocks driving logic      | Use reset instead; `initial` is for TB only                |
| Avoid tri-state / `inout` internally   | Limited support; use mux-based bidirectional                |
| `default_nettype none                  | Catches undeclared signals early                           |

### 4.2 Supported vs. Unsupported Constructs

| Supported (Verilator 5.x)              | Not Supported / Limited                                    |
|-----------------------------------------|------------------------------------------------------------|
| `always_ff`, `always_comb`, `always_latch` | UDP primitives (use `--bbox-unsup`)                     |
| `interface` / `modport`                 | `cmos`/`tran` gate primitives                              |
| `generate` / `for` / `if`              | Full 4-state X/Z propagation                               |
| `struct`, `union`, `enum`, `typedef`    | Program blocks (partial)                                   |
| `package` / `import`                    | `deassign`                                                 |
| `class` (basic OOP, constraints partial)| Encrypted IP (`.vp` files)                                 |
| `assert`, `assume`, `cover` (basic)     | Full UVM (no `uvm_pkg` out of box)                         |
| `DPI-C` import/export                   | Mixed-language (VHDL via Yosys workaround only)            |
| `$display`, `$readmemh`, `$finish`      | Analog/AMS                                                 |
| `#0` delay (5.x with `--timing`)        | `specify` blocks (timing checks)                           |

### 4.3 Coding for Synthesizability + Verilator Friendliness

**Combinational blocks — avoid self-referencing signals:**

```systemverilog
// BAD — causes UNOPTFLAT (self-loop on x)
always_comb begin
  x = {x[6:0], shift_in};
end

// GOOD — separate input and output signals
always_comb begin
  x_next = {x[6:0], shift_in};
end
```

**Use explicit bit-widths in assignments and comparisons:**

```systemverilog
// BAD — triggers WIDTHTRUNC
logic [7:0] a;
logic [3:0] b;
assign b = a;           // 8→4 bit truncation

// GOOD — explicit slice or cast
assign b = a[3:0];      // intentional truncation
```

---

## 5. Build System & Tool Flow

### 5.1 Essential Verilator Command Flags

| Flag                     | Purpose                                                    |
|--------------------------|------------------------------------------------------------|
| `--cc`                   | Generate C++ output (most common)                          |
| `--sc`                   | Generate SystemC output                                    |
| `--binary`               | All-in-one: `--main --exe --build --timing`                |
| `--exe`                  | Mark that a C++ main file will be provided                 |
| `--build`                | Auto-invoke `make` after Verilating                        |
| `-j <N>` / `-j 0`       | Parallel build (0 = use all cores)                         |
| `--timing`               | Enable delay/event timing support (default with `--binary`)|
| `--no-timing`            | Disable timing (faster compile, no delays)                 |
| `--lint-only`            | Lint only, no output generated                             |
| `-Wall`                  | Enable all warnings (recommended)                          |
| `--trace` / `--trace-fst`| Enable VCD / FST waveform tracing                         |
| `--coverage`             | Enable all coverage (line + toggle + expression)           |
| `--threads <N>`          | Multithreaded model (N threads)                            |
| `--top-module <name>`    | Specify top-level module                                   |
| `-I<dir>`                | Add include/search path                                    |
| `-f <file>`              | Read arguments from file                                   |
| `--prefix <name>`        | Set output class prefix (default: V + top module)          |
| `-CFLAGS "<flags>"`      | Pass flags to C++ compiler                                 |
| `-LDFLAGS "<flags>"`     | Pass flags to linker                                       |
| `--Mdir <dir>`           | Output directory (default: `obj_dir`)                      |
| `--bbox-unsup`           | Black-box unsupported constructs (for linting)             |
| `--bbox-sys`             | Black-box unknown system calls                             |
| `-sv`                    | Enable SystemVerilog parsing (on by default for `.sv`)     |

### 5.2 Typical Makefile Pattern

```makefile
VERILATOR  = verilator
TOP        = top
VFLAGS     = --cc --exe --build -j 0 -Wall --trace-fst
VSRC       = rtl/top.sv rtl/sub_a.sv rtl/sub_b.sv
CPPFLAGS   = -CFLAGS "-std=c++17 -O2"
TB         = tb/sim_main.cpp

.PHONY: sim lint clean

sim:
	$(VERILATOR) $(VFLAGS) $(CPPFLAGS) --top-module $(TOP) \
	  --Mdir obj_dir -o V$(TOP) $(VSRC) $(TB)
	./obj_dir/V$(TOP)

lint:
	$(VERILATOR) --lint-only -Wall --top-module $(TOP) $(VSRC)

clean:
	rm -rf obj_dir
```

### 5.3 Using `-f` Files (file lists)

```
// design.f
+incdir+rtl/include
-Irtl/lib
rtl/pkg.sv
rtl/top.sv
rtl/sub_a.sv
rtl/sub_b.sv
```

`verilator --cc -f design.f --exe tb/sim_main.cpp`

### 5.4 Verilator Configuration Files (`.vlt`)

Waiver files let you suppress warnings without touching RTL:

```
// project.vlt
`verilator_config
lint_off -rule UNUSED    -file "rtl/legacy/*.sv"
lint_off -rule UNDRIVEN  -file "rtl/ip/third_party.sv" -match "debug_*"
lint_off -rule WIDTH     -file "rtl/top.sv" -lines 42-50
```

Load with: `verilator --cc -f design.f project.vlt`

---

## 6. Testbench & Verification (C++/SystemC/DPI)

### 6.1 Minimal C++ Testbench Skeleton

```cpp
#include "Vtop.h"
#include "verilated.h"

int main(int argc, char** argv) {
    const std::unique_ptr<VerilatedContext> ctx{new VerilatedContext};
    ctx->commandArgs(argc, argv);

    const std::unique_ptr<Vtop> top{new Vtop{ctx.get(), "top"}};

    top->rst_n = 0;
    top->clk   = 0;

    while (!ctx->gotFinish() && ctx->time() < 100000) {
        ctx->timeInc(1);
        top->clk = !top->clk;  // Toggle clock

        if (ctx->time() > 10) top->rst_n = 1;  // Release reset

        top->eval();
    }

    top->final();
    return 0;
}
```

### 6.2 Key VerilatedContext / Model APIs

| API                                  | Purpose                                         |
|--------------------------------------|-------------------------------------------------|
| `ctx->time()`                        | Current simulation time                         |
| `ctx->timeInc(n)`                    | Advance time by n units                         |
| `ctx->gotFinish()`                   | True if `$finish` was called                    |
| `ctx->commandArgs(argc, argv)`       | Pass +plusargs to model                         |
| `ctx->traceEverOn(true)`             | Enable tracing globally                         |
| `ctx->coveragep()->write("cov.dat")` | Write coverage data                             |
| `top->eval()`                        | Evaluate the model (one delta cycle)            |
| `top->final()`                       | Call final blocks; must call before destruction  |
| `top->rootp->`                       | Access internal signals (if `--public`)          |

### 6.3 Driving Complex Interfaces from C++

| RTL Type          | C++ Access Type           | Notes                           |
|-------------------|---------------------------|---------------------------------|
| `logic`           | `CData` (uint8_t)        | Single bit in bit 0             |
| `logic [7:0]`     | `CData` (uint8_t)        | Up to 8 bits                    |
| `logic [15:0]`    | `SData` (uint16_t)       |                                 |
| `logic [31:0]`    | `IData` (uint32_t)       |                                 |
| `logic [63:0]`    | `QData` (uint64_t)       |                                 |
| `logic [127:0]`   | `WData*` (uint32_t[4])   | Wide data; array of 32-bit words|
| `real`            | `double`                  |                                 |
| `string`          | `std::string`             |                                 |

**Wide signal access (>64 bits):**

```cpp
// Writing a 128-bit value: top->wide_sig[0] = lo32; top->wide_sig[1] = ...; etc.
// WData is uint32_t[N], LSW first
```

### 6.4 DPI-C (Direct Programming Interface)

**RTL side:**

```systemverilog
import "DPI-C" function int c_model_predict(input int a, input int b);
export "DPI-C" function sv_get_status;

function int sv_get_status();
    return internal_status;
endfunction
```

**C++ side:**

```cpp
// Verilator auto-generates the header: #include "Vtop__Dpi.h"
extern "C" int c_model_predict(int a, int b) {
    return a + b;  // Your reference model
}
```

**Key DPI rules for Verilator:**
- DPI functions are evaluated in the calling thread (matters for `--threads`)
- Use `svBitVecVal*` for wide arguments
- `context` tasks get `svScope` for hierarchical access
- Profile DPI overhead with `--prof-exec` (shows in gantt chart)

### 6.5 SystemC Testbench (brief)

```cpp
// Compile with: verilator --sc --exe --build top.sv sc_main.cpp
#include "Vtop.h"
#include "verilated_sc.h"

int sc_main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vtop top{"top"};

    sc_clock clk{"clk", 10, SC_NS};
    sc_signal<bool> rst_n;

    top.clk(clk);
    top.rst_n(rst_n);

    rst_n = 0;
    sc_start(20, SC_NS);
    rst_n = 1;
    sc_start(1000, SC_NS);

    top.final();
    return 0;
}
```

### 6.6 Plusargs

```systemverilog
// RTL: $test$plusargs("trace"), $value$plusargs("seed=%d", seed)
```

```
# Runtime:
./obj_dir/Vtop +trace +seed=42
```

```cpp
// C++ access:
std::string val;
if (ctx->commandArgsPlusMatch("seed")) { /* found */ }
```

---

## 7. Waveform Tracing

| Option                | Format | File Size | Speed Impact | Viewer           |
|-----------------------|--------|-----------|--------------|------------------|
| `--trace`             | VCD    | Large     | ~2× slower   | GTKWave, any     |
| `--trace-fst`         | FST    | Small     | ~1.3× slower | GTKWave           |
| `--trace-vcd` (alias) | VCD    | Large     | ~2× slower   | Any VCD viewer    |

**Enabling tracing from C++:**

```cpp
#include "verilated_fst_c.h"  // or verilated_vcd_c.h

// After model creation:
ctx->traceEverOn(true);
VerilatedFstC* tfp = new VerilatedFstC;
top->trace(tfp, 99);           // 99 = trace depth
tfp->open("sim.fst");

// In sim loop after eval():
tfp->dump(ctx->time());

// At end:
tfp->close();
```

**Trace filtering (reduce file size):**

```
// trace.vlt — only trace specific signals/modules
`verilator_config
tracing_off -file "rtl/memory_model.sv"
tracing_on  -file "rtl/core.sv" -match "pc*"
```

---

## 8. Coverage

| Flag                      | Coverage Type         | Notes                          |
|---------------------------|-----------------------|--------------------------------|
| `--coverage`              | All (line+toggle+expression) | Recommended default      |
| `--coverage-line`         | Line/statement only   |                                |
| `--coverage-toggle`       | Signal toggle only    | Bit-level; >256-bit excluded   |
| `--coverage-user`         | `cover` statements    | Your custom cover points       |

**Collecting & viewing coverage:**

```
# Run simulation → produces coverage.dat
./obj_dir/Vtop +verilator+coverage+file+cov.dat

# Merge multiple runs
verilator_coverage --write merged.dat run1.dat run2.dat

# Generate annotated report
verilator_coverage --annotate ann_dir merged.dat

# View annotated source
less ann_dir/rtl/top.sv    # lines prefixed with hit counts
```

**In C++ (manual write):**

```cpp
ctx->coveragep()->write("coverage.dat");
```

---

## 9. Linting

**Basic usage:**

```
verilator --lint-only -Wall top.sv
verilator --lint-only -Wall --bbox-unsup --bbox-sys -f design.f
```

**Recommended wall flags for clean RTL:**

| Warning Category      | Flag           | What It Catches                      |
|-----------------------|----------------|--------------------------------------|
| All defaults          | `-Wall`        | Enables all style + correctness      |
| Width mismatches      | `WIDTHTRUNC`, `WIDTHEXPAND` | Implicit truncation/extension |
| Unused signals        | `UNUSED`       | Declared but not used                |
| Undriven signals      | `UNDRIVEN`     | Output/signal with no driver         |
| Combinational loops   | `UNOPTFLAT`    | Circular logic (performance killer)  |
| Missing sensitivity   | `ALWCOMBORDER` | Execution order in always_comb       |
| Case statement gaps   | `CASEINCOMPLETE`| Missing default/cases               |

**Suppression methods (in order of preference):**

1. **Fix the RTL** — always best
2. **`.vlt` waiver file** — per-file/line suppression without touching RTL
3. **Inline metacomment** — `/* verilator lint_off WIDTHTRUNC */` ... `/* verilator lint_on WIDTHTRUNC */`
4. **Command-line** — `-Wno-WIDTHTRUNC` (applies globally; avoid if possible)

---

## 10. Multithreading

**Enable:**

```
verilator --cc --threads 4 --build top.sv
```

| Flag / Variable                    | Purpose                                              |
|------------------------------------|------------------------------------------------------|
| `--threads <N>`                    | Target N simulation threads                          |
| `--threads 0`                      | Use all available cores                              |
| `--prof-exec`                      | Emit profiling data for `verilator_gantt`             |
| `--prof-pgo`                       | Generate profile-guided optimization data             |
| `VERILATOR_NUMA_STRATEGY`          | Control NUMA assignment (env variable, 5.x)          |
| `ctx->useNumaAssign(true)`         | C++ API for NUMA thread affinity                     |

**Thread-safety rules for your C++ testbench:**
- `eval()` is NOT thread-safe — call only from one thread at a time
- DPI functions execute in the calling thread
- `$display` / `$write` are serialized internally
- Use `--threads 1` during initial debug; increase after functional correctness

**PGO workflow (maximize thread utilization):**

```
# Step 1: Build with profiling
verilator --cc --threads 4 --prof-pgo --build top.sv

# Step 2: Run to collect profile
./obj_dir/Vtop +verilator+prof+exec+file+prof.dat

# Step 3: View gantt chart
verilator_gantt prof.dat > gantt.vcd   # Open in GTKWave

# Step 4: Rebuild with PGO data
verilator --cc --threads 4 --prof-pgo \
  +verilator+prof+exec+file+prof.dat --build top.sv
```

---

## 11. Performance Tuning

### 11.1 Compilation Speed

| Technique                     | Flag / Approach                                       |
|-------------------------------|-------------------------------------------------------|
| Parallel build                | `-j 0` (use all cores)                                |
| Split output files            | `--output-split <N>` (N statements per file)          |
| Reduce trace depth            | `--trace-depth <N>` (limit hierarchy depth)           |
| Disable unneeded features     | Omit `--trace` / `--coverage` for quick debug builds  |
| Precompiled model library     | `--protect-lib` for stable sub-blocks                 |

### 11.2 Simulation Speed

| Technique                         | Details                                                   |
|-----------------------------------|-----------------------------------------------------------|
| Fix UNOPTFLAT warnings            | Single biggest win; one fix reportedly gave 60% speedup   |
| Use `--threads` appropriately     | Diminishing returns past ~8 threads for most designs      |
| Compiler optimization             | `OPT_FAST="-O2 -march=native"` in make                   |
| `-Os` for large designs           | Instruction cache pressure; `-Os` can beat `-O2`          |
| Use FST not VCD                   | FST is compressed; much less I/O overhead                 |
| Trace filtering                   | Only trace signals you need (`tracing_off`/`tracing_on`)  |
| `--no-timing` if delays unused    | Disables timing scheduler overhead                        |
| Hierarchical verilation           | Split large designs into separately Verilated blocks      |
| Avoid `--public` on everything    | Prevents optimizations on exposed signals                 |
| `split_var` metacomment           | Helps Verilator split wide arrays for better scheduling   |
| Install `libjemalloc-dev`         | Verilator 5.x detects and uses jemalloc automatically     |

### 11.3 Make Variables for C++ Optimization

| Variable     | Applies To                | Recommended Value              |
|--------------|---------------------------|--------------------------------|
| `OPT_FAST`   | Hot-path code (per-cycle) | `-O2 -march=native` or `-Os`  |
| `OPT_SLOW`   | Cold-path (init/final)    | `-O0` or `-Os`                 |
| `OPT_GLOBAL`  | Runtime library           | `-O2`                          |
| `OPT`         | All compilation units     | Overrides all above            |

```
make OPT_FAST="-Os -march=native" OPT_SLOW="-O0" -f Vtop.mk
```

---

## 12. Hierarchical Verilation

For very large designs (>64 GB compile RAM), split into blocks:

```
verilator --cc --lib-create sub_block sub_block.sv
verilator --cc --exe --build top.sv -Lobj_dir_sub -lVsub_block
```

**When to use:** compile takes too long, RAM exhaustion, or stable IP blocks that rarely change.

---

## 13. Verilator Metacomments Cheat Sheet

| Metacomment                          | Placement              | Effect                                      |
|--------------------------------------|------------------------|----------------------------------------------|
| `/* verilator lint_off <MSG> */`     | Before code            | Suppress specific warning                    |
| `/* verilator lint_on <MSG> */`      | After code             | Re-enable warning                            |
| `/* verilator lint_save */`          | Start of region        | Push current lint state                      |
| `/* verilator lint_restore */`       | End of region          | Pop lint state                               |
| `/* verilator public */`             | On signal/module       | Make signal accessible from C++              |
| `/* verilator public_flat_rw */`     | On signal              | Flat, read/write C++ access                  |
| `/* verilator no_inline_module */`   | On module              | Prevent inlining (keeps hierarchy)           |
| `/* verilator no_inline_task */`     | On task/function       | Prevent task inlining                        |
| `/* verilator split_var */`          | On signal declaration  | Split variable to resolve UNOPTFLAT          |
| `/* verilator isolate_assignments */`| On signal declaration  | Isolate assignments to resolve UNOPTFLAT     |
| `/* verilator clock_enable */`       | On signal              | Hint for clock gating (pre-5.x; deprecated)  |
| `/* verilator coverage_off */`       | Before code            | Disable coverage for region                  |
| `/* verilator coverage_on */`        | After code             | Re-enable coverage                           |
| `/* verilator tracing_off */`        | On module/signal       | Exclude from tracing                         |
| `/* verilator tracing_on */`         | After region           | Re-enable tracing                            |
| `/* verilator sformat */`            | On function arg        | Mark as $sformat-style string                |

---

## 14. Warnings & Errors Troubleshooting

### 14.1 Most Common Warnings

| Warning          | What It Means                                          | Fix                                                      |
|------------------|--------------------------------------------------------|-----------------------------------------------------------|
| **WIDTHTRUNC**   | RHS wider than LHS; bits will be truncated             | Explicit slice: `b = a[3:0]`                              |
| **WIDTHEXPAND**  | RHS narrower than LHS; zero-extended                   | Explicit extend: `b = {24'b0, a}`                         |
| **UNUSED**       | Signal declared but never read                         | Remove it, or prefix with `unused_`, or `lint_off`        |
| **UNDRIVEN**     | Signal/output has no driver                            | Drive it, tie to `'0`, or mark as unused                  |
| **UNOPTFLAT**    | Circular combinational logic detected                  | Split signal with `split_var` / `isolate_assignments`, or refactor to separate input/output signals |
| **ALWCOMBORDER** | Execution order matters in `always_comb`               | Reorder assignments; put dependencies first               |
| **CASEINCOMPLETE** | `case` missing values or `default`                   | Add `default` clause                                      |
| **PINMISSING**   | Module port not connected at instantiation             | Connect it or use `.port()` for intentional no-connect    |
| **MULTIDRIVEN**  | Multiple `always` blocks drive the same signal         | Consolidate drivers or split into separate signals        |
| **INITIALDLY**   | `initial` block uses `<=` (non-blocking)               | Use `=` (blocking) in `initial` blocks                    |
| **BLKSEQ**       | `always_ff` uses `=` (blocking)                        | Use `<=` (non-blocking) in sequential blocks              |
| **ENUMVALUE**    | Enum value width mismatch                              | Match enum base width to assigned literal width           |
| **IMPLICIT**     | Implicitly declared net (no declaration found)          | Add explicit declaration; use `` `default_nettype none `` |
| **LITENDIAN**    | Little-endian range `[0:N]` used (unusual)             | Use `[N:0]` (big-endian ranges are standard)              |

### 14.2 Runtime Errors

| Error                | Cause                                                 | Fix                                                        |
|----------------------|-------------------------------------------------------|------------------------------------------------------------|
| **DIDNOTCONVERGE**   | Combinational logic doesn't settle                    | Fix UNOPTFLAT warnings; check for true circular logic      |
| **Segfault in eval** | NULL pointer / uninitialized model                    | Check model construction; ensure `ctx` is valid            |
| **`$finish` called** | RTL hit `$finish` — not an error                      | Check `ctx->gotFinish()` in sim loop                       |

### 14.3 Dealing with UNOPTFLAT (The Big One)

UNOPTFLAT is the most impactful warning. It means Verilator found a signal that feeds back to itself within combinational logic, forcing multiple evaluation passes.

**Diagnosis:**

```
verilator --cc -Wall --report-unoptflat top.sv
# Produces detailed graph of the circular path
```

**Fix strategies (in order of preference):**

1. **Refactor RTL** — separate input and output of the feedback path into distinct signals
2. **`/* verilator split_var */`** — on the offending signal declaration; Verilator splits it per-bit
3. **`/* verilator isolate_assignments */`** — isolates assignments to the signal into separate blocks
4. **Suppress** — `lint_off UNOPTFLAT` (last resort; costs simulation performance; risk of DIDNOTCONVERGE)

### 14.4 Warning Control Reference

| Command-Line                  | Effect                                                    |
|-------------------------------|-----------------------------------------------------------|
| `-Wall`                       | Enable all warnings                                       |
| `-Wno-<MSG>`                  | Disable specific warning globally                         |
| `-Werror-<MSG>`               | Promote warning to error                                  |
| `-Wno-fatal`                  | Warnings don't stop Verilator (not recommended)           |
| `--report-unoptflat`          | Detailed UNOPTFLAT diagnostics                            |

---

## 15. Verilator vs. Commercial Simulators — What to Expect

| Aspect                     | Verilator                              | Commercial (VCS/Xcelium/Questa)        |
|----------------------------|----------------------------------------|----------------------------------------|
| **Speed**                  | 10–1000× faster (cycle-based)          | Slower (event-driven) but full-featured|
| **Cost**                   | Free (LGPL/Artistic)                   | $$$ per-seat licenses                  |
| **X-propagation**          | 2-state only; no X/Z                   | Full 4-state                           |
| **UVM support**            | No built-in `uvm_pkg`                  | Full UVM                               |
| **Gate-level sim**         | Very limited                           | Full timing, SDF                       |
| **Debug**                  | GDB/waveform/printf                    | Interactive GUI debugger               |
| **Assertions**             | Basic immediate + concurrent (simple)  | Full SVA                               |
| **Compile-time**           | Longer (C++ compile step)              | Faster incremental                     |
| **Scalability**            | Threads + PGO                          | Threads + partitioning                 |
| **Best use case**          | Early RTL dev, regression, CI/CD       | Full verification, signoff             |

**Practical tip:** Use Verilator for speed during daily development and regression. Use commercial tools for signoff, X-prop analysis, gate-level sims, and full UVM environments. Many teams use both.

---

## 16. Project Structure Template

```
project/
├── rtl/
│   ├── pkg/
│   │   └── my_pkg.sv
│   ├── top.sv
│   ├── sub_a.sv
│   └── sub_b.sv
├── tb/
│   ├── sim_main.cpp       # C++ testbench
│   ├── tb_helpers.h       # Test utilities
│   └── models/
│       └── ref_model.cpp  # DPI reference model
├── cfg/
│   ├── design.f           # File list
│   ├── lint.vlt           # Lint waivers
│   └── trace.vlt          # Trace filtering
├── scripts/
│   └── run_sim.sh         # Build + run automation
├── waves/                 # Waveform output
├── coverage/              # Coverage output
├── obj_dir/               # Verilator build output (gitignore)
├── Makefile
└── README.md
```

**Example `design.f`:**

```
// design.f
+incdir+rtl/pkg
rtl/pkg/my_pkg.sv
rtl/top.sv
rtl/sub_a.sv
rtl/sub_b.sv
```

**Example `Makefile`:**

```makefile
TOP       = top
VFLAGS    = --cc --exe --build -j 0 -Wall --trace-fst --coverage
VSRC      = -f cfg/design.f cfg/lint.vlt
TB        = tb/sim_main.cpp tb/models/ref_model.cpp
OPT       = -CFLAGS "-std=c++17 -O2"

.PHONY: sim lint wave cov clean

sim:
	verilator $(VFLAGS) $(OPT) --top-module $(TOP) $(VSRC) $(TB)
	./obj_dir/V$(TOP) +verilator+coverage+file+coverage/cov.dat

lint:
	verilator --lint-only -Wall --top-module $(TOP) $(VSRC)

wave:
	gtkwave waves/sim.fst &

cov:
	verilator_coverage --annotate coverage/annotated coverage/cov.dat

clean:
	rm -rf obj_dir waves/*.fst waves/*.vcd coverage/*
```

---

## Quick Command Reference Card

```
# Lint
verilator --lint-only -Wall -f design.f

# Compile + build (C++ TB)
verilator --cc --exe --build -j 0 -Wall --trace-fst \
  --top-module top -f design.f tb/sim_main.cpp

# Compile + build (standalone, no custom TB)
verilator --binary -j 0 -Wall top.sv

# Run simulation
./obj_dir/Vtop +trace +seed=42

# Multithreaded
verilator --cc --exe --build --threads 4 -j 0 -Wall \
  --top-module top -f design.f tb/sim_main.cpp

# Coverage merge + report
verilator_coverage --write merged.dat cov1.dat cov2.dat
verilator_coverage --annotate ann_dir merged.dat

# PGO profiling
verilator_gantt prof.dat > gantt.vcd
```

---

*Updated for Verilator 5.x (devel 5.047, April 2026). Always check `verilator --version` and the [official docs](https://verilator.org/guide/latest/) for the latest features and flags.*
