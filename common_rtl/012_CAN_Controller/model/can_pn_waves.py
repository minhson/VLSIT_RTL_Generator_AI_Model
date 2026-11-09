#!/usr/bin/env python3
# Project  : VLSIT common RTL library
# Function : WaveJSON WF-065 to WF-068 of the sleep, wake-up and partial networking behavior (section 10.15)
"""Usage: python can_pn_waves.py OUT_DIR   (writes pn_wf_065..068.json and pn_notes.json)"""
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

    n = 16
    bus, bd = cells(n, {0: 'frame', 4: 'EOF', 5: 'INT', 6: 'idle'}, '=')
    st, std = cells(n, {0: 'NORMAL', 2: 'SLEEP_PEND', 7: 'SLEEP'}, '=')
    make(65, 'WF-065 Sleep entry: the frame on the bus is finished first, a pending Tx request refuses the sleep',
         'Software writes sleep_req at column 2 while a frame is on the bus. The controller finishes the frame, waits for the end of the intermission and the bus idle (column 6), checks that no Tx request is pending, sets INIT, drives o_trcv_en low and shows the state sleep (column 7). The second case at the right (columns 10 to 15): with a Tx request pending the sleep is refused, slp_blk of cfd_wksrc is set and the controller stays in NORMAL; software cancels the request and asks again (DEC-045).',
         [sig('bus', bus, bd), sig('sleep_req (sw)', pul(n, [2, 11])), sig('power state (first request)', st, std), sig('Tx request pending', lv(n, {0: '0', 10: '1'})),
          sig('init', lv(n, {0: '0', 7: '1'})), sig('o_trcv_en', lv(n, {0: '1', 7: '0'})), sig('slp_blk (cfd_wksrc)', lv(n, {0: '0', 12: '1'}))])

    n = 14
    fld, fdd = cells(n, {0: 'SOF', 1: 'ID', 3: 'CTRL', 4: 'DATA', 7: 'CRC', 10: 'CRCd', 11: 'ACK'}, 'x')
    make(66, 'WF-066 Wake-up frame match: the filter compares the bits on the fly and wakes at the CRC delimiter',
         'In sleep the controller listens and sends nothing (no acknowledge). The frame passes through the bit-serial filter: the identifier is compared with the filter identifier through the mask (columns 1 to 2), then the DLC and the data bytes with their masks; a mismatch in any field turns the match flag off. The CRC is computed on the destuffed bits; at the CRC delimiter (column 10) a still-valid match with a correct CRC sets o_wake_req. A frame with a CRC or stuff error, an FD frame or a frame that does not match does not wake the node (WF-068).',
         [sig('field', fld, fdd), sig('i_can_rx', '1' + '0101101011010'), sig('match so far', lv(n, {0: '1', 7: '1'})), sig('CRC ok', lv(n, {0: '0', 10: '1'})),
          sig('o_wake_req', lv(n, {0: '0', 11: '1'})), sig('cfd_wksrc.src_wuf', lv(n, {0: '0', 11: '1'}))])

    n = 18
    st, std = cells(n, {0: 'WAKE_PEND', 3: 'RESTART', 5: 'integrating', 16: 'NORMAL'}, '=')
    make(67, 'WF-067 Wake-up and restart: transceiver start-up delay, INIT cleared, bus integration',
         'The wake-up request o_wake_req stays high until software acknowledges it (wake_ack, column 3); the SoC power controller has restarted the BUS clock and the software runs. Software sets trcv_on, the controller raises o_trcv_en and waits the transceiver start-up time trcv_dly (columns 3 to 5); software clears init at column 5; the bus integration waits for 11 recessive bits (columns 5 to 16) before the node takes part in the communication; the frame that woke the node was not stored.',
         [sig('o_wake_req', lv(n, {0: '1', 4: '0'})), sig('wake_ack (sw)', pul(n, [3])), sig('o_trcv_en', lv(n, {0: '0', 3: '1'})), sig('trcv_dly running', lv(n, {0: '0', 3: '1', 5: '0'})),
          sig('init', lv(n, {0: '1', 5: '0'})), sig('state', st, std), sig('bus integration (11 recessive)', lv(n, {0: '0', 5: '1', 16: '0'}))])

    n = 14
    fld, fdd = cells(n, {0: 'SOF', 1: 'ID differs', 3: 'CTRL', 4: 'DATA', 7: 'CRC', 10: 'CRCd', 11: 'ACK'}, 'x')
    fld2, fd2 = cells(n, {0: 'FD frame', 1: 'FDF bit recessive: ignored until the idle bus', 10: 'idle'}, 'x')
    make(68, 'WF-068 Frames that do not wake the node: another identifier, an error, an FD frame',
         'Three cases. First: the identifier differs (column 1), the match flag falls and stays low until the next SOF; the CRC delimiter gives no wake request. Second (not drawn): a frame with a CRC or stuff error clears the match and is ignored; with pn_err_ign the error counters do not change in sleep. Third: a recessive FDF bit shows an FD frame: the filter stops until the bus is idle again and the frame is neither a match nor an error (FD passive, ASM-019). In all cases the node sends nothing.',
         [sig('first case: field', fld, fdd), sig('match so far', lv(n, {0: '1', 2: '0'})), sig('o_wake_req', '0' * n), sig('third case: bus', fld2, fd2), sig('filter active', lv(n, {0: '1', 2: '0', 10: '1'}))])

    for k, v in files.items():
        json.dump(v, open(os.path.join(out, 'pn_wf_%03d.json' % k), 'w', encoding='utf-8'), indent=1)
    json.dump({str(k): v for k, v in notes.items()}, open(os.path.join(out, 'pn_notes.json'), 'w', encoding='utf-8'), indent=1)
    print('wrote', len(files), 'waveforms to', out)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
