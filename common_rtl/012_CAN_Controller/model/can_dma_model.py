#!/usr/bin/env python3
# Project  : VLSIT common RTL library
# Function : reference model of the DMA request logic of the CAN FD controller (section 10.14)
"""Request logic of one Rx FIFO and of the Tx FIFO part, clock accurate on the BUS clock.

Rx request : rises when fill >= wm (wm > 0), falls on the acknowledge pulse, and may rise again only after the hardware has
             taken the acknowledge command (ack_go = 0) and the fill level has been updated (the re-arm rule, DEC-041).
Tx request : rises when the Tx FIFO part has a free buffer, falls on the acknowledge pulse, re-arms when the put index followed
             the request bit that the DMA set.
Usage      : python can_dma_model.py   (self test)
"""
import sys


class RxDma:
    """rearm=False is the naive rule; rearm=True is the rule of the specification.
    burst=False: single mode, a request for every message (fill >= 1). burst=True: a request when fill >= wm and, with a timeout
    to > 0 (clocks), a flush request for the remaining messages when 0 < fill < wm for to clocks. hs4: four-phase handshake."""

    def __init__(self, wm, rearm=True, apply_delay=2, burst=True, to=0, hs4=False):
        self.wm, self.rearm, self.delay, self.burst, self.to, self.hs4 = wm, rearm, apply_delay, burst, to, hs4
        self.fill = 0
        self.req = False
        self.flush = False
        self.timer = 0
        self.pending = None
        self.ack_go = False
        self.cycle = 0
        self.ack_q = False

    def _cond(self):
        if not self.burst:
            return self.fill >= 1, False
        if self.wm and self.fill >= self.wm:
            return True, False
        if self.to and 0 < self.fill < self.wm and self.timer >= self.to:
            return True, True
        return False, False

    def step(self, new_msgs=0, ack=False, ack_free=0):
        """ack: pulse (hs4 False) or level (hs4 True); ack_free: messages whose index the DMA engine wrote with ack_go."""
        self.cycle += 1
        self.fill += new_msgs
        if self.burst and self.to and 0 < self.fill < self.wm:
            self.timer += 1
        else:
            self.timer = 0
        if self.pending:
            left, n = self.pending
            if left == 0:
                self.fill -= n
                self.ack_go = False
                self.pending = None
                self.timer = 0
            else:
                self.pending = (left - 1, n)
        if ack_free:
            self.ack_go = True
            self.pending = (self.delay, ack_free)
        busy = self.ack_go or self.pending is not None
        if self.hs4 and ack:
            busy = True                                   # the acknowledge level must fall before the request may rise
        ok_to_rise = (not busy) if self.rearm else True
        cond, fl = self._cond()
        if ack and not self.hs4 or (self.hs4 and ack):
            self.req = False
            self.flush = False
        elif cond and ok_to_rise:
            self.req, self.flush = True, fl
        elif not cond:
            self.req = False
            self.flush = False
        self.ack_q = ack
        return self.req


class TxDma:
    def __init__(self, size, rearm=True, apply_delay=2):
        self.size, self.rearm, self.delay = size, rearm, apply_delay
        self.used = 0
        self.req = False
        self.pending = None
        self.cycle = 0

    def step(self, ack=False, set_request=False, sent=0):
        """set_request: the DMA wrote an element and set its request bit; sent: buffers freed by transmissions."""
        self.cycle += 1
        self.used -= sent
        if self.pending is not None:
            if self.pending == 0:
                self.used += 1
                self.pending = None
            else:
                self.pending -= 1
        if set_request:
            self.pending = self.delay
        busy = self.pending is not None
        free = self.size - self.used - (1 if busy else 0)
        if ack:
            self.req = False
        elif free > 0 and ((not busy) or not self.rearm):
            self.req = True
        elif free <= 0:
            self.req = False
        return self.req


def selftest():
    ok = True

    def check(c, m):
        nonlocal ok
        print(('PASS ' if c else 'FAIL ') + m)
        ok = ok and c

    # naive rule: the request rises again before the get index has moved: a second service of the same message
    d = RxDma(wm=1, rearm=False)
    d.step(new_msgs=1)
    d.step(ack=True, ack_free=1)                       # the DMA finished: pulse and ack_go together
    d.step()
    check(d.req, 'naive rule: the request rises again while the acknowledged message is still counted (double service)')
    d = RxDma(wm=1, rearm=True)
    d.step(new_msgs=1)
    d.step(ack=True, ack_free=1)
    again = [d.step() for _ in range(6)]
    check(not any(again[:2]) and not again[-1] and d.fill == 0, 'specified rule: no request until ack_go is taken and the fill level has fallen')
    # burst of wm = 4 messages: one request, one acknowledge, then quiet
    d = RxDma(wm=4, rearm=True)
    reqs = []
    for i in range(4):
        reqs.append(d.step(new_msgs=1))
    check(reqs == [False, False, False, True], 'burst: the request rises when the fill level reaches the watermark of 4')
    d.step(ack=True, ack_free=4)
    tail = [d.step() for _ in range(6)]
    check(not any(tail) and d.fill == 0, 'burst: after the acknowledge of 4 messages the request stays low')
    # arrival during the service: the request rises again only when the level is above the watermark after the update
    d = RxDma(wm=2, rearm=True)
    for i in range(2):
        d.step(new_msgs=1)
    d.step(new_msgs=1)                                  # a third message during the service
    d.step(ack=True, ack_free=2)
    r = [d.step() for _ in range(6)]
    check(d.fill == 1 and not any(r), 'a message that arrives during the service stays below the watermark: no request (the low-traffic latency case)')
    d.step(new_msgs=1)
    check(d.req, 'the next message brings the level to the watermark: the request rises')
    # single mode
    d = RxDma(wm=4, burst=False)
    check(d.step(new_msgs=1) and d.fill == 1, 'single mode: a request for one message although the watermark is 4')
    # flush timeout
    d = RxDma(wm=4, burst=True, to=5)
    r = [d.step(new_msgs=1 if i == 0 else 0) for i in range(8)]
    check(r[:4] == [False] * 4 and r[4] and d.flush, 'burst with timeout 5 clocks from the arrival: the flush request rises after the timeout for the one message that waits')
    d.step(ack=True, ack_free=1)
    t2 = [d.step() for _ in range(6)]
    check(not any(t2) and d.fill == 0 and not d.flush, 'after the flush service the request and the flag are clear')
    d = RxDma(wm=4, burst=True, to=0)
    r = [d.step(new_msgs=1 if i == 0 else 0) for i in range(40)]
    check(not any(r), 'timeout 0: no flush, the message waits (the old behavior)')
    d = RxDma(wm=4, burst=True, to=5)
    for i in range(3):
        d.step(new_msgs=1)
    for i in range(3):
        d.step()
    d.step(new_msgs=1)
    check(d.req and not d.flush, 'the fourth message gives the normal burst request, not a flush')
    # four-phase handshake: the request falls when the acknowledge level is seen, re-arms after the acknowledge level is low
    d = RxDma(wm=1, hs4=True)
    d.step(new_msgs=1)
    d.step(ack=True, ack_free=1)
    lv = [d.step(ack=True) for _ in range(3)]
    check(not any(lv), 'four-phase: the request stays low while the acknowledge is high')
    after = [d.step(ack=False) for _ in range(6)]
    check(not any(after) and d.fill == 0, 'four-phase: the request stays low after the acknowledge fell because the fill level was updated')
    # Tx
    t = TxDma(size=2)
    check(t.step() and t.used == 0, 'Tx: a free buffer raises the request')
    t.step(ack=True, set_request=True)
    q = [t.step() for _ in range(5)]
    check(t.used == 1 and q[-1], 'Tx: after the element was requested one buffer is used and the request rises again for the second buffer')
    t.step(ack=True, set_request=True)
    q = [t.step() for _ in range(5)]
    check(t.used == 2 and not q[-1], 'Tx: with all buffers used the request stays low')
    t.step(sent=1)
    check(t.step(), 'Tx: a sent frame frees a buffer and the request rises')
    print('SELFTEST', 'PASS' if ok else 'FAIL')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(selftest())
