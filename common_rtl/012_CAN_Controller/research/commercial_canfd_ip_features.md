# Commercial and open CAN FD IP: features, and what a drone or UAV needs

Date: 2026-11-03. Input for section 1.3/1.4 (features and real-world applications, rule R-041), section 6 (interfaces),
section 10 (behavior) and section 13 of the CAN controller specification. Nothing here is copied from a reference IP
(rule R-012): the documents were read and the features are restated in the words of this file, with the source named.

## 1. Documents that were read

| ID | Document | Size | How it was read | Notes |
|---|---|---|---|---|
| C1 | Bosch **M_CAN User's Manual**, revision 3.3.1 (2023-03-11), `mcan_users_manual_v331.pdf`, bosch-semiconductors.com | 518,850 bytes, 95 pages | Full text extracted | The reference commercial CAN FD IP (ISO 11898-1:2015). Registers, message RAM, TDC, modes |
| C2 | Bosch **M_CAN white paper WP001** v2.0 (2015-07-01), "Functionalities and Features" | 404,167 bytes, 14 pages | Full text | Tx/Rx handler, filters, safety, power down |
| C3 | Bosch **M_CAN support of optional ISO 11898-1 features**, REL20160404 | 66,705 bytes, 3 pages | Release table read | Core release history (CAN FD 3.0.0 in 2013, update to ISO/CD in 3.1.0) |
| C4 | Bosch **M_CAN application note AN004**, bus-off recovery handling v1.0 (2019-11-29) | 177,006 bytes, 7 pages | Full text | Bus-off recovery sequence |
| C5 | Frontgrade Gaisler **GRLIB IP Core manual**, chapter 48 GRCANFD (version 2026.3, 2026-10) | 19,906,447 bytes, 2,501 pages (chapter read, about 37 pages) | Chapter text | CAN FD IP with DMA and bus redundancy for space and avionics use |
| C6 | AMD **PG223** CAN FD LogiCORE IP Product Guide, version 3.0 | online HTML | Table of contents only | Features seen only as chapter and register names |
| C9 | **CTU CAN FD IP Core Datasheet v2.0** (September 2016), GitHub mirror `antmicro/ctucanfd_ip_core`, `doc/datasheets/Datasheet_v2_0.pdf` | 2,791,511 bytes, 80 pages | Full text extracted | Open IP in VHDL with Linux driver; ISO and non-ISO CAN FD by a configuration bit; hardware blocks described entity by entity. An early version of the datasheet (2016) |
| C7 | Web pages and search summaries: Bosch M_CAN page, TES IP CAN FD datasheet (Feb 2025), Arasan CAN FD flyer (2017), CAST, Fraunhofer IPMS, Digital Core Design | not downloaded | Search summaries | Feature claims only; treat as marketing statements |
| C8 | PX4 CAN documentation (DroneCAN, Cyphal) | online HTML | Search summary | Application side |

The **CTU CAN FD datasheet** (C9) could not be fetched from the CTU server (not reachable from this machine); with the user's approval the GitHub mirror copy (v2.0, 2,791,511 bytes) was read instead of the approved 2,121,333-byte file.

## 2. Feature comparison

"Stated" means a read document says so. "Listed" means only a chapter or register title was seen.

| Feature | Bosch M_CAN (C1, C2) | Gaisler GRCANFD (C5) | AMD PG223 (C6) | Others (C7) |
|---|---|---|---|---|
| Standard | ISO 11898-1:2015, Classic and CAN FD up to 64 bytes; **NISO** bit selects the Bosch 2012 frame format | ISO 11898-1:2015 (2nd edition); all frame types and formats | listed: "Standards" | Arasan, Fraunhofer, TES: ISO and non-ISO |
| Host interface | 8/16/32-bit generic slave; generic master to message RAM; two clock domains (CAN clock and host clock) | APB slave for configuration; generic bus master (AHB and AXI4 wrappers) with **DMA** | AXI | TES: AMBA wrappers |
| Message storage | **Message RAM outside the core**, shared by several cores; 11-bit filters up to 128, 29-bit filters up to 64; two Rx FIFOs of up to 64 messages; up to 64 dedicated Rx buffers; up to 32 Tx buffers (dedicated, FIFO or queue); Tx event FIFO | Frames in **circular buffers in external memory** moved by DMA; internal SRAMs of 1 to 8 frames per direction | listed: TX buffers, RX FIFOs, RX mailbox | TES: single-port RAM or dual-port double buffers |
| Acceptance filtering | Range, dual ID, or mask; accept or reject; high-priority message flag | One acceptance code and mask register pair; SYNC code and mask filters | listed: acceptance filters | |
| Transmit control | Highest-priority ID goes first; cancel a request; Tx event with timestamp; single-shot (disabled automatic retransmission); wide message marker (16 bit) | Single-shot (frame is dropped, channel is disabled when arbitration is lost or an error occurs) | listed: TX cancellation | |
| Receive control | Blocking or overwrite mode when a FIFO is full; watermark; flush | Overload frame optionally generated when the Rx buffer is full | listed: RX FIFO status | |
| Timestamp | 16-bit bit-time counter, prescaler, internal or external (TSU add-on, CiA 603) | Not found in the chapter | listed: timestamp register | |
| Timeout counter | Yes (free, Tx event, Rx FIFO modes) | CANopen heartbeat timeout | | |
| Bit timing | Nominal: separate registers; data phase: prescaler 0 to 31 (0 or 1 with TDC on), DTSEG1 0 to 31 plus 1, DTSEG2 1 to 15 plus 1, DSJW 0 to 15 plus 1; the data rate must be at least the nominal rate | Nominal prescaler 0 to 255, PS1 2 to 63, PS2 2 to 16, SJW 1 to 16; separate data registers | listed: nominal and data bit timing registers | |
| Transmitter delay compensation | Always measures; SSP = measured delay + offset TDCO (0 to 127 mtq), optional filter window TDCF; sum of delay and offset below 6 data bits and at most 127 mtq; only in the data phase of a transmitter | TDC register; compensates up to 2 data bit times | not mentioned | |
| Protocol exception | Configurable (PXHD): handled as an event and the node goes to integrating state, or as a form error | not found | | |
| Modes | Restricted operation, bus monitoring, loop-back (internal and external), disable automatic retransmission, software initialization, power-down by clock stop | Listen only (silent), loop-back (internal or external), Self-ACK | listed: operating modes, sleep mode | |
| Error handling | Error counters (TEC, REC, error logging), last error codes for arbitration and data phase separately, error-passive and warning interrupts | TEC and REC visible (8 bit each); error-passive, bus-off, overrun | listed: error count and error status registers; the search summary says the fast data phase is logged separately | |
| Bus-off | Sets INIT; software clears INIT; the core waits 129 occurrences of 11 recessive bits (C4) | Automatic restart after bus-off unless disabled (DISREST) | | |
| Interrupts | Two lines, many flags, each maskable | Up to 3 lines (common and two SYNC lines) | listed | |
| Safety | Input for external message RAM parity or ECC error (stops the core), RAM watchdog on the memory interface | not found | not found | |
| Redundancy | — (two cores can be integrated) | **Two CAN interfaces (nominal and redundant), selectable by software**; transceiver enable pins | | |
| Higher layers | AUTOSAR, SAE J1939 support | **CANopen minimal set** (PDO 1 to 4, SYNC, heartbeat) with run-time switch | | |
| Add-ons | TSU (timestamp) and DMU (DMA) | — | | |
| Deliverable | VHDL RTL; message RAM, ECC and arbiter are **not** part of the core (C2) | VHDL, device drivers for RTEMS and VxWorks | | |

### 2a. CTU CAN FD core (C9), features read from the datasheet

Early version (2016), described entity by entity: one core with CAN FD, ISO/non-ISO selected by a configuration bit;
bit destuffing and stuffing with the fixed-stuff method for the CRC field and a stuff counter modulo 8 for ISO FD;
three CRC registers (CRC15, CRC17, CRC21) computed in parallel by shift registers, the ISO/non-ISO difference being the
initial value of the highest bit; transmit buffers (two instances, selected by priority); a receive buffer (true dual
port RAM) with an overrun flag; a 64-bit timestamp input used for transmit and receive times; sampling control with
nominal, data and **secondary** sampling and a transceiver delay measurement; fault confinement counters that the host
can read and write (test function), plus separate error counters for the nominal and the data phase; an optional event
logger; internal and external loop-back modes. These match the features listed for the commercial cores and add the
**writable error counters** and the **64-bit external timestamp** as design choices.

## 3. What a drone or UAV needs from a CAN FD controller

The application side comes from the PX4 documentation (C8, summary) and from general engineering knowledge; items marked
**(inference)** are mine and have to be confirmed with the designer (rule R-004, R-041).

| Need | Why a flight controller or a drone peripheral needs it | Where the commercial IP already does it |
|---|---|---|
| Both Classic CAN and CAN FD | DroneCAN (the former UAVCAN v0) is a Classic CAN protocol; Cyphal can run on CAN FD (this last point is **(inference)** from general knowledge, not verified in this run). A node should talk to old and new peripherals on one controller | M_CAN, GRCANFD |
| Two independent CAN interfaces or a redundant bus | PX4 recommends wiring a second CAN port for redundancy; Pixhawk flight controllers have two CAN interfaces | GRCANFD has a redundant line pair and a transceiver enable; M_CAN is integrated twice |
| Priority-ordered transmit queue with cancellation | Control messages (motor commands, actuator setpoints) must not wait behind telemetry; an old setpoint should be cancellable **(inference)** | M_CAN Tx buffers by ID priority, cancel |
| Hardware timestamps on receive and transmit | Sensor fusion and time synchronization need the arrival time of GNSS, IMU, and ESC messages **(inference)** | M_CAN timestamp counter, Tx event FIFO, CiA 603 add-on |
| Enough filter elements and a hardware FIFO or DMA | Dozens of node IDs and message types on one bus at high rate, low CPU load for a small flight controller MCU **(inference)** | M_CAN 128+64 filters and two FIFOs; GRCANFD DMA |
| Fast and safe recovery from bus errors | A short or noisy cable must not lock the node; the node must recover without a reset and keep flying | M_CAN bus-off recovery, GRCANFD automatic restart |
| Bit rates of 1 to 5 Mbit/s with transmitter delay compensation | Short cables inside the airframe allow a fast data phase; the transceiver loop delay then exceeds the data bit time | M_CAN TDC, GRCANFD TDC |
| Diagnostics: error counters, last error code, loop-back, listen-only, bus monitoring | Preflight self-test and in-flight logging of bus health (PX4 logs CAN device information) | M_CAN, GRCANFD |
| Low power and sleep | Battery powered payload nodes, wake on CAN **(inference)** | M_CAN clock stop request, AMD sleep mode |
| Memory error protection (parity or ECC input) and a watchdog on the bus interface | A radiation- and vibration-tolerant airframe is not required, but a flight-critical bus should not use corrupted data **(inference)** | M_CAN error input and RAM watchdog |
| Deterministic latency from receive to host | A control loop at 1 kHz or faster **(inference)** | High-priority message interrupt (M_CAN), SYNC interrupts (GRCANFD) |

## 4. Candidate feature set for the specification (to be decided with the designer)

| No. | Feature | Proposal | Source of the idea |
|---|---|---|---|
| F1 | Classic CAN 2.0A/B and CAN FD (ISO and non-ISO) in one core | Required (scope already agreed) | M_CAN, GRCANFD |
| F2 | Priority Tx queue with cancel and a Tx event record with timestamp | Required | M_CAN |
| F3 | Two Rx FIFOs plus dedicated Rx buffers, filters as range, dual ID, mask, with accept and reject | Required (sizes are parameters) | M_CAN |
| F4 | Message RAM outside the core (a generic memory interface) so the integrator picks the RAM and ECC | Option to decide | M_CAN (the RAM is not in the deliverable) |
| F5 | DMA master interface to system memory | Option | GRCANFD, M_CAN DMU |
| F6 | Transmitter delay compensation, measured at the FDF to res edge | Required | M_CAN, Bosch spec |
| F7 | Hardware timestamp (16 bit, with prescaler, or an external vector) | Required | M_CAN |
| F8 | Operating modes: restricted, bus monitoring, loop-back, silent, single-shot | Required | M_CAN, GRCANFD |
| F9 | Bus-off recovery with a software or automatic option | Required | M_CAN AN004, GRCANFD |
| F10 | Protocol exception handling configurable | Required | M_CAN |
| F11 | Redundant transceiver pair selectable by software | Option for the UAV profile | GRCANFD |
| F12 | Parity or ECC error input, and a watchdog on the memory interface | Option | M_CAN |
| F13 | Power-down handshake (clock stop request and acknowledge) | Required | M_CAN |
| F14 | Error logging with separate arbitration-phase and data-phase counters | Required | M_CAN (last error codes), AMD summary |
| F15 | Two interrupt lines | Required | M_CAN |

## 5. Facts from these documents that settle or narrow points of `iso_canfd_findings.md`

| Point | New fact | Source |
|---|---|---|
| ISO-030 (TDC) | Delay measurement starts at the falling edge from FDF to res in each transmitted FD frame and stops at the same edge seen at the receive input; resolution one minimum time quantum; SSP = measured delay + TDCO, rounded down to a whole minimum time quantum; delay plus offset must stay below 6 data bits and at most 127 minimum time quanta; arbitration phase never uses TDC; TDC measurement is always done (no fixed delay setting); optional filter window TDCF keeps the SSP from being placed early by a dominant glitch | C1 3.1.4 |
| ISO-032 / D5 (bus idle, protocol exception) | Bus idle is the detection of **11 consecutive recessive bits** (C4). A protocol exception in a receiver (FDF recessive and res recessive) sets a status flag; with handling enabled the node goes to the integrating state at the next sample point; with handling disabled it sends an error frame (form error) | C1 3.1.3, C4 |
| ISO-024 (non-ISO) | A configuration bit selects the frame format: 0 = ISO 11898-1:2015, 1 = Bosch CAN FD Specification V1.0; it is changed only while the core is in configuration mode (INIT and CCE set) | C1 CCCR.NISO |
| ISO-027 (bit timing ranges) | The data phase of a commercial ISO core has wider ranges than the 2012 text: DTSEG1 up to 32 time quanta, DTSEG2 1 to 16, DSJW up to 16; the manual says the DTSEG2 range was harmonized with ISO 11898-1:2015 in revision 3.3.1 | C1 2.3.4 and revision list |
| ISO-033 (rates) | With a 20 MHz CAN clock and the shortest data bit time of 4 time quanta the data rate is 5 Mbit/s; the data rate must be at least the arbitration rate | C1 3.1.3 |
| ESI | The transmitted ESI follows the error state at the start of the transmission (recessive if error passive) | C1 3.1.3 |
| Format control | CAN FD transmission and bit rate switching are enabled by two configuration bits (FDOE, BRSE), changeable only in configuration mode; with FDOE = 0 an FD frame on the bus gives an error frame; the frame format and the bit rate switch are chosen per transmit buffer | C1 3.1.3 |
| Bus-off | Entering bus-off stops all CAN activity; recovery needs 129 occurrences of 11 recessive bits | C1, C4 |

The CTU datasheet (C9) narrows D1: ISO and non-ISO differ in the highest bit of the CRC shift register initialization (ISO: top bit set). Still open after these documents: the parity type and the Gray mapping of the stuff count (D2), the stuff bit counting at the data field boundary (D3), and the exact ISO initial value (D1, confirm with a test vector). The M_CAN manual does not
describe the frame coding at bit level; these points need the ISO text or a conformance test source.

## 6. Licences and handling

- All Bosch documents carry "© Robert Bosch GmbH" and the standard "as is" legal notice; no redistribution permission was
  found for the PDFs, so they stay outside git (kept in the session scratchpad). The Gaisler manual is "free download"
  with a note that access may need a request; it also stays outside git.
- A **CAN protocol licence from Bosch** is required for every CAN FD implementation (Bosch site, AMD PG223, OpenCores
  README). This is a business condition of the project, not a design feature.

## 7. TTCAN and AUTOSAR documents read (added 2026-11-04)

| ID | Document | Size | Pages | Licence found in the document |
|---|---|---|---|---|
| C10 | Bosch **TTCAN IP Module User's Manual**, revision 1.6 (2002-11-11), copy from archive.org (a copy of the manualsonline file, **not an official Bosch download**) | 786,681 bytes | 77 | © Bosch, no redistribution statement in the part read |
| C11 | AUTOSAR **Requirements on TTCAN** (SRS TTCAN), CP R23-11 | 123,037 bytes | 19 | See below |
| C12 | AUTOSAR **Requirements on CAN** (SRS CAN), CP R23-11 | 412,016 bytes | 71 | See below |
| C13 | AUTOSAR **Specification of CAN Driver**, CP R25-11 | 1,135,014 bytes | 140 | See below |
| C14 | AUTOSAR **Specification of CAN Interface**, CP R25-11 | 1,459,203 bytes | 245 | See below (read through the requirement tracing of C12/C13 and headings only) |
| C15 | AUTOSAR **Specification of CAN Transceiver Driver**, CP R25-11 | 565,632 bytes | 99 | See below |
| C16 | AUTOSAR **Specification of CAN State Manager**, CP R25-11 | 554,466 bytes | 114 | See below |
| C17 | AUTOSAR **Specification of Time Synchronization over CAN**, CP R25-11 | 662,357 bytes | 120 | See below |
| C18 | AUTOSAR **Specification of CAN Network Management**, CP R25-11 | 608,003 bytes | 120 | See below |
| C19 | AUTOSAR **Specification of CAN Transport Layer**, CP R25-11 | 1,647,288 bytes | 126 | See below |

AUTOSAR licence text (disclaimer page of the documents, paraphrased): the material is for information only; it may be
utilized or reproduced **without modification for informational purposes only**; any other use needs written permission;
**commercial exploitation of the material needs a licence** to the intellectual property rights; the work was developed for
**automotive applications only** and has neither been developed nor tested for non-automotive use. Consequence for this
project: the AUTOSAR files stay outside git (session scratchpad), nothing is pasted into the specification, and the
drone profile cannot claim AUTOSAR compliance (it only reuses the ideas).

## 8. Features and functions extracted from the TTCAN and AUTOSAR documents

The AUTOSAR documents describe **software** layers (driver, interface, state manager, transport). The hardware controller
IP never contains them, but they fix what the **hardware must offer to the driver**.

### 8.1 Hardware needs set by the AUTOSAR CAN Driver (C13) and Requirements on CAN (C12)

| ID | Function or feature the IP has to support | Source | Priority |
|---|---|---|---|
| A-001 | Hardware objects (mailboxes) that are either **transmit or receive**, grouped as **BasicCAN** (one object serves several IDs through a filter) or **FullCAN** (one object per ID) | C13 configuration (CanHandleType, CanObjectType) | Must |
| A-002 | Per object ID type **standard, extended, or mixed**; a received extended ID is reported with a marker bit | C13 | Must |
| A-003 | Per receive object a **32-bit acceptance code and mask** (hardware filter); static configuration | C12 (SRS_Can_01037), C13 | Must |
| A-004 | Several transmit objects forming one transmit entity (**multiplexed transmission**) that send in the **order of message priority**, to avoid priority inversion; the driver can find a free object | C13 section 7.5.1 | Must |
| A-005 | Per object **payload size** 8, 12, 16, 20, 24, 32, 48, or 64 bytes, and a **fill (padding) value** for unused bytes in FD frames | C13 (CanObjectPayloadLength, CanFdPaddingValue), C12 (SRS_Can_01160) | Must |
| A-006 | Each event (receive, transmit confirmation, bus-off, wake-up, mode change) detected by **interrupt or polling**, selectable per object and per event | C12 (SRS_Can_01062, 01132) | Must |
| A-007 | **Nominal bit timing** per controller: baud rate up to 2000 kbit/s, PropSeg, Seg1, Seg2, SJW each 0 to 255; **FD data bit timing** up to 16000 kbit/s with its own segments, a **TX bit rate switch** option, and a **secondary sample point offset** 0 to 255; run-time change of the baud rate | C13 | Must |
| A-008 | Controller modes **stopped, started, sleep**; wake-up by bus detected also while the controller goes to sleep; wake-up event reported | C12 (SRS_Can_01122), C13 | Must |
| A-009 | **Partial networking**: filter for a wake-up frame (CAN ID with mask, DLC, data masks, a dynamic data mask that can be changed at run time) | C13 (CanPartialNetwork, Can_SetCanPnFrameDataMask), C15 | Option |
| A-010 | Read the **controller error state** (active, passive, bus-off) and the **receive and transmit error counters** | C12 (SRS_Can_01167, 01170), C13 | Must |
| A-011 | **Bus-off notification**; the driver must **not recover automatically** (the state manager decides) | C12 (SRS_Can_01055, 01060) | Must |
| A-012 | **No loss of received messages** and the ability to produce **100 % bus load** (back-to-back frames) | C12 (SRS_Can_01125, 01126) | Must |
| A-013 | **Data consistency** of a received message while the host reads it | C12 (SRS_Can_01059) | Must |
| A-014 | **Remote frames are not required** in the driver (frames are not requested by remote frames) | C12 (SRS_Can_01147, 01161) | Option (support but do not rely on it) |
| A-015 | **Hardware timestamp** with a free-running counter that counts clock cycles, resolution between 1 ns and 1 us, a 32-bit counter and 32-bit timestamp registers recommended (CiA 603); services: read the current time, enable the egress timestamp of a transmit object, read the egress and the ingress timestamp; the timestamp is taken when the frame is valid | C13 section 7.11, C17 | Must for the automotive and the drone profile |
| A-016 | **TX offline active mode** (ECU passive: the node receives and acknowledges but does not transmit), and **TX cancellation** | C12 (SRS_Can_01158), C13, C14 | Must (maps to restricted mode and cancel) |
| A-017 | **Trigger transmit**: the data of a transmit object are fetched from the host at the moment of transmission | C13 (CanTriggerTransmitEnable) | Option |
| A-018 | Support of **Classic CAN and CAN FD frames** together; DLC to length coding visible to the upper layer | C12 (SRS_Can_01162) | Must |

### 8.2 Time-triggered CAN (C10 Bosch TTCAN manual, C11 AUTOSAR SRS TTCAN)

ISO 11898-4:2004 is built on **Classic CAN**: the Bosch module reaches 1 Mbit/s and supports levels 1 and 2 in hardware.
Whether a time-triggered schedule is defined for CAN FD frames is not stated in the documents read (UNVERIFIED).

| ID | Function | Source |
|---|---|---|
| T-001 | **Level 1** (time-triggered transmission with a reference message) and **level 2** (global system time with continuous clock drift correction) | C10, C11 (SRS_TtCan_41001) |
| T-002 | Operating modes: event-driven CAN (default), configuration mode, strictly time-triggered, **event-synchronised time-triggered** | C10 (TTMode), C11 (SRS_TtCan_41006) |
| T-003 | **Time master** capability with a 3-bit priority (the last three bits of the reference message identifier), an initial reference trigger offset, and the reference message DLC | C10 |
| T-004 | **Trigger memory** holding the **time marks** of the system matrix; each mark linked to a message object; configurable | C10, C11 (SRS_TtCan_41012) |
| T-005 | Message objects mappable to **time windows** of the system matrix | C11 (SRS_TtCan_41003) |
| T-006 | **Cycle time, cycle count, local time, global time** counters, a network time unit (NTU) with a configurable ratio, and a **Tx_Enable window** | C10 |
| T-007 | **Stop-watch trigger** and **event trigger** pins, time-mark interrupt, **interrupt status vector** | C10, C11 (SRS_TtCan_41007) |
| T-008 | **Application watchdog** with a configurable limit, and **gap control** | C10, C11 (SRS_TtCan_41004) |
| T-009 | Severe error **S3**: notified to the driver, **not recovered automatically**, treated like bus-off by the upper layers | C11 (SRS_TtCan_41008, 41009, 41013) |
| T-010 | Timing parameters (for example the master's reference offset) adjustable at run time when the node is time master; synchronization state and master state readable | C11 (SRS_TtCan_41005) |
| T-011 | **Disabled automatic retransmission** is part of the time-triggered operation | C10 |

### 8.3 Functions of the other layers that need a hardware hook

| ID | Layer (document) | Function | Hardware hook |
|---|---|---|---|
| L-001 | CAN Transceiver Driver (C15) | Transceiver modes normal, standby, sleep; wake-up reasons (by bus, by pin, power-on, reset, error); selective wake-up frames (partial networking) with CAN ID, mask, DLC and data masks; silence and timeout diagnostic flags | Control outputs for the transceiver mode (enable, standby), a wake-up input, and an interrupt; the transceiver itself is outside the IP |
| L-002 | CAN State Manager (C16) | **Two-level bus-off recovery**: a short delay (time L1) for the first retries, a longer delay (time L2) after a counter limit; a transmit-ensured check; a configurable recovery time | A bus-off interrupt, a controller restart request, a software-controlled recovery (the IP does not recover alone, A-011) |
| L-003 | CAN Network Management (C18) | NM message cycle, repeat message state, immediate NM transmissions, partial network bits, bus-load reduction | Filters for the NM message IDs, a fast transmit path; software timers |
| L-004 | Time Synchronization over CAN (C17) | SYNC and follow-up messages with a CRC, offset messages, time gateway; the master reads the **egress** timestamp of the SYNC frame and the slave the **ingress** timestamp | Hardware ingress and egress timestamps (A-015) |
| L-005 | CAN Transport Layer (C19) | Segmentation of messages longer than 8 bytes (Classic) or 64 bytes (CAN FD), flow control (block size, separation time), padding of unused bytes, FD support switch | Frame size up to 64 bytes and the padding value (A-005) |
| L-006 | CAN Interface (C14) | Buffering of transmit PDUs per object, transmit cancellation, DLC check, software filtering in front of the hardware filter, polling and callback notification in parallel, bus mirroring of received and transmitted frames | Transmit cancel, per-object status, and a way for software to mirror frames (listen-only or monitor mode) |

## 9. Maximum feature set proposed for the automotive and drone profiles

Combines sections 2 to 8. "A" = automotive (AUTOSAR driver compatible), "D" = drone profile (DroneCAN and Cyphal; the
application part is an **inference**).

| No. | Feature | A | D | Source |
|---|---|---|---|---|
| F1 to F15 | As in section 4 | | | Section 4 |
| F16 | BasicCAN and FullCAN message objects, standard, extended and mixed ID type per object | Must | Must | A-001, A-002 |
| F17 | 32-bit filter code and mask per receive object, plus range and dual-ID filters | Must | Must | A-003, M_CAN |
| F18 | Multiplexed transmit objects with priority order and cancellation | Must | Must | A-004, A-016 |
| F19 | Payload sizes 8 to 64 bytes per object and a padding value | Must | Must | A-005 |
| F20 | Interrupt or polling per event, two interrupt lines | Must | Must | A-006 |
| F21 | Wide bit timing: nominal and FD data segments up to 255 quanta, SJW, TX bit rate switch, SSP offset, run-time baud change; the AUTOSAR configuration limit for the data rate is 16 Mbit/s | Must | Must | A-007 |
| F22 | Controller modes, wake-up by bus, sleep handshake | Must | Should | A-008, M_CAN |
| F23 | Partial-networking wake-up frame filter | Option | No | A-009 |
| F24 | Error state and error counters readable; bus-off interrupt; **no automatic recovery** unless enabled by a bit | Must | Must | A-010, A-011 |
| F25 | Sustained back-to-back reception and transmission (100 % bus load), no message loss | Must | Must | A-012 |
| F26 | Consistent read of a received message (buffer lock or flag) | Must | Must | A-013 |
| F27 | Remote frame support as an option | Option | No | A-014 |
| F28 | 32-bit timestamp with a configurable prescaler, egress and ingress, CiA 603 compatible | Must | Must | A-015 |
| F29 | Restricted mode (TX offline active) | Must | Should | A-016 |
| F30 | Trigger transmit | Option | No | A-017 |
| F31 | **TTCAN level 1 and 2** (time master, trigger memory, system matrix, global time, event synchronised mode, watchdog) | Option | No (inference) | T-001 to T-011 |
| F32 | Transceiver control outputs (enable, standby) and a wake-up input | Must | Should | L-001 |
| F33 | Bus-off recovery support for a two-level policy (software) | Must | Must | L-002 |
| F34 | Frame mirroring and monitor mode for bus logging | Should | Must | L-006, M_CAN bus monitoring |

Open points for the designer: which of the "Option" features enter the first release (F23, F27, F30, F31), whether the
timestamp counter is inside the IP or an external vector, and how the message storage is organised (message RAM outside
the core as in M_CAN, or registers as in the Bosch TTCAN module).
