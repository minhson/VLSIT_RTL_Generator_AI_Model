#!/usr/bin/env python3
# Project  : VLSIT common RTL library
# Function : reference model of the partial networking wake-up frame filter and the sleep state machine (section 10.15)
"""Bit-serial wake-up frame filter. The filter works on the destuffed bit stream of a Classic frame (SOF to the CRC delimiter);
it compares each field with the filter on the fly (no frame buffer) and decides at the CRC delimiter, only when the frame is
error free. FD frames and frames with errors never wake the node (the author's choice, ASM-019).

Filter : id (29 bits, base ids left-aligned in bits 28 to 18), xtd, idm (mask: 1 = bit must match), dlc, dlc_en, data (64 bits, byte 0 first), dm (data mask).
Usage  : python can_pn_model.py   (self test)
"""
import sys


def crc15(bits):
    reg = 0
    for b in bits:
        nxt = ((reg >> 14) & 1) ^ b
        reg = (reg << 1) & 0x7FFF
        if nxt:
            reg ^= 0x4599
    return reg


def frame_bits(ident, xtd, dlc, data, fd=False, bad_crc=False):
    """Destuffed bits from SOF to the end of the CRC sequence of a Classic data frame."""
    b = [0]
    if not xtd:
        b += [(ident >> (28 - i)) & 1 for i in range(11)] + [0, 0, 1 if fd else 0] + [(dlc >> (3 - i)) & 1 for i in range(4)]   # RTR, IDE, r0 (EDL in an FD frame), DLC
    else:
        b += [(ident >> (28 - i)) & 1 for i in range(11)] + [1, 1] + [(ident >> (17 - i)) & 1 for i in range(18)] + [0, 1 if fd else 0, 0] + [(dlc >> (3 - i)) & 1 for i in range(4)]
    n = min(dlc, 8)
    for k in range(n):
        for i in range(8):
            b.append((data[k] >> (7 - i)) & 1)
    c = crc15(b)
    if bad_crc:
        c ^= 1
    return b + [(c >> (14 - i)) & 1 for i in range(15)]


def stuff(bits):
    out, run, last = [], 0, None
    for x in bits:
        out.append(x)
        run = run + 1 if x == last else 1
        last = x
        if run == 5:
            out.append(1 - x)
            last, run = 1 - x, 1
    return out


class Wuf:
    def __init__(self, ident, xtd, idm, dlc=0, dlc_en=False, data=0, dm=0):
        self.id, self.xtd, self.idm, self.dlc, self.dlc_en, self.data, self.dm = ident, xtd, idm, dlc, dlc_en, data, dm


def receive(bits_stuffed, filters, pn_err_ign=True):
    """Feed the stuffed bits; returns (index of the matching filter or None, reason)."""
    # destuff
    d, run, last, skip = [], 0, None, False
    for x in bits_stuffed:
        if skip:
            if x == last:
                return None, 'stuff error'
            last, run, skip = x, 1, False
            continue
        d.append(x)
        run = run + 1 if x == last else 1
        last = x
        if run == 5:
            skip = True
    if len(d) < 19:
        return None, 'short'
    # field positions: base: SOF 0, id 1..11, RTR 12, IDE 13, r0 14, DLC 15..18; extended: id 1..11, SRR 12, IDE 13, id 14..31, RTR 32, r1 33, r0 34, DLC 35..38
    xtd = bool(d[13])
    if not xtd:
        # base frame bits: d[12] RTR, d[13] IDE, d[14] r0 or FDF-like bit
        if d[14] == 1:
            return None, 'FD frame ignored'
        ident = sum(d[1 + i] << (28 - i) for i in range(11))
        dlc = sum(d[15 + i] << (3 - i) for i in range(4))
        pos = 19
    else:
        if len(d) < 39:
            return None, 'short'
        if d[33] == 1:
            return None, 'FD frame ignored'
        ident = sum(d[1 + i] << (28 - i) for i in range(11)) | sum(d[14 + i] << (17 - i) for i in range(18))
        dlc = sum(d[35 + i] << (3 - i) for i in range(4))
        pos = 39
    n = min(dlc, 8)
    data = d[pos:pos + 8 * n]
    crc = d[pos + 8 * n:pos + 8 * n + 15]
    if len(crc) < 15:
        return None, 'short'
    if crc15(d[:pos + 8 * n]) != sum(crc[i] << (14 - i) for i in range(15)):
        return None, 'CRC error ignored'
    dval = 0
    for k in range(n):
        byte = sum(data[8 * k + i] << (7 - i) for i in range(8))
        dval |= byte << (8 * k)
    for idx, f in enumerate(filters):
        if f.xtd != xtd:
            continue
        if (ident ^ f.id) & f.idm:
            continue
        if f.dlc_en and dlc != f.dlc:
            continue
        need_bits = f.dm
        if need_bits >> (8 * n):                          # the filter asks for data bytes that the frame does not carry
            continue
        if (dval ^ f.data) & f.dm:
            continue
        return idx, 'match'
    return None, 'no match'


def sleep_next(state, ev):
    """Power state machine: 'NORMAL' -> 'SLEEP_PEND' -> 'SLEEP' -> 'WAKE_PEND' -> 'RESTART' -> 'NORMAL'."""
    t = {
        ('NORMAL', 'sleep_req'): 'SLEEP_PEND', ('NORMAL', 'sleep_req_blocked'): 'NORMAL',
        ('SLEEP_PEND', 'bus_idle_and_tx_done'): 'SLEEP', ('SLEEP_PEND', 'sleep_cancel'): 'NORMAL',
        ('SLEEP', 'wake_event'): 'WAKE_PEND', ('SLEEP_PEND', 'wake_event'): 'WAKE_PEND',
        ('WAKE_PEND', 'wake_ack'): 'RESTART', ('RESTART', 'init_cleared_and_integrated'): 'NORMAL',
    }
    return t.get((state, ev), state)


def selftest():
    ok = True

    def check(c, m):
        nonlocal ok
        print(('PASS ' if c else 'FAIL ') + m)
        ok = ok and c

    ID = 0x123 << 18
    data = [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]
    f_id = Wuf(ID, False, 0x7FF << 18)
    check(receive(stuff(frame_bits(ID, False, 8, data)), [f_id])[0] == 0, 'a base frame with the right identifier wakes the node at the CRC delimiter')
    check(receive(stuff(frame_bits(0x124 << 18, False, 8, data)), [f_id])[0] is None, 'a base frame with another identifier does not wake')
    f_mask = Wuf(ID, False, 0x7F0 << 18)
    check(receive(stuff(frame_bits(0x12F << 18, False, 8, data)), [f_mask])[0] == 0, 'the identifier mask makes the low 4 bits do not care')
    f_dlc = Wuf(ID, False, 0x7FF << 18, dlc=4, dlc_en=True)
    check(receive(stuff(frame_bits(ID, False, 4, data)), [f_dlc])[0] == 0 and receive(stuff(frame_bits(ID, False, 8, data)), [f_dlc])[0] is None, 'the DLC check accepts DLC 4 and rejects DLC 8')
    f_data = Wuf(ID, False, 0x7FF << 18, data=0x44332211, dm=0xFFFFFFFF)
    check(receive(stuff(frame_bits(ID, False, 8, data)), [f_data])[0] == 0, 'a data mask of 4 bytes matches the first four data bytes')
    bad = list(data)
    bad[2] = 0x00
    check(receive(stuff(frame_bits(ID, False, 8, bad)), [f_data])[0] is None, 'a different data byte does not wake')
    f_dm = Wuf(ID, False, 0x7FF << 18, data=0x00000011, dm=0x000000FF)
    check(receive(stuff(frame_bits(ID, False, 8, bad)), [f_dm])[0] == 0, 'only the masked data bits are compared')
    check(receive(stuff(frame_bits(ID, False, 2, data)), [f_data])[0] is None, 'a frame shorter than the data mask never matches')
    check(receive(stuff(frame_bits(ID, False, 8, data, bad_crc=True)), [f_id])[0] is None, 'a frame with a CRC error does not wake')
    err = stuff(frame_bits(ID, False, 8, data))
    err = err[:20] + [err[19]] * 6 + err[26:]
    check(receive(err, [f_id])[0] is None, 'a frame with a stuff error does not wake')
    check(receive(stuff(frame_bits(ID, False, 8, data, fd=True)), [f_id])[0] is None, 'an FD frame is ignored without an error (FD passive)')
    XID = 0x1ABCDEF0
    f_x = Wuf(XID, True, 0x1FFFFFFF)
    check(receive(stuff(frame_bits(XID, True, 8, data)), [f_x])[0] == 0, 'an extended frame with the right 29-bit identifier wakes')
    check(receive(stuff(frame_bits(XID, True, 8, data)), [f_id])[0] is None, 'a base filter never matches an extended frame')
    check(receive(stuff(frame_bits(ID, False, 8, data)), [f_x, f_data, f_id])[0] == 1, 'the first matching filter of the list is reported')
    s = 'NORMAL'
    for ev, want in (('sleep_req', 'SLEEP_PEND'), ('bus_idle_and_tx_done', 'SLEEP'), ('wake_event', 'WAKE_PEND'), ('wake_ack', 'RESTART'), ('init_cleared_and_integrated', 'NORMAL')):
        s = sleep_next(s, ev)
        if s != want:
            check(False, 'state machine: %s gave %s, expected %s' % (ev, s, want))
            break
    else:
        check(True, 'state machine: normal, sleep pending, sleep, wake pending, restart, normal')
    check(sleep_next('SLEEP_PEND', 'wake_event') == 'WAKE_PEND', 'a wake event during the sleep entry is not lost')
    print('SELFTEST', 'PASS' if ok else 'FAIL')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(selftest())
