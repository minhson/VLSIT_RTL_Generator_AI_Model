# RTL rule check

Files: m_canfd_bsp.sv, m_canfd_eml.sv

| Level | Rule | File:line | Finding |
|---|---|---|---|
| WARN | CMT-01 | m_canfd_bsp.sv:411 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_bsp.sv:424 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_bsp.sv:430 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_bsp.sv:435 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_bsp.sv:622 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_bsp.sv:624 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_bsp.sv:626 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_bsp.sv:629 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_bsp.sv:631 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_bsp.sv:642 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_bsp.sv:645 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_bsp.sv:647 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_bsp.sv:662 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_bsp.sv:673 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_bsp.sv:676 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_bsp.sv:688 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_bsp.sv:690 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_bsp.sv:1309 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_bsp.sv:1473 | no functional comment before this assign group |
| WARN | HIE-02 | m_canfd_bsp.sv:14 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | NAM-08 | m_canfd_bsp.sv:103 | port 'o_tx_result_error' spells out 'error'; NAM-08 writes 'err' |
| WARN | PAR-03 | m_canfd_bsp.sv:33 | literal 32'd32 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_bsp.sv:339 | literal 7'd2 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_bsp.sv:340 | literal 7'd3 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_bsp.sv:341 | literal 7'd4 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_bsp.sv:342 | literal 7'd5 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_bsp.sv:343 | literal 7'd6 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_bsp.sv:344 | literal 7'd7 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_bsp.sv:345 | literal 7'd8 may be a magic number (P10); name it with a parameter, localparam or enum member |

Rules failed: none
Rules warned: CMT-01, HIE-02, NAM-08, PAR-03
Rules clean: ARI-04, CMT-05, COM-02, COM-03, COM-04, COM-06, COM-07, ENM-01, ENM-03, ENM-04, ENM-05, ENM-06, FIL-01, FIL-02, FIL-03, FIL-04, FIL-05, FIL-06, HIE-01, HIE-03, HIE-05, NAM-07, NAM-09, NAM-TBL, P1, P11, P12, P13, P14, P17, P18, P19, P2, P20, P21, P22, P24, P25, P26, P27, P29, P3, P30, P4, P6, P7, PAR-01, PAR-02, R-019, R-027, R-032, R-035, R-036, R-038, R-071, R-072, SCP-01, SEC-8.1, SEQ-01, TYP-02, TYP-06
