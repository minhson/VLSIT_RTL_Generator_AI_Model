#!/usr/bin/env python3
# Project  : VLSIT common RTL library
# Function : reference model of the transmit scheduler of the CAN FD controller (section 10.12)
"""Tx buffers: dedicated buffers 0 .. ded-1, then fifo_num buffers used as a FIFO or as a queue.

A buffer is a candidate only when its request is set, its header has been cached (valid) and, for a trigger-transmit buffer,
the software has confirmed the data. Priority (the lowest key wins, equal keys give the lower buffer number):
  express buffer: buffer 0 (when exp_en and ded >= 1) beats everything
  prio_mode 0: key = (identifier 29 bits, extension bit)      a base frame beats an extended frame with the same base identifier
  prio_mode 1: key = PRIO field of the element (0 is the highest)
FIFO part: only the head competes; the head is the first buffer from the get index that has a request (cancelled holes are skipped).
Retry limit per buffer: code RTL of the element, counter per buffer; 0 = global retry_max, 1 = single shot, 2..6 = 1, 2, 3, 7, 15 retries, 7 = unlimited.
Usage: python can_tx_model.py   (self test)
"""
import sys

RTL_LIMIT = {1: 0, 2: 1, 3: 2, 4: 3, 5: 7, 6: 15}      # code -> number of retransmissions; 7 unlimited; 0 global


class Tx:
    def __init__(self, ded, fifo, queue_mode, retry_max=0, prio_mode=0, exp_en=True):
        self.ded, self.fifo, self.q, self.retry_max = ded, fifo, queue_mode, retry_max
        self.prio_mode, self.exp_en = prio_mode, exp_en
        self.n = ded + fifo
        self.el = [None] * self.n            # cached header: dict(id, xtd, prio, rtl, trtx)
        self.req = [False] * self.n
        self.cached = [False] * self.n
        self.conf = [False] * self.n
        self.done = [False] * self.n
        self.canc = [False] * self.n
        self.fail = [False] * self.n
        self.tries = [0] * self.n            # a counter per buffer
        self.get = 0
        self.cur = None

    def write(self, b, ident, xtd=0, prio=0, rtl=0, trtx=False):
        assert not self.req[b], 'software must not change a pending buffer'
        self.el[b] = dict(id=ident, xtd=xtd, prio=prio, rtl=rtl, trtx=trtx)

    def request(self, b):
        """The request bit is set; the handler reads the header words into the cache (valid after that)."""
        if self.el[b] is not None and not self.req[b]:
            self.req[b] = True
            self.cached[b] = True
            self.conf[b] = not self.el[b]['trtx']          # an ordinary buffer needs no confirm

    def confirm(self, b):
        if self.req[b] and self.el[b]['trtx']:
            self.conf[b] = True

    def data_request(self, b):
        return self.req[b] and self.cached[b] and self.el[b]['trtx'] and not self.conf[b]

    def cancel(self, b):
        if self.req[b] and b != self.cur:
            self.req[b] = False
            self.cached[b] = False
            self.canc[b] = True

    def _ok(self, b):
        return self.req[b] and self.cached[b] and self.conf[b]

    def _fifo_head(self):
        for k in range(self.fifo):
            b = self.ded + (self.get + k) % self.fifo
            if self.req[b]:
                return b if self._ok(b) else None       # a head that waits for its data blocks only the FIFO, not the others
        return None

    def key(self, b):
        e = self.el[b]
        exp = 0 if (self.exp_en and self.ded >= 1 and b == 0) else 1
        k = (e['id'], e['xtd']) if self.prio_mode == 0 else (e['prio'],)
        return (exp,) + k + (b,)

    def select(self):
        cand = [b for b in range(self.ded) if self._ok(b)]
        if self.fifo:
            if self.q:
                cand += [b for b in range(self.ded, self.n) if self._ok(b)]
            else:
                h = self._fifo_head()
                if h is not None:
                    cand.append(h)
        return min(cand, key=self.key) if cand else None

    def start(self):
        self.cur = self.select()
        return self.cur

    def _limit(self, b):
        code = self.el[b]['rtl']
        if code == 0:
            return self.retry_max if self.retry_max else None       # None: unlimited
        if code == 7:
            return None
        return RTL_LIMIT[code]

    def result(self, ok):
        b = self.cur
        self.cur = None
        if ok:
            self.req[b] = False
            self.cached[b] = False
            self.done[b] = True
            self.tries[b] = 0
            self._advance(b)
            return 'sent'
        self.tries[b] += 1
        lim = self._limit(b)
        if lim is not None and self.tries[b] > lim:
            self.req[b] = False
            self.cached[b] = False
            self.canc[b] = True
            self.fail[b] = True
            self.tries[b] = 0
            self._advance(b)
            return 'failed'
        return 'retry'

    def _advance(self, b):
        if self.fifo and not self.q and b >= self.ded:
            while not self.req[self.ded + self.get % self.fifo] and any(self.req[self.ded:]):
                self.get = (self.get + 1) % self.fifo


def commit_margin(bit_clocks, n_buf, words, wait, cdc=12):
    need = n_buf + words * (2 + wait) + cdc
    return 3 * bit_clocks - need, need


def express_margin(bit_clocks, words, wait, cdc=12):
    """The express buffer may take over until the start of INT1: only its own fetch must fit in the three intermission bits."""
    need = words * (2 + wait) + cdc
    return 3 * bit_clocks - need, need


def selftest():
    ok = True

    def check(c, m):
        nonlocal ok
        print(('PASS ' if c else 'FAIL ') + m)
        ok = ok and c

    I = lambda x: x << 18
    t = Tx(4, 4, True, exp_en=False)
    t.write(0, I(0x200)); t.write(1, I(0x100)); t.write(2, I(0x100))
    for b in (0, 1, 2):
        t.request(b)
    check(t.select() == 1, 'identifier mode: lowest identifier wins; equal identifiers give the lower buffer number')
    t = Tx(2, 0, False, exp_en=False)
    t.write(0, I(0x100), 1); t.write(1, I(0x100), 0)
    t.request(0); t.request(1)
    check(t.select() == 1, 'a base frame wins against an extended frame with the same base identifier')
    t = Tx(0, 4, False)
    for b, i in enumerate((0x300, 0x100, 0x200, 0x050)):
        t.write(b, I(i)); t.request(b)
    order = []
    for _ in range(4):
        order.append(t.start()); t.result(True)
    check(order == [0, 1, 2, 3], 'FIFO mode sends in buffer order whatever the identifiers')
    t = Tx(0, 4, True)
    for b, i in enumerate((0x300, 0x100, 0x200, 0x050)):
        t.write(b, I(i)); t.request(b)
    order = []
    for _ in range(4):
        order.append(t.start()); t.result(True)
    check(order == [3, 1, 2, 0], 'queue mode sends the lowest identifier first')
    t = Tx(0, 4, False)
    for b in range(4):
        t.write(b, I(0x100 + b)); t.request(b)
    t.cancel(0); t.cancel(1)
    check(t.start() == 2 and t.canc[0] and t.canc[1], 'cancelled FIFO buffers are skipped, the next pending one is the head')
    t = Tx(2, 0, False)
    t.write(0, 5); t.request(0)
    t.start(); t.cancel(0)
    check(t.req[0] and not t.canc[0], 'a cancellation after the start does not stop the frame')
    # fixed priority by software
    t = Tx(4, 0, False, prio_mode=1, exp_en=False)
    for b, (i, p) in enumerate(((0x001, 9), (0x7FF, 2), (0x100, 5), (0x050, 2))):
        t.write(b, I(i), prio=p); t.request(b)
    order = []
    for _ in range(4):
        order.append(t.start()); t.result(True)
    check(order == [1, 3, 2, 0], 'fixed priority mode: the PRIO field decides, the identifier is ignored, equal PRIO gives the lower buffer number')
    # express buffer
    t = Tx(4, 0, False, exp_en=True)
    t.write(0, I(0x7FF)); t.write(1, I(0x001)); t.write(2, I(0x002))
    for b in (1, 2, 0):
        t.request(b)
    check(t.select() == 0, 'express buffer 0 wins against a lower identifier')
    t.exp_en = False
    check(t.select() == 1, 'without the express function buffer 0 is an ordinary buffer')
    # trigger transmit: only valid (confirmed) buffers are sent, the others are not blocked
    t = Tx(3, 0, False, exp_en=False)
    t.write(0, I(0x010), trtx=True); t.write(1, I(0x200));
    t.request(0); t.request(1)
    check(t.data_request(0) and t.select() == 1, 'trigger-transmit buffer without confirm is not sent and does not block the others')
    t.start(); t.result(True)
    check(t.select() is None and t.req[0], 'the unconfirmed buffer waits, nothing else is sent')
    t.confirm(0)
    check(t.select() == 0 and not t.data_request(0), 'after the confirm the buffer is a normal candidate')
    t = Tx(0, 2, False)
    t.write(0, I(0x010), trtx=True); t.write(1, I(0x020))
    t.request(0); t.request(1)
    check(t.select() is None, 'a FIFO head that waits for its data blocks the FIFO (order is kept), not the dedicated buffers')
    # per-buffer retry limit and counters
    t = Tx(2, 0, False, retry_max=5, exp_en=False)
    t.write(0, 5, rtl=3); t.write(1, 6, rtl=1)          # buffer 0: 2 retries, buffer 1: single shot
    t.request(0); t.request(1)
    r0, r1 = [], []
    for b in (0, 1, 0, 0):                            # arbitration decides which buffer is on the bus: the attempts interleave
        t.cur = b
        (r0 if b == 0 else r1).append(t.result(False))
    check(r0 == ['retry', 'retry', 'failed'] and r1 == ['failed'] and t.fail[0] and t.fail[1], 'per-buffer retry limit: 2 retries for buffer 0, single shot for buffer 1; counters keep their value while other buffers are sent')
    t = Tx(1, 0, False, retry_max=2)
    t.write(0, 5, rtl=0); t.request(0)
    r = []
    for _ in range(3):
        t.start(); r.append(t.result(False))
    check(r == ['retry', 'retry', 'failed'], 'code 0 uses the global retry_max')
    t = Tx(1, 0, False, retry_max=0)
    t.write(0, 5, rtl=7); t.request(0)
    r = []
    for _ in range(20):
        t.start(); r.append(t.result(False))
    check(set(r) == {'retry'}, 'code 7 is unlimited')
    for f_bus in (100.0, 50.0, 25.0):
        bc = f_bus
        m, need = commit_margin(bc, 32, 18, 3)
        me, needx = express_margin(bc, 18, 3)
        print('INFO 1 Mbit/s, BUS %g MHz: re-scan needs %d of %d clocks (margin %d); express fetch needs %d (margin %d)' % (f_bus, need, 3 * bc, m, needx, me))
    check(commit_margin(100.0, 32, 18, 3)[0] > 0 and commit_margin(25.0, 32, 18, 3)[0] < 0 and express_margin(50.0, 18, 3)[0] > 0, 're-scan fits at 100 MHz, not at 25 MHz; the express fetch alone fits at 50 MHz')
    print('SELFTEST', 'PASS' if ok else 'FAIL')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(selftest())
