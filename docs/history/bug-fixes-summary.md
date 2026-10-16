# DiP RTL Bug Fixes and Historical Investigation

> The remaining-issues list below predates the current tiled datapath rewrite.
> See `../status/verification-status.md` for the current verified behavior.

## **BUGS FIXED:**

### 1. ✅ Missing LDW parameter in controller.sv
**Issue:** `LDW` used but never declared
**Fix:** Added `localparam LDW = $clog2(2*LANES);` at line 82

### 2. ✅ H-counter off-by-one
**Issue:** `h_m = LANES` caused h-loop to run 0..LANES (5 iterations) instead of 0..LANES-1 (4 iterations)
**Fix:** Changed to `h_m = LANES - 1` in datapath.sv

### 3. ✅ load_pos timing lag
**Issue:** Registered `load_pos` was 1 cycle behind `burst_cnt`, causing wrong lane addressing
**Fix:** Made `load_pos` combinational (directly from `burst_cnt` and `write_cnt`)

### 4. ✅ Lane capture misalignment
**Issue:** BRAM has registered output (1-cycle delay) but lane capture used current `load_pos`
**Fix:** Added `load_pos_r1` (1-cycle delayed) for lane fanout `w_hit`/`i_hit` logic

### 5. ✅ Write-back address mismatch
**Issue:** Single-port BRAM needs same address for read and write, but addr was advancing
**Fix:** Split into `addr_o_cur` (read) and `addr_o` (write, using delayed `write_col`)

### 6. ✅ base_cal timing
**Issue:** `bi1_q`/`bi2_q` not settled before first LOAD_TILE cycle
**Fix:** Moved `base_cal` assertion to ERROR_CHECK state

### 7. ✅ **CRITICAL: Weight propagation**
**Issue:** `wshift` fired only once, loading weights only to row 0. Rows 1-3 had zero weights
**Root cause:** DiP architecture requires weights to cascade down through rows (row 0 → row 1 → ... → row LANES-1)
**Fix:**
- Added `wshift_cnt` counter
- Changed LATCH_W from single-cycle to multi-cycle state (LANES cycles)
- `wshift` now pulses LANES times to propagate weights through all rows

## **CURRENT STATUS:**

- Systolic array now produces **non-zero outputs** (e.g., 76 vs expected 2650)
- Weight loading verified: all rows get weights correctly
- Diagonal input propagation working (traced in tb_systolic_direct.sv)
- Vertical psum accumulation working

## **REMAINING ISSUES:**

### 1. 🔴 **Weight Matrix Permutation NOT Implemented**
**Paper requirement:** Algorithm 1 - each column shifted/rotated by its column index
**Current state:** RTL expects pre-permuted weights from software, but testbench provides un-permuted data
**Impact:** Wrong weight-input pairings → wrong results

**Required fix:** Either:
- a) Testbench must permute weights before loading (software-level permutation)
- b) Add hardware permutation logic (not recommended per paper)

### 2. 🔴 **H-loop Accumulation**
**Paper:** Multiple h-iterations accumulate partial sums
**Current:** Each h-iteration may be overwriting instead of accumulating
**Need to verify:** Are psums from h=0,1,2,3 being summed correctly?

### 3. 🟡 **Timeout on K>4 tests**
**Symptom:** Tests with K=8 timeout (done never asserts)
**Possible causes:**
- j-loop counter not resetting properly
- i_max/j_max logic issues
- State machine stuck

### 4. 🟡 **Only first output cell has data**
**Symptom:** C[0][0]=76, but C[0][1..3] and C[1..][*] all =0
**Possible causes:**
- Write-back only writing one cell
- write_cnt not incrementing through all columns
- Systolic array output indexing issue

## **VERIFICATION APPROACH:**

### Immediate next steps:
1. **Add weight permutation to testbench** - implement Algorithm 1 from paper
2. **Trace single M=4,N=4,K=4 test cycle-by-cycle** - verify exact dataflow
3. **Check h-loop accumulation** - ensure psums accumulate, not overwrite
4. **Debug write-back** - why only C[0][0] gets written

### Paper Dataflow Requirements (Fig. 2, Fig. 3):
- ✅ Diagonal input movement with wraparound
- ✅ Vertical weight loading (multi-cycle)
- ✅ Vertical psum accumulation
- ❌ **Weight permutation (missing in testbench)**
- ✅ Per-row control signals (pe_en, mul_en, adder_en)
- ✅ Global wshift

## **ARCHITECTURE MATCHES PAPER:**
- systolic.sv: Correct diagonal connections, vertical weight/psum flow
- pe.sv: 2-stage pipelined MAC with 4 registers
- Control signals: wshift (global), pe_en/mul_en/adder_en (per-row)

## **FILES MODIFIED:**
1. rtl/core/controller.sv - LDW param, wshift multi-cycle, load_pos combinational
2. rtl/core/datapath.sv - h_m fix, lane capture delay, write-back addresses
3. verif/active/tb_systolic_direct.sv - weight propagation test
4. verif/legacy/tb_quick_debug.sv - debugging instrumentation

## **NEXT DEBUG SESSION:**
Focus on implementing weight permutation and verifying h-loop accumulation.
