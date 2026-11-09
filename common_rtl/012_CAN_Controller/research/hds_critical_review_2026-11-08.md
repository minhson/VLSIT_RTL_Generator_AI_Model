# Critical review of the CAN FD Controller HDS (v0.4) against Classic CAN and commercial IP

Date: 2026-11-08. Reviewed file: `VLSIT_CAN_FD_CONTROLLER_HDS.md` (v0.4, 87 decisions, 130 requirements, 69 tests, 29 assertions).
This is a review only: **the HDS, CSR and RTL were not changed.**

## 1. What this review rests on, and what it does not

| Source | Status |
|---|---|
| The HDS itself and `research/iso_11898_1_2024_technical_extract.md` | Read in this run. The standard text is not available to this review; only the project extract is. |
| `research/commercial_canfd_ip_features.md` (Bosch M_CAN manual 3.3.1, white paper, Gaisler GRCANFD, CTU datasheet) | Read earlier from the full documents. Strongest evidence for commercial IP. |
| Web search summaries of 2026-11-08 (STM32H7 FDCAN, NXP FlexCAN, Renesas RS-CANFD, a CAN XL IP press release) | **Secondary and partial**; marked "web" below. No reference manual was opened. |
| Statements marked "general knowledge" | From the reviewer's memory; not verified in this run. Check before relying on them. |
| Numbers derived from HDS rules (section 3) | Computed here from the HDS text; the arithmetic is shown. |

Not done: no RTL was simulated, no timing or area was measured, no commercial datasheet beyond the files above was read in full.

## 2. Comparison table

| Attribute | Classic CAN controller (general knowledge: for example STM32 bxCAN, MCP2515 class) | Commercial CAN FD IP (source) | This HDS |
|---|---|---|---|
| Protocol | CAN 2.0A/B, up to 1 Mbit/s, 8 bytes, CRC15 | ISO 11898-1:2015 FD up to 64 bytes (M_CAN, GRCANFD); NXP FlexCAN lists ISO 11898-1, FD and 2.0B (web) | CC + ISO FD 11898-1:2024, optional non-ISO FD; **no CAN XL** |
| Message storage | Few mailboxes (about 3 Tx, 2 Rx FIFOs of 3) in the IP | M_CAN: message RAM **outside** the core (128 + 64 filters, 2 Rx FIFOs of 64, 64 Rx buffers, 32 Tx buffers); the same sizes on STM32H7 with a 10 KB shared RAM (web); GRCANFD: circular buffers in external memory with DMA | External RAM, same M_CAN-class sizes, DMA request/ack; software reads the RAM directly (DEC-073) |
| Filtering | Mask/list banks | Range, dual, mask; high-priority flag (M_CAN) | Same four types, list walked sequentially after the frame ends (DEC-026) |
| Tx scheduling | Mailbox priority | By identifier, cancel, event FIFO with timestamp (M_CAN); Renesas adds TX queue and **gateway** mode (web) | By identifier or FIFO, cancel, event FIFO; **no forwarding path** |
| FD bit timing | n/a | Separate nominal and data prescaler; data prescaler 1 or 2 with TDC (M_CAN, from C1); TDC always measures | **One common prescaler** m = 1..32; TDC only with m = 1 or 2; total bit time capped at 80 tq nominal / 25 tq data (REQ-BTL-001/002/005) |
| Timestamp | Optional | 16-bit counter, external TSU (M_CAN); 64-bit in CTU | 16/32-bit, external vector, SOF sample point (DEC-068) |
| Power / wake | Sleep, wake on bus | M_CAN clock stop; NXP **pretended networking** (web) | Clock stop, two acknowledges, bit-serial wake-up filter (Classic frames only) |
| Time-triggered | Rare | Bosch TTCAN module (ISO 11898-4) | "TTCAN-like", secondary sources, **no ISO 11898-4 claim** |
| Safety | None | M_CAN: RAM error input + watchdog; a third-party CAN XL IP is announced as ISO 26262 ASIL-B certified (web press release, unverified) | 14 selectable mechanisms, ASIL-D target, **no ASIL claim**, FMEDA inputs assumed |
| Conformance evidence | Vendor test | Vendors state ISO 16845-1 and interoperability tests (general knowledge, unverified here) | **No mention of ISO 16845-1** (0 hits); own reference models |

## 3. Findings, ranked

### High

**H1. An acceptance test contradicts its own requirement (loss of received frames).**
`TEST-031` expects "No lost message" at the highest rates with the slowest message RAM, while `REQ-PERF-001` states "no loss-free sustained-throughput guarantee" and PERF-001/002 are "Not a current guarantee" (TBD-007, DEC-065). Section 1.2 promises "frames back to back at 100 % bus load" and the AUTOSAR needs recorded in the research (A-012, no loss at 100 % bus load) are not in the HDS (0 hits of SRS_Can_01125).
Sizing the missing guarantee is a one-line formula: the BUS side needs `f_BUS >= N_clk / T_frame_min`, with `N_clk = n_filter x (2 + W) + n_words x (2 + W)` from REQ-MSG-014. Illustration, not a result: a minimum Classic frame with 0 data bytes is 47 bit times (44 + 3 intermission), 47 us at 1 Mbit/s; a minimum FD frame at 1 Mbit/s with a 5 Mbit/s data phase is of the order of 35 us. With 128 standard filters, W = 3 and about 20 element words, N_clk is about 700 clocks, which is 14 us at 50 MHz and 35 us at 20 MHz: **at a 20 MHz BUS clock the budget is already equal to the shortest frame.**
*Action:* either state a minimum `f_BUS / f_CAN` and RAM service bound as a requirement (and make TEST-031 test exactly that), or change TEST-031 to expect `ovr` above the bound. A spec that tests what it does not promise cannot close.

**H2. Bit-timing ceilings make some mainstream FD configurations impossible.**
The HDS enforces total bit time 8..80 tq (nominal) and 5..25 tq (data), one prescaler for both phases, and TDC only with m = 1 or 2 (REQ-BTL-001, 002, 005). Derived consequences (arithmetic: `f_nominal_min = f_CAN / (m x 80)`, with TDC m <= 2):

| CAN clock | m | tq | Slowest nominal rate while TDC is usable | 250 kbit/s nominal + 5 Mbit/s data |
|---|---|---|---|---|
| 40 MHz | 1 | 25 ns | 500 kbit/s | Not possible (needs 160 tq) |
| 40 MHz | 2 | 50 ns | 250 kbit/s | Not possible for 5 Mbit/s (data bit 4 tq, below the 5 tq minimum) |
| 80 MHz | 1 | 12.5 ns | 1 Mbit/s | Not possible |
| 80 MHz | 2 | 25 ns | 500 kbit/s; 5 Mbit/s data is 8 tq | Not possible |

The HDS's own worked example (80 MHz, nominal 500 kbit/s at m = 4, data 5 Mbit/s at m = 1) is **rejected by REQ-BTL-002** because the prescalers differ. That is, the example in 10.6.1 cannot be configured. A data bit of 8 tq also limits the sample point to steps of 12.5 %. M_CAN, per the research file, keeps the data prescaler separate (0..31, 0 or 1 with TDC) so nominal 250 kbit/s with a 5 Mbit/s data phase is possible there (nominal prescaler width: general knowledge, 9 bits).
Further inconsistency: `nprop` has 9 bits for 384 tq, but a nominal total of 80 tq with PHASE_SEG1 >= 1 and PHASE_SEG2 >= 2 makes every `nprop` above 76 illegal, and the 8-bit `dprop` (documented range 0..128) is usable only up to 21 (total 25); the rest of those CSR ranges is dead.
*Open:* the extract does not contain the 8..80 and 5..25 totals; only PROP/PHASE ranges. Confirm in the standard whether these are **minimum** ranges a node must support. If they are floors, the HDS has turned a floor into a ceiling, which no commercial IP in the comparison does.
*Action:* confirm the source; separate the nominal prescaler (cost: one 9-bit field and one counter) or lift the total-bit-time ceiling; correct the 10.6.1 worked example whichever way it is decided.

**H3. No conformance test plan; the reference models share the author.**
The verification plan (section 15) relies on reference models written for this project and on directed tests of the author's reading. ISO 16845-1 (the CAN FD conformance test plan) is not mentioned (0 hits), no interoperability test with a third-party node or a known-good core is planned, TBD-030 (oscillator tolerance) and TBD-031 (edge filter model known to be wrong) are deferred (DEC-067), and the README states that no conformance claim is made. For a controller that targets automotive SoCs, the shipped evidence of the commercial cores is conformance, not a unit test count (general knowledge). A model and an RTL written from the same text fail together.
*Action:* add ISO 16845-1 as a stated verification target, with a decision on the source of the tests (licence, or a reusable open suite; whether the CTU project's tests are reusable was **not** checked), and a cross-check against an independent core (the CTU core is already in the research) at frame level.

**H4. Safety claims and structure.**
(a) The stop reaction is INIT in the CAN domain (REQ-SAFE-006); I found no independent output gate after the core in sections 6 and 18, so a stuck protocol core defeats its own stop. A one-gate Tx kill path in the top, driven by the safe-state flag, is cheap and is the first thing a safety assessor asks for (SG-03). *Confirm by reading section 18.3.2; the search found none.*
(b) 14 build parameters give 2^14 combinations; the plan builds CFG-SAFE, CFG-SAFE-L1 and CFG-SAFE-DUP only. The interactions (for example `AUTO_MASK` with a mechanism that flags a start-up condition, ASM-023) are not enumerated.
(c) The FMEDA worksheet gives a 99.4 % single-point metric at level 2. It rests on assumed coverage of SM-16 (80 %) and was tuned in the same session to close a gap (without SM-16 the same formula gives 98.5 %). It is labeled assumed everywhere, but a number of this kind is quoted out of context; consider removing the headline figure from 18.5.1 until real inputs exist.
(d) Section 18 now says "no ASIL target, compliance or certification claim" and "No quantitative safety coverage is claimed" (DEC-066), yet 18.5.1 still tabulates single-point and latent metrics (99.4 % at level 2) and the three "lessons" that depend on them. The disclaimer and the table contradict each other for any reader who sees only one. A commercial IP names the level it is certified or assessed to (the press release found names ASIL-B, unverified).

### Medium

**M1. CAN XL excluded in a 2026 design.** ISO 11898-1:2024 now defines an implementation option with CC, FD and XL together (web, abstract only); an XL controller IP was announced in 2024 (web, press release). The HDS excludes XL (DEC recorded in 1.1) which is a legitimate scope decision, but it is not argued against the 5–10 year life of an automotive SoC. At minimum record which interfaces would change for XL (frame record, element size beyond 64 bytes (XL payload up to 2048 bytes: general knowledge), RAM layout, bit timing) so the 4×32-bit frame bundle of DEC-086 and the RAM element format do not need a second incompatible redesign.

**M2. TDC history is brute force (DEC-084).** A 287-entry shift history of `{qualified tx_point, tx_bit}` at minimum-tq resolution is about 574 flops. The ISO/Bosch rule limits delay plus offset to six data bits, so at most six bits are in flight; a small queue of transmitted bit values with a per-bit timer needs a few tens of flops (design hypothesis, **not** verified or modeled). Both are valid; the cost difference is the reason to decide it explicitly while PPA is undefined (PPA-001..003 "Not specified").

**M3. No forwarding path for gateway SoCs.** Renesas RS-CANFD routes frames from the receive rules to a transmit queue of another channel without the CPU (web); the HDS offers DMA only. Fine for a drone; for an automotive gateway SoC it is a stated non-goal worth writing down.

**M4. The redundant bus pair (FEAT-014) does not match the drone evidence.** The research says a Pixhawk-class board wires **two CAN controllers**; a controller with a selectable pair gives one active bus at a time and no simultaneous reception (HDS 1.4 states this). The Gaisler pair is a space-avionics feature. Value for the stated drone use is low compared with instantiating two controllers; the cost is verification of REQ-IF-006/007.

**M5. TTCAN-like profile.** About a dozen requirements, a trigger cache, 16 interrupts and an estimated 1.8 thousand flops (FMEDA input, assumed) for a profile that the HDS itself says is not ISO 11898-4 conformant, built from secondary sources (TBD-015, 016). Use in 2026 automotive CAN is low (general knowledge). It is off by default, but it is also a large share of the section 10 text and of the review burden. Consider marking it experimental or deferring it from the first RTL release.

### Low (spec hygiene)

- `FEAT-016` in the application table (1.4) still cites `REQ-SAFE-001 to REQ-SAFE-005`; the feature table cites 001..012.
- Section 20 lists resolved items (TBD-001..003, 005, 008..013 and others) under type "Decision"; the open ones (TBD-006, 029, 030, 031) are only identifiable by reading each row.
- Section 18.3.2 has a damaged sentence ("...not after the fault, the integrator, sets the flag and `o_saf_err`"): a clause was lost in an edit; the bound of the stop reaction (the one-clock claim of REQ-SAFE-006) is therefore not readable.
- Traceability: all 130 requirements have a row in section 19. By a mechanical check (ranges expanded), `REQ-MSG-020` and `REQ-TT-017` are named by no test or assertion row; `REQ-BTL-011` is covered only by "system validation". The check may miss other citation forms; it is a lead, not a verdict.
- `bo_cnt` resets to 129 while ISO needs 128 (DEC-074 explains the clamp); acceptable, but the reason for 129 rather than 128 should be one sentence in the register description.
- The document is 518 KB with 87 decisions; the decision log and the normative text are interleaved. A reader cannot tell which of the 87 still bind.

## 4. What the HDS does well (so the review is not one-sided)

- ISO 11898-1:2024 is the stated normative target, and the CRC init, stuff count, fixed stuff, CRC-error timing split (CC at EOF, FD after three bits) and reactive-overload rules are taken from it, which are the points most open-source cores get wrong.
- Feature parity with M_CAN-class IP on storage, filters, Tx scheduling, event FIFO, timestamp and DMA, with Tx-event DMA and a flush timeout (the research file does not show these in M_CAN or GRCANFD; not checked against their full manuals).
- Honest limits: no conformance, PPA or ASIL claim; deferrals recorded as DEC-067 and DEC-070; the formula check is labeled as assumed.
- Explicit CDC and reset-skew treatment (CDC-001..012, DEC-059) and reuse of the shared VLSIT CDC cells.

## 5. Suggested order of work

1. H1: decide the minimum clock ratio and RAM service bound, or change TEST-031. (small, blocks the Rx handler design)
2. H2: confirm the 8..80 / 5..25 source; decide the prescaler split before the BTL RTL is frozen (the BTL leaf exists already).
3. H4a: add the independent Tx kill gate to the top contract before the top is written.
4. H3: choose the conformance source and add it to section 15.
5. M1, M2, M3: record decisions (XL-readiness, TDC structure, gateway non-goal).
6. Hygiene items in one pass.

Sources used for the web column: STM32H7 FDCAN driver and manual copies (indicative only); NXP FlexCAN IP page and S32K community posts; Renesas RH850/RS-CANFD application notes and leaflet; ISO 11898-1:2024 catalogue abstract; a CAN XL IP press release (design-reuse). None is a primary datasheet.
