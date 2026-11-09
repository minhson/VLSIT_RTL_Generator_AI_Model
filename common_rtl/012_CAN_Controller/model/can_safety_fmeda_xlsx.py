#!/usr/bin/env python3
# Project  : VLSIT common RTL library
# Function : Write the FMEDA worksheet with live Excel formulas from the inputs of can_safety_model.py
"""Usage: python can_safety_fmeda_xlsx.py OUT.xlsx

Every input is an ASSUMPTION (ASM-021, ASM-025, TBD-010). Replace the blue cells with the
numbers of the FMEDA (synthesis netlist, failure-rate source, diagnostic coverage evidence).
"""
import os
import sys

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter as L

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import can_safety_model as m  # noqa: E402

BLUE = Font(color='0000FF')
HEAD = Font(bold=True)
FILL = PatternFill('solid', fgColor='DDEBF7')
WARN = PatternFill('solid', fgColor='FFF2CC')


def head(ws, row, vals):
    for c, v in enumerate(vals, 1):
        x = ws.cell(row=row, column=c, value=v)
        x.font, x.fill = HEAD, FILL
        x.alignment = Alignment(wrap_text=True, vertical='top')


def main(out):
    wb = Workbook()
    ws = wb.active
    ws.title = 'Read me'
    lines = [
        'FMEDA worksheet of the CAN FD controller IP (VLSIT, 012_CAN_Controller)',
        'STATUS: FORMULA CHECK ONLY. Every blue cell is an ASSUMPTION of the author (ASM-021, ASM-025). This file is not a safety metric of the IP.',
        'The numbers of ISO 26262 (targets 99 % single-point, 90 % latent, generic coverage classes) are from general knowledge and unverified (ASM-007).',
        'Sheets: Blocks (flops, safety relation, share of goal-violating faults, inherent coverage), Mechanisms (overhead flops, test coverage), Coverage (coverage of each mechanism on each block),',
        'Config (0/1 selection of the mechanisms per configuration; edit it to try any set of parameters), Results (single-point metric, latent-fault metric, area), Residual (per block).',
        'Method: residual of a block = flops x lambda x safety-related x violating share x (1 - inherent) x product over built mechanisms of (1 - coverage). Independence of the mechanisms is assumed (DFA).',
        'Single-point metric = 1 - total residual / total safety-related failure rate. Latent metric = 1 - uncovered mechanism faults / (safety-related rate - residual + mechanism rate).',
        'PMHF is not computed: it needs real failure rates and a lifetime (TBD-010).',
        'The model model/can_safety_model.py computes the same numbers in Python (python can_safety_model.py fmeda); the two must agree.',
        'Power and partial networking are not safety-related (DEC-058, ASM-022): set the column Safety related of the block to 1 to include them.',
    ]
    for i, t in enumerate(lines, 1):
        ws.cell(row=i, column=1, value=t)
    ws['A1'].font = Font(bold=True, size=13)
    ws['A2'].fill = WARN
    ws.column_dimensions['A'].width = 180

    nb, nm = len(m.BLOCKS), len(m.MECH)
    # ---- Blocks
    wb_ = wb.create_sheet('Blocks')
    head(wb_, 1, ['Block', 'Flops (ASSUMED)', 'Safety related (1/0)', 'Violating share (ASSUMED)', 'Inherent coverage SM-09 (ASSUMED)', 'Failure rate (relative)', 'Safety-related rate'])
    wb_['I1'], wb_['J1'] = 'Lambda per flop (relative, ASSUMED)', m.LAMBDA_FLOP
    wb_['I2'], wb_['J2'] = 'Injection test coverage of the mechanism faults (ASSUMED)', m.INJ_DC
    wb_['J1'].font = wb_['J2'].font = BLUE
    for r, (name, fl, sr, viol) in enumerate(m.BLOCKS, 2):
        wb_.cell(row=r, column=1, value=name)
        for c, v in ((2, fl), (3, 1 if sr else 0), (4, viol), (5, m.INHERENT.get(name, 0.0))):
            x = wb_.cell(row=r, column=c, value=v)
            x.font = BLUE
        wb_.cell(row=r, column=6, value='=B%d*$J$1' % r)
        wb_.cell(row=r, column=7, value='=F%d*C%d' % (r, r))
    tr = nb + 2
    wb_.cell(row=tr, column=1, value='Total').font = HEAD
    wb_.cell(row=tr, column=2, value='=SUM(B2:B%d)' % (tr - 1))
    wb_.cell(row=tr, column=6, value='=SUM(F2:F%d)' % (tr - 1))
    wb_.cell(row=tr, column=7, value='=SUM(G2:G%d)' % (tr - 1))
    wb_.column_dimensions['A'].width = 22
    wb_.column_dimensions['I'].width = 55
    for c in 'BCDEFG':
        wb_.column_dimensions[c].width = 18

    # ---- Mechanisms
    wm = wb.create_sheet('Mechanisms')
    head(wm, 1, ['Mechanism', 'Name', 'Overhead flops (ASSUMED)', 'Build parameter'])
    for r, k in enumerate(m.MECH, 2):
        wm.cell(row=r, column=1, value=m.SM[k])
        wm.cell(row=r, column=2, value=k)
        x = wm.cell(row=r, column=3, value=m.OVERHEAD_FLOPS[k])
        x.font = BLUE
        wm.cell(row=r, column=4, value='PARA_CANFD_SAF_%s_EN' % k)
    wm.column_dimensions['C'].width = 24
    wm.column_dimensions['D'].width = 28

    # ---- Coverage matrix (blocks x mechanisms), columns C.. = MECH order
    wc = wb.create_sheet('Coverage')
    head(wc, 1, ['Block', 'Block no.'] + ['%s %s' % (m.SM[k], k) for k in m.MECH])
    for r, (name, fl, sr, viol) in enumerate(m.BLOCKS, 2):
        wc.cell(row=r, column=1, value=name)
        wc.cell(row=r, column=2, value=r - 1)
        for c, k in enumerate(m.MECH, 3):
            blocks, dc = m.COVER.get(k, ([], 0.0))
            x = wc.cell(row=r, column=c, value=dc if name in blocks else 0.0)
            x.font = BLUE
    wc.column_dimensions['A'].width = 22

    # ---- Config (configs x mechanisms), same columns
    wf = wb.create_sheet('Config')
    head(wf, 1, ['Configuration', 'Level'] + ['%s %s' % (m.SM[k], k) for k in m.MECH])
    cfgs = [('L0 none', 0, {}), ('L1 basic', 1, {}), ('L2 full', 2, {}), ('L2 + DUP', 2, {'DUP': 1})]
    for r, (name, lv, sg) in enumerate(cfgs, 2):
        built = m.resolve(lv, sg, m.FEATS)
        wf.cell(row=r, column=1, value=name)
        wf.cell(row=r, column=2, value=lv)
        for c, k in enumerate(m.MECH, 3):
            x = wf.cell(row=r, column=c, value=1 if k in built else 0)
            x.font = BLUE
    wf.cell(row=7, column=1, value='Set a 1 where the mechanism is built (or built and enabled). A mechanism that is built but off covers nothing. SM-09 is always present.')
    wf.column_dimensions['A'].width = 18

    # ---- Residual (blocks x configs)
    wr = wb.create_sheet('Residual')
    head(wr, 1, ['Block'] + [c[0] for c in cfgs])
    last = L(2 + nm)
    for r in range(2, nb + 2):
        wr.cell(row=r, column=1, value='=Blocks!A%d' % r)
        for ci in range(len(cfgs)):
            cr = ci + 2
            f = ('=Blocks!$F%d*Blocks!$C%d*Blocks!$D%d*(1-Blocks!$E%d)*'
                 'EXP(SUMPRODUCT(LN(1-Config!$C$%d:$%s$%d*Coverage!$C%d:$%s%d)))') % (r, r, r, r, cr, last, cr, r, last, r)
            wr.cell(row=r, column=ci + 2, value=f)
    tr2 = nb + 2
    wr.cell(row=tr2, column=1, value='Total residual').font = HEAD
    for ci in range(len(cfgs)):
        col = L(ci + 2)
        wr.cell(row=tr2, column=ci + 2, value='=SUM(%s2:%s%d)' % (col, col, tr2 - 1))
    wr.cell(row=tr2 + 2, column=1, value='Share of the residual (%)').font = HEAD
    for r in range(2, nb + 2):
        wr.cell(row=tr2 + 1 + r, column=1, value='=Blocks!A%d' % r)
        for ci in range(len(cfgs)):
            col = L(ci + 2)
            wr.cell(row=tr2 + 1 + r, column=ci + 2, value='=IF(%s$%d=0,0,%s%d/%s$%d*100)' % (col, tr2, col, r, col, tr2))
    wr.column_dimensions['A'].width = 24

    # ---- Results
    wz = wb.create_sheet('Results', 1)
    head(wz, 1, ['Configuration', 'Single-point metric', 'Latent-fault metric', 'Mechanism flops', 'Area relative to no safety', 'Single-point target (unverified)', 'Latent target (unverified)', 'Single-point met', 'Latent met'])
    inj_col = L(3 + m.MECH.index('INJ'))
    for ci, (name, lv, sg) in enumerate(cfgs):
        r, cr = ci + 2, ci + 2
        col = L(ci + 2)
        wz.cell(row=r, column=1, value=name)
        wz.cell(row=r, column=2, value='=1-Residual!%s%d/Blocks!$G$%d' % (col, tr2, tr))
        wz.cell(row=r, column=4, value='=SUMPRODUCT(Config!$C%d:$%s%d,Overhead!$B$2:$%s$2)' % (cr, last, cr, L(1 + nm)))
        wz.cell(row=r, column=3, value='=1-(D%d*Blocks!$J$1*(1-Config!$%s%d*Blocks!$J$2))/(Blocks!$G$%d-Residual!%s%d+D%d*Blocks!$J$1)' % (r, inj_col, cr, tr, col, tr2, r))
        wz.cell(row=r, column=5, value='=1+D%d*Blocks!$J$1/Blocks!$F$%d' % (r, tr))
        wz.cell(row=r, column=6, value=0.99).font = BLUE
        wz.cell(row=r, column=7, value=0.90).font = BLUE
        wz.cell(row=r, column=8, value='=IF(B%d>=F%d,"yes","no")' % (r, r))
        wz.cell(row=r, column=9, value='=IF(C%d>=G%d,"yes","no")' % (r, r))
        for c in (2, 3):
            wz.cell(row=r, column=c).number_format = '0.0%'
        wz.cell(row=r, column=5).number_format = '0.000'
    wz.cell(row=7, column=1, value='FORMULA CHECK ONLY: inputs are assumptions (ASM-021). The yes and no columns compare with unverified targets (ASM-007) and say nothing about the silicon.').fill = WARN
    for c in range(1, 10):
        wz.column_dimensions[L(c)].width = 22

    # helper sheet: overhead as a row vector (same order as Config columns)
    wo = wb.create_sheet('Overhead')
    wo.cell(row=1, column=1, value='Helper: overhead flops as a row in the order of Config')
    # row 2 holds the values, B..; Config columns start at C, so align with an offset in the formula
    for c, k in enumerate(m.MECH):
        wo.cell(row=2, column=2 + c, value='=Mechanisms!C%d' % (c + 2))
    wb.save(out)
    print('wrote', out)


if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else 'CAN_FD_FMEDA_Worksheet.xlsx')
