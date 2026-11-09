# RTL review of the CAN FD Controller leaf modules (state of 2026-11-09)

Review only: **no RTL, HDS or CSR file was changed.** Scope, evidence level and limits first, findings after.

## 1. Scope and evidence level

| Item | Status |
|---|---|
| Files read in full | `rtl/m_canfd_bsp.sv` (1462 lines), `m_canfd_btl.sv`, `m_canfd_tdc.sv`, `m_canfd_stuf.sv`, `m_canfd_crc.sv`, `m_canfd_eml.sv`, `m_canfd_cdc.sv`, `m_canfd_rst.sv` |
| Not read in detail | `m_canfd_sync_bit.sv`, `m_canfd_sync_hsk.sv`; the generated CSR (`m_vlsit_csr_canfd.sv`, 390 KB, 106 registers, 765 ports) only through `CSR_GENERATED.md` |
| Not existing yet | Rx filter, Rx and Tx handlers, message RAM master, timestamp, DMA, interrupts, power and partial networking, TTCAN, safety module, write protection, **top module** |
| Lint | Verilator 5.053 `-Wall` on `m_canfd_crc` + `m_canfd_stuf` + `m_canfd_bsp`: one UNUSEDSIGNAL warning (unused bits of `i_tx_frame_can`: `[127:54]` and `[47:31]`). No lint log of the BSP exists in `rtl/`. |
| Simulation | **Not done.** A small testbench was written (`research/rtl_review_tb/tb_core.sv`: BTL + BSP + EML as a minimal core, internal-loopback mode and bus-fault mode). It compiled with Verilator, but the link step failed in this environment (`ld returned 5`, the executable is truncated); Icarus Verilog cannot compile the enum assignments of the BSP. |

Consequence: every behavioral finding below comes from **reading the code against the HDS (v0.4) and the protocol rules**, not from a run. Each one names the test that would confirm or refute it. "Confirmed by reading" means the code path is explicit; "Suspected" means it depends on a reading of the standard or on a cross-module connection that does not exist yet.

## 2. Findings that block software development or interoperability

| # | Finding | Evidence in the code | Status | Test that decides it |
|---|---|---|---|---|
| R1 | **Internal loopback cannot complete a transmission.** The own transmitted bit is looped back (`w_rx_wire_bit = lbk_int ? reg_tx_bit_sent : i_sample_val`), but the node never drives a dominant ACK slot in loopback (only a receiver does) and a recessive ACK slot is an ACK error for the transmitter; `reg_ack_seen`, required for `w_tx_end_good`, needs a dominant ACK. | bsp 409, 535-539, 633-634, 1037-1039, 655-658 | Confirmed by reading | `tb_core.sv` MODE 0: expect `tx_ok = 0`, `ack_err > 0`. Commercial IP (M_CAN, research file C1) lets internal loopback ignore the ACK; the HDS says loopback is "a functional self-test" (OP, 10.1). |
| R2 | **Classic DLC 9 to 15 is received as 0 data bytes.** `f_dlc_len` has no case for `{fd=0, dlc 9..15}` and falls to the default 0, while ISO treats these Classic codes as 8 bytes. A valid Classic frame with DLC > 8 is then parsed with no data field, the CRC is read at the wrong position and the node answers with errors. The Tx path clamps to 8 correctly (bsp 389-392). | bsp 325-358, 402 | Confirmed by reading; the rule "Classic DLC > 8 = 8 bytes" is general CAN knowledge, check the ISO clause | Directed Rx test with DLC = 9..15 Classic frames from a reference node |
| R3 | **The error delimiter does not wait for a recessive bit.** After the 6 flag bits the BSP counts 8 samples in `ERR_DEL` whatever the bus level (only a dominant-sequence counter is kept). When other nodes' flags overlap (up to 12 dominant bits on the bus), this node leaves the delimiter early, sees dominant in its own intermission and sends overload frames; its timing no longer matches the other nodes. | bsp 879-886, 1179-1184, 1373-1389 | Confirmed by reading; the delimiter rule is in HDS REQ-FUNC-014 and ISO | Two-node test with one node starting its flag later than the other |
| R4 | **Bus-off recovery cannot complete unless the top masks `i_bus_off`.** The BSP leaves `BUS_OFF` only when `i_bus_off` falls (889); `o_bus_off` of the EML falls only after 128 `evt_idle11` events (EML 141, 149-151); the BSP emits `evt_idle11` only in state `INTEG` (1368-1371), which it never enters while `i_bus_off` is high (680-683, 670-673). The HDS port table (14.2.5) says only "error-management state"; no document defines the masking. | bsp 670-683, 887-889, 1368-1371; eml 141-151 | Confirmed for the module pair as written; may be solved at the top, which does not exist | `tb_core.sv` MODE 1: after the fault is released and `restart_req` pulsed, `bus_off` must fall within about 128 x 11 bit times |
| R5 | **Transmit error counting differs from HDS 10.8.3 (rules 3 and 4, exceptions 1 and 2).** (a) For an error-active transmitter a first bit error raises both `evt_tx_err_count` and `evt_tx_bit_err_flag` in the same cycle (bsp 1330-1334) and the EML adds 8 for each, so TEC rises by 16 where rule 3 gives 8 (rule 4 is for a bit error *while sending a flag*). (b) `evt_tx_err_count` is suppressed for the whole error-passive state (1331), not only for exception 1; a passive transmitter's form or stuff error is then never counted. (c) Exception 2 (stuff error in arbitration on a recessive stuff bit) is not implemented. | bsp 1330-1334; eml 97-108 | Confirmed by reading against HDS text; the HDS says the BSP "excludes exceptions 1 and 2" and implements dedicated events for rules 4 to 6 | `tb_core.sv` MODE 1 prints each TEC step: expect +8 per failed attempt |
| R6 | **CC CRC error: the error flag starts one bit late.** HDS REQ-ERR-001: first EOF bit. In the RTL the transition to `ERR_FLAG` happens on the sample of the first EOF bit (idx 0), so the flag is driven from the second EOF bit. The FD path (wait of 3 samples) is consistent with the HDS. | bsp 845-851, 829-831 | Suspected (depends on the exact convention of "first EOF bit" in WF-071) | Directed test with a Classic frame with a bad CRC, compare with WF-071 |
| R7 | **A dominant bit in the third intermission bit is not taken as SOF.** The FSM moves to `IDLE` on the third intermission sample whatever its level (871) and `w_rx_sof_start` needs state `IDLE` at the sample (420-422) with `idle_count >= 11`, which a dominant sample has just reset (1225). A frame that starts in that bit (allowed by the standard for a node with a pending request) is then not acknowledged by this node. | bsp 863-873, 420-422, 1225 | Suspected (check the ISO clause on intermission) | Two nodes, one starting SOF exactly in the third intermission bit |

R1 to R5 should be fixed before any verification work, because each of them changes what software sees: the self-test, the Rx data length, the error counters and the bus-off recovery are the first things a driver exercises.

## 3. Findings that matter for integration and safety

| # | Finding | Evidence | Note |
|---|---|---|---|
| R8 | **REC is capped at 127 and error-passive is declared at 127.** HDS rule 9 says passive at a counter of at least 128, rule 8 says REC saturates at 127; both cannot hold. The RTL resolves it with `REC >= 127` as passive, one count earlier than ISO (passive when the counter exceeds 127). | eml 86-96, 207-209 | Decide in the HDS; a 7-bit REC plus a sticky flag (the M_CAN way, research C1) or a full 8-bit REC fixes it. |
| R9 | **The counter "mirror" of SM-06 shares the next-state logic.** `reg_tec_mirror/reg_rec_mirror` are loaded from the same `w_tec_nxt/w_rec_nxt` (eml 222-236): a fault in that logic hits both copies and is not detected. The FMEDA worksheet assumes 99 % coverage for SM-06 as a full duplicate. | eml 82-132, 222-236; `model/can_safety_model.py` COVER | The assumed coverage is higher than what this structure gives. Duplicate the logic, or lower the assumption (ASM-021). |
| R10 | **The timing ceilings of the HDS are in the RTL**: total bit time 8..80 tq nominal and 5..25 tq data, one prescaler for both, data total no larger than nominal total (btl 22-26, 222-233). The HDS limits TDC to m = 1 or 2 (REQ-BTL-005, DEC-082), which makes a 250 kbit/s nominal rate with a fast data phase impossible to configure at 40 or 80 MHz. The BSP, however, has no prescaler input: `o_tdc_frame_active` and `o_tdc_measure_start` (bsp 591-601) are not qualified by m, so the RTL does not implement the m = 1 or 2 condition that DEC-082 assigns to it. The port `i_cfd_nbt_nbrp` is 9 bits but only 0..31 is used (btl 174-179). | btl; see `hds_critical_review_2026-11-08.md` H2 | Same decision as H2; the RTL only inherits it. |
| R11 | **Out-of-range timing values are clamped silently and the node starts.** A scalar field above its limit is replaced and only `cfg_fix` is set; `timing_cfg_valid` stays 1 when the clamped tuple is legal (btl 153-236, 317-319; bsp 583-585). The node then runs with a bit rate that software did not program, on a live bus. | btl, bsp | For a drone or a vehicle a wrong bit rate disturbs the bus. Either hold INIT for any clamp (as for an illegal tuple) or make `cfg_fix` sticky and documented in the driver flow. |
| R12 | **The TDC delay line is two shift registers of 287 bits plus two 287-to-1 selectors** (tdc 45-46, 107, 110): about 574 flops and a wide mux in the CAN clock. | tdc | Known as M2 in the HDS review; the timing of the 287:1 select at the CAN clock has to be checked in synthesis. |
| R13 | **Tx metadata is mostly not consumed by the BSP.** Lint shows `i_tx_frame_can[127:54]` and `[47:31]` unused: the Tx event, message marker and similar fields must be kept by the (missing) Tx handler. The Rx bundle words 1-3 are zero except the flags (bsp 554-565): the SOF timestamp word is left to the missing timestamp block. | bsp 554-565; lint | Not a defect today; it fixes what the handler must do. |
| R14 | **Transmit start depends on the frame waiting at the CDC output.** The BSP accepts a Tx frame only in `IDLE` or `INTEG` (bsp 410-413) and starts at the next transmit point (415-419). Back-to-back transmission without a gap therefore needs the frame already presented by the 4-phase CDC handshake before the intermission ends. | bsp 410-419; cdc 217-233 | The latency of the handshake (two 2-flop crossings each way) against the shortest intermission has to be a stated requirement (REQ-MSG-016). |

Positive findings from the same reading: the CRC polynomials, initial values and the serial update are as in the ISO extract (crc 14-19, 48-53); the ISO FD stuff count is Gray coded with parity and counts only dynamic stuff bits (stuf 63-66, 138-144); dynamic stuffing and fixed stuff slots follow the field map (bsp 428-476); the reactive overload conditions and the two LLC-requested overloads follow HDS 10.8.2 (bsp 863-874, 845-859); the CC/FD CRC-error timing is split (bsp 819-831); ESI is sent from the error state (bsp 503); the reset-ready exchange and the soft-reset drain are simple and clear (rst 95-138).

## 4. Comparison with Classic CAN controllers and commercial CAN FD IP

"M_CAN" and "GRCANFD" come from the documents read earlier (`commercial_canfd_ip_features.md`); "web" means a search summary only; "general" means the reviewer's memory, not verified here.

| Function | Classic CAN controller (general) | Commercial CAN FD IP | RTL today | Fit |
|---|---|---|---|---|
| 11/29-bit frames, RTR, DLC 0..8 | Yes; DLC 9..15 = 8 bytes | Yes (M_CAN) | Tx yes; **Rx DLC 9..15 wrong (R2)** | No until R2 |
| Arbitration, ACK, error and overload frames | Yes | Yes | Present; delimiter and 3rd-bit SOF issues (R3, R7) | Not yet |
| Fault confinement | 2.0 rules | ISO 8.1.4 rules, bus-off 128 x 11 | Counters present; deviations (R5, R8); recovery blocked (R4) | No |
| Internal loopback for self-test | Often (bxCAN: loop-back and silent modes, general) | M_CAN: internal loopback ignoring ACK (C1) | Does not complete (R1) | No |
| Bit timing, SJW, hard and soft sync | Prescaler, TS1, TS2, SJW | M_CAN: separate nominal and data prescaler; wide ranges | Rules implemented as in the ISO extract, but with ceilings (R10) | Partly |
| TDC, SSP | n/a | M_CAN: delay measured every frame, SSP = delay + offset | Implemented (brute force, R12); no run verification | Unverified |
| Message storage, filters, FIFOs, Tx scheduling | 3 mailboxes, 14 filter banks (bxCAN, general) | M_CAN-class RAM, 128+64 filters; FlexCAN enhanced Rx FIFO with DMA (web) | **Not in the RTL yet** | n/a |
| Timestamp, DMA, interrupts | Optional | Yes | **Not in the RTL yet** | n/a |
| Sleep, wake-up, partial networking | Basic | NXP pretended networking (web) | **Not in the RTL yet** | n/a |
| Safety | None | RAM error input, watchdog (M_CAN); ISO 26262 claims by some vendors (web) | Counter mirror only, with shared logic (R9) | Weak |

## 5. Is the RTL usable for integration, software development, and a drone?

**Integration.** Not yet. There is no top, no message handling and no message RAM master, so there is nothing to connect the register block to. What exists is a protocol core (BTL, BSP, STUF, CRC, TDC, EML), a CDC hub and a reset block, each with a stable-looking port list, and the generated register block (106 registers). The module contracts (named-field ports of 14.2.5) are good for integration; R4 shows that at least one contract (`i_bus_off`) is incomplete.

**Software development.** Not yet, and four of the findings would hit the first driver tests: loopback (R1), Rx length of Classic DLC > 8 (R2), TEC values (R5) and bus-off recovery (R4). Software can already be written against the register map, but the behavior behind the map is not there. The register model and the driver can start from the CSR workbook, which is the source of truth.

**Drone (DroneCAN over Classic CAN at 1 Mbit/s with 29-bit identifiers, Cyphal over Classic or FD; from the research file, partly inference).** The Classic path of the core is what a DroneCAN node uses first, so R2, R3, R5 and R7 matter more for a drone than the FD path. DroneCAN nodes are expected to recover from bus faults on their own; R4 and R5 decide that. Hardware timestamps and the priority Tx queue, which the research marks as needs of a flight controller, are not in the RTL yet. The 80-tq nominal ceiling is no obstacle at 1 Mbit/s (R10), but the clamp policy (R11) matters on a small drone where a wrong bit rate disturbs every other node.

## 6. Suggested order

1. Fix R1 to R5 in the BSP and EML (small, local); decide R6 and R7 against the ISO text.
2. Get a working simulation: the Verilator link failure here is an environment problem (`ld returned 5`, truncated executable); the testbench in `research/rtl_review_tb/` can then be run in MODE 0 and MODE 1, and extended with a second node model for R3, R6 and R7.
3. Add a stated rule for `i_bus_off` at the top (R4) and for the Tx handshake latency (R14).
4. Decide R8 to R11 in the HDS (counter width, safety duplicate, prescaler policy, clamp policy).
5. Only then write the missing blocks; each of them will otherwise inherit these behaviors.
