# DiP RTL Verification - Historical Status

> This file records the earlier incomplete investigation. It is superseded by
> `../status/verification-status.md`, which describes the current RTL and current
> interface tests.

## Executive Summary

The RTL has been partially debugged and now implements the core DiP architecture from the paper, but **does not yet reproduce paper results**. Major infrastructure bugs have been fixed, but functional issues remain in the computation dataflow.

## Architecture Verification ✅

The RTL **correctly implements** the DiP paper architecture (Section III-A, Fig. 2):

| Paper Requirement | RTL Implementation | Status |
|---|---|---|
| N×N systolic array | `rtl/core/systolic.sv` with parameterized LANES | ✅ Correct |
| Diagonal input movement | `i_reg[r-1][(c + LANES - 1) % LANES]` | ✅ Verified |
| Wraparound connections | Leftmost col of row r-1 → rightmost col of row r | ✅ Correct |
| Vertical weight loading | Cascade through rows via `w_reg[r-1][c]` | ✅ Fixed (was broken) |
| Vertical psum accumulation | `psum(p_out[r-1][c])` feeds down | ✅ Correct |
| Outputs from last row | `pe_output_flat` packs `p_out[LANES-1][*]` | ✅ Correct |
| 2-stage pipelined MAC | `rtl/core/pe.sv`: mul_reg + pe_output stages | ✅ Correct |
| Per-row enables | `pe_en[r]`, `mul_en[r]`, `adder_en[r]` | ✅ Correct |
| Global wshift | Single `wshift` to all PEs | ✅ Correct |
| No input/output FIFOs | Direct connections, no FIFO modules | ✅ Correct |

## Bugs Fixed (7 Critical Issues) ✅

### 1. Missing LDW Parameter
- **File:** `rtl/core/controller.sv:250`
- **Fix:** Added `localparam LDW = $clog2(2*LANES);`

### 2. H-Counter Off-by-One
- **File:** `rtl/core/datapath.sv`
- **Fix:** `h_m = LANES - 1` (was `LANES`)

### 3. Load Position Timing Lag
- **File:** `rtl/core/controller.sv`
- **Fix:** Made `load_pos` combinational (was registered, causing 1-cycle lag)

### 4. Lane Capture Misalignment
- **File:** `rtl/core/datapath.sv`
- **Fix:** Added `load_pos_r1` for 1-cycle delayed lane fanout to match BRAM output timing

### 5. Write-Back Address Mismatch
- **File:** `rtl/core/datapath.sv`
- **Fix:** Separated `addr_o_cur` (read) and `addr_o` (write) using delayed `write_col`

### 6. Base Address Timing
- **File:** `rtl/core/controller.sv`
- **Fix:** Moved `base_cal` assertion to ERROR_CHECK state

### 7. **CRITICAL: Weight Propagation**
- **File:** `rtl/core/controller.sv`
- **Problem:** `wshift` fired only once → only row 0 got weights
- **Root Cause:** DiP requires cascading weight load through all rows
- **Fix:**
  - Added `wshift_cnt` counter
  - Changed LATCH_W to multi-cycle state (LANES cycles)
  - `wshift` now pulses LANES times

### 8. Weight Permutation
- **File:** `verif/legacy/tb_dip_256.sv`
- **Fix:** Implemented Algorithm 1 weight permutation in testbench

## Current Test Results ❌

```
M=4 N=4 K=4: C[0][0]=76 (expect 2650) - FAIL
Only first cell has data, others=0
Timeouts on tests with K>4
```

## Remaining Issues 🔴

### Issue 1: Incomplete Output
**Symptom:** Only C[0][0] gets a value, C[0][1..3] and C[1..][*] are all zero
**Likely causes:**
- Write-back logic only writing one column
- Systolic array not producing outputs for columns 1-3
- Output unpacking issue

### Issue 2: Wrong Computation Value
**Symptom:** C[0][0]=76 vs expected 2650 (38x too small)
**Likely causes:**
- Missing accumulation across h-loop iterations
- Incorrect diagonal input timing (inputs not reaching all rows)
- PE pipeline timing mismatch

### Issue 3: Timeouts on K>4 Tests
**Symptom:** `done` never asserts when K=8
**Likely causes:**
- j-loop counter stuck or not incrementing
- State machine deadlock in multi-tile scenarios

## What Works ✓

1. **Weight loading**: All rows now receive weights correctly (verified in tb_systolic_direct.sv)
2. **Systolic structure**: Diagonal connections, vertical flows correct
3. **Control FSM**: State transitions through LOAD→LATCH_W→COMPUTE→WRITE
4. **Non-zero output**: Getting partial results (not all zeros)

## What Doesn't Work ✗

1. **Functional correctness**: Wrong numerical results
2. **Multi-column output**: Only first column written
3. **Multi-tile scenarios**: Timeouts on larger matrices
4. **Paper result reproduction**: Cannot verify paper claims

## Recommended Next Steps

### Immediate (1-2 hours):
1. **Debug write-back loop** - trace why only one cell writes
   - Check `write_cnt` incrementing through 0..LANES-1
   - Verify `w_out` pulses LANES times during WRITE_TILE
   - Check output address generation for all columns

2. **Trace h-loop accumulation** - verify psums accumulate across h=0,1,2,3
   - Add probes for `dout_mem` during WRITE_TILE
   - Check if old C values are being read correctly
   - Verify `rsum = pe_output + dout_mem` calculation

### Medium-term (4-8 hours):
3. **Fix multi-tile scenarios** - debug j-loop and timeout issues
   - Check counter reset logic in INC_I, INC_J states
   - Verify i_max, j_max signals
   - Trace state transitions for K=8 case

4. **End-to-end single computation trace** - M=4,N=4,K=4
   - Dump all PE registers every cycle
   - Verify exact paper dataflow (Fig. 3 example)
   - Compare cycle-by-cycle against golden model

### Long-term (1+ days):
5. **Comprehensive verification**
   - Create directed tests for each h-iteration
   - Verify diagonal propagation timing with waveforms
   - Test all LANES configurations (4, 8, 16, 64)

## Files Modified

```
 rtl/core/controller.sv       - 7 changes (LDW, wshift multi-cycle, load_pos, base_cal)
 rtl/core/datapath.sv         - 5 changes (h_m, lane delays, addresses, w_phase_r)
 verif/legacy/tb_dip_256.sv   - Weight permutation added
 verif/active/tb_systolic_direct.sv - Created for low-level systolic testing
 verif/legacy/tb_quick_debug.sv - Updated with probes
```

## Conclusion

The RTL architecture matches the DiP paper design, and major bugs have been fixed. However, **functional verification fails** - the RTL does not produce correct matrix multiplication results. The systolic array structure is correct, but the data flow timing or accumulation logic has remaining issues that prevent reproduction of paper results.

**Estimated effort to complete:** 8-16 hours of detailed cycle-level debugging and dataflow tracing.

**Confidence in architecture match:** High (95%) - structure verified against paper
**Confidence in functional correctness:** Low (20%) - results don't match expected values
