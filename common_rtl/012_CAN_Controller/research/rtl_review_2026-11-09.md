# CAN Controller RTL review disposition (2026-11-09)

## Scope and evidence

This is the post-review disposition for the approved change set. The review compared the BSP/EML RTL and HDS with the supplied ISO 11898-1:2024 technical extract. Bosch CAN FD Specification 1.0 is not present in the project, so Bosch non-ISO FD behavior remains source-limited.

The approved profile set is Classic-only, ISO CAN FD, and selectable Bosch non-ISO CAN FD. Classical CAN remains supported in FD-capable builds. CAN XL is excluded from every profile.

“RTL corrected” below means the code was changed and passed static rule-check/lint. No simulation was run, so waveform-level behavior remains unverified.

## Findings

| ID | Disposition | Review result |
|---|---|---|
| R1 | RTL corrected; simulation pending | Internal and external loopback now provide a virtual dominant ACK to the transmit-side monitor. The virtual ACK does not change the physical CAN output. The self-transmitted frame can complete and enter the receive/filter path as required by REQ-FUNC-013/019. |
| R2 | RTL corrected; simulation pending | Classic DLC codes 9–15 now decode to 8 data bytes. FD DLC decoding is unchanged. |
| R3 | RTL corrected; simulation pending | The error delimiter counts from the first sampled bit after the six-bit flag for both TX and RX. It completes after eight consecutive recessive samples; any dominant sample resets the run, and a dominant sample at the final delimiter position starts a reactive overload. No role-specific delimiter-sample skip is used. Overlapping-flag and delimiter waveforms are still required. |
| R4 | Deferred to top-level integration | BSP bus-off exit waits for its i_bus_off input to fall, while EML recovery needs idle events that BSP currently produces only in integration state. No top exists to define the required recovery handshake/masking. Do not connect the leaves directly without resolving this contract. |
| R5 | RTL and HDS corrected; simulation pending | A transmit error now generates one generic +8 event, avoiding the previous +16 double count. The passive-transmitter ACK exception is deferred until the passive flag has been observed. Exception 2 suppresses TEC only for the specified arbitration stuff-error wire condition. Dedicated TX/RX events now represent bit errors while sending active error/overload flags. HDS §10.8.3 and TEST-040 describe the cases. |
| R6 | Deferred to waveform confirmation | No RTL change. The Classic CRC-error flag start still needs comparison against WF-071 and the exact sample/bit-transition convention before deciding whether it is late. |
| R7 | RTL and HDS corrected; simulation pending | A dominant SOF at the third intermission bit is accepted directly while the FSM is in INTERM with the third-bit count selected. No pending-boundary state is needed because detection and the state transition use the same bus sample. |
| R8 | RTL and HDS corrected; simulation pending | REC can now reach and saturate at 255; error-passive begins at 128. +8 REC events saturate at 255. A successful reception sets REC above 127 to the product-selected value 127, per the ISO rule and HDS decision. |
| R9 | HDS risk classification corrected; RTL unchanged | The EML mirror registers use the same next-state logic as the primary counters. They can detect a stored-state mismatch but cannot detect a common fault in that logic. HDS no longer grants independent logic-fault coverage credit. Independent counter-update logic needs a separate design review before any FMEDA credit. |
| R10 | Review arithmetic corrected; TDC gate deferred | The non-XL Table 13 timing ranges are not the issue claimed in the original review. At 40 MHz, m=2 and 80 tq produce 250 kbit/s nominal timing. At 80 MHz with m<=2, 250 kbit/s would require 160 tq, beyond the 80-tq nominal maximum; this is a product clock/TDC constraint, not a general protocol-range defect. The missing RTL qualification of TDC by m=1/2 remains open until top-level integration. |
| R11 | Not an RTL defect | Scalar timing clamp plus cfg_fix is the approved behavior in REQ-ERR-005/DEC-074. Illegal cross-field tuples keep INIT asserted. No change was made. |
| R12 | PPA risk, not a functional finding | The two 287-entry delay histories imply roughly 574 state bits plus selection logic. The actual cell area and timing depend on synthesis, library, and constraints; no PPA claim is made. |
| R13 | Integration dependency | The BSP does not consume all Tx metadata because the Tx handler is absent. This is not a leaf-module bug. The handler must retain and use the metadata needed for Tx events and message markers. The existing unused-field lint warning remains visible. |
| R14 | Requirement exists; implementation proof deferred | REQ-MSG-016 already requires the next candidate to start no later than the end of intermission. The missing Tx handler/top prevents proving CDC prefetch latency meets that requirement. |

## RTL changes

- rtl/m_canfd_bsp.sv: virtual loopback ACK, Classic DLC mapping, consecutive-recessive error delimiter without a role-specific sample skip, direct third-intermission SOF acceptance, and role/exception-qualified counter events.
- rtl/m_canfd_eml.sv: 8-bit REC behavior through 255, passive threshold at 128, saturation on +8, and successful-reception recovery from REC above 127.
- VLSIT_CAN_FD_CONTROLLER_HDS.md: clarified profiles, loopback ACK, DLC mapping, delimiter/SOF behavior, counter rules, safety mirror limits, and approved deferrals.

## Static validation

- VLSIT RTL rule checker: 2 files, 0 errors, 29 warnings. The warning count matches the pre-fix baseline; warning classes are existing comment, hierarchy, naming, and parameter-literal findings.
- Verilator BSP lint: 0 errors, 1 existing UNUSEDSIGNAL warning for unused Tx-bundle fields.
- Verilator EML lint: 0 errors, 0 warnings.
- Simulation was not run. The earlier diagnostic testbench is not assertion-based verification evidence.
- Bosch non-ISO FD conformance is not claimed because its normative source is unavailable.

Logs: research/rtl_review_2026-11-09_post_fix_rule_check.md, research/rtl_review_2026-11-09_post_fix_bsp_lint_final_2.log, and research/rtl_review_2026-11-09_post_fix_eml_lint_final_2.log.

