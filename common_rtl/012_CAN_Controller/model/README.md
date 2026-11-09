# CAN FD controller reference model

Reference models for the CAN FD controller specification [`../VLSIT_CAN_FD_CONTROLLER_HDS.md`](../VLSIT_CAN_FD_CONTROLLER_HDS.md). These scripts are not synthesizable RTL or a testbench; their self-tests check the models only.

| File | Purpose | Run |
|---|---|---|
| `can_bit_timing_model.py` | Cycle-accurate model of `m_canfd_btl` (synchronizer, prescaler, segments, hard and soft synchronization, sample point, bit rate switch) and its self test (12 checks) | `python can_bit_timing_model.py selftest` |
| `can_bit_timing_waves.py` | WaveJSON of WF-029 to WF-042 (WF-029 to WF-039 from the model) | `python can_bit_timing_waves.py OUT_DIR` |
| `can_logic_diagrams.py` | SVG logic diagrams of the bit timing, the frame datapath and the error monitoring | `python can_logic_diagrams.py OUT_DIR` |

Sources: Bosch CAN 2.0 (REF-001) and CAN FD 1.0 (REF-002). Python 3, standard library only. The model is a reference for the RTL test (TEST-036), not a replacement for it.

## Receive path model (section 10.11)

| File | Purpose | Run |
|---|---|---|
| `can_rx_model.py` | Acceptance filter (range, dual, mask, global rules), Rx FIFO (blocking, overwrite, generation counter), word-time budget; self test with 15 checks | `python can_rx_model.py` |
| `can_rx_waves.py` | WaveJSON of WF-044 to WF-046 and the logic diagram of the receive path | `python can_rx_waves.py OUT_DIR` |

## Transmit path model (section 10.12)

| File | Purpose | Run |
|---|---|---|
| `can_tx_model.py` | Tx scheduler: priority (identifier, fixed PRIO, express buffer), FIFO and queue, cancel, valid buffers and trigger transmit, per-buffer retry limit, commit-point budget; 17 checks | `python can_tx_model.py` |
| `can_tx_waves.py` | WF-047 to WF-050 and the logic diagram of the transmit path | `python can_tx_waves.py OUT_DIR` |

## TTCAN model (section 10.13)

| File | Purpose | Run |
|---|---|---|
| `can_tt_model.py` | Cycle codes, trigger list checks, NTU generator, sync states, backup master, error levels, level 2 drift compensation; 22 checks | `python can_tt_model.py` |
| `can_tt_waves.py` | WF-053 to WF-058 and the logic diagram of the TTCAN frame synchronization entity | `python can_tt_waves.py OUT_DIR` |

## DMA model (section 10.14)

| File | Purpose | Run |
|---|---|---|
| `can_dma_model.py` | Rx and Tx DMA request logic with the re-arm rule (shows the double service of the naive rule); 17 checks | `python can_dma_model.py` |
| `can_dma_waves.py` | WF-059 to WF-064 | `python can_dma_waves.py OUT_DIR` |

## Sleep and partial networking model (section 10.15)

| File | Purpose | Run |
|---|---|---|
| `can_pn_model.py` | Bit-serial wake-up frame filter (ids, masks, DLC, data masks, CRC and stuff errors, FD frames) and the power state machine; 16 checks | `python can_pn_model.py` |
| `can_pn_waves.py` | WF-065 to WF-068 | `python can_pn_waves.py OUT_DIR` |

## can_safety_model.py

Section 18.3 and 18.5: option resolution (level preset OR single parameter, dependency rules), the fault reaction register `cfd_saf_rct` and a FORMULA CHECK of the FMEDA metrics. `python can_safety_model.py` runs the self test (37 checks, it also compares the flag order and the reaction reset values with `regs_canfd.json`); `python can_safety_model.py fmeda` prints the table of section 18.5.1. All FMEDA inputs are assumptions (ASM-021): it is not a metric of the IP.

## can_safety_fmeda_xlsx.py

Writes `safety/CAN_FD_FMEDA_Worksheet.xlsx` with live formulas (Blocks, Mechanisms, Coverage, Config, Residual, Results). Inputs are assumptions (ASM-021). Not recalculated in Excel in this run; the inputs were re-read and the metrics recomputed in Python and agree with can_safety_model.py.
