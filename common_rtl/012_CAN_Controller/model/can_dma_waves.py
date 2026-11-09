#!/usr/bin/env python3
# Project  : VLSIT common RTL library
# Function : WaveJSON WF-059 to WF-064 of the DMA request logic (section 10.14)
"""Usage: python can_dma_waves.py OUT_DIR   (writes dma_wf_059..064.json and dma_notes.json)"""
import json
import os
import sys


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
        short = foot.split('. ')[0]
        short = short if len(short) <= 105 else short[:105].rsplit(' ', 1)[0] + ' ...'
        files[num] = {'signal': sg, 'head': {'text': head}, 'foot': {'text': short + ' (notes: section 10.3)'}}
        notes[num] = foot

    n = 14
    fill, fd = cells(n, {0: '0', 1: '1', 9: '0'}, '=')
    make(59, 'WF-059 Rx DMA request for one message (watermark 1) and the re-arm rule',
         'BUS clock. A message arrives at column 1 and the request rises at column 2. The DMA engine reads the element from the message RAM (not shown) and writes the acknowledge index with ack_go at column 6; it pulses the acknowledge at column 7, which drops the request. The hardware takes ack_go and moves the get index two clocks later (column 9). With the naive rule the request would rise again at column 8 because the fill level still shows the message; the specified re-arm rule holds the request low until ack_go is taken and the fill level has fallen (DEC-041).',
         [sig('i_clk_bus', 'p' * n), sig('rx0 fill level', fill, fd), sig('o_dma_req_rx0 (specified rule)', lv(n, {0: '0', 2: '1', 7: '0'})), sig('i_dma_ack_rx0', pul(n, [7])),
          sig('ack_go (cfd_rxf0_ack)', lv(n, {0: '0', 6: '1', 9: '0'})), sig('request with the naive rule', lv(n, {0: '0', 2: '1', 7: '0', 8: '1', 9: '0'}))])

    n = 16
    fill, fd = cells(n, {0: '0', 1: '1', 2: '2', 3: '3', 4: '4', 13: '0'}, '=')
    make(60, 'WF-060 Rx DMA burst of four messages (watermark 4)',
         'The watermark is the burst size: the request rises when the fill level reaches 4 (column 5) and stays until the DMA engine has moved the four messages and pulses the acknowledge (column 11); the acknowledge index of the last message is written with ack_go at column 10. After the update the level is 0 and the request stays low. One request therefore means one burst, and a fill level below the watermark is not served (the low-traffic case, decision below).',
         [sig('i_clk_bus', 'p' * n), sig('rx0 fill level', fill, fd), sig('o_dma_req_rx0', lv(n, {0: '0', 5: '1', 11: '0'})), sig('DMA reads four elements', lv(n, {0: '0', 6: '1', 10: '0'})),
          sig('ack_go (cfd_rxf0_ack)', lv(n, {0: '0', 10: '1', 13: '0'})), sig('i_dma_ack_rx0', pul(n, [11]))])

    n = 16
    used, ud = cells(n, {0: '0', 8: '1', 13: '2'}, '=')
    make(61, 'WF-061 Tx DMA request while Tx FIFO buffers are free (two buffers)',
         'The request rises while the Tx FIFO part has a free buffer. The DMA engine writes one element into the buffer at the put index, sets its request bit in cfd_txb_req and pulses the acknowledge (columns 5 to 6). The request bit makes the buffer used two clocks later (column 8) and the request rises again for the second buffer; when both buffers are used the request stays low until a transmission frees one. The put index is derived from the request bits, so the DMA engine reads cfd_txf_sts.pidx once and counts.',
         [sig('i_clk_bus', 'p' * n), sig('used Tx FIFO buffers', used, ud), sig('o_dma_req_tx', lv(n, {0: '1', 6: '0', 9: '1', 12: '0', 14: '1'})),
          sig('DMA writes the element', lv(n, {0: '0', 3: '1', 5: '0', 10: '1', 11: '0'})), sig('request bit set (cfd_txb_req)', pul(n, [5, 11])), sig('i_dma_ack_tx', pul(n, [6, 12])),
          sig('frame sent (frees a buffer)', pul(n, [14]))])

    n = 18
    fill, fd = cells(n, {0: '0', 1: '1', 14: '0'}, '=')
    make(62, 'WF-062 Burst service with the flush timeout: one message below the watermark is served',
         'Burst service with watermark 4 and a timeout (shortened to 8 clocks for the drawing; the register counts 64 BUS clocks per step). One message arrives at column 1 and is below the watermark; the timer runs from its arrival and the flush request rises at column 9 with the flag rx0_fl set, so the DMA engine reads the fill level (1) and moves one message; after the acknowledge at column 15 the timer restarts and the request stays low. Without the timeout (dma_to = 0) the message would wait for three more messages.',
         [sig('i_clk_bus', 'p' * n), sig('rx0 fill level', fill, fd), sig('flush timer running', lv(n, {0: '0', 1: '1', 9: '0'})), sig('o_dma_req_rx0', lv(n, {0: '0', 9: '1', 15: '0'})),
          sig('rx0_fl (cfd_dma_sts)', lv(n, {0: '0', 9: '1', 15: '0'})), sig('ack_go (cfd_rxf0_ack)', lv(n, {0: '0', 13: '1', 14: '0'})), sig('i_dma_ack_rx0', pul(n, [15]))])

    n = 14
    make(63, 'WF-063 Four-phase handshake (PARA_CANFD_DMA_HS = 1)',
         'The acknowledge is a level. Phase 1: the IP raises the request (column 2). Phase 2: the DMA engine raises the acknowledge when its service is finished (column 5). Phase 3: the IP drops the request when it sees the acknowledge (column 6). Phase 4: the engine drops the acknowledge when it sees the request low (column 8). The IP re-arms only when the acknowledge is low and the effect of the engine\'s write is complete (ack_go taken, fill level updated); the pulse mode needs no phase 4.',
         [sig('i_clk_bus', 'p' * n), sig('o_dma_req_rx0', lv(n, {0: '0', 2: '1', 6: '0'})), sig('i_dma_ack_rx0 (level)', lv(n, {0: '0', 5: '1', 8: '0'})), sig('ack_go (cfd_rxf0_ack)', lv(n, {0: '0', 4: '1', 7: '0'})),
          sig('rx0 fill level', *cells(n, {0: '1', 7: '0'}, '=')), sig('request may rise again', lv(n, {0: '0', 9: '1'}))])

    n = 16
    make(64, 'WF-064 Tx event DMA burst of two events (watermark 2)',
         'The Tx event FIFO holds the events of the frames that were sent with EFC set. With watermark 2 and the burst service the request o_dma_req_txe rises when the second event is stored (column 4). The engine reads the two event elements (3 words each) from the event section, writes ack_idx and ack_go to cfd_txe_ack and pulses the acknowledge (column 12); the request stays low until the level is updated. A single event below the watermark is served by the flush timeout like in WF-062.',
         [sig('i_clk_bus', 'p' * n), sig('Tx event fill level', *cells(n, {0: '0', 2: '1', 4: '2', 11: '0'}, '=')), sig('o_dma_req_txe', lv(n, {0: '0', 5: '1', 12: '0'})),
          sig('DMA reads two events', lv(n, {0: '0', 6: '1', 10: '0'})), sig('ack_go (cfd_txe_ack)', lv(n, {0: '0', 10: '1', 12: '0'})), sig('i_dma_ack_txe', pul(n, [12]))])

    for k, v in files.items():
        json.dump(v, open(os.path.join(out, 'dma_wf_%03d.json' % k), 'w', encoding='utf-8'), indent=1)
    json.dump({str(k): v for k, v in notes.items()}, open(os.path.join(out, 'dma_notes.json'), 'w', encoding='utf-8'), indent=1)
    print('wrote', len(files), 'waveforms to', out)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
