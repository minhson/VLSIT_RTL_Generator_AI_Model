#!/usr/bin/env python3
# Project  : VLSIT common RTL library
# Function : reference model of the TTCAN frame synchronization entity (section 10.13)
"""Model of m_canfd_tt at the level of the network time unit (NTU).

Source of the behavior: the Bosch TTCAN IP module user's manual 1.6 (REF-010, chapters 5.1 to 5.7), which describes ISO 11898-4;
the ISO text itself was not available (open points TBD-015 and TBD-016 of the specification).

Time base       : the node counts local time in NTU with a 3-bit fraction; TUR = NumAct / DenomCfg system clocks per NTU.
Cycle time      : local time minus the reference mark, restarted at each valid reference message.
Triggers        : a list sorted by time mark; type, message number, cycle code, time mark; processed in order for each basic cycle.
Level 2         : the node compares the length of a basic cycle in local time and in the master's global time and corrects NumAct
                  inside the synchronization deviation limit SDL = 2 ** (ldSDL + 5).
Usage           : python can_tt_model.py   (self test)
"""
import sys

TX_REF, TX_REF_GAP, TX_SINGLE, TX_MERGED, WATCH, WATCH_GAP, RX_TRIG, END_LIST = range(8)
OUT_OF_SYNC, SYNCHRONISING, IN_SCHEDULE, IN_GAP = range(4)


def cycle_code_match(code, count):
    """Cycle_Code of a trigger (7 bits) against the cycle count (6 bits), REF-010 section 3.5.2."""
    if code & 0x7E == 0:
        return True                                   # 000000x: every cycle
    if code & 0x7E == 0x02:
        return (count & 1) == (code & 1)              # 000001c: every second cycle
    if code & 0x7C == 0x04:
        return (count & 3) == (code & 3)              # 00001cc
    if code & 0x78 == 0x08:
        return (count & 7) == (code & 7)              # 0001ccc
    if code & 0x70 == 0x10:
        return (count & 15) == (code & 15)            # 001cccc
    if code & 0x60 == 0x20:
        return (count & 31) == (code & 31)            # 01ccccc
    return (count & 63) == (code & 63)                # 1cccccc


def code_for(period, phase):
    """Cycle_Code for a trigger that is valid at (count mod period) = phase, period 1, 2, 4, 8, 16, 32 or 64."""
    base = {1: 0x00, 2: 0x02, 4: 0x04, 8: 0x08, 16: 0x10, 32: 0x20, 64: 0x40}[period]
    return base | (phase & (period - 1)) if period > 1 else 0


class Trigger:
    def __init__(self, ttype, mark, msg=0, code=0):
        self.t, self.mark, self.msg, self.code = ttype, mark, msg, code


def check_trigger_list(trigs, is_master, tew, ref_len_ntu):
    """Configuration errors (error level 3) that the FSE detects, REF-010 section 5.1.3. Returns a list of strings."""
    errs = []
    last = -1
    for k, g in enumerate(trigs):
        if g.t == END_LIST:
            errs.append('EndOfList trigger at %d' % k)
        if g.mark < last:
            errs.append('trigger %d is not sorted by time mark' % k)
        last = max(last, g.mark)
        if not is_master and g.t in (TX_REF, TX_REF_GAP):
            errs.append('time slave with a reference trigger at %d' % k)
        if g.t == TX_MERGED:
            nxt = trigs[k + 1] if k + 1 < len(trigs) else None
            if nxt is None or nxt.t not in (TX_SINGLE, TX_MERGED):
                errs.append('merged trigger %d not followed by a single or merged trigger' % k)
        if g.t == RX_TRIG:
            for h in trigs:
                if h.t in (TX_SINGLE, TX_MERGED) and h.mark <= g.mark < h.mark + tew:
                    errs.append('Rx trigger %d inside a Tx_Enable window' % k)
                    break
        if g.t in (TX_SINGLE, TX_MERGED, RX_TRIG, WATCH, WATCH_GAP) and g.mark < ref_len_ntu and g.t != TX_REF:
            errs.append('trigger %d earlier than the end of the reference message (never active)' % k)
    return errs


class NtuGen:
    """Network time unit generator: one NTU tick when the accumulator of DenomCfg per clock reaches NumAct; 8 micro ticks per NTU."""

    def __init__(self, num_act, denom):
        self.num, self.den = num_act, denom
        self.acc = 0
        self.macro = 0
        self.micro = 0

    def clock(self):
        self.acc += 8 * self.den                       # micro tick resolution of one eighth NTU
        if self.acc >= self.num:
            self.acc -= self.num
            self.micro += 1
            if self.micro == 8:
                self.micro = 0
                self.macro = (self.macro + 1) & 0xFFFF
                return True
        return False


def ntu_generator_error(num, denom, clocks):
    g = NtuGen(num, denom)
    n = sum(1 for _ in range(clocks) if g.clock())
    exact = clocks * denom / float(num)
    return n, exact


def drift_compensate(num_act, num_cfg, d_local, d_master, ld_sdl):
    """New NumAct from the basic cycle length in local NTU (d_local) and in the master's global NTU (d_master).
    Returns (new NumAct, ok). ok is False when |NumAct - NumCfg| would exceed SDL: the compensation is suspended."""
    sdl = 1 << (ld_sdl + 5)
    new = int(round(num_act * d_local / float(d_master)))
    if abs(new - num_cfg) > sdl:
        return num_act, False
    return new, True


def sync_state(state, got_ref, next_is_gap):
    """Synchronization state after a reference message: first message gives SYNCHRONISING, the second IN_SCHEDULE or IN_GAP."""
    if not got_ref:
        return state
    if state == OUT_OF_SYNC:
        return SYNCHRONISING
    return IN_GAP if next_is_gap else IN_SCHEDULE


def backup_start(init_ref_offset, mpr, factor):
    """NTU after which a backup master starts the reference message when the bus stays idle: Init_Ref_Offset = MPr x factor."""
    return init_ref_offset if init_ref_offset else mpr * factor


def tx_error_level(n_activated, ett):
    """Tx_Underflow (level 1) when fewer Tx triggers than expected were activated in the basic cycle, Tx_Overflow (level 2) when more."""
    return 1 if n_activated < ett else 2 if n_activated > ett else 0


def selftest():
    ok = True

    def check(c, m):
        nonlocal ok
        print(('PASS ' if c else 'FAIL ') + m)
        ok = ok and c

    seq = [(0, 0), (1, 0)]
    check(all(cycle_code_match(0, k) and cycle_code_match(1, k) for k in range(64)), 'cycle code 000000x is valid in every cycle')
    check([k for k in range(8) if cycle_code_match(code_for(2, 1), k)] == [1, 3, 5, 7], 'cycle code 000001c with c = 1: every second cycle starting at 1')
    check([k for k in range(16) if cycle_code_match(code_for(4, 2), k)] == [2, 6, 10, 14], 'cycle code 00001cc with cc = 2: every fourth cycle')
    check([k for k in range(32) if cycle_code_match(code_for(8, 5), k)] == [5, 13, 21, 29], 'cycle code 0001ccc with ccc = 5: every eighth cycle')
    check([k for k in range(64) if cycle_code_match(code_for(64, 37), k)] == [37], 'cycle code 1cccccc: one cycle in 64')
    for per in (2, 4, 8, 16, 32, 64):
        cover = sorted(k for ph in range(per) for k in range(64) if cycle_code_match(code_for(per, ph), k))
        if cover != list(range(64)) * 1 and len(cover) != 64:
            check(False, 'the codes of period %d partition the 64 cycles' % per)
            break
    else:
        check(True, 'for every period the codes of its phases partition the 64 cycles')
    good = [Trigger(TX_SINGLE, 10, 1), Trigger(RX_TRIG, 40, 2), Trigger(TX_REF, 100), Trigger(WATCH, 120)]
    check(check_trigger_list(good, True, 8, 6) == [], 'a sorted master trigger list has no configuration error')
    check(any('slave' in e for e in check_trigger_list(good, False, 8, 6)), 'a time slave with a Tx_Ref_Trigger is a configuration error')
    bad = [Trigger(TX_MERGED, 10, 1), Trigger(RX_TRIG, 40, 2)]
    check(any('merged' in e for e in check_trigger_list(bad, False, 8, 6)), 'a Tx_Trigger_Merged must be followed by a single or merged trigger')
    bad = [Trigger(TX_SINGLE, 10, 1), Trigger(RX_TRIG, 14, 2)]
    check(any('Tx_Enable' in e for e in check_trigger_list(bad, False, 8, 6)), 'an Rx_Trigger inside a Tx_Enable window is a configuration error')
    bad = [Trigger(TX_SINGLE, 50, 1), Trigger(TX_SINGLE, 20, 2)]
    check(any('sorted' in e for e in check_trigger_list(bad, False, 8, 6)), 'triggers must be sorted by time mark')
    check(any('EndOfList' in e for e in check_trigger_list([Trigger(END_LIST, 0)], True, 8, 6)), 'an EndOfList trigger is a configuration error')
    # NTU generator
    for num, den in ((0x1FFF8, 0x3FFF), (0x10880, 0x0880), (0x1E848, 0x0001), (0x19000, 0x3000)):
        n, exact = ntu_generator_error(num, den, 2000000)
        check(abs(n - exact) <= 1.0, 'NTU generator NumCfg %#x / DenomCfg %#x: %d ticks in 2 million clocks, exact %.2f' % (num, den, n, exact))
    # state machine
    st = OUT_OF_SYNC
    st = sync_state(st, True, False)
    check(st == SYNCHRONISING, 'the first reference message gives the state synchronising')
    check(sync_state(st, True, False) == IN_SCHEDULE and sync_state(st, True, True) == IN_GAP, 'the second reference message gives in schedule or in gap by Next_is_Gap')
    check(backup_start(0, 3, 4) == 12 and backup_start(9, 3, 4) == 9, 'a backup master starts the reference message after Init_Ref_Offset (MPr x factor by default)')
    check(tx_error_level(5, 6) == 1 and tx_error_level(7, 6) == 2 and tx_error_level(6, 6) == 0, 'Tx_Underflow is level 1, Tx_Overflow level 2, equal is no error')
    # drift compensation: slave clock fast by 300 ppm
    num_cfg = 0x1FFF0
    num = num_cfg
    d_master = 10000.0                                         # a basic cycle of 10000 master NTU
    slave_ppm = 300e-6
    lock = []
    for cycle in range(12):
        d_local = d_master * num_cfg / num * (1.0 + slave_ppm) # NTU counted locally with the present NumAct
        num, good_cycle = drift_compensate(num, num_cfg, d_local, d_master, 4)
        lock.append(abs(d_local - d_master))
    check(lock[-1] < 0.5 and lock[-1] < lock[0] / 10 and good_cycle, 'level 2 drift compensation: a slave 300 ppm fast converges, the cycle length error falls from %.2f to %.3f NTU' % (lock[0], lock[-1]))
    n2, ok2 = drift_compensate(num_cfg, num_cfg, d_master * 1.05, d_master, 4)
    check(not ok2 and n2 == num_cfg, 'a deviation above SDL (ldSDL 4: %d) suspends the compensation' % (1 << 9))
    print('SELFTEST', 'PASS' if ok else 'FAIL')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(selftest())
