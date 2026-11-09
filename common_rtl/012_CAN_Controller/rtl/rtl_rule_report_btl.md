# BTL RTL check report

Files checked: `m_canfd_btl.sv`, `m_canfd_sync_bit.sv`.

## Rule checker

Command:

```powershell
python "C:\Users\PC\.codex\skills\vlsit-rtl-generator\scripts\vlsit_rtl_check.py" check `
  common_rtl/012_CAN_Controller/rtl/m_canfd_btl.sv `
  common_rtl/012_CAN_Controller/rtl/m_canfd_sync_bit.sv
```

Result: PASS, 0 errors.

| Level | Rule | Finding | Disposition |
|---|---|---|---|
| WARN | HIE-02 | `m_canfd_btl` instantiates `m_canfd_sync_bit` and also contains timing logic. | Expected leaf-module composition: the asynchronous CAN RX path reuses the approved shared synchronizer. The module is not a structural top. |

## Verilator lint

Command:

```powershell
python "C:\Users\PC\.codex\skills\vlsit-rtl-generator\scripts\vlsit_lint_rtl.py" lint `
  common_rtl/012_CAN_Controller/rtl/filelist_btl.f `
  --top m_canfd_btl --tool verilator `
  --log common_rtl/012_CAN_Controller/rtl/lint_btl_verilator_3.log
```

Result: PASS, 0 errors, 9 warnings. Seven `BLKSEQ` and two `UNUSEDPARAM` warnings originate in the shared synchronizer's simulation model, not in `m_canfd_btl` or `m_canfd_sync_bit`. No simulation or synthesis run was performed.

## Specification check

`vlsit_spec_tool.py check VLSIT_CAN_FD_CONTROLLER_HDS.md` reports PASS: 0 errors, 22 sections. The specification gap scan reports 0 BLOCK gaps and 44 informational TBD items.
