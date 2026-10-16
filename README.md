# DiP-GT2N

This repository contains a parameterized SystemVerilog implementation of the
Diagonal-Input and Permutated weight-stationary (DiP) matrix-multiply dataflow
described in [`docs/papers/dip-paper.md`](docs/papers/dip-paper.md).

## Repository layout

```text
rtl/core/                 Current portable DiP RTL
rtl/legacy/               FPGA wrapper and unused historical primitives
verif/active/             Current SRAM-model testbenches
verif/legacy/             Obsolete-interface tests retained as history
verif/filelists/          Active and historical compile manifests
verif/evidence/           Intentionally retained historical waveform evidence
docs/papers/              Paper sources and local paper conversion
docs/status/              Current verification status
docs/history/             Superseded investigation notes
```

The current RTL dependency chain is:

```text
top_module -> controller, datapath
datapath   -> systolic, error_check
systolic   -> pe
```

The portable source list is
[`verif/filelists/active/rtl.f`](verif/filelists/active/rtl.f). It excludes
the vendor-dependent FPGA monitor and all obsolete helper modules.

## Current implementation

- `rtl/core/systolic.sv` builds an `LANES x LANES` array with paper-style
  diagonal input rotation, vertical stationary weights, and vertical partial
  sum flow.
- `rtl/core/pe.sv` implements the two-stage signed INT8 MAC pipeline.
- `rtl/core/controller.sv` and `rtl/core/datapath.sv` tile arbitrary matrix
  dimensions, including edge tiles and reduction tiles, through the scalar
  SRAM interface exposed by `rtl/core/top_module.sv`.
- Weights can be supplied in the paper's software-permuted format (the
  default) or as ordinary row-major B with `WEIGHTS_PREPERMUTED=0`.

The scalar SRAM wrapper is a functional integration model. The paper's
throughput, area, and power numbers assume banked wide memory and a 22 nm
physical implementation; those PPA results are not reproduced by an Icarus
simulation.

## Simulation

Run these commands from the repository root. The SRAM model is
combinational-read and synchronous-write, matching the current top-level
contract.

```bash
# LANES=4: small, multi-tile, reduction-tile, and edge-tile suite
iverilog -g2012 -o /tmp/dip_sram.vvp -s tb_dip_sram \
  -c verif/filelists/active/rtl.f \
  verif/active/tb_dip_sram.sv verif/active/sram_model.sv
vvp /tmp/dip_sram.vvp

# LANES=8 parameterization suite
iverilog -g2012 -o /tmp/dip_l8.vvp -s tb_dip_sram -DLANES=8 \
  -c verif/filelists/active/rtl.f \
  verif/active/tb_dip_sram.sv verif/active/sram_model.sv
vvp /tmp/dip_l8.vvp

# Protocol/error checks
iverilog -g2012 -o /tmp/dip_protocol.vvp -s tb_dip_protocol \
  -c verif/filelists/active/rtl.f \
  verif/active/tb_dip_protocol.sv verif/active/sram_model.sv
vvp /tmp/dip_protocol.vvp

# Raw row-major B mode
iverilog -g2012 -o /tmp/dip_raw.vvp -s tb_dip_raw \
  -c verif/filelists/active/rtl.f \
  verif/active/tb_dip_raw.sv verif/active/sram_model.sv
vvp /tmp/dip_raw.vvp

# Paper Fig. 3-style non-power-of-two 3x3 schedule
iverilog -g2012 -o /tmp/dip_paper3.vvp -s tb_dip_paper3 \
  -c verif/filelists/active/rtl.f \
  verif/active/tb_dip_paper3.sv verif/active/sram_model.sv
vvp /tmp/dip_paper3.vvp

# Paper-sized 64x64 array and 64x64x64 signed INT8 multiply
iverilog -g2012 -o /tmp/dip_target64.vvp -s tb_dip_target64 \
  -c verif/filelists/active/rtl.f \
  verif/active/tb_dip_target64.sv verif/active/sram_model.sv
vvp /tmp/dip_target64.vvp
```

The directed low-level smoke test is
`verif/active/tb_systolic_direct.sv`.

## Synthesis and lint checks

The low-level array is accepted by Yosys:

```bash
yosys -p 'read_verilog -sv rtl/core/pe.sv rtl/core/systolic.sv; \
  hierarchy -top systolic -chparam LANES 4; proc; check'
```

Verilator lint can be run against the complete portable top. Width-extension
warnings remain around integer address arithmetic; they are documented in
[`docs/status/verification-status.md`](docs/status/verification-status.md).

```bash
verilator --lint-only --language 1800-2012 --top-module top_module \
  rtl/core/*.sv -Wno-fatal
```

The tests under `verif/legacy/` target the former Xilinx BRAM and old
`top_module` ports. They are retained for investigation provenance and are not
part of the current regression suite.
