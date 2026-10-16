# DiP RTL verification status

## Verdict

The current RTL now reproduces signed INT8 matrix multiplication functionally
for the paper's DiP dataflow. The array is parameterized and the same source
was exercised at `LANES=4`, `LANES=8`, and the paper-sized `LANES=64` target.

The implementation does **not** claim to reproduce the paper's 22 nm area,
power, energy-efficiency, or peak-throughput numbers. The repository top has a
scalar SRAM port and stages tiles locally; the paper evaluates wide/banked
memory and post-layout hardware.

## Checks run

| Command/test | Result |
|---|---|
| `tb_dip_sram`, `LANES=4` | PASS: 4x4, multi-tile, reduction-tile, edge-tile, 5x6x7, and 12x12x12 cases |
| `tb_dip_sram`, `LANES=8` | PASS: 8x8x8, 8x16x8, and 16x8x8 parameterization cases |
| `tb_dip_raw` | PASS: ordinary row-major B with hardware-side equivalent permutation |
| `tb_dip_protocol` | PASS: one-shot done, held-start suppression, invalid-dimension abort/no writes |
| `tb_systolic_direct` | PASS: weight cascade, paper diagonal rotation, and two-stage MAC |
| `tb_dip_target64` | PASS: 64x64 array, 64x64x64 signed INT8 multiply |
| `tb_dip_paper3` | PASS: non-power-of-two 3x3 Fig. 3-style schedule |
| Icarus top elaboration | PASS |
| Verilator complete-top lint | PASS with width/timescale warnings |
| Yosys low-level `systolic` check | PASS, 0 structural problems |

## Important fixes

1. Added the missing controller phase-width parameter/logic so the current
   top elaborates.
2. Corrected diagonal routing to the paper's left-to-right convention:
   `row[r][c]` receives `row[r-1][(c+1) % LANES]`.
3. Made weight shifting preserve distinct rows while `weight_flat` changes on
   successive cycles.
4. Replaced the incomplete h-loop/address schedule with explicit B/A tile
   gathering, weight permutation handling, diagonal wavefront control,
   reduction-tile accumulation, edge zero-padding, and aligned writeback.
5. Added held-start protection and current-interface protocol tests.

## Remaining scope

- The scalar SRAM controller is functionally correct but is not the paper's
  banked-memory throughput implementation; its cycle count includes tile
  gather and writeback cycles.
- Full physical PPA reproduction requires the target technology libraries,
  synthesis constraints, and place-and-route flow, which are not present in
  this repository.
- `../../rtl/legacy/fpga/top_monitor_module.sv` still depends on the vendor
  `vio_0` IP and is not a standalone simulation top. Use
  `../../rtl/core/top_module.sv` with `../../verif/active/sram_model.sv`.
