#!/usr/bin/env python3
# Project  : VLSIT common RTL library
# Function : WaveJSON WF-053 to WF-058 and the logic diagram of the TTCAN frame synchronization entity
"""Usage: python can_tt_waves.py OUT_DIR   (writes tt_wf_053..058.json, tt_notes.json and canfd_tt_logic.svg)"""
import json
import os
import sys

from can_logic_diagrams import Svg
import can_tt_model as M


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
        files[num] = {'signal': sg, 'head': {'text': head}, 'foot': {'text': (lambda f: (f if len(f) <= 105 else f[:105].rsplit(' ', 1)[0] + ' ...'))(foot.split('. ')[0]) + ' (notes: section 10.3)'}}
        notes[num] = foot

    # WF-053 system matrix of 4 basic cycles with cycle codes
    n = 8
    cyc, cd = cells(n, {0: '0', 2: '1', 4: '2', 6: '3'}, '=')
    ref, rd = cells(n, {0: 'RM', 2: 'RM', 4: 'RM', 6: 'RM'}, 'x')
    sig_a = ''.join('1' if M.cycle_code_match(0, c // 2) and c % 2 == 1 else '0' for c in range(n))
    sig_d = ''.join('1' if M.cycle_code_match(M.code_for(2, 1), c // 2) and c % 2 == 1 else '0' for c in range(n))
    sig_e = ''.join('1' if M.cycle_code_match(M.code_for(4, 2), c // 2) and c % 2 == 1 else '0' for c in range(n))
    make(53, 'WF-053 System matrix of four basic cycles: the cycle code decides in which cycle a trigger is active',
         'Each pair of columns is one basic cycle: the first column is the reference message, the second the time windows. Message A has the cycle code 0 (every cycle), message D the code 000001c with c = 1 (cycles 1 and 3), message E the code 00001cc with cc = 2 (cycle 2 only). The cycle count comes from the reference message (a time slave takes the received count, a time master counts up to the last basic cycle `ccm`). The model checks that the codes of one period partition the 64 cycles.',
         [sig('cycle count', cyc, cd), sig('reference message', ref, rd), sig('Tx trigger A active', sig_a), sig('Tx trigger D active', sig_d), sig('Tx trigger E active', sig_e)])

    # WF-054 merged arbitrating window with retransmission inside the window
    n = 12
    bus, bd = cells(n, {0: 'RM', 1: 'free', 2: 'X', 5: 'Y (retransmit)', 9: 'free'}, 'x')
    make(54, 'WF-054 Merged arbitrating window: a lost message is sent again inside the same window',
         'The window starts at a Tx_Trigger_Merged of this node (column 2) and ends at the following Tx_Trigger_Single (column 9). Our message Y and another node\'s message X start together, X has the lower identifier and wins; Y lost the arbitration, stays pending and is sent again at column 5 because it is still inside the window and the Tx_Enable window of the merged trigger allowed the start. With a single arbitrating window the retransmission would wait for the next trigger of Y. The request of an event message stays set until the transmission succeeds (REF-010 5.3.2.2).',
         [sig('bus', bus, bd), sig('window of the merged trigger', lv(n, {0: '0', 2: '1', 9: '0'})), sig('Tx_Trigger_Merged', pul(n, [2])), sig('Tx_Trigger_Single (end)', pul(n, [9])),
          sig('Y request', lv(n, {0: '1', 8: '0'})), sig('Y done', lv(n, {0: '0', 8: '1'})), sig('arbitration lost', pul(n, [3]))])

    # WF-055 Tx_Enable window missed
    n = 10
    bus, bd = cells(n, {0: 'RM', 1: 'previous message (long)', 5: 'free'}, 'x')
    make(55, 'WF-055 Tx_Enable window missed because the bus is busy',
         'The trigger of message B becomes active at column 3, but the previous message still occupies the bus. A transmission may only start inside the Tx_Enable window (columns 3 to 4, TEW = 2 NTU); the window ends at column 5 before the bus is free, so the message is not sent in this time window. The missing transmission is counted (the Tx_Underflow of the error level and the miss flag of the buffer). The message is not sent late: the next chance is its trigger in the next basic cycle (strictly time-triggered operation never repeats a message).',
         [sig('bus', bus, bd), sig('trigger B active', pul(n, [3])), sig('Tx_Enable window of B', lv(n, {0: '0', 3: '1', 5: '0'})), sig('start allowed', lv(n, {0: '0', 3: '0', 5: '0'})),
          sig('B sent', '0' * n), sig('buffer miss flag (cfd_ttb_miss)', lv(n, {0: '0', 5: '1'})), sig('txu event (cfd_ttirq_raw)', lv(n, {0: '0', 9: '1'}))])

    # WF-056 time master failure, backup master takes over
    n = 12
    rm, rmd = cells(n, {0: 'RM master 0', 3: 'no RM (master failed)', 6: 'RM backup 1', 9: 'RM backup 1'}, 'x')
    make(56, 'WF-056 Time master failure: the backup master sends the reference message after Init_Ref_Offset',
         'The current time master (priority 0) fails after column 0. The expected start of the next basic cycle passes with an idle bus (column 3). The backup master with master priority 1 waits Init_Ref_Offset = MPr x factor NTU (here the columns 3 to 6) and sends its own reference message; a backup with a lower priority has a longer offset and sees the reference message first, so it does not send. The new reference message has the identifier of master priority 1; the nodes keep their synchronization state. If the offsets were not ordered by priority with the maximum clock drift taken into account, two backup masters could start together and arbitrate (the lower identifier wins).',
         [sig('reference message on the bus', rm, rmd), sig('backup master timer running', lv(n, {0: '0', 3: '1', 6: '0'})), sig('master state of node 1', *cells(n, {0: 'backup', 6: 'current master'}, '=')),
          sig('sync state of the slaves', *cells(n, {0: 'in schedule'}, '='))])

    # WF-057 gap in the event-synchronised mode
    n = 12
    bus, bd = cells(n, {0: 'basic cycle', 4: 'RM Next_is_Gap', 5: 'gap: bus idle', 9: 'RM'}, 'x')
    make(57, 'WF-057 Event-synchronised operation: a gap after a basic cycle and the restart by the event',
         'The time master sets Next_is_Gap (software bit nig or the level of the event pin when epe is set) before the reference message of the last basic cycle. At the end of that cycle the gap starts: all transmissions stop and the bus stays idle (the nodes are in the state in gap and use the gap variants of the reference and watch triggers). The gap ends when the master restarts the schedule: by the bit fgp, by the low level of the event pin, by the time mark of tmg, or at its Tx_Ref_Trigger_Gap if the event did not come in time. The next reference message starts a normal basic cycle.',
         [sig('bus', bus, bd), sig('nig (software)', lv(n, {0: '0', 3: '1', 5: '0'})), sig('Next_is_Gap in the reference message', pul(n, [4])), sig('sync state', *cells(n, {0: 'in schedule', 5: 'in gap', 9: 'in schedule'}, '=')),
          sig('event pin low or fgp', pul(n, [8]))])

    # WF-058 level 2 drift compensation (values from the model)
    num_cfg = 0x1FFF0
    num = num_cfg
    d_master = 10000.0
    ppm = 300e-6
    vals, errs = [], []
    for cycle in range(8):
        d_local = d_master * num_cfg / num * (1.0 + ppm)
        errs.append('%.2f' % (d_local - d_master))
        num, ok = M.drift_compensate(num, num_cfg, d_local, d_master, 4)
        vals.append('%#x' % num)
    n = 8
    make(58, 'WF-058 Level 2 drift compensation of a slave whose clock is 300 ppm fast',
         'One cell is one basic cycle (10000 NTU of the master). At each reference message the slave compares the length of the basic cycle in its local NTU with the length in the global time of the master and corrects NumAct inside the limit SDL = 2^(ldSDL + 5). The cycle length error falls from 3 NTU to about 0.02 NTU in the second cycle and stays there; NumAct changes by less than the limit SDL of 512. A deviation above SDL, or a reference message with the Disc bit, suspends the compensation and raises gte or dis. Values computed by the model of this specification.',
         [sig('NumAct after the cycle', *cells(n, dict((i, vals[i]) for i in range(n)), '=')), sig('cycle length error (NTU)', *cells(n, dict((i, errs[i]) for i in range(n)), '=')),
          sig('compensation active (qcs)', '1' * n), sig('gte event', '0' * n)])

    for k, v in files.items():
        json.dump(v, open(os.path.join(out, 'tt_wf_%03d.json' % k), 'w', encoding='utf-8'), indent=1)
    json.dump({str(k): v for k, v in notes.items()}, open(os.path.join(out, 'tt_notes.json'), 'w', encoding='utf-8'), indent=1)

    s = Svg(1240, 640, 'Logic diagram of the TTCAN frame synchronization entity (m_canfd_tt, CLK-CAN)')
    s.box(20, 60, 190, 80, ['NTU generator', 'accumulator: + DenomCfg,', 'tick at NumAct (8 micro ticks)'])
    s.box(270, 60, 190, 80, ['Local time', '16-bit macro tick +', '3-bit micro tick'])
    s.arrow([(210, 100), (270, 100)], 'tick', 230, 92)
    s.box(520, 60, 190, 80, ['Sync_Mark and Ref_Mark', 'Sync_Mark at the SOF sample', 'point; Ref_Mark at a valid RM'])
    s.arrow([(460, 100), (520, 100)])
    s.box(770, 60, 190, 80, ['Cycle time', 'local time - Ref_Mark', '(restarts at each RM)'])
    s.arrow([(710, 100), (770, 100)])
    s.box(1020, 60, 190, 80, ['Global time (level 2)', 'local time + Local_Offset', 'low-pass filtered'])
    s.arrow([(960, 100), (1020, 100)])
    s.box(1020, 200, 190, 80, ['Drift compensation', 'NumAct = NumAct x dLocal / dMaster', 'inside SDL, Disc bit'])
    s.arrow([(1115, 140), (1115, 200)])
    s.arrow([(1115, 280), (1115, 310), (15, 310), (15, 100), (20, 100)], 'NumAct', 560, 304)
    s.box(770, 200, 190, 80, ['Trigger sequencer', 'next trigger: cycle code match,', 'time mark = cycle time'])
    s.arrow([(865, 140), (865, 200)], 'cycle time', 873, 175)
    s.box(520, 200, 190, 80, ['Trigger cache', 'PARA_CANFD_TRIG_NUM words in', 'flops, parity, loaded in TT config'])
    s.arrow([(710, 240), (770, 240)], 'triggers', 716, 232)
    s.box(270, 200, 190, 80, ['Window control', 'Tx_Enable window (TEW),', 'single, merged, exclusive'])
    s.arrow([(865, 280), (865, 300), (400, 300), (400, 280)], 'trigger events', 560, 294)
    s.box(20, 200, 190, 80, ['Interface to m_canfd_txh', 'time-triggered request,', 'start allowed, periodic flags'])
    s.arrow([(270, 240), (210, 240)])
    s.box(270, 340, 190, 80, ['Reference message', 'build (master) and parse', '(cycle count, Next_is_Gap, mark)'])
    s.arrow([(365, 280), (365, 340)])
    s.box(520, 340, 190, 80, ['Sync and master state', 'out of sync, synchronising,', 'in schedule, in gap; master priority'])
    s.arrow([(460, 380), (520, 380)])
    s.box(770, 340, 190, 80, ['Gap control', 'nig, fgp, tmg, event pin', '(event-synchronised mode)'])
    s.arrow([(770, 380), (710, 380)])
    s.box(1020, 340, 190, 80, ['Application watchdog', 'limit x 256 NTU,', 'served by software'])
    s.box(20, 340, 190, 80, ['Error level and interrupts', 'S0 to S3, 16 sources,', 'fatal: bus monitoring mode'])
    s.arrow([(270, 380), (210, 380)])
    s.box(20, 480, 440, 70, ['Stopwatch and time mark: capture of local, cycle or global time at the trigger pins;', 'time mark compare for the time-mark interrupt'])
    s.text(20, 610, 'The unit works on the CAN clock. Configuration is copied from the BUS domain only while INIT = 1 (CDC-003); events and status leave through CDC-007 and CDC-004.', size=12)
    s.save(os.path.join(out, 'canfd_tt_logic.svg'))
    print('wrote', len(files), 'waveforms and 1 diagram to', out)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else '.')
