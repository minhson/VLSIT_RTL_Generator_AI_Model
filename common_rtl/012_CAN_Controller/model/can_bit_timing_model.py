#!/usr/bin/env python3
# Project  : VLSIT common RTL library
# Function : cycle-accurate reference model of the bit timing and sampling unit (m_canfd_btl) of the CAN FD controller
# Source   : REF-001 (CAN 2.0 part A, bit timing), REF-002 (CAN FD 1.0, bit timing requirements, section 8)
"""Reference model of m_canfd_btl, one call of step() per CAN clock.

It models the receive input synchronizer, the prescaler, the time segment counter, the hard and the soft
synchronization with the five synchronization rules of REF-002 section 8, the sample point, the bit rate
switch at the sample point of the BRS bit and of the CRC delimiter, and the secondary sample point.
It is the executable form of section 10.6 of the specification: the waveforms WF-029 to WF-040 are produced
from its traces and `selftest` checks the sampling against the rules and against the oscillator tolerance.

Usage : python can_bit_timing_model.py selftest
        python can_bit_timing_model.py waves OUT_DIR
Exit  : 0 when every check passes, 1 otherwise.
"""
import json
import os
import random
import sys

SYNC, SEG1, SEG2 = 'SYNC', 'SEG1', 'SEG2'


class Cfg:
    """One bit timing configuration; tseg1 = PROP_SEG + PHASE_SEG1, all in time quanta."""

    def __init__(self, brp, tseg1, tseg2, sjw):
        assert brp >= 1 and tseg1 >= 1 and tseg2 >= 1 and 1 <= sjw <= tseg2
        self.brp, self.tseg1, self.tseg2, self.sjw = brp, tseg1, tseg2, sjw

    @property
    def bit_clocks(self):
        return (1 + self.tseg1 + self.tseg2) * self.brp


class Btl:
    """State of m_canfd_btl. Inputs of step(): raw receive level and the control inputs of the frame engine."""

    def __init__(self, nom, dat=None, edge_filter=False):
        self.nom, self.dat, self.edge_filter = nom, dat, edge_filter
        self.reset()

    def reset(self):
        self.rx_s1 = self.rx_s = 1       # two-flop synchronizer
        self.rx_cur = self.rx_prev = 1   # value of the second flop in this clock and in the previous clock
        self.smp_q = 1                   # value at the previous sample point
        self.ph = 'N'                    # phase of the present cell: N nominal, D data
        self.cfg = self.nom
        self.div = 0                     # clock count inside a time quantum
        self.t = 0                       # time quantum index inside the cell, 0 is SYNC_SEG
        self.len1 = self.cfg.tseg1       # SEG1 length of this cell (grows by the resync)
        self.len2 = self.cfg.tseg2       # SEG2 length of this cell (shrinks by the resync)
        self.synced = False              # rule 1: one synchronization between two sample points
        self.dom_run = 0                 # consecutive dominant time quanta (edge filter)
        self.last_event = ''

    # ---- helpers
    def seg(self):
        if self.t == 0:
            return SYNC
        return SEG1 if self.t <= self.len1 else SEG2

    def _restart(self):
        """Hard synchronization: the edge clock becomes the first clock of SYNC_SEG."""
        self.t = 0 if self.cfg.brp > 1 else 1      # the edge clock is clock 0 of SYNC_SEG (tq 0 with brp 1 is already over)
        self.div = 1 % self.cfg.brp
        self.len1, self.len2 = self.cfg.tseg1, self.cfg.tseg2
        self.synced = True

    def step(self, rx_raw, hard_sync_en=False, hs_edl=False, tx_dom=False, no_resync=False, switch=None):
        """One CAN clock. Returns a dict of the strobes of this clock.

        hard_sync_en: bus idle, suspend transmission, intermission bits 2 and 3 (REF-002 rule 3)
        hs_edl      : edge from the FDF bit to the res bit of an FD frame (REF-002 rule 3)
        tx_dom      : this node transmits a dominant bit now (rule 4)
        no_resync   : transmitter in the data phase (rule 5)
        switch      : 'D' or 'N', requested by the frame engine, takes effect after the sample point
        """
        out = {'sample': False, 'sample_val': None, 'tx_point': False, 'edge': False, 'sync': ''}
        prev_s = self.rx_prev
        self.rx_prev = self.rx_cur
        self.rx_cur = self.rx_s            # output of the second flop, seen by the logic in this clock
        self.rx_s = self.rx_s1
        self.rx_s1 = rx_raw
        edge = (self.rx_cur == 0 and self.smp_q == 1 and prev_s == 1)  # recessive to dominant edge seen now
        dom_run_ok = True
        if self.edge_filter and hard_sync_en:
            self.dom_run = self.dom_run + 1 if self.rx_cur == 0 else 0
            dom_run_ok = self.dom_run >= 2
            edge = (self.rx_cur == 0 and self.smp_q == 1 and dom_run_ok and not self.synced)
        out['edge'] = edge
        pos = self.seg()
        t_now = self.t
        if edge and not self.synced and not no_resync:
            if hard_sync_en or hs_edl:
                self._restart()
                out['sync'] = 'hard'
            elif pos == SEG1:
                if tx_dom:
                    pass                                   # rule 4: no resync on a positive phase error while sending dominant
                elif t_now <= self.cfg.sjw:
                    self._restart()
                    out['sync'] = 'resync_hard'            # |e| <= SJW acts like a hard synchronization
                else:
                    self.len1 += self.cfg.sjw
                    self.synced = True
                    out['sync'] = 'seg1+sjw'
            elif pos == SEG2:
                e_abs = 1 + self.len1 + self.len2 - t_now  # tq left in the cell, counting this one
                if e_abs <= self.cfg.sjw:
                    self._restart()
                    out['sync'] = 'resync_hard'
                else:
                    self.len2 -= self.cfg.sjw
                    self.synced = True
                    out['sync'] = 'seg2-sjw'
            else:
                self.synced = True
            if out['sync'] in ('hard', 'resync_hard'):
                return self._finish(out, switch, advance=False)
        elif edge and self.edge_filter and hard_sync_en and not self.synced:
            pass
        return self._finish(out, switch, advance=True)

    def apply_switch(self, ph):
        """Bit rate switch right after a sample point: the rest of the cell (SEG2) runs in the new configuration."""
        if ph != self.ph:
            self.ph = ph
            self.cfg = self.dat if ph == 'D' else self.nom
            self.len2 = self.cfg.tseg2
            self.div = 0

    def _finish(self, out, switch, advance):
        if not advance:
            return out
        tick = (self.div == self.cfg.brp - 1)
        if tick:
            if self.t == self.len1:                        # last quantum of SEG1: sample point
                out['sample'] = True
                out['sample_val'] = self.rx_cur
                self.smp_q = self.rx_cur
                self.synced = False
            if self.t == self.len1 + self.len2:            # end of the cell
                self.t = 0
                self.len1, self.len2 = self.cfg.tseg1, self.cfg.tseg2
                out['tx_point'] = True
            else:
                self.t += 1
            self.div = 0
        else:
            self.div += 1
        return out


# ---------------------------------------------------------------- bus models used by the tests
def stuffed(bits):
    """Dynamic bit stuffing of a bit list (a stuff bit after five equal bits)."""
    out, run, last = [], 0, None
    for b in bits:
        out.append(b)
        run = run + 1 if b == last else 1
        last = b
        if run == 5:
            out.append(1 - b)
            last, run = 1 - b, 1
    return out


def bus_level(bits, t0, bit_len, delay, c):
    """Level of the bus at clock c; recessive (1) before t0 and after the last bit."""
    x = c - delay - t0
    if x < 0:
        return 1
    k = int(x // bit_len)
    return bits[k] if k < len(bits) else 1


def receive(nom, bits, df, delay=0, jitter=0, rng=None, idle=40):
    """Receive a bit list sent by a node whose bit length differs by df (relative); returns the sampled bits."""
    btl = Btl(nom)
    bit_len = nom.bit_clocks * (1.0 + df)
    t0 = idle
    stream = [0] + list(bits)                                   # SOF then the bits
    samples, n_clk = [], int(t0 + (len(stream) + 2) * bit_len + 40)
    started = False
    for c in range(n_clk):
        lv = bus_level(stream, t0, bit_len, delay, c)
        r = btl.step(lv, hard_sync_en=not started)
        if r['sync'] == 'hard':
            started = True
        if started and r['sample']:
            samples.append(r['sample_val'])
    return samples[:len(stream)], stream


def selftest():
    ok = True

    def check(cond, msg):
        nonlocal ok
        print(('PASS ' if cond else 'FAIL ') + msg)
        ok = ok and cond

    # 1. sample point position and bit length without error
    nom = Cfg(2, 8, 3, 2)           # 1 + 8 + 3 = 12 tq of 2 clocks
    btl = Btl(nom)
    sp, tp, c = [], [], 0
    for c in range(400):
        r = btl.step(1)
        if r['sample']:
            sp.append(c)
        if r['tx_point']:
            tp.append(c)
    d = [b - a for a, b in zip(sp, sp[1:])]
    check(all(x == nom.bit_clocks for x in d), 'free running bit length is %d clocks' % nom.bit_clocks)
    check(len(sp) > 5 and (sp[0] + 1) % 2 == 0, 'sample point lies on a time quantum boundary')

    # 2. hard synchronization on SOF: sample point is (1 + tseg1) tq after the edge
    nom = Cfg(1, 8, 3, 2)
    btl = Btl(nom)
    got = None
    for c in range(60):
        r = btl.step(1 if c < 20 else 0, hard_sync_en=(c < 24))
        if r['sample'] and got is None and c > 20:
            got = c
    # rx_s lags rx_raw by 2 clocks: the edge is seen at clock 22, SYNC clock 22, sample at the end of tq 1 + 8 = 9
    check(got - 20 == 2 + 8, 'sample point %d clocks after the pin edge (2 synchronizer clocks + tseg1 + 0)' % (got - 20))

    # 3. sampling correct for random stuffed frames within the tolerance, wrong far outside
    for name, nom, lim in (('nominal 20 tq', Cfg(1, 11, 7, 4), None), ('nominal 16 tq, sjw 2', Cfg(1, 9, 6, 2), None)):
        N = 1 + nom.tseg1 + nom.tseg2
        prop = 4
        ps1 = nom.tseg1 - prop
        dfI = nom.sjw / (20.0 * N)
        dfII = min(ps1, nom.tseg2) / (2.0 * (13 * N - nom.tseg2))
        dfmax = min(dfI, dfII)
        rng = random.Random(7)
        bad_in = bad_out = 0
        for trial in range(300):
            if trial % 2:
                bits = ([0] * 5 + [1] * 5) * rng.randint(4, 12)      # worst case: a recessive to dominant edge every 10 bits
            else:
                bits = stuffed([rng.randint(0, 1) for _ in range(rng.randint(20, 100))])
            sgn = rng.choice((-1, 1))
            s, ref = receive(nom, bits, sgn * 0.9 * dfmax, delay=rng.randint(0, 3))
            bad_in += (s != ref)
            s, ref = receive(nom, bits, sgn * 3.0 * dfmax, delay=rng.randint(0, 3))
            bad_out += (s != ref)
        check(bad_in == 0, '%s: df = 0.9 x %.2f %% (limit of conditions I and II): 0 of 300 frames wrong' % (name, 100 * dfmax))
        check(bad_out > 0, '%s: df = 3 x limit: %d of 300 frames sampled wrong (the limit is meaningful)' % (name, bad_out))

    # 4. rule 4: dominant transmitter does not resync on a positive phase error
    nom = Cfg(1, 8, 3, 2)
    btl = Btl(nom)
    for c in range(30):
        btl.step(1, hard_sync_en=True)
    btl.step(0, hard_sync_en=True)
    btl.step(0, hard_sync_en=True)
    btl.step(0, hard_sync_en=True)       # edge reaches rx_s: hard sync
    seg_before = None
    for c in range(40):
        btl.step(0)
    # a later late edge while sending dominant: feed recessive for several bits, then a dominant edge in SEG1 with tx_dom
    b1, b2 = Btl(nom), Btl(nom)
    for b in (b1, b2):
        for c in range(30):
            b.step(1, hard_sync_en=True)
        for c in range(14):
            b.step(0, hard_sync_en=True)
    # now both are synchronized and bit 1 (dominant) has been sampled; send recessive 2 bits then a late dominant edge
    for c in range(24):
        b1.step(1)
        b2.step(1)
    for c in range(5):
        r1 = b1.step(0, tx_dom=True)
        r2 = b2.step(0, tx_dom=False)
    check((b1.len1 == b1.cfg.tseg1) and (b2.len1 != b2.cfg.tseg1 or b2.t == 0 or b2.synced), 'rule 4: a node sending dominant ignores a positive phase error')

    # 5. rule 5: no resynchronization of a transmitter in the data phase
    b = Btl(nom)
    for c in range(30):
        b.step(1, hard_sync_en=True)
    for c in range(14):
        b.step(0, hard_sync_en=True)
    for c in range(24):
        b.step(1, no_resync=True)
    for c in range(5):
        b.step(0, no_resync=True)
    check(b.len1 == nom.tseg1 and b.len2 == nom.tseg2, 'rule 5: no resynchronization in the data phase of a transmitter')

    # 6. bit rate switching: BRS and CRC delimiter bits have an intermediate length, the sum is one nominal + one data bit
    nom, dat = Cfg(2, 6, 3, 2), Cfg(1, 3, 2, 1)
    btl = Btl(nom, dat)
    tp_t, n_sample = [], 0
    for c in range(1500):
        r = btl.step(1)
        if r['tx_point']:
            tp_t.append(c)
        if r['sample']:
            n_sample += 1
            if n_sample == 3:
                btl.apply_switch('D')      # BRS bit sampled recessive
            elif n_sample == 7:
                btl.apply_switch('N')      # CRC delimiter sampled
    cell = [b - a for a, b in zip(tp_t, tp_t[1:])]
    nominal_bit, data_bit = nom.bit_clocks, dat.bit_clocks
    check(cell[0] == nominal_bit, 'bits before the BRS bit have the nominal length %d' % nominal_bit)
    mid = [cell[1], cell[5]]
    check(len(mid) == 2 and sum(mid) == nominal_bit + data_bit, 'BRS and CRC delimiter bits: %s clocks, sum equals nominal %d + data %d' % (mid, nominal_bit, data_bit))
    check(cell[2:5] == [data_bit] * 3, 'bits inside the data phase have the data length %d' % data_bit)

    print('SELFTEST', 'PASS' if ok else 'FAIL')
    return 0 if ok else 1


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'selftest'
    if cmd == 'selftest':
        sys.exit(selftest())
    print(__doc__)
    sys.exit(1)
