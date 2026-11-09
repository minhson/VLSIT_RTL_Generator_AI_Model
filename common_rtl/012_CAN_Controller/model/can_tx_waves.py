#!/usr/bin/env python3
# Project  : VLSIT common RTL library
# Function : WaveJSON WF-047 to WF-049 and the logic diagram of the transmit path
"""Usage: python can_tx_waves.py OUT_DIR   (writes tx_wf_047..049.json, tx_notes.json and canfd_tx_logic.svg)"""
import json
import os
import sys

from can_logic_diagrams import Svg


def cells(n, d, first='x'):
    w, data = [], []
    for c in range(n):
        if c in d:
            w.append('=')
            data.append(d[c])
        else:
            w.append(first if c == 0 else '.')
    return ''.join(w), data


def lv(n, ch):
    return ''.join(ch[c] if c in ch else '.' for c in range(n))


def pul(n, cols):
    return ''.join('1' if c in cols else '0' for c in range(n))


def sig(name, wave, data=None):
    r = {'name': name, 'wave': wave}
    if data:
        r['data'] = data
    return r


def main(out):
    os.makedirs(out, exist_ok=True)
    files, notes = {}, {}

    def make(num, head, foot, sg):
        files[num] = {'signal': sg, 'head': {'text': head}, 'foot': {'text': foot.split('. ')[0] + ' (notes: section 10.3)'}}
        notes[num] = foot

    n = 8
    bus, bd = cells(n, {0: 'DATA', 1: 'CRC', 2: 'ACK', 3: 'EOF', 4: 'INT 1', 5: 'INT 2', 6: 'INT 3', 7: 'SOF'}, '=')
    pa, pad = cells(n, {0: 'scan', 1: 'fetch', 2: 'ready'}, 'x')
    ra, rad = cells(n, {3: 'scan', 4: 'fetch', 5: 'fetch', 6: 'ready'}, 'x')
    make(47, 'WF-047 Transmit commit point: prefetch mode and re-scan mode',
         'One cell is a field of the bus (not to scale). Prefetch mode (PARA_CANFD_TX_PREFETCH = 1): the winner among the other pending buffers is scanned and fetched while the present frame is still on the bus; the choice is frozen at the start of EOF, a request that arrives later waits for the frame after. Re-scan mode (0): the scan starts at EOF and the fetch ends before the SOF, so a request that arrives until EOF still competes, but the three intermission bits must cover scan, fetch and crossing (section 10.12.5).',
         [sig('frame on the bus', bus, bd), sig('prefetch: scan, fetch', pa, pad), sig('prefetch: frozen', pul(n, [3])),
          sig('re-scan: scan, fetch', ra, rad), sig('late request', pul(n, [4])),
          sig('early request', pul(n, [2]))])

    n = 12
    att, ad = cells(n, {0: 'frame 1', 3: 'frame 2', 6: 'frame 3', 9: 'idle'}, 'x')
    res, rd = cells(n, {2: 'error', 5: 'error', 8: 'error + limit'}, 'x')
    tri, td = cells(n, {0: '0', 2: '1', 5: '2', 8: '3 > 2'}, '=')
    make(48, 'WF-048 Retransmission limit of 2 (RTL = 3): the buffer is cancelled after the third failed attempt',
         'The element of the buffer has RTL = 3, which allows 2 retransmissions. Every failed attempt (error or lost arbitration) leaves the request set; the third failure exceeds the limit: the request is cleared, the cancellation flag and the fail flag of the buffer are set and no more attempts are made. The counter belongs to the buffer and keeps its value while other buffers are sent between the attempts. RTL = 0 uses the global retry_max, RTL = 1 is a single shot, RTL = 7 is unlimited.',
         [sig('attempt', att, ad), sig('result', res, rd), sig('retry counter of the buffer', tri, td), sig('Tx request (buffer)', lv(n, {0: '1', 8: '0'})),
          sig('cancellation done', lv(n, {0: '0', 8: '1'})), sig('fail flag', lv(n, {0: '0', 8: '1'})), sig('tx_can event', lv(n, {0: '0', 9: '1'}))])

    n = 10
    st, std = cells(n, {0: 'request set', 1: 'not valid, data request', 4: 'valid', 5: 'candidate', 6: 'sent'}, 'x')
    make(49, 'WF-049 Trigger transmit buffer: only valid data is sent',
         'The trigger-transmit buffer (TRTX = 1) is requested at column 0 with its header only; the handler caches the header and raises the data request. The buffer is not a candidate, so the other buffer is sent at column 2 and nothing blocks it. Software writes the data and sets the confirm at column 3; from column 4 the buffer is valid and a candidate; it is sent when it wins (column 6). A late confirm only makes the buffer a candidate later; there is no timeout and no missed slot (DEC-030).',
         [sig('trigger buffer state', st, std), sig('request bit', lv(n, {0: '0', 1: '1', 7: '0'})), sig('cfd_txb_dreq bit', lv(n, {0: '0', 1: '1', 4: '0'})),
          sig('software writes data', pul(n, [2, 3])), sig('cfd_txb_trtx confirm', pul(n, [3])), sig('other buffer sent', pul(n, [2])), sig('trigger buffer sent', pul(n, [6]))])

    n = 3
    r1, d1 = cells(n, {0: 'A', 1: 'B', 2: 'C'}, '=')
    r2, d2 = cells(n, {0: 'B', 1: 'A', 2: 'C'}, '=')
    r3, d3 = cells(n, {0: 'C', 1: 'A', 2: 'B'}, '=')
    r4, d4 = cells(n, {0: 'C', 1: 'B', 2: 'A'}, '=')
    make(50, 'WF-050 Priority configurations: the order of three requested buffers',
         'Three buffers are requested together: A (identifier 0x100, PRIO 5), B (identifier 0x200, PRIO 1) and C = buffer 0 (identifier 0x7FF, PRIO 9). By identifier the order is A, B, C. With the fixed priority of the PRIO field it is B, A, C. With the express function buffer 0 (C) is first in both modes: C, A, B and C, B, A (section 10.12.3).',
         [sig('by identifier (exp_en = 0)', r1, d1), sig('fixed priority (exp_en = 0)', r2, d2), sig('by identifier, express', r3, d3), sig('fixed priority, express', r4, d4)])

    for k, v in files.items():
        json.dump(v, open(os.path.join(out, 'tx_wf_%03d.json' % k), 'w', encoding='utf-8'), indent=1)
    json.dump({str(k): v for k, v in notes.items()}, open(os.path.join(out, 'tx_notes.json'), 'w', encoding='utf-8'), indent=1)

    s = Svg(1240, 560, 'Logic diagram of the transmit path (m_canfd_txh, CLK-BUS)')
    s.box(20, 60, 190, 80, ['Request, cancel, done flags', 'cfd_txb_req, cfd_txb_cancel', 'cfd_txb_done, cfd_txb_cdone'])
    s.box(270, 60, 190, 80, ['Key cache', 'identifier, PRIO, RTL, TRTX,', 'EFC, valid, retry counter'])
    s.arrow([(210, 100), (270, 100)], 'request', 214, 93)
    s.box(520, 60, 190, 80, ['Scan and priority', 'candidates only, one per clock', 'express first, key of 10.12.3'])
    s.arrow([(460, 100), (520, 100)])
    s.box(770, 60, 190, 80, ['FIFO / queue select', 'FIFO: head from get index', 'queue: lowest key'])
    s.arrow([(710, 100), (770, 100)])
    s.box(1020, 60, 190, 80, ['Fetch sequencer', 'header and data words'])
    s.arrow([(960, 100), (1020, 100)])
    s.box(1020, 200, 190, 80, ['Message RAM master', 'u_mram', 'one request at a time'])
    s.arrow([(1115, 140), (1115, 200)], 'read', 1123, 175)
    s.box(770, 200, 190, 80, ['Tx transfer register(s)', 'current (and next with', 'PARA_CANFD_TX_PREFETCH)'])
    s.arrow([(1060, 280), (1060, 300), (865, 300), (865, 280)], 'words', 940, 294)
    s.box(520, 200, 190, 80, ['Crossing CDC-006', 'four-phase handshake', 'to m_canfd_bsp'])
    s.arrow([(770, 240), (710, 240)])
    s.box(270, 200, 190, 80, ['Frame engine result', 'sent, lost arbitration,', 'error (from m_canfd_bsp)'])
    s.arrow([(520, 260), (460, 260)], 'result', 478, 252)
    s.box(20, 200, 190, 80, ['Retry control', 'RTL and cfd_txr_cfg.retry_max', 'counter per buffer'])
    s.arrow([(270, 240), (210, 240)])
    s.arrow([(115, 200), (115, 140)], 'clear, cancel, fail', 123, 175)
    s.box(770, 340, 190, 80, ['Trigger transmit', 'data request, confirm', '(PARA_CANFD_TRTX_EN)'])
    s.arrow([(865, 340), (865, 280)])
    s.box(270, 340, 190, 80, ['Tx event writer', 'identifier, marker,', 'type, timestamp'])
    s.arrow([(365, 280), (365, 340)])
    s.box(520, 340, 190, 80, ['Tx event FIFO', 'put, get, fill, full, lost', 'full: event lost, frame sent'])
    s.arrow([(460, 380), (520, 380)])
    s.box(20, 340, 190, 80, ['Events', 'tx_done, tx_can, tx_emp,', 'txe_new, txe_wm, txe_ful'])
    s.arrow([(270, 380), (210, 380)])
    s.text(20, 520, 'A pending buffer is never changed by the IP; software must not change it either. Only a candidate (request set, header cached, data valid) is fetched and sent.', size=12)
    s.save(os.path.join(out, 'canfd_tx_logic.svg'))
    print('wrote', len(files), 'waveforms and 1 diagram to', out)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
