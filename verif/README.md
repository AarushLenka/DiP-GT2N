# Verification layout

## Active

`active/` contains the current testbenches and the combinational-read,
synchronous-write SRAM model used by `rtl/core/top_module.sv`.

The active RTL manifest is `filelists/active/rtl.f`. Commands in the root
`README.md` are run from the repository root and use this manifest explicitly;
the vendor-dependent monitor and legacy helper modules are not included.

## Legacy

`legacy/` contains tests, compile manifests, and the registered-read Xilinx
BRAM substitute from the earlier interface revision. These files are retained
for debugging provenance but are not current regression tests.

## Evidence

`evidence/` contains only intentionally retained historical outputs. New
simulation products should be written to the ignored `build/` directory or to
`/tmp`, not committed as source.
