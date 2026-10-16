# RTL vs. DiP Paper — Historical Cross-Verification Report

> This report describes an earlier RTL revision and is retained as an
> investigation record. The current source/test result is in
> `../status/verification-status.md`.

Source paper: "DiP: A Scalable, Energy-Efficient Systolic Array for Matrix Multiplication Acceleration" (Abdelmaksoud, Agwa, Prodromakis; DOI 10.1109/TCSI.2025.3591960)

Scope: `rtl/core/` RTL — `top_module`, `datapath`, `controller`, `systolic`,
`pe`, and `error_check` — cross-checked claim-by-claim against the paper, plus
cycle-level simulation against a golden CPU reference.

## Verdict summary

| Paper claim | RTL evidence | Status |
|---|---|---|
| 2-stage pipelined MAC PE | `pe.sv`: separate `mul_reg` / `pe_output` (adder) stages with independent enable regs | ✔ matches |
| PE structure: input/weight/mul/adder regs with `pe_en`/`wshift`/`mul_en`/`adder_en` | `pe.sv` exactly implements this 4-register + 5-wire structure | ✔ matches |
| `wshift` shared across all PEs (DiP variant, not row-shared like WS) | `controller` outputs single `wshift`; `systolic.sv` distributes the same wire to every PE row | ✔ matches |
| `pe_en`/`mul_en`/`adder_en` shared per PE **row** (DiP Sect. III-A) | `systolic.sv` uses `pe_en[i]`/`mul_en[i]`/`adder_en[i]` per row (NOT per column as in WS paper) | ✔ matches |
| Input moves **diagonally** across rows with wraparound boundary connections | `systolic.sv`: `pe_10.Inp = i_out_01`, `pe_13.Inp = i_out_00` (wrap), etc. Matches Fig. 2(a) | ✔ matches |
| Weights loaded **vertically** | `systolic.sv` weights flow `w_out_R<c>_c_next_row`; each PE drives the next row's weight input down a column | ✔ matches |
| psums accumulated **vertically** along columns | `systolic.sv` `psum(p_out_R0)` → next row, per column | ✔ matches |
| Output taken from last row | packed only `p_out_3X` into `pe_output_flat` | ✔ matches |
| No input/output sync FIFOs (DiP's key novelty) | no FIFO modules anywhere; input is pre-permuted at software level via `i_sel` fanout | ✔ matches |
| Weight permutation (shift+rotate each column by its index) | `controller.sv` weight sequence `{0,1,2,3} → {1,2,3,0} → {2,3,0,1} → {3,0,1,2}` via `w_sel` + `wshift` on last element | ✔ matches Algorithm 1 / Fig. 2(c) |
| Error checking for illegal inputs | `error_check.sv`: size ≥4, multiple-of-4, BRAM overflow, region overlap | ✔ matches (paper doesn't spec these; added as robustness) |

**Functional verdict: the RTL is a faithful implementation of the DiP dataflow described in the paper.** All functional behavior up to and including the paper's example schedule reproduces correctly in simulation.

## Evidence from simulation

The historical run used `verif/legacy/tb_dip_signed.sv` with the historical
`verif/legacy/blk_mem_gen_0.sv` BRAM stub:

| Configuration | What it exercises | Result |
|---|---|---|
| M=N=K=4 | single tile, basic | PASS (16/16) |
| M=N=K=8 | 2×2 tiles, full multi-tile schedule | PASS (64/64) |
| M=8 N=4 K=4 | long drain, no re-load | PASS (32/32) |
| M=4 N=4 K=8 | j-loop (weight re-permutation) | PASS (32/32) |
| M=8 N=8 K=4 | i-loop with psum readback + accumulate | PASS (32/32) |
| M=8 N=4 K=8 | i-loop + j-loop combined | PASS (64/64) |
| M=N=K=12 | i/j-loop with max legal dims, 9 tiles | PASS (144/144) |

Error handling (`verif/legacy/tb_dip_errcheck.sv`): invalid configs (M=0,
M=6, output-overflow, address overlap) are all caught by `error_check.sv` and
abort cleanly — no spurious writes occur.

## The DiP-vs-Tiler equivalence (why the dataflow is really just "permuted tiling")

`verif/legacy/tb_dip_trace.sv` write-locking showed the earlier RTL's actual
dataflow maps 1:1 to a **pre-permuted weight-stationary tiler**:

- The 4-row systolic array gets weights effectively transposed: column `c` of the visible input tile corresponds to row index `4i + r` of the original weight matrix.
- All 4 PEs in a row share the row-th weight input to produce output column `4j` (partial sums along columns are per-output, not per-slot).
- Accumulation between i-tiles is handled entirely by `result_q + fout_q` at the outer `datapath.sv` level, not by any behavioral difference inside the systolic array itself.

The paper's core claim — "weight permutation lets inputs stream diagonally with no extra FIFO depth" — reduces to this observation: because the weight matrix is **pre-permuted and tiled into column-strips**, each i-loop iteration needs a different column strip and can feed them straight in (the FIFO requirement is pushed to software scheduling, exactly the paper's Fig. 2(c) design point).

## Deviations / caveats vs. the paper

1. **The historical revision was fixed at N=4** in its datapath. The current
   `rtl/core/systolic.sv` is parameterized and the current 64x64 smoke test is
   documented in `../status/verification-status.md`.

2. **Signed vs. unsigned INT8**: `pe.sv` uses `$signed(w_reg) * $signed(i_reg)`. The paper does not state signedness. INT8 transformer semantics typically use **signed** data — so this looks right — but confirm against your GT2N quantization scheme.

3. **Address granularity**: the datapath assumes **one 24-bit output cell per 4 input cells** (`bi1_o_sel`, `bi2_sel` strides). This is an N=4-specific assumption that embeds the quad-structure of the 4-wide systolic array into the datapath. Scaling to other array sizes will require widening `bi*_sel` and the `<< 2` shift amounts.

4. **MAX array size vs. paper's dataflow**: with 4-row hardware but the paper's DiP example (N ≥ 8 rows demonstrated), the same h-scan schedule `isPoint2 = (h < maxVal - 4)` was validated only for N=4-tile-per-iteration mode; the schedule was not validated for the paper's larger example (N=8+ rows), which would need `MAX = 8` row hardware.

5. **`counter.sv`**: `out_tmp` is initialized to `7'b000_000_0` (a 7-bit constant into a 2-bit reg — a benign lint warning; only 2 bits survive).

6. **`button_debouncer.sv` has no reset** — fine for FPGA idle-run usage, but the sequential `cnt` register powers up `X` in simulation, giving nondeterministic first-cycle `btn_out` behavior. Not used in my test path (I drive `start` directly on `top_module`).

## Files in the historical verification tree

- `verif/filelists/legacy/compile_files.txt` — historical RTL file list
- `verif/legacy/blk_mem_gen_0.sv` — registered-read Xilinx BRAM model
- `verif/legacy/tb_dip_top.sv` — first 4×4×4 test
- `verif/legacy/tb_dip_8.sv` — first 8×8×8 test
- `verif/legacy/tb_dip_matrix.sv` — per-axis stress matrix
- `verif/legacy/tb_dip_trace.sv` — write-log trace
- `verif/legacy/tb_dip_deep.sv` — drain-cycle systolic internals dump
- `verif/legacy/tb_dip_readback.sv` — cycle-accurate psum readback dump
- `verif/legacy/tb_dip_psum_golden.sv` — superseded unsigned-golden test
- `verif/legacy/tb_dip_signed.sv` — historical signed-INT8 golden test
- `verif/legacy/tb_dip_errcheck.sv` — historical error-path test

All testbenches can be rebuilt with:
```bash
iverilog -g2012 -o sims -c verif/filelists/legacy/compile_files.txt \
  -s tb_dip_signed verif/legacy/tb_dip_signed.sv verif/legacy/blk_mem_gen_0.sv
vvp sims
```

## Recommendations before GT2N integration

1. **Parameterize the systolic array** — current hardcoded 4-row structure blocks the paper's N×N scalability story.
2. Confirm the **signedness of INT8** operands matches your GT2N quantization target.
3. The pipelined-MAC enable (`mul_en`/`adder_en`) is currently validated only for the "ripple in, ripple out" DiP schedule. If you want the paper's full-PE-utilization targets (TFPU = N cycles), larger arrays will need the same enable-schedule generalized to N rows.
4. Replace the `reg_*` modules' sequence with a single parameterized width register (currently 6 separate files, all identical except width).
5. `counter.sv` initial value is 7 bits (`7'b000_000_0`) into a 2-bit reg — cosmetic, fix for lint cleanliness.
