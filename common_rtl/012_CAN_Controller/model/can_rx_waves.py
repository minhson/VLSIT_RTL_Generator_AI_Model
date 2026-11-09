#!/usr/bin/env python3
# Project  : VLSIT common RTL library
# Function : WaveJSON of the receive path scenarios WF-044 to WF-046 and the logic diagram of the receive path
"""Usage: python can_rx_waves.py OUT_DIR   (writes rx_wf_044..046.json, rx_notes.json and canfd_rx_logic.svg)"""
import json
import os
import sys

from can_logic_diagrams import Svg


def lvl(n, ch):
    out, prev = [], None
    for c in range(n):
        if c in ch:
            out.append(ch[c])
            prev = ch[c]
        else:
            out.append('.')
    return ''.join(out)


def cells(n, d, first='x'):
    w, data = [], []
    for c in range(n):
        if c in d:
            w.append('=')
            data.append(d[c])
        else:
            w.append(first if c == 0 else '.')
    return ''.join(w), data


def sig(name, wave, data=None):
    r = {'name': name, 'wave': wave}
    if data:
        r['data'] = data
    return r


def pul(n, cols):
    return ''.join('1' if c in cols else '0' for c in range(n))


def main(out):
    os.makedirs(out, exist_ok=True)
    notes, files = {}, {}

    def make(num, head, foot, sg):
        files[num] = {'signal': sg, 'head': {'text': head}, 'foot': {'text': foot.split('. ')[0] + ' (notes: section 10.3)'}}
        notes[num] = foot

    # WF-044 filter walk with one wait state: each word costs 2 + wait = 3 clocks
    n = 16
    req = ''.join('1' if (c in (2, 3, 5, 6, 8, 9)) else '0' for c in range(n))
    ack = pul(n, [3, 6, 9])
    fidx, fd = cells(n, {2: '0', 5: '1', 8: '2', 11: 'x'})
    typ, td = cells(n, {2: 'range', 5: 'dual', 8: 'mask', 11: 'x'})
    act, ad = cells(n, {11: 'FIFO 0 (element 2)'})
    make(44, 'WF-044 Acceptance filter walk in list order with one RAM wait state',
         'BUS clock. The received frame (base format, identifier 0x402) waits in the transfer register. One filter element is read per access; an access costs 2 + 1 clocks (request, acknowledge, one idle clock, REQ-IF-002). The range and the dual element do not match, the mask element matches: the walk stops and the action is taken; later elements are not read. A standard list of 128 elements costs up to 128 x 3 = 384 clocks. The same frame in blocking or overwrite mode is stored next (WF-010).',
         [sig('i_clk_bus', 'p' * n), sig('rx_valid (transfer register)', lvl(n, {0: '0', 1: '1'})), sig('o_mram_req', req), sig('i_mram_ack', ack),
          sig('filter index', fidx, fd), sig('element type', typ, td), sig('match', pul(n, [10])), sig('action', act, ad)])

    # WF-045 overwrite mode: concurrent read of the element at the get index
    n = 10
    sw, swd = cells(n, {1: 'word 1', 3: 'data 0', 5: 'word 1 again'})
    hw, hwd = cells(n, {2: 'W0', 3: 'W1', 4: 'W2', 5: 'put'})
    gen, gd = cells(n, {0: '1', 3: '2'}, first='=')
    make(45, 'WF-045 Overwrite mode: an element is overwritten while software reads it',
         'FIFO full in overwrite mode: the new message replaces the oldest element, at the get index. Software has read word 1 (generation 1) and the first data word; the hardware writes the new element and the generation counter in word 1 changes to 2. Software reads word 1 again at the end, sees the changed generation and discards what it read (DEC-024). The lost flag is set by the overwrite.',
         [sig('software reads element 0', sw, swd), sig('hardware writes element 0', hw, hwd), sig('generation (word 1 bits 23:22)', gen, gd),
          sig('lost flag', lvl(n, {0: '0', 3: '1'})), sig('get index', *cells(n, {0: '0', 5: '1'}, first='=')),
          sig('software decision', *cells(n, {6: 'generation differs: discard'}))])

    # WF-046 handoff overrun
    n = 12
    f0, f0d = cells(n, {1: 'F1', 8: 'free'}, first='=')
    f1, f1d = cells(n, {3: 'F2', 10: 'free'}, first='=')
    hdl, hd = cells(n, {2: 'store F1', 8: 'store F2', 11: 'idle'}, first='=')
    make(46, 'WF-046 Handoff overrun when both transfer registers are full',
         'PARA_CANFD_RXHOLD_NUM = 2. Frames F1 and F2 are complete at columns 1 and 3 and fill the two transfer registers; the handler is slow (RAM wait states) and stores F1 first. Frame F3 completes at column 5: no register is free, the frame is lost before the filter and the sticky flag ovr of cfd_rx_sts is set; no FIFO can be named because the filter has not run. A longer RAM access or a smaller PARA_CANFD_RXHOLD_NUM makes this happen earlier.',
         [sig('frame complete (CAN)', pul(n, [1, 3, 5])), sig('transfer register 0', f0, f0d), sig('transfer register 1', f1, f1d),
          sig('Rx handler', hdl, hd), sig('frame lost (handoff)', pul(n, [5])), sig('cfd_rx_sts.ovr', lvl(n, {0: '0', 5: '1'}))])

    for k, v in files.items():
        json.dump(v, open(os.path.join(out, 'rx_wf_%03d.json' % k), 'w', encoding='utf-8'), indent=1)
    json.dump({str(k): v for k, v in notes.items()}, open(os.path.join(out, 'rx_notes.json'), 'w', encoding='utf-8'), indent=1)

    # logic diagram of the receive path
    s = Svg(1240, 560, 'Logic diagram of the receive path (m_canfd_rxh, m_canfd_flt, CLK-BUS)')
    s.box(20, 60, 170, 70, ['Transfer registers', '1 or 2 registers', '(from CDC-005)'])
    s.box(250, 60, 170, 70, ['Pre-checks', 'remote frame rule', 'FD or Classic, DLC'])
    s.arrow([(190, 95), (250, 95)])
    s.box(480, 60, 190, 70, ['Filter walker (m_canfd_flt)', 'one element per RAM read', 'std list or ext list'])
    s.arrow([(420, 95), (480, 95)])
    s.box(480, 190, 190, 70, ['Element compare', 'range, dual, mask', 'XIDAM for extended ids'])
    s.arrow([(575, 130), (575, 190)], 'element', 583, 165)
    s.box(730, 190, 170, 70, ['First match', 'action, filter index', 'no match: global rule'])
    s.arrow([(670, 225), (730, 225)])
    s.box(730, 60, 170, 70, ['Message RAM master', 'u_mram (one request)', 'at a time'])
    s.arrow([(670, 95), (730, 95)], 'read', 685, 88)
    s.arrow([(815, 130), (815, 190)], 'element word', 823, 165)
    s.box(960, 190, 240, 70, ['Action decode', 'FIFO 0, FIFO 1, buffer n,', 'high priority, reject'])
    s.arrow([(900, 225), (960, 225)])
    s.box(960, 320, 240, 90, ['Store sequencer', 'data words first, then the', 'header word with the generation,', 'then put index / new-data flag'])
    s.arrow([(1080, 260), (1080, 320)])
    s.arrow([(960, 345), (930, 345), (930, 95), (900, 95)], 'write words', 870, 80)
    s.box(480, 320, 190, 90, ['FIFO state', 'get, put, fill, full, lost', 'watermark, overwrite mode'])
    s.arrow([(960, 380), (670, 380)], 'put update', 780, 396)
    s.box(20, 320, 200, 90, ['Status and events', 'rxN_new, rxN_wm, rxN_ful,', 'rxN_lst, rxb_new, hpm,', 'cfd_rx_sts.ovr'])
    s.arrow([(480, 365), (220, 365)])
    s.box(250, 320, 170, 90, ['DMA request', 'fill >= watermark', '(m_canfd_dma)'])
    s.arrow([(480, 395), (420, 395)])
    s.text(20, 520, 'The handler takes the oldest frame of the transfer registers, filters it, stores it and releases the register; a frame that completes while no register is free is lost and sets ovr.', size=12)
    s.save(os.path.join(out, 'canfd_rx_logic.svg'))
    print('wrote', len(files), 'waveforms and 1 diagram to', out)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
