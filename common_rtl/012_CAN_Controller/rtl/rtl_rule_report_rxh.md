# RTL rule check

Files: m_canfd_rxh.sv

| Level | Rule | File:line | Finding |
|---|---|---|---|
| WARN | CMT-01 | m_canfd_rxh.sv:400 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_rxh.sv:403 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_rxh.sv:431 | no functional comment before this assign group |
| WARN | HIE-02 | m_canfd_rxh.sv:12 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | PAR-03 | m_canfd_rxh.sv:195 | literal 32 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_rxh.sv:282 | literal 32 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_rxh.sv:290 | literal 7'd8 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_rxh.sv:291 | literal 7'd12 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_rxh.sv:292 | literal 3'd2 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_rxh.sv:293 | literal 3'd3 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_rxh.sv:294 | literal 3'd4 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_rxh.sv:295 | literal 3'd5 may be a magic number (P10); name it with a parameter, localparam or enum member |

Rules failed: none
Rules warned: CMT-01, HIE-02, PAR-03
Rules clean: ARI-04, CMT-05, COM-02, COM-03, COM-04, COM-06, COM-07, ENM-01, ENM-03, ENM-04, ENM-05, ENM-06, FIL-01, FIL-02, FIL-03, FIL-04, FIL-05, FIL-06, HIE-01, HIE-03, HIE-05, NAM-07, NAM-08, NAM-09, NAM-TBL, P1, P11, P12, P13, P14, P17, P18, P19, P2, P20, P21, P22, P24, P25, P26, P27, P29, P3, P30, P4, P6, P7, PAR-01, PAR-02, R-019, R-027, R-032, R-035, R-036, R-038, R-071, R-072, SCP-01, SEC-8.1, SEQ-01, TYP-02, TYP-06
