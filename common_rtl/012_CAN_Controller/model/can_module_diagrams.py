#!/usr/bin/env python3
"""Generate one specification-level functional SVG per CAN-FD RTL module.

Usage: python can_module_diagrams.py OUT_DIR
The diagrams describe the HDS design intent; they are not inferred from RTL.
"""
from html import escape
import os
import sys
import textwrap


MODULES = [
    ("m_canfd_rst", "CLK-CAN + CLK-BUS", "Coordinate reset release and CDC readiness",
     ["i_rst_n_can", "i_rst_n_bus", "i_clk_can", "i_clk_bus"],
     [("Local reset release", ["Async assertion", "Two-stage release per clock"]),
      ("Peer-ready exchange", ["Synchronize ready levels", "Support release skew"]),
      ("Traffic gating", ["Hold CAN in INIT", "Block CDC until both ready"])],
     ["RST-CAN / RST-BUS", "CDC-ready", "CAN transmit remains recessive"],
     "Reset domains assert together; each release is synchronized independently."),
    ("m_canfd_csr", "CLK-BUS", "Generated APB register interface and storage",
     ["APB4 request", "Hardware status / event loads"],
     [("APB protocol", ["Setup and access", "Wait-state / error response"]),
      ("Register bank", ["Store writable fields", "Apply field access policies"]),
      ("Read / status mux", ["Return register fields", "Expose status snapshots"])],
     ["APB read data / response", "Configuration fields", "W1C event clears"],
     "Register offsets and field definitions remain in the CSR workbook."),
    ("m_canfd_wprot", "CLK-BUS", "Protect configuration writes",
     ["APB write", "INIT / CCE", "Safety lock status"],
     [("Address decode", ["Identify protected fields", "Preserve ordinary accesses"]),
      ("Permission check", ["INIT = 1 and CCE = 1", "Check lock/key policy"]),
      ("Write decision", ["Forward allowed write", "Suppress or return error"])],
     ["Filtered APB to CSR", "APB response", "Protection status / event"],
     "Protection applies before the generated CSR block; see DEC-018/DEC-021."),
    ("m_canfd_cdc", "CLK-CAN + CLK-BUS", "Move control, status, frames and events across clocks",
     ["CSR configuration", "CAN status/events", "Rx / Tx frame bundles"],
     [("Readiness gate", ["Wait for both domains", "Keep crossings inactive"]),
      ("Transfer structures", ["Stable-bundle handshakes", "Toggle pulses / level syncs"]),
      ("Snapshot and release", ["Copy config/status", "Acknowledge and free buffers"])],
     ["CAN-side config / Tx frame", "BUS-side status / Rx frame", "Cross-domain events"],
     "Each crossing uses its CDC-00x contract; bundle data stays stable through handshake."),
    ("m_canfd_sync_bit", "Destination clock", "Synchronize an asynchronous level",
     ["Asynchronous level", "Destination clock / reset"],
     [("Stage 1", ["Capture asynchronous input", "No functional fanout"]),
      ("Stage 2", ["Reduce metastability propagation", "Provide destination level"]),
      ("Consumer", ["Use synchronized output", "No combinational bypass"])],
     ["Synchronized level", "Nominal two-clock latency"],
     "A level synchronizer is not a pulse catcher or a glitch/noise filter."),
    ("m_canfd_sync_tgl", "Source + destination clocks", "Transfer a short event pulse between domains",
     ["Source pulse", "Source and destination resets"],
     [("Encode event", ["Toggle source state", "One toggle per event"]),
      ("Synchronize", ["Two destination flops", "No logic between stages"]),
      ("Decode event", ["Detect toggle change", "Emit one destination pulse"])],
     ["Destination pulse", "Event spacing follows CDC contract"],
     "Closely spaced source events may merge as specified by CDC-007/008."),
    ("m_canfd_sync_hsk", "Source + destination clocks", "Transfer a stable multi-bit bundle safely",
     ["Source data bundle", "Request / acknowledge", "Both clocks"],
     [("Hold source bundle", ["Register data", "Keep stable until completion"]),
      ("Four-phase control", ["Synchronize request", "Capture after request"]),
      ("Return acknowledge", ["Synchronize acknowledge", "Release source register"])],
     ["Captured destination bundle", "Completion to source"],
     "Only handshake controls are synchronized bit by bit; the bundled data uses a timed stable path."),
    ("m_canfd_btl", "CLK-CAN", "Generate bit timing and sample points",
     ["Synchronized i_can_rx", "Nominal / data timing", "BRS / INIT state"],
     [("Prescale and segment", ["Generate time quanta", "Track SYNC / SEG1 / SEG2"]),
      ("Synchronize to edges", ["Hard sync / resync", "Limit correction by SJW"]),
      ("Sample and switch", ["One primary sample per bit", "Switch timing at BRS / CRC delimiter"])],
     ["sample / sample_val", "tx_point", "Active bit phase"],
     "Detailed timing and edge behavior: figures canfd_btl_logic.svg and WF-029–WF-039."),
    ("m_canfd_tdc", "CLK-CAN", "Compensate transmitter loop delay during an FD data phase",
     ["Transmit / receive edges", "tdco / tdcf", "TDC enable"],
     [("Measure loop delay", ["Use FDF-to-res edge", "Count minimum time quanta"]),
      ("Place secondary point", ["SSP = measured delay + offset", "Track delayed Tx history"]),
      ("Compare transmitted bit", ["Check receive level at SSP", "Report mismatch to error logic"])],
     ["tdcv status", "Secondary sample point", "Bit-error event"],
     "TDC is transmitter monitoring; it does not filter receiver noise."),
    ("m_canfd_bsp", "CLK-CAN", "Sequence and validate CAN / CAN-FD frames",
     ["Tx frame bundle", "sample_val / timing strobes", "Error-state inputs"],
     [("Field sequencer", ["SOF, arbitration, control", "data, CRC, ACK, EOF"]),
      ("Serial transforms", ["m_canfd_stuf", "m_canfd_crc"]),
      ("Monitor and react", ["Arbitration / form / CRC checks", "ACK, error, overload control"])],
     ["o_can_tx", "Rx frame bundle", "Error events / frame result"],
     "The field sequence is shown in section 10.7; dedicated child-module diagrams follow."),
    ("m_canfd_stuf", "CLK-CAN", "Insert and remove CAN bit-stuff fields",
     ["Tx logical bit stream", "Rx sampled bit stream", "Frame mode / CRC phase"],
     [("Transmit run count", ["Track equal-bit run", "Insert complement after five"]),
      ("ISO-FD CRC handling", ["Track dynamic stuff count", "Insert/check fixed stuff bits"]),
      ("Receive destuff", ["Remove dynamic stuff bits", "Detect stuff violations"])],
     ["Stuffed Tx bit", "Destuffed Rx bit", "Stuff error / SBC result"],
     "Dynamic stuffing and fixed CRC-field stuffing are separate rules; see REQ-FUNC-008."),
    ("m_canfd_crc", "CLK-CAN", "Generate and check Classic / ISO-FD CRC sequences",
     ["Destuffed / CRC input stream", "Frame format", "DLC / stuff count"],
     [("Parallel CRC state", ["CRC15 for Classic", "CRC17 and CRC21 for FD"]),
      ("Select profile", ["CRC15 for Classic", "CRC17 <= 16 bytes", "CRC21 > 16 bytes"]),
      ("Transmit / compare", ["Emit selected sequence", "Compare received sequence"])],
     ["CRC Tx bits", "CRC pass / fail", "CRC event"],
     "ISO FD CRC initialization and fixed-stuff treatment are specified in section 10.7.4."),
    ("m_canfd_eml", "CLK-CAN", "Update error counters and fault-confinement state",
     ["Encoded protocol error", "Successful frame result", "Bus samples"],
     [("Classify event", ["Role / phase / error type", "Apply protocol exception rules"]),
      ("Update counters", ["TEC / REC rules", "Warning and passive thresholds"]),
      ("Recovery state", ["Bus-off / recovery count", "Apply INIT and error state"])],
     ["Error state / last error", "TEC / REC", "Bus-off / IRQ events"],
     "Counter rules and threshold behavior: section 10.8 and WF-042/WF-051."),
    ("m_canfd_rxh", "CLK-BUS", "Filter, store and retire received messages",
     ["Rx frame from CDC", "Message RAM response", "Software FIFO acknowledge"],
     [("Hold and route", ["Reserve transfer slot", "Reject unsupported frame"]),
      ("Filter and store", ["Call m_canfd_flt", "Write data then header"]) ,
      ("Update bookkeeping", ["Advance put index / new-data", "Raise IRQ and DMA events"])],
     ["Message RAM requests", "FIFO / buffer status", "Rx events"],
     "Full FIFO, overwrite, and RAM-fault behavior are specified in section 10.11."),
    ("m_canfd_flt", "CLK-BUS", "Evaluate message-RAM acceptance filters in order",
     ["Standard / extended ID", "Filter-list configuration", "RAM read data"],
     [("Select list", ["Base uses standard list", "Extended uses extended list"]),
      ("Read and compare", ["Range / dual / mask", "Apply XIDAM for extended ID"]),
      ("First-match action", ["FIFO0 / FIFO1 / buffer", "High priority or reject"])],
     ["Accept action", "Filter index / match", "Next RAM address"],
     "No-match behavior comes from cfd_gfc; filter list order defines priority."),
    ("m_canfd_txh", "CLK-BUS", "Select, fetch and manage transmit buffers",
     ["Software request / cancel", "Message RAM", "CAN-domain completion"],
     [("Validate request", ["Range-check full element", "Read header into key cache"]),
      ("Select candidate", ["Apply priority / FIFO mode", "Handle cancel / retry policy"]),
      ("Fetch and hand off", ["Read full Tx element", "CDC transfer and event update"])],
     ["Tx request / frame bundle", "Done / cancel / fail flags", "Tx event FIFO"],
     "Software must keep an element unchanged while its request bit remains set."),
    ("m_canfd_mram", "CLK-BUS", "Serialize and protect the external message-RAM interface",
     ["Rx / Tx / TT clients", "External RAM acknowledge / data", "Address-range configuration"],
     [("Select request", ["One outstanding access", "Keep client identity"]),
      ("Check and monitor", ["Range / full-span check", "Optional watchdog and ECC status"]),
      ("Hold transaction", ["Keep request until acknowledge", "Route response to owner"])],
     ["RAM pins", "Read data / acknowledge", "RAM fault / safety event"],
     "The RAM array is external; invalid generated addresses are rejected before request."),
    ("m_canfd_ts", "CLK-CAN + CLK-BUS", "Count, capture and expose time values",
     ["Selected clock / external vector", "SOF sample point", "Timeout configuration"],
     [("Select and prescale", ["Internal or external source", "Build timestamp tick"]),
      ("Count and capture", ["Free-running time", "Capture Tx / Rx SOF time"]),
      ("Timeout / snapshot", ["Detect wrap / timeout", "Cross status to BUS domain"])],
     ["Timestamp values", "Timeout status / event", "Capture to message handler"],
     "The exact SOF timestamp compensation remains TBD-009."),
    ("m_canfd_dma", "CLK-BUS", "Request DMA service for eligible queues",
     ["FIFO fill / watermark", "DMA enable / mode", "DMA acknowledge"],
     [("Qualify work", ["Check enabled source", "Single or watermark burst"]),
      ("Request service", ["Hold request to acknowledge", "Optional flush timeout"]),
      ("Retire and re-arm", ["Advance FIFO ack as defined", "Force low interval before re-request"])],
     ["o_dma_req_*", "DMA status", "FIFO / Tx service acknowledgements"],
     "Handshake and flush semantics: section 10.14 and WF-059–WF-064."),
    ("m_canfd_irq", "CLK-BUS", "Latch, mask and route interrupt events",
     ["Hardware event pulses", "Raw W1C writes", "Enable / line / injection fields"],
     [("Latch raw events", ["Sticky raw flags", "Hardware set wins same-cycle clear"]),
      ("Mask and inject", ["raw AND enable", "Optional software injection"]),
      ("Route lines", ["Apply per-event line select", "Gate each IRQ output"])],
     ["cfd_irq_raw / cfd_irq_sts", "o_irq_0 / o_irq_1"],
     "IRQ register semantics and set/clear priority are in section 6.4 and WF-016."),
    ("m_canfd_pn", "CLK-CAN", "Detect configured wake-up frames while asleep",
     ["Sampled frame fields", "Wake-up filters", "CRC / error status"],
     [("Select candidate", ["Classic frame only", "Compare ID / format"]),
      ("Match payload", ["Check DLC and masked data", "Reject any mismatch"]),
      ("Decide at frame end", ["Require valid CRC / no stuff error", "Raise wake request on match"])],
     ["o_wake_req", "Matched filter index / source status"],
     "Partial-networking behavior: section 10.15.6 and WF-066/WF-068."),
    ("m_canfd_tt", "CLK-CAN + CLK-BUS", "Synchronize and schedule TTCAN traffic",
     ["Reference message", "Trigger RAM / matrix", "Application kick / status"],
     [("Time base", ["NTU / local cycle time", "Reference sync / drift update"]),
      ("Window and trigger", ["Cycle-code / time-mark compare", "Tx_Enable and gap rules"]),
      ("Message action", ["Request Tx / check Rx", "Update TT status and events"])],
     ["TT Tx commands", "Time marks / cycle status", "TT IRQ events"],
     "The enabled TT mode and event semantics are specified in section 10.13."),
    ("m_canfd_pwr", "CLK-CAN + CLK-BUS", "Control INIT, sleep, wake and clock-stop sequencing",
     ["Software requests", "Bus / transceiver wake inputs", "Frame and CDC activity"],
     [("Qualify transition", ["Wait for frame / bus idle", "Refuse unsafe sleep request"]),
      ("Sequence power state", ["INIT / sleep / restart", "Wake delay and integration"]),
      ("Control external pins", ["Transceiver enable / bus select", "Clock stop acknowledge"])],
     ["o_trcv_en / o_wake_req", "INIT / bus selection", "o_clk_stop_ack"],
     "Power-state transitions and wake sources: section 10.15 and WF-065–WF-069."),
    ("m_canfd_safe", "CLK-CAN + CLK-BUS", "Monitor enabled safety mechanisms and apply configured reactions",
     ["RAM / clock / register faults", "Compare / signature mismatches", "Fault injection inputs"],
     [("Mechanism checks", ["Parity / lock / clock", "Counters / FSM / payload"]),
      ("Collect and latch", ["Set detailed safety flags", "Capture fault address / cause"]),
      ("Apply reaction", ["Report or set INIT", "Drive safety output / IRQ"])],
     ["o_saf_err", "Safety flags / IRQ", "Optional stop request"],
     "Functional boundary only. Full SM-12–SM-16 instance hierarchy is still open in section 14.2."),
]


def wrap(text, width):
    return textwrap.wrap(text, width=width, break_long_words=False, break_on_hyphens=False) or [""]


def text(x, y, value, size=16, color="#243247", weight="normal", anchor="start"):
    return (f'<text x="{x}" y="{y}" font-family="Arial, Helvetica, sans-serif" '
            f'font-size="{size}" fill="{color}" font-weight="{weight}" text-anchor="{anchor}">{escape(value)}</text>')


def card(x, y, w, h, heading, lines, fill, border, heading_color="#172033"):
    out = [f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="{fill}" stroke="{border}" stroke-width="2"/>']
    out.append(text(x + 16, y + 30, heading, size=18, color=heading_color, weight="bold"))
    yy = y + 62
    for item in lines:
        for ln in wrap(item, max(18, int((w - 32) / 8.4))):
            out.append(text(x + 16, yy, ln, size=15, color="#344054"))
            yy += 22
        yy += 7
    return "".join(out)


def arrow(x0, x1, y):
    return (f'<path d="M{x0} {y} L{x1-10} {y}" fill="none" stroke="#475467" stroke-width="2.4"/>'
            f'<polygon points="{x1},{y} {x1-12},{y-6} {x1-12},{y+6}" fill="#475467"/>')


def render(item):
    name, domain, purpose, inputs, stages, outputs, note = item
    w, h = 1800, 520
    out = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" role="img" aria-labelledby="title desc">',
           f'<title id="title">Functional diagram of {escape(name)}</title>',
           f'<desc id="desc">Inputs, main processing stages, outputs and clock domain for {escape(name)}.</desc>',
           '<rect width="100%" height="100%" fill="#ffffff"/>',
           text(30, 40, f"{name} · Functional block diagram", size=26, color="#101828", weight="bold"),
           text(30, 72, f"{domain}  |  {purpose}", size=16, color="#475467"),
           card(30, 145, 260, 245, "Inputs", inputs, "#f2f4f7", "#98a2b3"),
           card(330, 145, 320, 245, stages[0][0], stages[0][1], "#eaf2ff", "#84adff", "#175cd3"),
           card(700, 145, 320, 245, stages[1][0], stages[1][1], "#ecfdf3", "#75e0a7", "#067647"),
           card(1070, 145, 320, 245, stages[2][0], stages[2][1], "#f4f3ff", "#bdb4fe", "#5925dc"),
           card(1440, 145, 330, 245, "Outputs", outputs, "#fff6ed", "#fec84b"),
           arrow(290, 330, 270), arrow(650, 700, 270), arrow(1020, 1070, 270), arrow(1390, 1440, 270),
           text(30, 440, "Design intent from the HDS; module boundaries and signal names are defined in sections 6 and 14.", size=14, color="#667085"),
           text(30, 480, f"Note: {note}", size=14, color="#475467"),
           '</svg>']
    return "".join(out)


def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for item in MODULES:
        name = item[0]
        path = os.path.join(out_dir, name + "_function.svg")
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write(render(item))
    print(f"Wrote {len(MODULES)} module functional diagrams to {out_dir}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "figures", "module_functional"))
