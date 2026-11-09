#!/usr/bin/env python3
# Project  : VLSIT common RTL library
# Function : Executable model of the safety options of the CAN FD controller (section 10.16 and 18):
#            parameter resolution (level preset OR single parameter), dependency rules,
#            fault reaction register, and a FORMULA CHECK of the FMEDA metrics.
"""Usage: python can_safety_model.py [selftest|fmeda|resolve LEVEL]

IMPORTANT: every number in the FMEDA part (flop counts, failure rate per flop, diagnostic
coverage) is an ASSUMPTION of the author (ASM-007, TBD-010). The output shows that the
formulas behave correctly (more mechanisms never lower the metric); it is NOT a metric of the IP.
"""
import json
import os
import sys

MECH = ['RAM', 'WDT', 'REG', 'LOCK', 'CLK', 'CNT', 'FSM', 'E2E', 'TXC', 'TRG', 'DMA', 'INJ', 'DUP', 'SAN']
SM = {'RAM': 'SM-01', 'WDT': 'SM-02', 'REG': 'SM-03', 'LOCK': 'SM-04', 'CLK': 'SM-05', 'CNT': 'SM-06', 'FSM': 'SM-07',
      'E2E': 'SM-08', 'TXC': 'SM-12', 'TRG': 'SM-13', 'DMA': 'SM-14', 'INJ': 'SM-11', 'DUP': 'SM-15', 'SAN': 'SM-16'}
# preset of PARA_CANFD_SAF_LEVEL (DEC-049); DUP is never in a preset
PRESET = {0: set(), 1: {'RAM', 'WDT', 'REG', 'LOCK', 'INJ'},
          2: {'RAM', 'WDT', 'REG', 'LOCK', 'CLK', 'CNT', 'FSM', 'E2E', 'TXC', 'TRG', 'DMA', 'INJ', 'SAN'}}
NEEDS = {'TRG': 'TT_EN', 'DMA': 'DMA_EN'}   # a mechanism that needs a feature


def resolve(level, singles, feats):
    """Return the set of built mechanisms. A preset silently skips a mechanism whose feature is
    missing; an explicit single parameter with a missing feature is an illegal combination."""
    if level not in PRESET:
        raise ValueError('SAF_LEVEL above 2')
    built = set()
    for m in MECH:
        want_single = bool(singles.get(m, 0))
        want_preset = m in PRESET[level]
        ok = feats.get(NEEDS.get(m, ''), True) if m in NEEDS else True
        if want_single and not ok:
            raise ValueError('SAF_%s_EN needs %s' % (m, NEEDS[m]))
        if (want_single or want_preset) and ok:
            built.add(m)
    return built


def auto_enable(built, mask, auto_off):
    """Run-time enable of a mechanism at reset: the build mask sets it; auto_off clears every automatic enable.
    A mask bit of a mechanism that is not built is an illegal combination (DEC-054)."""
    on = set()
    for i, m in enumerate(MECH):
        if (mask >> i) & 1:
            if m not in built:
                raise ValueError('AUTO_MASK bit %d (%s) is not built' % (i, m))
            if not auto_off:
                on.add(m)
    return on


# ---- fault reaction (cfd_saf_rct) ------------------------------------------------------------
FLAGS = ['ram_cor', 'ram_unc', 'ram_wdt', 'reg_par', 'clk_err', 'cnt_cmp', 'st_cmp', 'e2e_err', 'lk_viol',
         'txc_par', 'trg_par', 'dma_wdt', 'dup_cmp', 'san_err']
RCT_RESET = {'ram_cor': 0, 'ram_unc': 1, 'ram_wdt': 1, 'reg_par': 1, 'clk_err': 1, 'cnt_cmp': 1, 'st_cmp': 1,
             'e2e_err': 1, 'lk_viol': 0, 'txc_par': 1, 'trg_par': 1, 'dma_wdt': 0, 'dup_cmp': 1, 'san_err': 1}
FLAG_MECH = {'ram_cor': 'RAM', 'ram_unc': 'RAM', 'ram_wdt': 'WDT', 'reg_par': 'REG', 'clk_err': 'CLK', 'cnt_cmp': 'CNT',
             'st_cmp': 'FSM', 'e2e_err': 'E2E', 'lk_viol': 'LOCK', 'txc_par': 'TXC', 'trg_par': 'TRG', 'dma_wdt': 'DMA',
             'dup_cmp': 'DUP', 'san_err': 'SAN'}


def rct_value(d=None):
    d = d or RCT_RESET
    return sum(d[f] << i for i, f in enumerate(FLAGS))


class Safe:
    """Behavior of m_canfd_safe seen from the outside."""

    def __init__(self, built, rct=None):
        self.built, self.rct = built, rct_value(rct)
        self.sts = 0
        self.init = 0          # INIT forced by a stop reaction
        self.tx_recessive = 0
        self.err_out = 0

    def fault(self, flag, ctrl_en=True, inj=False):
        m = FLAG_MECH[flag]
        if m not in self.built or not ctrl_en:
            return False       # mechanism not built or not enabled: nothing happens
        i = FLAGS.index(flag)
        self.sts |= 1 << i
        self.err_out = 1
        if (self.rct >> i) & 1:
            self.init = 1
            self.tx_recessive = 1
        return True

    def clear(self, mask):
        self.sts &= ~mask
        if not self.sts:
            self.err_out = 0


# ---- FMEDA formula check ----------------------------------------------------------------------
# ASSUMED data: (block, flops, safety_related, share of faults that violate a goal when undetected)
BLOCKS = [
    ('m_canfd_csr', 3000, True, 0.30), ('m_canfd_btl', 600, True, 0.60), ('m_canfd_bsp', 1500, True, 0.50),
    ('m_canfd_stuf_crc', 400, True, 0.70), ('m_canfd_eml', 150, True, 0.60), ('m_canfd_cdc', 900, True, 0.60),
    ('m_canfd_rxh_flt', 2100, True, 0.40), ('m_canfd_txh', 2500, True, 0.40), ('m_canfd_mram', 600, True, 0.50),
    ('m_canfd_irq_dma', 600, True, 0.20), ('m_canfd_ts', 150, False, 0.0), ('m_canfd_tt', 1800, True, 0.40),
    ('m_canfd_pwr_pn', 1900, False, 0.10)]   # not safety-related (DEC-058)
# mechanism -> (blocks covered, diagnostic coverage), generic classes low 0.60, medium 0.90, high 0.99
COVER = {
    'RAM': (['m_canfd_mram', 'm_canfd_rxh_flt'], 0.90), 'WDT': (['m_canfd_mram'], 0.90),
    'REG': (['m_canfd_csr'], 0.90), 'LOCK': (['m_canfd_csr'], 0.60), 'CLK': (['m_canfd_btl', 'm_canfd_bsp', 'm_canfd_cdc'], 0.60),
    'CNT': (['m_canfd_btl', 'm_canfd_eml'], 0.99), 'FSM': (['m_canfd_bsp'], 0.99),
    'E2E': (['m_canfd_cdc', 'm_canfd_rxh_flt', 'm_canfd_txh', 'm_canfd_stuf_crc'], 0.90),
    'TXC': (['m_canfd_txh'], 0.90), 'TRG': (['m_canfd_tt'], 0.90), 'DMA': (['m_canfd_irq_dma'], 0.60),
    'SAN': (['m_canfd_tt', 'm_canfd_irq_dma', 'm_canfd_csr'], 0.80),
    'DUP': (['m_canfd_btl', 'm_canfd_bsp', 'm_canfd_stuf_crc', 'm_canfd_eml'], 0.99)}
INHERENT = {'m_canfd_btl': 0.60, 'm_canfd_bsp': 0.60, 'm_canfd_stuf_crc': 0.60, 'm_canfd_eml': 0.60, 'm_canfd_txh': 0.30}  # SM-09
OVERHEAD_FLOPS = {'RAM': 40, 'WDT': 40, 'REG': 100, 'LOCK': 40, 'CLK': 120, 'CNT': 600, 'FSM': 150, 'E2E': 300,
                  'TXC': 40, 'TRG': 70, 'DMA': 80, 'INJ': 60, 'DUP': 4100, 'SAN': 60}   # ASSUMED, area/latent faults of the mechanisms
LAMBDA_FLOP = 1.0     # relative failure rate of one flop (ASSUMED, unit: relative, not FIT)
INJ_DC = 0.90         # coverage of the latent faults of the mechanisms by the periodic injection test (ASSUMED)


def fmeda(built):
    lam_tot = lam_sr = lam_res = 0.0
    for name, fl, sr, viol in BLOCKS:
        lam = fl * LAMBDA_FLOP
        lam_tot += lam
        if not sr:
            continue
        lam_sr += lam
        v = lam * viol                     # faults that violate a goal when undetected
        unc = 1.0 - INHERENT.get(name, 0.0)
        for m in built:
            if m in COVER and name in COVER[m][0]:
                unc *= 1.0 - COVER[m][1]   # independence of the mechanisms is assumed (DFA)
        lam_res += v * unc
    spfm = 1.0 - lam_res / lam_sr
    lam_sm = sum(OVERHEAD_FLOPS[m] for m in built) * LAMBDA_FLOP
    lat_unc = lam_sm * (1.0 - (INJ_DC if 'INJ' in built else 0.0))
    lfm = 1.0 - lat_unc / (lam_sr - lam_res + lam_sm)
    return {'built': sorted(built), 'lambda_total': lam_tot, 'lambda_sr': lam_sr, 'lambda_res': lam_res,
            'SPFM': spfm, 'LFM': lfm, 'sm_flops': lam_sm / LAMBDA_FLOP, 'area_ratio': 1.0 + lam_sm / lam_tot}


CONFIGS = [('L0 none', 0, {}), ('L1 basic', 1, {}), ('L2 full', 2, {}), ('L2+DUP', 2, {'DUP': 1})]
FEATS = {'TT_EN': True, 'DMA_EN': True}


def table():
    rows = []
    for name, lv, sg in CONFIGS:
        r = fmeda(resolve(lv, sg, FEATS))
        r['name'] = name
        rows.append(r)
    return rows


def selftest():
    n = [0]

    def ok(c, msg):
        assert c, 'FAIL ' + msg
        n[0] += 1
    ok(PRESET[0] == set() and 'DUP' not in PRESET[2], 'presets')
    ok(resolve(1, {}, FEATS) == PRESET[1], 'level 1')
    ok(resolve(2, {}, {'TT_EN': False, 'DMA_EN': False}) == PRESET[2] - {'TRG', 'DMA'}, 'preset skips missing feature')
    ok(resolve(0, {'REG': 1, 'DUP': 1}, FEATS) == {'REG', 'DUP'}, 'single parameters with level 0')
    ok(resolve(1, {'CNT': 1}, FEATS) == PRESET[1] | {'CNT'}, 'single OR preset')
    for bad in (lambda: resolve(0, {'TRG': 1}, {'TT_EN': False}), lambda: resolve(0, {'DMA': 1}, {'DMA_EN': False}), lambda: resolve(3, {}, FEATS)):
        try:
            bad()
            ok(False, 'illegal combination accepted')
        except ValueError:
            ok(True, 'illegal combination rejected')
    ok(rct_value() == 0x36FE, 'rct reset value %#x' % rct_value())
    s = Safe(resolve(2, {}, FEATS))
    ok(s.fault('ram_unc') and s.init and s.tx_recessive and s.err_out, 'stop reaction')
    s2 = Safe(resolve(2, {}, FEATS))
    ok(s2.fault('ram_cor') and not s2.init and s2.err_out, 'report only reaction')
    s2.clear(1)
    ok(not s2.err_out and not s2.sts, 'clear drops o_saf_err')
    s3 = Safe(resolve(1, {}, FEATS))
    ok(not s3.fault('cnt_cmp') and not s3.err_out, 'a mechanism that is not built never reports')
    s4 = Safe(resolve(2, {}, FEATS))
    ok(not s4.fault('reg_par', ctrl_en=False) and s4.sts == 0, 'a built but not enabled mechanism never reports')
    b2 = resolve(2, {}, FEATS)
    ok(auto_enable(b2, 0b0000000100100, 0) == {'REG', 'CNT'}, 'auto mask enables the chosen mechanisms')
    ok(auto_enable(b2, 0b0000000100100, 1) == set(), 'auto_off clears every automatic enable')
    ok(auto_enable(b2, 0, 0) == set(), 'mask 0 = software enables')
    try:
        auto_enable(resolve(1, {}, FEATS), 1 << MECH.index('DUP'), 0)
        ok(False, 'mask bit of a mechanism that is not built accepted')
    except ValueError:
        ok(True, 'mask bit of a mechanism that is not built rejected')
    t = table()
    ok(all(t[i]['SPFM'] <= t[i + 1]['SPFM'] + 1e-12 for i in range(3)), 'SPFM never falls with more mechanisms')
    ok(all(t[i]['area_ratio'] <= t[i + 1]['area_ratio'] for i in range(3)), 'area grows with more mechanisms')
    ok(t[0]['LFM'] == 1.0, 'no mechanism, no latent fault of a mechanism')
    # every single mechanism alone must not lower SPFM, and the injection test must raise the LFM
    base = fmeda(set())['SPFM']
    for m in MECH:
        if m in COVER:
            ok(fmeda({m})['SPFM'] >= base, 'single %s' % m)
    ok(fmeda({'CNT', 'INJ'})['LFM'] > fmeda({'CNT'})['LFM'], 'injection raises LFM')
    # order of the flags equals the order in the register file
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'regs_canfd.json')
    if os.path.exists(p):
        doc = json.load(open(p, encoding='utf-8'))
        regs = {r['name']: r for r in doc.get('registers', doc.get('regs', []))}
        sts = regs.get('cfd_saf_sts')
        if sts:
            names = [f['name'] for f in sts['fields'] if f['name'] in FLAGS]
            ok(names == FLAGS, 'flag order equals the register file %s' % names)
            rr = {f['name']: f for f in regs['cfd_saf_rct']['fields']}
            ok(all(int(rr['r_' + f]['reset'], 16) == RCT_RESET[f] for f in FLAGS), 'reaction reset values equal the register file')
    print('selftest PASS: %d checks' % n[0])


if __name__ == '__main__':
    a = sys.argv[1] if len(sys.argv) > 1 else 'selftest'
    if a == 'fmeda':
        print('FORMULA CHECK ONLY: all inputs are assumptions (ASM-007, TBD-010); not a metric of the IP')
        for r in table():
            print('%-8s SPFM %.4f  LFM %.4f  mechanism flops %5d  area x%.3f  built %s' % (r['name'], r['SPFM'], r['LFM'], r['sm_flops'], r['area_ratio'], ','.join(r['built'])))
    elif a == 'resolve':
        print(sorted(resolve(int(sys.argv[2]), {}, FEATS)))
    else:
        selftest()
