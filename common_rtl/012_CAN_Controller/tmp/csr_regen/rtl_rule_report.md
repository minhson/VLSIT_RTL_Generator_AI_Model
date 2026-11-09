# RTL rule check

Files: m_vlsit_csr_canfd.sv, m_csr_sync.sv

| Level | Rule | File:line | Finding |
|---|---|---|---|
| ERROR | NAM-07 | m_vlsit_csr_canfd.sv:117 | localparam 'LPARA_CFD_PNF_IDM_OFFSET_STRIDE' is 31 characters; the limit is 30 |
| ERROR | NAM-07 | m_vlsit_csr_canfd.sv:120 | localparam 'LPARA_CFD_PNF_DLC_OFFSET_STRIDE' is 31 characters; the limit is 30 |
| ERROR | NAM-07 | m_vlsit_csr_canfd.sv:129 | localparam 'LPARA_CFD_PNF_DM0_OFFSET_STRIDE' is 31 characters; the limit is 30 |
| ERROR | NAM-07 | m_vlsit_csr_canfd.sv:132 | localparam 'LPARA_CFD_PNF_DM1_OFFSET_STRIDE' is 31 characters; the limit is 30 |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:205 | clock input 'i_cfd_feat0_saf_clk' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:621 | reset input 'i_hw_wdata_cfd_srst_soft_rst' must be named i_rst_n_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:622 | reset input 'i_hw_we_cfd_srst_soft_rst' must be named i_rst_n_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:874 | clock input 'i_cfd_tt_clk_qgtp' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:875 | clock input 'i_cfd_tt_clk_qcs' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:877 | clock input 'i_hw_wdata_cfd_tt_clk_sgt' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:878 | clock input 'i_hw_we_cfd_tt_clk_sgt' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:880 | clock input 'i_hw_wdata_cfd_tt_clk_ecs' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:881 | clock input 'i_hw_we_cfd_tt_clk_ecs' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:1087 | clock input 'i_hw_wdata_cfd_saf_sts_clk_err' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:1088 | clock input 'i_hw_we_cfd_saf_sts_clk_err' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:1147 | clock input 'i_cfd_saf_auto_auto_clk' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:2198 | sequential state 'w_addr' must be named reg_<name> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:2200 | sequential state 'w_addr' must be named reg_<name> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:2206 | sequential state 'w_wdata' must be named reg_<name> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:2208 | sequential state 'w_wdata' must be named reg_<name> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:2214 | sequential state 'w_wstrb' must be named reg_<name> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:2216 | sequential state 'w_wstrb' must be named reg_<name> |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1783 | 'w_cfd_pnf_id_decode' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1784 | 'w_cfd_pnf_id_decode_valid' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1785 | 'w_cfd_pnf_id_decode_data' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1790 | 'w_cfd_pnf_idm_decode' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1791 | 'w_cfd_pnf_idm_decode_valid' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1792 | 'w_cfd_pnf_idm_decode_data' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1799 | 'w_cfd_pnf_dlc_decode' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1800 | 'w_cfd_pnf_dlc_decode_valid' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1801 | 'w_cfd_pnf_dlc_decode_data' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1806 | 'w_cfd_pnf_d0_decode' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1807 | 'w_cfd_pnf_d0_decode_valid' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1808 | 'w_cfd_pnf_d0_decode_data' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1813 | 'w_cfd_pnf_d1_decode' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1814 | 'w_cfd_pnf_d1_decode_valid' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1815 | 'w_cfd_pnf_d1_decode_data' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1820 | 'w_cfd_pnf_dm0_decode' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1821 | 'w_cfd_pnf_dm0_decode_valid' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1822 | 'w_cfd_pnf_dm0_decode_data' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1827 | 'w_cfd_pnf_dm1_decode' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1828 | 'w_cfd_pnf_dm1_decode_valid' is declared but nothing uses it: remove the declaration (R-072) |
| ERROR | R-072 | m_vlsit_csr_canfd.sv:1829 | 'w_cfd_pnf_dm1_decode_data' is declared but nothing uses it: remove the declaration (R-072) |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2296 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2302 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2308 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2314 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2320 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2326 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2329 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2392 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2411 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2413 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2432 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2438 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2450 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2456 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2461 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2467 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2494 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2500 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5154 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5174 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5181 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5182 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5196 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5201 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5203 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5220 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5226 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5227 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5241 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5246 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5247 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5261 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5266 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5267 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5281 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5286 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5287 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5301 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:7151 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:7160 | no functional comment before this assign group |
| WARN | HIE-02 | m_vlsit_csr_canfd.sv:12 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | PAR-03 | m_vlsit_csr_canfd.sv:2222 | literal 8 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_vlsit_csr_canfd.sv:6875 | literal 32'd2 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_vlsit_csr_canfd.sv:6876 | literal 32'd2 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_vlsit_csr_canfd.sv:6879 | literal 32'd3 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_vlsit_csr_canfd.sv:6880 | literal 32'd3 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_vlsit_csr_canfd.sv:6883 | literal 32'd4 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_vlsit_csr_canfd.sv:6884 | literal 32'd4 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_vlsit_csr_canfd.sv:6887 | literal 32'd5 may be a magic number (P10); name it with a parameter, localparam or enum member |

Rules failed: NAM-07, NAM-TBL, R-072
Rules warned: CMT-01, HIE-02, PAR-03
Rules clean: ARI-04, CMT-05, COM-02, COM-03, COM-04, COM-06, COM-07, ENM-01, ENM-03, ENM-04, ENM-05, ENM-06, FIL-01, FIL-02, FIL-03, FIL-04, FIL-05, FIL-06, HIE-01, HIE-03, HIE-05, NAM-08, NAM-09, P1, P11, P12, P13, P14, P17, P18, P19, P2, P20, P21, P22, P24, P25, P26, P27, P29, P3, P30, P4, P6, P7, PAR-01, PAR-02, R-019, R-027, R-032, R-035, R-036, R-038, R-071, SCP-01, SEC-8.1, SEQ-01, TYP-02, TYP-06
