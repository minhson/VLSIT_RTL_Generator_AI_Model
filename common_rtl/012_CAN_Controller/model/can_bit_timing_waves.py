#!/usr/bin/env python3
# Project  : VLSIT common RTL library
# Function : exports WaveJSON of the bit timing scenarios WF-029 to WF-040 from the reference model
"""Runs the reference model of m_canfd_btl (can_bit_timing_model.py) on the scenarios of section 10.6 and writes
one WaveJSON file per waveform plus wm_notes.json.  Usage: python can_bit_timing_waves.py OUT_DIR"""
import json
import os
import sys

from can_bit_timing_model import Btl, Cfg


def levels(parts, n_total, start_level=1):
    lv, cur, out = dict(parts), start_level, []
    for c in range(n_total):
        cur = lv.get(c, cur)
        out.append(cur)
    return out


def trace(btl, rx, ctrl=None, switch_at=None):
    rows, ns, started = [], 0, False
    for c in range(len(rx)):
        kw = ctrl(c) if ctrl else {}
        seg0, t0 = btl.seg(), btl.t
        r = btl.step(rx[c], **kw)
        if r['sync'] in ('hard', 'resync_hard'):
            seg0, t0 = 'SYNC', 0
        row = {'rx': rx[c], 'rx_s': btl.rx_cur, 'seg': seg0, 't': t0, 'sample': r['sample'], 'val': r['sample_val'],
               'tx_point': r['tx_point'], 'sync': r['sync'], 'ph': btl.ph}
        if r['sync'] == 'hard':
            started = True
        if r['sample'] and started:
            ns += 1
            if switch_at and ns in switch_at:
                btl.apply_switch(switch_at[ns])
                row['ph'] = btl.ph
        rows.append(row)
    return rows


def lvl(vals):
    out, prev = [], None
    for v in vals:
        out.append('.' if v == prev else str(int(v)))
        prev = v
    return ''.join(out)


def dcells(vals):
    out, data, prev = [], [], object()
    for v in vals:
        if v == prev:
            out.append('.')
        else:
            out.append('=')
            data.append(str(v))
        prev = v
    return ''.join(out), data


def sig(name, wave, data=None):
    d = {'name': name, 'wave': wave}
    if data:
        d['data'] = data
    return d


def pulses(vals):
    return ''.join('1' if v else '0' for v in vals)


def wave_of(rows, prefix='', show=('rx', 'rx_s', 'seg', 'tq', 'sync', 'sample', 'val', 'tx')):
    sg = []
    if 'rx' in show:
        sg.append(sig(prefix + 'i_can_rx (pin)', lvl([r['rx'] for r in rows])))
    if 'rx_s' in show:
        sg.append(sig(prefix + 'rx_s (after 2 flops)', lvl([r['rx_s'] for r in rows])))
    if 'seg' in show:
        w, d = dcells([r['seg'] for r in rows])
        sg.append(sig(prefix + 'segment', w, d))
    if 'tq' in show:
        w, d = dcells([r['t'] for r in rows])
        sg.append(sig(prefix + 'tq index', w, d))
    if 'sync' in show:
        sg.append(sig(prefix + 'sync event', ''.join('=' if r['sync'] else '0' for r in rows), [r['sync'] for r in rows if r['sync']]))
    if 'sample' in show:
        sg.append(sig(prefix + 'sample point', pulses([r['sample'] for r in rows])))
    if 'val' in show:
        sg.append(sig(prefix + 'sampled bit', ''.join('=' if r['sample'] else 'x' for r in rows), [str(r['val']) for r in rows if r['sample']]))
    if 'tx' in show:
        sg.append(sig(prefix + 'tx point', pulses([r['tx_point'] for r in rows])))
    return sg


def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    nom = Cfg(1, 6, 3, 2)               # 10 tq of 1 clock: SYNC 1, SEG1 6 (PROP 2 + PHASE_SEG1 4), SEG2 3, SJW 2
    N = nom.bit_clocks
    A = 20                              # clock of the pin edge of SOF
    notes, files = {}, {}

    def make(num, head, foot, sg):
        files[num] = {'signal': sg, 'head': {'text': head}, 'foot': {'text': foot}}
        notes[num] = foot

    def stream(bits, a, shifts=None, extra=0):
        sh = shifts or {}
        parts = [(0, 1)] + [(a + k * N + sh.get(k, 0), b) for k, b in enumerate(bits)]
        return levels(sorted(parts, key=lambda x: x[0]), a + len(bits) * N + extra)

    def idle_run(first_ok=A + 6):
        return lambda c: {'hard_sync_en': c < first_ok}

    # WF-029
    rx = stream([0, 1, 1, 0, 0, 1], A)
    rows = trace(Btl(nom), rx, idle_run())
    make(29, 'WF-029 Bit time segments, sample point and transmit point (1 clock = 1 time quantum)',
         'Bit time of 10 time quanta: SYNC_SEG 1, PROP_SEG + PHASE_SEG1 6, PHASE_SEG2 3, SJW 2. The pin edge of SOF at clock 20 reaches rx_s two clocks later (two-flop synchronizer) and hard-synchronizes the counter: that clock is SYNC_SEG. The sample point is the end of the last SEG1 quantum; the transmit point is the start of SYNC_SEG of the next bit.',
         wave_of(rows[16:A + 4 * N]))

    # WF-030
    rx = stream([0, 1, 0, 0], A + 3)
    rows = trace(Btl(nom), rx, idle_run(A + 9))
    make(30, 'WF-030 Hard synchronization on the SOF edge from bus idle',
         'Before SOF the free-running counter has an arbitrary phase. The recessive to dominant edge of SOF during bus idle restarts the bit time: the clock of the edge becomes SYNC_SEG and the counter continues from tq 1 (REF-002 synchronization rule 3).',
         wave_of(rows[8:A + 2 * N + 4]))

    # WF-031
    rx = stream([0, 1, 0, 0, 1, 1], A, shifts={2: 4, 3: 4, 4: 4, 5: 4})
    rows = trace(Btl(nom), rx, idle_run())
    make(31, 'WF-031 Resynchronization, late edge with a phase error larger than SJW',
         'The third bit starts 4 quanta late (e = +4 > SJW = 2): PHASE_SEG1 is lengthened by SJW = 2, so the sample point of that bit moves 2 quanta later and the cell is 12 quanta long (REF-002 resynchronization). The following edge has e = +2 and acts as a hard synchronization.',
         wave_of(rows[A + N + 4:A + 4 * N + 6]))

    # WF-032
    rx = stream([0, 1, 0, 0, 1, 1], A, shifts={2: -4, 3: -4, 4: -4, 5: -4})
    rows = trace(Btl(nom), rx, idle_run())
    make(32, 'WF-032 Resynchronization, early edge with a phase error larger than SJW',
         'The third bit starts 4 quanta early (e = -4 < -SJW): PHASE_SEG2 is shortened by SJW = 2, the cell is 8 quanta long and the transmit point comes 2 quanta earlier. The next edge has e = -2 and hard-synchronizes.',
         wave_of(rows[A + N + 4:A + 4 * N + 4]))

    # WF-033
    rx = stream([0, 1, 0, 0, 1], A, shifts={2: 1, 3: 1, 4: 1})
    rows = trace(Btl(nom), rx, idle_run())
    make(33, 'WF-033 Resynchronization with a phase error not larger than SJW',
         'The edge is 1 quantum late (e = +1 <= SJW): the effect is the same as a hard synchronization: the bit time restarts with SYNC_SEG at the edge and the sample point keeps its distance (1 + 6 quanta) from the edge.',
         wave_of(rows[A + N + 4:A + 3 * N + 6]))

    # WF-034
    rx = stream([0, 1, 0, 0, 1, 1], A, shifts={2: 4, 3: 4, 4: 4, 5: 4})
    rowsT = trace(Btl(nom), rx, lambda c: {'hard_sync_en': c < A + 6, 'tx_dom': (A + 2 * N <= c < A + 3 * N + 6)})
    rowsR = trace(Btl(nom), rx, idle_run())
    lo, hi = A + N + 4, A + 4 * N + 6
    make(34, 'WF-034 A node that sends a dominant bit does not resynchronize on a positive phase error',
         'The edge arrives 4 quanta late because of the loop delay of the transmitting node itself. The transmitting node ignores it (rule 4): its bit time is not lengthened. A pure receiver sees the same edge as a phase error and lengthens PHASE_SEG1.',
         wave_of(rowsR[lo:hi], '', ('rx',)) + wave_of(rowsT[lo:hi], 'tx node: ', ('seg', 'sync', 'sample')) + wave_of(rowsR[lo:hi], 'rx node: ', ('seg', 'sync', 'sample')))

    # WF-035
    rx = stream([0, 1, 0, 0, 1], A)
    for c in range(A + N + 7, A + N + 8):
        rx[c] = 0
    rows = trace(Btl(nom), rx, idle_run())
    make(35, 'WF-035 Synchronization rules: a glitch edge is used once',
         'A one-clock dominant glitch inside the recessive bit is a recessive to dominant edge after a recessive sample: it resynchronizes once (rule 2). A second edge before the next sample point is ignored (rule 1), and a dominant to recessive edge never synchronizes (rule 4).',
         wave_of(rows[A + N - 2:A + 3 * N + 4]))

    # WF-036 bit rate switch and back
    nomS, datS = Cfg(1, 6, 3, 2), Cfg(1, 2, 1, 1)
    seq = [(0, 10), (1, 10), (0, 10), (1, 8), (0, 4), (1, 4), (0, 4), (1, 6)]
    parts, c = [(0, 1)], A
    for lvl_, ln in seq:
        parts.append((c, lvl_))
        c += ln
    parts.append((c, 1))
    rx = levels(sorted(parts, key=lambda x: x[0]), c + 24)
    rows = trace(Btl(nomS, datS), rx, idle_run(), switch_at={4: 'D', 8: 'N'})
    seg = rows[A + 2 * N - 2:A + 2 * N + 50]
    sg = wave_of(seg, '', ('rx', 'seg', 'sample', 'tx'))
    w, d = dcells([r['ph'] for r in seg])
    sg.insert(2, sig('bit time in use', w, ['nominal' if x == 'N' else 'data' for x in d]))
    make(36, 'WF-036 Bit rate switch at the BRS bit and switch back at the CRC delimiter',
         'Nominal bit 10 quanta, data bit 4 quanta. The controller switches immediately after the sample point of the recessive BRS bit: that bit lasts 1 + 6 nominal quanta plus PHASE_SEG2 of the data configuration (8 quanta); the CRC delimiter lasts SYNC + SEG1 in data quanta plus PHASE_SEG2 in nominal quanta (6 quanta). Together they last one nominal plus one data bit (REF-002 section 8).',
         sg)

    # WF-038 secondary sample point
    n = 40
    tx = levels([(0, 1), (8, 0), (12, 1), (16, 1), (20, 0), (24, 1), (28, 0), (32, 1)], n)
    delay, off = 6, 2
    rxl = [1] * delay + tx[:n - delay]
    strobe = [1 if (c - delay - off) >= 8 and ((c - delay - off - 8) % 4 == 0) else 0 for c in range(n)]
    cmpd = ['%d=%d' % (tx[c - delay - off], rxl[c]) for c in range(n) if strobe[c]]
    make(37, 'WF-037 Secondary sample point with a loop delay longer than the data bit',
         'Data bit 4 quanta, loop delay 6 quanta (longer than a bit), offset 2: the delay is measured at the edge from FDF to res (clock 8 to 14). The transmitted bit is compared with the received bit at the secondary sample point, 8 quanta after the start of the transmitted bit, i.e. after the end of that bit; the received value at the normal sample point is ignored by the transmitter (REF-002 transceiver delay compensation).',
         [sig('o_can_tx', lvl(tx)), sig('i_can_rx (delayed by 6)', lvl(rxl)), sig('secondary sample point', pulses(strobe)),
          sig('compare tx with rx', ''.join('=' if s else 'x' for s in strobe), cmpd)])

    # WF-039
    rx = stream([0, 1, 1, 1, 0, 1], A, shifts={4: 2, 5: 2})
    rows = trace(Btl(nom), rx, lambda c: {'hard_sync_en': c < A + 6, 'hs_edl': c == A + 4 * N + 4})
    make(38, 'WF-038 Hard synchronization on the recessive to dominant edge from FDF to res',
         'In an FD frame the receiver hard-synchronizes at the edge from the FDF bit (recessive) to the res bit (dominant), even with a phase error, so that the data phase that follows starts from a fresh alignment (REF-002 rule 3). The same edge starts the delay measurement of the transmitter.',
         wave_of(rows[A + 3 * N + 2:A + 6 * N]))

    # WF-040
    rx = [1] * 80
    rx[20] = 0
    for c in range(40, 60):
        rx[c] = 0
    rows = trace(Btl(nom, edge_filter=True), rx, lambda c: {'hard_sync_en': True})
    make(39, 'WF-039 Edge filtering during bus integration',
         'With the edge filter set, two consecutive dominant quanta are needed for the hard synchronization while the bus integration runs. The one-clock glitch at clock 20 is ignored; the real SOF at clock 40 synchronizes.',
         wave_of(rows[14:66], '', ('rx', 'rx_s', 'seg', 'sync')))


    # ---- error monitoring waveforms (hand-built from the rules of REF-001 section 6 and 7)
    def cells(n_, d):
        w_, dd = [], []
        for c in range(n_):
            if c in d:
                w_.append('=')
                dd.append(d[c])
            else:
                w_.append('.' if c else 'x')
        return ''.join(w_), dd

    n = 8
    f, fd = cells(n, {0: 'ARB', 2: 'CTRL', 4: 'ACK', 6: 'DATA'})
    r, rd = cells(n, {1: 'arb. lost', 3: 'BIT ERR', 5: 'ACK ok', 7: 'BIT ERR'})
    make(40, 'WF-040 Bit monitoring of the transmitter and its exceptions',
         'Four independent cases, two bits each (the bit before and the monitored bit). A recessive bit sent in the arbitration field and read dominant is a loss of arbitration, not an error; a recessive bit sent in the control field and read dominant is a bit error; a recessive bit in the ACK slot read dominant is the acknowledge; a dominant bit sent in the data field and read recessive is a bit error (REF-001 section 6.1).',
         [sig('field', f, fd), sig('o_can_tx', '11111100'),
          sig('i_can_rx (bus)', '10101001'), sig('monitor result', r, rd),
          sig('bit_err', '00010001')])
    n = 14
    r2, rd2 = cells(n, {0: 'CRC end', 1: 'CRCd', 2: 'ACK', 3: 'ACKd', 4: 'error flag (6 bits)', 10: 'delimiter'})
    make(41, 'WF-041 Start of the error flag: CRC error and other errors',
         'A node that finds a CRC error does not acknowledge the frame and starts its error flag at the bit after the ACK delimiter (columns 4 to 9). For a bit, stuff, form or acknowledge error the flag starts at the next bit (WF-007). An error-active node sends 6 dominant bits, an error-passive node 6 recessive bits.',
         [sig('field', r2, rd2), sig('o_can_tx (receiver, error active)', '11110000001111'),
          sig('crc_err', '01000000000000'), sig('err_flag_active', '00001111110000')])
    n = 10
    e, ed = cells(n, {0: 'start', 1: 'rx err', 2: 'tx err', 3: 'tx ok', 4: 'rx ok', 5: '...', 6: 'tx err', 7: 'tx err'})
    t, td = cells(n, {0: '0', 2: '8', 3: '7', 5: '120', 6: '128', 7: '136'})
    rr, rrd = cells(n, {0: '0', 1: '1', 4: '0'})
    ft, ftd = cells(n, {0: 'ACTIVE', 7: 'PASSIVE'})
    make(42, 'WF-042 Error counters and the change from error active to error passive',
         'Events, not bits. A receiver error adds 1 to REC, an error of the transmitter adds 8 to TEC, a successful frame subtracts 1. The transmit error counter reaching 128 makes the node error passive; the error that causes it still gets an active error flag, the next error flag is 6 recessive bits and it waits 8 bit times after the intermission before it sends again (REF-001 section 7).',
         [sig('event', e, ed), sig('TEC', t, td), sig('REC', rr, rrd), sig('ep (error passive)', '0000001111'),
          sig('error flag type', ft, ftd)])

    for num, v in files.items():
        json.dump(v, open(os.path.join(out_dir, 'wm_%03d.json' % num), 'w', encoding='utf-8'), indent=1)
    json.dump({str(k): v for k, v in notes.items()}, open(os.path.join(out_dir, 'wm_notes.json'), 'w', encoding='utf-8'), indent=1)
    print('wrote', len(files), 'waveforms to', out_dir)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
