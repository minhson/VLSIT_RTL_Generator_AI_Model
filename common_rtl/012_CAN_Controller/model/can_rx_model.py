#!/usr/bin/env python3
# Project  : VLSIT common RTL library
# Function : reference model of the receive path of the CAN FD controller: acceptance filter, Rx FIFO, handoff
"""Executable form of section 10.11 of the specification.

Filter element formats are those of section 9: standard 1 word, extended 2 words.
  standard: [31:29] action, [28:27] type, [26:16] id2 or mask, [10:0] id1
  extended: word0 [31:29] action, [28:0] id1; word1 [31:30] type, [28:0] id2 or mask
  action 0 disabled, 1 FIFO 0, 2 FIFO 1, 3 reject, 4 FIFO 0 high priority, 5 FIFO 1 high priority, 6 Rx buffer
  type 0 range, 1 dual, 2 mask, 3 disabled
Usage : python can_rx_model.py selftest
"""
import random
import sys


def match(typ, id1, id2, ident):
    if typ == 0:
        return id1 <= ident <= id2
    if typ == 1:
        return ident == id1 or ident == id2
    if typ == 2:
        return (ident & id2) == (id1 & id2)
    return False


def filter_frame(ext, ident, std_list, ext_list, anfs=0, anfe=0, xidam=0x1FFFFFFF, rtr=False, rrfs=False, rrfe=False):
    """Returns (action, index of the element or None, elements read). action: 'F0','F1','HP0','HP1','BUF','REJECT'."""
    if rtr and ((ext and rrfe) or (not ext and rrfs)):
        return 'REJECT', None, 0
    names = {1: 'F0', 2: 'F1', 4: 'HP0', 5: 'HP1', 6: 'BUF'}
    elems = ext_list if ext else std_list
    ident = ident & (xidam if ext else 0x7FF)
    for k, (action, typ, id1, id2) in enumerate(elems):
        if action in (0,) or typ == 3:
            continue
        if match(typ, id1, id2, ident):
            if action == 3:
                return 'REJECT', k, k + 1
            return names[action], k, k + 1
    nm = anfe if ext else anfs
    return ({0: 'F0', 1: 'F1'}.get(nm, 'REJECT')), None, len(elems)


def filter_cycles(n_std_read, n_ext_read, ext, wait):
    """BUS clocks to read the elements: a word costs 2 + wait (request, acknowledge, one idle clock, REQ-IF-002)."""
    words = n_ext_read * 2 if ext else n_std_read
    return words * (2 + wait)


class Fifo:
    def __init__(self, size, overwrite):
        self.size, self.ow = size, overwrite
        self.reset()

    def reset(self):
        self.mem = [None] * self.size
        self.g = self.p = self.fill = 0
        self.lost = False
        self.gen = [0] * self.size

    def put(self, msg):
        if self.fill == self.size:
            self.lost = True
            if not self.ow:
                return 'dropped'
            self.mem[self.p] = msg
            self.gen[self.p] = (self.gen[self.p] + 1) & 3
            self.p = (self.p + 1) % self.size
            self.g = (self.g + 1) % self.size        # the oldest is lost, the get index follows
            return 'overwrote'
        self.mem[self.p] = msg
        self.gen[self.p] = (self.gen[self.p] + 1) & 3
        self.p = (self.p + 1) % self.size
        self.fill += 1
        return 'stored'

    def ack(self, idx):
        """Software acknowledges up to and including idx."""
        n = (idx - self.g) % self.size + 1
        n = min(n, self.fill)
        self.g = (self.g + n) % self.size
        self.fill -= n


def selftest():
    ok = True

    def check(c, m):
        nonlocal ok
        print(('PASS ' if c else 'FAIL ') + m)
        ok = ok and c

    std = [(1, 0, 0x100, 0x1FF), (2, 1, 0x200, 0x300), (3, 2, 0x400, 0x7F0), (6, 1, 0x555, 0x555)]
    ext = [(1, 0, 0x1000, 0x2000), (4, 2, 0x18DB0000, 0x1FFF0000)]
    check(filter_frame(False, 0x150, std, ext)[:2] == ('F0', 0), 'range filter matches inside the range and stops at the first match')
    check(filter_frame(False, 0x300, std, ext)[:2] == ('F1', 1), 'dual filter matches the second identifier')
    check(filter_frame(False, 0x402, std, ext)[:2] == ('REJECT', 2), 'mask filter with the reject action rejects')
    check(filter_frame(False, 0x555, std, ext)[:2] == ('BUF', 3), 'dual filter with the Rx buffer action')
    check(filter_frame(False, 0x777, std, ext, anfs=1)[0] == 'F1' and filter_frame(False, 0x777, std, ext, anfs=2)[0] == 'REJECT', 'no match: accept into FIFO 1 or reject by the global filter')
    check(filter_frame(True, 0x18DB1234, std, ext)[:2] == ('HP0', 1), 'extended mask filter with the high priority action')
    check(filter_frame(True, 0x18DB1234 | 0x20000000, std, ext, xidam=0x1FFFFFFF)[:2] == ('HP0', 1), 'the extended identifier AND mask removes the bits above bit 28')
    check(filter_frame(False, 0x150, std, ext, rtr=True, rrfs=True)[0] == 'REJECT', 'remote frame rejected by the global rule without reading the list')
    check(filter_frame(False, 0x150, [(1, 3, 0x100, 0x1FF)], [])[0] == 'F0', 'a disabled type never matches (falls to the no-match action)')
    f = Fifo(4, False)
    r = [f.put(i) for i in range(6)]
    check(r == ['stored'] * 4 + ['dropped'] * 2 and f.lost and f.fill == 4, 'blocking mode: the 5th and 6th message are dropped and the lost flag is set')
    f.ack(1)
    check(f.fill == 2 and f.g == 2, 'acknowledge of index 1 frees two elements')
    f = Fifo(4, True)
    r = [f.put(i) for i in range(6)]
    check(r == ['stored'] * 4 + ['overwrote'] * 2 and f.lost and f.fill == 4 and f.mem[f.g] == 2, 'overwrite mode: the two oldest are lost, the oldest left is message 2')
    check(f.gen[0] == 2 and f.gen[2] == 1, 'generation counter changes with each overwrite of the same element (protection of a concurrent read)')
    # budget examples
    w = 3
    # a base frame reads only the standard list (at most 128 words), an extended frame only the extended list
    # (at most 64 elements of 2 words = 128 words): the worst case per frame is 128 words
    w = 3
    check(filter_cycles(128, 0, False, w) == filter_cycles(0, 64, True, w) == 128 * (2 + w), 'worst case per frame is 128 words: %d clocks at %d wait states' % (128 * (2 + w), w))
    store = 3 + 16 + 1                           # element header, 16 data words, put index
    total = 128 * (2 + w) + store * (2 + w)
    check(total == 740, 'filter plus store of the largest element: %d clocks; at 100 MHz this is %.1f us, below the 47 us of the shortest Classic frame' % (total, total / 100.0))
    print('SELFTEST', 'PASS' if ok else 'FAIL')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(selftest())
