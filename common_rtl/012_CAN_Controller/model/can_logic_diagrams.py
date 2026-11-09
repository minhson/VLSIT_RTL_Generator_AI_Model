#!/usr/bin/env python3
# Project  : VLSIT common RTL library
# Function : draws the logic diagrams of section 10.6 to 10.8 of the CAN FD controller specification as SVG
"""Usage: python can_logic_diagrams.py OUT_DIR   (writes canfd_btl_logic.svg, canfd_frame_datapath.svg, canfd_error_logic.svg)

Black and white, one font, boxes and straight orthogonal arrows. Sources: section 10.6 to 10.8 of the specification."""
import os
import sys
from xml.sax.saxutils import escape

FONT = 'font-family="Times New Roman, serif" font-size="13"'


class Svg:
    def __init__(self, w, h, title):
        self.w, self.h, self.items = w, h, []
        self.text(10, 20, title, bold=True, size=16)

    def text(self, x, y, s, bold=False, size=13, anchor='start'):
        self.items.append('<text x="%d" y="%d" %s font-size="%d" %s text-anchor="%s">%s</text>' % (
            x, y, FONT.replace('font-size="13"', ''), size, 'font-weight="bold"' if bold else '', anchor, escape(s)))

    def box(self, x, y, w, h, lines, dashed=False):
        self.items.append('<rect x="%d" y="%d" width="%d" height="%d" fill="#fff" stroke="#000" stroke-width="1.4"%s/>' % (
            x, y, w, h, ' stroke-dasharray="6,4"' if dashed else ''))
        n = len(lines)
        for i, ln in enumerate(lines):
            self.text(x + w // 2, y + h // 2 + int((i - (n - 1) / 2.0) * 15) + 5, ln, anchor='middle', bold=(i == 0 and n > 1))

    def arrow(self, pts, label=None, lx=0, ly=0):
        d = 'M ' + ' L '.join('%d %d' % p for p in pts)
        self.items.append('<path d="%s" fill="none" stroke="#000" stroke-width="1.4"/>' % d)
        (x0, y0), (x1, y1) = pts[-2], pts[-1]
        dx = (x1 > x0) - (x1 < x0)
        dy = (y1 > y0) - (y1 < y0)
        px, py = -dy, dx
        tip = (x1, y1)
        b1 = (x1 - 9 * dx + 4 * px, y1 - 9 * dy + 4 * py)
        b2 = (x1 - 9 * dx - 4 * px, y1 - 9 * dy - 4 * py)
        self.items.append('<polygon points="%d,%d %d,%d %d,%d" fill="#000"/>' % (tip + b1 + b2))
        if label:
            self.text(lx or pts[0][0] + 4, ly or pts[0][1] - 4, label, size=11)

    def save(self, path):
        head = ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
                '<defs><marker id="a" markerWidth="9" markerHeight="9" refX="8" refY="4" orient="auto">'
                '<path d="M0,0 L8,4 L0,8 z" fill="#000"/></marker></defs><rect width="100%%" height="100%%" fill="#fff"/>') % (self.w, self.h, self.w, self.h)
        open(path, 'w', encoding='utf-8').write(head + ''.join(self.items) + '</svg>')


def btl(path):
    s = Svg(1180, 640, 'Logic diagram of the bit timing and sampling unit m_canfd_btl (CLK-CAN)')
    s.box(20, 70, 110, 50, ['i_can_rx', '(pin, async)'])
    s.box(170, 70, 130, 50, ['Two-flop', 'synchronizer', 'rx_s1, rx_s'])
    s.box(340, 70, 140, 50, ['rx_cur, rx_prev', '(registered)'])
    s.arrow([(130, 95), (170, 95)])
    s.arrow([(300, 95), (340, 95)])
    s.box(340, 170, 200, 70, ['Edge detect', 'rx_cur = 0, rx_prev = 1', 'smp_q = 1, synced = 0'])
    s.arrow([(410, 120), (410, 170)], 'rx_cur, rx_prev', 418, 148)
    s.box(600, 170, 270, 150, ['Synchronization controller', 'hard: hard_sync_en or hs_edl', 'tx_dom and e > 0: ignore (rule 4)', 'no_resync (data phase): ignore (rule 5)', 'e = t (SEG1) or e = -(len1+len2+1-t) (SEG2)', '|e| <= sjw: restart | e > sjw: len1 += sjw', 'e < -sjw: len2 -= sjw'])
    s.arrow([(540, 205), (600, 205)], 'edge', 548, 198)
    s.box(20, 170, 270, 70, ['Edge filter (option)', '2 consecutive dominant tq', 'only while hard_sync_en'])
    s.arrow([(290, 205), (340, 205)])
    s.box(600, 380, 270, 80, ['Segment decode', 'SYNC: t = 0 | SEG1: t <= len1', 'SEG2: t > len1, t <= len1 + len2'])
    s.box(20, 330, 200, 70, ['Prescaler div', '0 .. brp - 1', 'tick = (div = brp - 1)'])
    s.box(280, 330, 250, 70, ['tq counter t', 'increments on tick', 'cell end: t = len1 + len2'])
    s.arrow([(220, 365), (280, 365)], 'tick', 238, 358)
    s.arrow([(530, 365), (600, 420)], 't, len1, len2', 540, 385)
    s.arrow([(735, 320), (735, 380)], 'restart / len adjust', 742, 355)
    s.box(280, 470, 250, 70, ['Cell reload', 'len1 = tseg1, len2 = tseg2', 'of the configuration in use'])
    s.arrow([(405, 400), (405, 470)])
    s.box(20, 470, 200, 70, ['Configuration mux', 'ph = N: nominal registers', 'ph = D: data registers'])
    s.arrow([(220, 505), (280, 505)], 'brp, tseg, sjw', 224, 498)
    s.arrow([(120, 470), (120, 400)])
    s.box(600, 500, 270, 90, ['Sample point and tx point', 'sample = tick and t = len1:', 'sample_val = rx_cur, smp_q = rx_cur,', 'synced = 0 | tx_point = cell end'])
    s.arrow([(735, 460), (735, 500)])
    s.box(930, 380, 220, 80, ['Bit rate switch', 'ph <- D after the BRS sample', 'ph <- N after the CRCd sample'])
    s.arrow([(930, 420), (870, 420)])
    s.arrow([(870, 545), (930, 545)])
    s.box(930, 500, 220, 90, ['To m_canfd_bsp', 'sample, sample_val,', 'tx_point, sync event'])
    s.box(930, 170, 220, 150, ['Secondary sample point (m_canfd_tdc)', 'delay counter: tx edge to rx edge', 'at the FDF to res edge', 'ssp = delay + tdco after tx_point', 'bit error test at ssp'])
    s.arrow([(870, 245), (930, 245)], 'sync event', 878, 238)
    s.arrow([(1040, 500), (1040, 460)], 'sample', 1048, 485)
    s.text(20, 620, 'Clock: i_clk_can only. Strobes (tick, sample, tx_point) are one-clock pulses. Registers: div, t, len1, len2, ph, smp_q, synced.', size=12)
    s.save(path)


def datapath(path):
    s = Svg(1240, 640, 'Logic diagram of the frame engine datapath m_canfd_bsp (CLK-CAN)')
    s.box(20, 60, 150, 60, ['Tx frame register', '(from m_canfd_txh', 'through CDC-006)'])
    s.box(220, 60, 170, 60, ['Field sequencer', 'SOF, ID, control, data,', 'CRC, ACK, EOF'])
    s.arrow([(170, 90), (220, 90)])
    s.box(440, 40, 150, 50, ['CRC generator', 'CRC15 / CRC17 / CRC21'])
    s.box(440, 110, 150, 50, ['Stuff count', 'mod 8, Gray + parity'])
    s.arrow([(390, 75), (440, 65)], 'bit', 398, 62)
    s.arrow([(390, 105), (440, 135)])
    s.box(650, 60, 150, 60, ['Stuffing', 'dynamic: 5 equal bits', 'fixed: in CRC field'])
    s.arrow([(590, 65), (650, 75)])
    s.arrow([(590, 135), (650, 105)])
    s.box(860, 60, 140, 60, ['o_can_tx register', '(loaded at tx_point)'])
    s.arrow([(800, 90), (860, 90)], 'tx_bit', 805, 82)
    s.box(1040, 60, 170, 60, ['Output override', 'error flag, delimiter,', 'overload, ACK dominant'])
    s.arrow([(1040, 90), (1000, 90)])
    s.box(20, 250, 150, 60, ['i_can_rx', 'rx_cur (m_canfd_btl)'])
    s.box(220, 250, 170, 60, ['Sampler', 'sample_val at the', 'sample point (or ssp)'])
    s.arrow([(170, 280), (220, 280)])
    s.box(440, 250, 150, 60, ['Destuffer', 'drop stuff bits', 'stuff error: 6th equal'])
    s.arrow([(390, 280), (440, 280)])
    s.box(650, 250, 150, 60, ['Field shift register', 'ID, flags, DLC, data'])
    s.arrow([(590, 280), (650, 280)])
    s.box(860, 250, 140, 60, ['Rx frame register', '(to m_canfd_rxh', 'through CDC-005)'])
    s.arrow([(800, 280), (860, 280)])
    # bus from the destuffer to the checkers
    s.arrow([(515, 310), (515, 350)])
    s.items.append('<path d="M 295 350 L 735 350" fill="none" stroke="#000" stroke-width="1.4"/>')
    s.box(20, 420, 150, 70, ['Bit monitor', 'tx_bit = sample_val?', 'exceptions: ARB,', 'ACK, passive flag'])
    s.box(220, 420, 150, 70, ['Form check', 'delimiters, EOF, res,', 'FDF in a Classic-only', 'node'])
    s.box(420, 420, 150, 70, ['CRC check', 'recompute and compare,', 'stuff count compare'])
    s.box(620, 420, 170, 70, ['ACK slot logic', 'dominant when the frame', 'is valid and the mode', 'allows'])
    s.arrow([(295, 350), (295, 420)])
    s.arrow([(495, 350), (495, 420)])
    s.arrow([(570, 455), (620, 455)], 'crc ok', 575, 447)
    s.arrow([(830, 90), (830, 200), (190, 200), (190, 440), (170, 440)], 'tx_bit (to the sample point)', 220, 194)
    s.arrow([(305, 310), (305, 335), (200, 335), (200, 470), (170, 470)], 'sample_val', 210, 330)
    s.arrow([(790, 455), (1120, 455), (1120, 120)], 'ack_drive', 900, 447)
    s.box(860, 520, 200, 60, ['Error event bus', 'type, phase, role'])
    s.items.append('<path d="M 95 490 L 95 550 L 860 550" fill="none" stroke="#000" stroke-width="1.4"/>')
    s.items.append('<path d="M 295 490 L 295 550" fill="none" stroke="#000" stroke-width="1.4"/>')
    s.items.append('<path d="M 495 490 L 495 550" fill="none" stroke="#000" stroke-width="1.4"/>')
    s.arrow([(840, 550), (860, 550)])
    s.arrow([(1060, 550), (1200, 550)], 'to m_canfd_eml', 1090, 543)
    s.text(20, 620, 'The receive path and the transmit path share the stuffing rules and the field counters; the transmitter also monitors its own bit. The output override block takes control of o_can_tx.', size=12)
    s.save(path)


def err(path):
    s = Svg(1240, 600, 'Logic diagram of the error monitoring and fault confinement (m_canfd_bsp and m_canfd_eml, CLK-CAN)')
    s.box(20, 60, 200, 60, ['Bit monitor', 'tx_bit != sample_val', 'not in ARB field recessive, ACK slot'])
    s.box(20, 140, 200, 50, ['Stuff checker', '6th equal bit, fixed stuff bit'])
    s.box(20, 210, 200, 50, ['Form checker', 'fixed-form bits illegal'])
    s.box(20, 280, 200, 50, ['CRC and stuff count check', 'at the end of the CRC field'])
    s.box(20, 350, 200, 50, ['ACK checker', 'no dominant in ACK slot'])
    for y in (90, 165, 235, 305, 375):
        s.arrow([(220, y), (290, y)])
    s.box(290, 60, 180, 340, ['Error event encoder', 'type: BIT, STUFF, FORM,', 'ACK, CRC', 'phase: arbitration or data', 'role: transmitter or receiver', 'first error of the frame', 'sets last error code'])
    s.arrow([(470, 120), (540, 120)], 'error event', 475, 112)
    s.box(540, 60, 250, 120, ['Fault confinement counters (m_canfd_eml)', 'TEC + 8 : transmitter flag (exc. 1, 2)', 'REC + 1 : receiver error', 'REC + 8 : dominant after flag; bit error in flag', 'TEC - 1 / REC - 1 after success'])
    s.box(540, 220, 250, 90, ['State', 'active: TEC, REC < 128', 'passive: either >= 128', 'bus-off: TEC >= 256 (INIT set)'])
    s.arrow([(665, 180), (665, 220)], 'TEC, REC', 672, 205)
    s.box(540, 350, 250, 60, ['Bus-off recovery', '11 recessive bits x LPARA count'])
    s.arrow([(665, 310), (665, 350)])
    s.box(850, 60, 190, 100, ['Error signaling control', 'active flag 6 dominant', 'passive flag 6 recessive', 'delimiter 8 recessive'])
    s.arrow([(790, 120), (850, 110)], 'start flag', 796, 112)
    s.arrow([(790, 265), (820, 265), (820, 130), (850, 130)], 'state', 760, 258)
    s.box(850, 220, 190, 90, ['Suspend / overload', 'suspend: 8 bit times when', 'passive and was transmitter', 'overload: max 2 frames'])
    s.arrow([(945, 160), (945, 220)])
    s.box(1080, 60, 140, 100, ['o_can_tx override', 'flag, delimiter,', 'overload', 'to m_canfd_bsp'])
    s.arrow([(1040, 110), (1080, 110)])
    s.box(1080, 220, 140, 90, ['Status to CSR', 'canfd_sts, canfd_ecnt,', 'canfd_lec, interrupts'])
    s.arrow([(790, 290), (840, 340), (1130, 340), (1130, 310)])
    s.text(20, 560, 'Counter rules follow REF-001 section 7: rules 1 to 12 and exceptions 1 and 2. The counters and the state are duplicated and compared when PARA_CANFD_SAF_CNT_EN is set (SM-06).', size=12)
    s.save(path)


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(out, exist_ok=True)
    btl(os.path.join(out, 'canfd_btl_logic.svg'))
    datapath(os.path.join(out, 'canfd_frame_datapath.svg'))
    err(os.path.join(out, 'canfd_error_logic.svg'))
    print('wrote 3 diagrams to', out)
