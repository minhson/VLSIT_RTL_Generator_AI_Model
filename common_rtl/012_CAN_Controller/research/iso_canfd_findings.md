# Historical ISO 11898-1:2015 CAN FD findings from open sources

**Status (2026-11-07):** This file is an archival record of earlier research against ISO 11898-1:2015 and open sources. The user has since supplied ISO 11898-1:2024. For current Classical CAN and ISO FD requirements, use `iso_11898_1_2024_technical_extract.md` and REF-007 in the HDS. Do not use unresolved statements below to override the 2024 source. Bosch CAN FD Specification 1.0 (2012) remains relevant only to the separate non-ISO profile.

The earlier open-source findings are retained to preserve research history and context. In particular, implementation behavior from an open core or vendor manual is not normative protocol evidence.

## 1. How to read the status column

| Status | Meaning |
|---|---|
| **CONFIRMED-PRIMARY** | Stated in a Bosch document that was read in full text: the converted Bosch specifications in `md_doc` (`vlsit_can_bosch_can_spec_2_0.md`, `vlsit_can_bosch_canfd_spec_1_0.md`) or the two Bosch conference papers (S3, S4) |
| **CONFIRMED** | Stated by at least two independent sources that agree (Bosch paper, vendor manual, Linux kernel documentation, CiA) |
| **LIKELY** | One source only, or a direct consequence of confirmed facts (the derivation is shown) |
| **UNVERIFIED** | No read source states it; it comes from memory, a search snippet, or a hypothesis. Do **not** write it in the specification as a fact |

Important: Bosch CAN FD Specification **1.0 (2012) is the non-ISO variant**. ISO 11898-1:2015 differs from it. The text of
the 2012 specification is therefore a primary source for the non-ISO behavior only, and for ISO only where another source
says the behavior is unchanged.

## 2. Sources

| ID | Source | What was read | Reliability |
|---|---|---|---|
| S1 | Bosch, CAN with Flexible Data-Rate Specification 1.0 (2012-04-17), converted text previously consulted; source file absent from the current project folder | Full text (34 pages; not re-auditable in this package) | Intended primary source, non-ISO |
| S2 | Bosch, CAN Specification 2.0 (1991), converted text previously consulted; source file absent from the current project folder | Full text (72 pages; not re-auditable in this package) | Intended primary source, classical CAN |
| S3 | Mutter and Hartwich (Bosch), *Advantages of CAN FD error detection mechanisms compared to Classical CAN*, iCC 2015 | Full text (extracted from the PDF) | Primary Bosch, written for ISO CAN FD |
| S4 | Hartwich (Bosch), *Bit Time Requirements for CAN FD*, iCC 2013 | Full text (extracted from the PDF) | Primary Bosch, written while FD was entering ISO 11898-1 |
| S5 | Microchip CAN FD controller manual, section "ISO vs. Non-ISO CRC" and section "Transmitter Delay Compensation" (online docs) | Pages fetched | Vendor manual of a controller |
| S6 | Linux kernel documentation `networking/can` (SocketCAN) | Page fetched | Software view (ISO is the default) |
| S7 | Linux kernel patch "can: length: fix bitstuffing count" (quotes ISO 11898-1:2015 clauses 10.4.2.6 and 10.5) | Page fetched | Quotes the ISO text |
| S8 | CAN in Automation (CiA) pages on CAN FD and CRC | **Search-result summaries only** (the pages themselves returned 404 or a certificate error) | Secondary, snippet |
| S9 | CRC catalogues: crc-calc.com guide, compu-tools.com, GitHub `crc17-canfd-pure` | Pages fetched or search snippets | Third-party, no ISO/non-ISO distinction |
| S10 | Wikipedia, CAN FD | Page fetched | Tertiary; silent on ISO details |
| S11 | Texas Instruments MCAN documentation (TDC) | Search snippet | Secondary |
| S12 | Bosch patent US 10334089 B2 (family EP3189630B1, WO2016034350A1, CN107148760B, DE102015209201A1), read on Google Patents (HTML) | Abstract, claims 1/6/7 and problem statement | Bibliographic and legal status data are Google's estimates, not legal conclusions |
| S13 | Vector e-learning (CRC polynomials) | Search snippet | Secondary |
| S14 | CTU CAN FD IP Core Datasheet v2.0, September 2016 (Ondrej Ille, CTU Prague), GitHub mirror `antmicro/ctucanfd_ip_core`, `doc/datasheets/Datasheet_v2_0.pdf`, 2,791,511 bytes, 80 pages | Full text extracted | Open IP, FPGA-proven, implements ISO and non-ISO CAN FD; early version, written before the ISO standard was final |
| S15 | Microchip, MCP25XXFD CAN FD Controller Module Family Reference Manual, DS20005678E, Rev. E (2020), [official PDF](https://ww1.microchip.com/downloads/aemDocuments/documents/OTH/ProductDocuments/ReferenceManuals/MCP25XXFD-CAN-FD-Controller-Module-Family-Reference-Manual-DS20005678E.pdf) | §3.4 and Tables 3-1/3-2; TSEG2 ranges and segment definitions | Manufacturer implementation reference; informative only, not protocol authority |

## 3. Feature list

### 3.1 Frame format

| ID | Statement | Status | Sources | Note for the specification |
|---|---|---|---|---|
| ISO-001 | CAN FD supplements classical CAN; classical frame formats are unchanged and are now called "Classical Frame Formats" | CONFIRMED | S4, S3 | A controller supports both formats |
| ISO-002 | Field names changed from the 2012 text to ISO: bit EDL is now **FDF**, the reserved bit r0 after FDF is **res**, the reserved bit r1 at the position of the classical RTR bit is **RRS**; the function is the same | CONFIRMED-PRIMARY | S4 (text), S1 (old names) | Use the ISO names in the specification (FDF, res, RRS) |
| ISO-003 | FD frame fields in order: SOF, identifier (11 or 29 bits), RRS (dominant), IDE, FDF (recessive), res (dominant), BRS, ESI, DLC (4 bits), data (0 to 64 bytes), stuff count (ISO), CRC, CRC delimiter, ACK slot, ACK delimiter, EOF | CONFIRMED | S1 (old names, no stuff count), S4 figure, S3 figure, S10 | The extended identifier has SRR before IDE as in classical CAN |
| ISO-004 | There is **no remote frame** and no RTR bit in the FD format. A remote frame can be sent only in classical format | CONFIRMED-PRIMARY | S1 | A FD node still sends classical remote frames |
| ISO-005 | DLC coding: codes 0 to 8 are 0 to 8 bytes; 9, 10, 11, 12, 13, 14, 15 are 12, 16, 20, 24, 32, 48, 64 bytes. In classical frames codes 9 to 15 mean 8 bytes | CONFIRMED | S1, S10, S6 (helpers `can_fd_dlc2len`), S3 | |
| ISO-006 | BRS recessive: the bit rate is switched; BRS dominant: the whole frame stays at the nominal rate. ESI is dominant for an error-active transmitter and recessive for an error-passive one | CONFIRMED-PRIMARY | S1 | |
| ISO-007 | The reserved bit res must be dominant. A recessive res is a **form error**, unless the node is configured for protocol exception: then the receiver enters the **protocol exception state** until the bus is idle again (so that future frame formats are tolerated) | CONFIRMED-PRIMARY | S3 | Protocol exception is **not** in S1. The details of bus-idle detection and transmit behavior are UNVERIFIED (ISO-032) |
| ISO-008 | Three kinds of node exist: "FD enabled", "FD tolerant" (do not disturb FD frames) and legacy. A legacy classical-only node signals an error when it sees an FD frame | CONFIRMED | S4 | A configuration bit "protocol exception on" selects tolerant behavior |
| ISO-009 | A controller may support only a subset of data lengths, but must acknowledge and filter longer frames, discard the surplus bytes, and pad a longer transmit frame with a pattern that causes no stuff bits (example 0xCC) | CONFIRMED-PRIMARY | S1 section 9 | Applies to a controller with a smaller buffer |

### 3.2 Bit stuffing, CRC and stuff count (the main ISO changes)

| ID | Statement | Status | Sources | Note for the specification |
|---|---|---|---|---|
| ISO-010 | Dynamic stuffing: after five equal bits the transmitter inserts one inverse bit; applies from SOF to the end of the data field in FD frames. A receiver detects a stuff error on the sixth equal bit | CONFIRMED-PRIMARY | S1, S3 | |
| ISO-011 | In the FD **CRC field** fixed stuff bits replace dynamic stuffing: the value is the inverse of the preceding bit; a receiver detects a stuff error (format error) if a fixed stuff bit equals its predecessor | CONFIRMED-PRIMARY | S1, S3 | |
| ISO-012 | Non-ISO (2012): one fixed stuff bit **before the first CRC bit** and one after each fourth CRC bit. Count: 1 + 4 = **5** for CRC17 and 1 + 5 = **6** for CRC21 | S1 states the rule; the counts are LIKELY (derived) | S1 | Needed only for non-ISO support |
| ISO-013 | ISO: one fixed stuff bit **before the first bit of the stuff count**, then one after each fourth bit of the "CRC field" (stuff count plus CRC). Count = 1 + floor((4 + nCRC) / 4) = **6** for CRC17, **7** for CRC21 | CONFIRMED | S7 (quotes ISO 11898-1:2015 10.5), S3 ("once at the start of the CRC field and then after each fourth bit"), S8 | This is the main reason the ISO frame is longer by one fixed stuff bit and the 4-bit stuff count |
| ISO-014 | **Stuff count** (ISO only): the number of dynamic stuff bits counted by the transmitter, **modulo 8**, sent as a **3-bit Gray code followed by a parity bit** (4 bits) at the beginning of the CRC field; the fixed stuff bits are not counted. Every receiver compares it with its own count; a mismatch is handled like a CRC error | CONFIRMED | S3, S5, S7, S8 | Not present in the 2012 specification (S1 has no stuff count); added during ISO standardization |
| ISO-014a | The CTU core counts stuff bits modulo 8 in both the transmitter and the receiver; in ISO mode the count stops at the stuff count field, in non-ISO FD and classical CAN the stuff bits are counted to the end of the frame (a status counter, not a frame field). Its status register shows the count binary, **not** Gray coded as the ISO frame field is | LIKELY (one datasheet) | S14 | Confirms the modulo-8 counter; the Gray coding is only for the frame field |
| ISO-015 | Coding of the Gray code: standard reflected binary Gray code (0 to 7 as 000, 001, 011, 010, 110, 111, 101, 100) | **UNVERIFIED** (the sources say only "Gray-coded") | none | Ask for confirmation; the reflected code is the usual meaning |
| ISO-016 | Parity of the stuff count: **even** or **odd** | **UNVERIFIED** (the sources say only "with a parity bit") | none | Needed to write the bit sequence; to be confirmed from ISO or a conformance reference |
| ISO-017 | Which dynamic stuff bits are counted at the boundary between the data field and the stuff count (the stuff bit that follows five equal bits at the end of the data field, and the fixed stuff bit before the stuff count) | **UNVERIFIED** | S3 says "number of dynamic stuff bits" and "fixed stuff bits are not counted" | Likely: all dynamic stuff bits from SOF to the end of the data field, including a trailing one; confirm |
| ISO-018 | CRC lengths and selection: CRC15 for classical frames, **CRC17 for FD frames with up to 16 data bytes**, **CRC21 for more than 16 bytes**. The three CRCs are computed concurrently from SOF in all nodes; the transmitter sends the one selected by the frame format and DLC | CONFIRMED | S1 (text), S3, S5, S10, S6 | |
| ISO-019 | Polynomials: CRC15 = 0xC599 (x15+x14+x10+x8+x7+x4+x3+1); CRC17 = 0x3685B including the top bit, i.e. x17+x16+x14+x13+x11+x6+x4+x3+x1+1 (0x1685B without the x17 term); CRC21 = 0x302899, i.e. x21+x20+x13+x11+x7+x4+x3+1 (0x102899 without the x21 term). Hamming distance 6 | CONFIRMED-PRIMARY | S1 (text), S9, S13 | A CiA search snippet listed CRC17 without the x3 term; this contradicts S1 and S9 and is treated as a snippet error |
| ISO-020 | CRC input: SOF, arbitration field, control field and data field, **including the dynamic stuff bits** in FD frames (classical frames: stuff bits not included); then nCRC zero bits are appended | CONFIRMED-PRIMARY | S1, S3 | The ISO CRC also covers the stuff count? **UNVERIFIED**: S3 says "inclusion of dynamic stuff bits into the CRC"; whether the stuff count bits enter the CRC is not stated |
| ISO-021 | CRC register initial value, non-ISO: **0** | CONFIRMED-PRIMARY | S1 (`CRC_RG = 0`) | |
| ISO-022 | CRC register initial value, **ISO**: the CTU CAN FD IP core datasheet v2.0 (September 2016; an open core that implements ISO FD and non-ISO FD with a configuration bit) states that ISO FD and non-ISO FD differ **in the highest bit of the CRC shift register initialization**, so the ISO register starts with its most significant bit set and the non-ISO register starts at 0. The exact value (only the top bit set, in each of the three registers) is not written out. Catalogues that list init = 0 do not name the variant; a Bosch patent snippet mentions an initialization vector "1...0" | LIKELY (one core datasheet, consistent with the patent hint) | S14 (CTU datasheet), S12, S9 | Take as initial value 1 followed by zeros: 0x10000 for CRC17 and 0x100000 for CRC21 (the classical CRC15 is assumed to stay 0, UNVERIFIED); confirm with a test vector (D1) |
| ISO-023 | Reason for the ISO change: a CRC problem was found in ISO/CD 11898-1 (2014-08); the task force solved it by changing the FD frame format (stuff count) | LIKELY | S8 snippet, S3 ("improvement (3) was introduced during the ISO standardization process") | |
| ISO-024 | ISO and non-ISO CAN FD are **not interoperable**; CiA says never mix them. Controllers offer a switch: Microchip `ISOCRCEN`, Linux `fd-non-iso` (default ISO), STM32 and CTU "non-ISO" bits | CONFIRMED | S5, S6, S8 | The controller needs a static mode bit (ISO or non-ISO) |
| ISO-025 | On a CRC error or stuff count mismatch the receiver does not acknowledge and sends the error frame after the ACK delimiter | CONFIRMED-PRIMARY | S3 | |

### 3.3 Bit timing, bit rate switching, transmitter delay compensation

| ID | Statement | Status | Sources | Note for the specification |
|---|---|---|---|---|
| ISO-026 | Two bit time configurations: the nominal bit time (arbitration phase, ACK, EOF, error frames) and the data bit time (data phase). The data phase starts at the BRS bit sample point and ends at the CRC delimiter sample point (or at an error). The BRS and CRC delimiter bits have an intermediate length: their sum equals one nominal plus one data bit | CONFIRMED-PRIMARY | S1 section 8, S4 | |
| ISO-027 | Time segments (2012 text): SYNC_SEG = 1 tq; nominal PROP_SEG and PHASE_SEG1 programmable 1 to 32 or more tq; data PROP_SEG 0 to 8 tq, data PHASE_SEG1 1 to 8 tq; PHASE_SEG2 = max(PHASE_SEG1, information processing time), information processing time at most 2 tq; SJW as in classical CAN | CONFIRMED-PRIMARY (for the 2012 text) | S1 | Ranges in ISO 11898-1:2015 may be wider: **UNVERIFIED**. Vendor controllers use larger fields (not an ISO statement) |
| ISO-028 | A hard synchronization is done at the edge from FDF to res, so that a node that lost arbitration just before FDF is synchronized completely | CONFIRMED | S4 | |
| ISO-029 | Format detection (FDF) and bit rate switching (BRS) are separate; a frame can be FD format at the nominal bit rate (BRS dominant) | CONFIRMED | S4, S1 | |
| ISO-030 | **Transmitter delay compensation (TDC)** is used only by the transmitter in the data phase. The delay TRV_DELAY is measured in each transmitted frame **at the edge from the FDF (EDL) bit to the res (r0) bit**, between the transmitted edge and the received edge. The **secondary sample point** SSP = TRV_DELAY + an offset (for example half the data bit), rounded down to a whole time quantum; it may fall after the end of the transmitted bit. At the SSP the transmitted bit is compared with the received bit; the bit value at the normal sample point is ignored. A bit error found at the SSP is acted on at the next normal sample point | CONFIRMED-PRIMARY | S1 section 8.1 (2012), S5, S11, S6 (SSP = TDCV + TDCO) | In the 2012 text TDC is **optional**; in ISO 11898-1:2015 it is described in detail (S11) and Bosch (S3) lists the secondary sample point for bit monitoring. Whether ISO makes it mandatory is UNVERIFIED |
| ISO-031 | Vendor register form: SSP = TDCV[5:0] + TDCO[6:0] (measured value, offset); software can set auto mode (device measures TDCV, user sets TDCO) or manual mode; an optional filter window TDCF exists | LIKELY (vendor feature, not an ISO register) | S5, S6, S11 | Field widths are an implementation choice |
| ISO-032 | Protocol exception: how many recessive bits mean "bus idle" before the node resumes, and whether a transmitter in the same state behaves differently | **UNVERIFIED** | S3 gives only the principle | Choose a rule with the user |
| ISO-033 | Bit rates: nominal at most 1 Mbit/s; the data rate must be at least the nominal rate; 2 Mbit/s with first transceivers, 5 Mbit/s and 8 Mbit/s with newer or signal-improvement transceivers; no ISO-fixed maximum was found | CONFIRMED (the numbers), **UNVERIFIED** (ISO limit) | S6, S4, S10 | The IP limit is set by the clocks and the transceiver, not by the protocol |
| ISO-034 | Resynchronization: the longest time between two edges that can be used is bounded by stuffing: 10 bits according to S4 (the text of S2 and S1 quotes 29 bit times for the classical case including error and overload flags) | CONFIRMED-PRIMARY for the quoted numbers; which number applies to which phase is UNVERIFIED | S4, S2, S1 | Used for the oscillator tolerance formulas |
| ISO-035 | Oscillator tolerance and the exact formulas for the data phase | **UNVERIFIED** (S4 gives the principle: a tolerance of 1 % can accumulate to 20 % of a bit between edges) | S4 | Write the IP requirement as a bit timing limit, not as a tolerance claim |

### 3.4 Error handling, fault confinement, conformance

| ID | Statement | Status | Sources |
|---|---|---|---|
| ISO-036 | The error detection mechanisms are bit monitoring, frame format check, CRC, acknowledgement check, stuff rule check, and (FD) stuff count check | CONFIRMED-PRIMARY | S3 |
| ISO-037 | Error signalling (error frame, delimiter, overload frame) and fault confinement (error active, error passive, bus-off with counters) are the classical rules. FD-specific counter rules: not read | LIKELY (classical rules apply; S1 section 7 repeats them) | S1, S2 |
| ISO-038 | The error frame and the overload frame are sent at the nominal bit rate | CONFIRMED-PRIMARY | S1 |
| ISO-039 | Conformance testing: ISO 16845 covers the three node types | CONFIRMED | S4 |
| ISO-040 | A CAN protocol licence from Bosch is needed for every CAN FD implementation on silicon | CONFIRMED | Bosch site, OpenCores CAN README |
| ISO-041 | Bosch patent US 10334089 B2 (priority 2014-09-03, granted 2019-06-25, Google status "Active", estimated expiry 2035-10-22, **not a legal determination**) explains why a non-zero CRC initialization exists: with an all-zero initial CRC, a CAN FD frame whose identifier starts with four dominant bits can be misread at the start (for example identifier 0x001 received as 0x081) and the CRC does not catch it. Claim 1 does not claim an initial value: it claims inserting a "1" into the CRC generator when the interim CRC value is all zeros; the "1...0" initialization vector is described as a related option | CONFIRMED (the statements of the page); whether ISO 11898-1:2015 uses the init vector, the insertion, or both is UNVERIFIED | S12 | Supports ISO-022 (top bit set); keep the choice open until a test vector confirms it |

## 4. What differs between non-ISO (Bosch 2012) and ISO (2015)

| Item | Non-ISO (S1) | ISO 11898-1:2015 | Status |
|---|---|---|---|
| Bit names | EDL, r0, r1 | FDF, res, RRS | CONFIRMED |
| Stuff count field (3-bit Gray + parity) | absent | present, first 4 bits of the CRC field | CONFIRMED |
| Fixed stuff bit before the first field bit | before the first CRC bit | before the first stuff count bit | CONFIRMED |
| Number of fixed stuff bits | 5 (CRC17), 6 (CRC21) | 6 (CRC17), 7 (CRC21) | CONFIRMED for ISO, LIKELY for non-ISO |
| CRC initial value | 0 | **not known** (possibly with the top bit set) | UNVERIFIED |
| CRC polynomials, lengths, selection | CRC17/CRC21 | same | CONFIRMED |
| Dynamic stuff bits in the CRC | yes | yes | CONFIRMED |
| Protocol exception (tolerant of future formats) | absent | present (configurable) | CONFIRMED |
| TDC | optional, described in section 8.1 | detailed (secondary sample point) | CONFIRMED that it exists |
| Interoperability | | not interoperable with non-ISO | CONFIRMED |

## 5. Points to discuss with the designer before the specification is written

| No. | Question | Why it matters | Proposal |
|---|---|---|---|
| D1 | Which source decides the **ISO CRC initial value** (ISO-022)? | A wrong value makes the IP unusable with ISO nodes | Use "top bit set, rest 0" (CTU datasheet), keep it a localparam and verify with a known-good ISO frame from a conformance reference; record the confidence in section 20 until then |
| D2 | Parity of the stuff count and exact Gray mapping (ISO-015, ISO-016) | The bit sequence of every ISO FD frame depends on it | Same as D1; both come from one ISO or reference excerpt |
| D3 | Is a dynamic stuff bit at the end of the data field counted (ISO-017)? Is the stuff count part of the CRC input (ISO-020)? | CRC and count value | Same as D1 |
| D4 | Is TDC mandatory in the IP (ISO-030)? What measurement edge and offset range? | Determines the maximum data bit rate (TDC is needed when the data bit time is shorter than the transceiver loop delay, S1 8.1) | Implement TDC with a measured value and an offset, enabled by a register; measurement at the FDF to res edge |
| D5 | Protocol exception rule (ISO-007, ISO-032) | Interoperability with future formats | Configurable; resume after 11 recessive bits is a common rule, **not verified** |
| D6 | Bit timing ranges (ISO-027) | Register widths, achievable rates | Use the Bosch ranges as a minimum and ask for the wider vendor ranges |
| D7 | Non-ISO mode (ISO-024): static bit or run-time bit? | Area and test effort | Static elaboration parameter plus a run-time bit that can be set only in configuration mode |

## 6. Files that tools saved while this search was made

WebFetch saved binary copies of the documents it read into `C:\Users\PC\.claude\projects\C--HQuan-102-MyGithub\<session>\tool-results\`: the NXP/Freescale CAN module reference manual (BCANPSV2, not used), the two Bosch iCC papers (S3, S4, text extracted to the scratchpad) and the Bosch patent PDF (S12, an image, not readable). They are outside the project and outside git.


## Addendum 2026-11-05: evidence from the source of the CTU CAN FD core

Source: the VHDL of the CTU CAN FD IP core (GitHub mirror antmicro/ctucanfd_ip_core, MIT-style licence), directory `src/can_core`. The core implements ISO and non-ISO FD and was proven in FPGA and silicon; this is evidence of what a working node does, not a reading of ISO 11898-1.

| ID | Statement | File and function | Status |
|---|---|---|---|
| ISO-022a | CRC15 initial value all zero; CRC17 and CRC21: only the most significant bit is 1 in the ISO mode, all zero in the non-ISO mode | `can_crc.vhd`, `init_vect_15`, `init_vect_17`, `init_vect_21` | CONFIRMED by open core (replaces the LIKELY of ISO-022) |
| ISO-015a | Gray code of the stuff count is the standard reflected binary code | `err_detector.vhd`, table `dst_ctr_grey` | CONFIRMED by open core (replaces the UNVERIFIED of ISO-015) |
| ISO-016a | The parity bit is the XOR of the three Gray bits (even parity of the four bits) | `err_detector.vhd`, `dst_parity`, `stuff_count_ok` | CONFIRMED by open core (replaces the UNVERIFIED of ISO-016) |
| ISO-017a | The counter counts non-fixed stuff bits modulo 8 from the start of the stuffing; the fixed stuff bits are not counted | `bit_stuffing.vhd`, `bst_ctr_d`; `bit_destuffing.vhd`, `dst_ctr_d` | CONFIRMED by open core |
| ISO-020a | In the ISO mode the CRC calculation stays enabled in the stuff count state: the stuff count bits are part of the CRC input | `protocol_control_fsm.vhd`, state `s_pc_stuff_count`, `crc_enable` | CONFIRMED by open core (answers the open question of ISO-020) |
| ISO-032a | Protocol exception: a recessive res bit (FD enabled) or a recessive FDF bit (FD disabled) with the protocol exception on sets the status and leads to the bus integration of 11 recessive bits | `protocol_control_fsm.vhd`, states `s_pc_r0_fd`, `s_pc_edl_r0` | CONFIRMED by open core (replaces the UNVERIFIED of ISO-032) |
| ISO-042 | Bus-off recovery: the reintegration counter expires at 128, which is 129 sequences of 11 recessive bits | `reintegration_counter.vhd` | CONFIRMED by open core |
