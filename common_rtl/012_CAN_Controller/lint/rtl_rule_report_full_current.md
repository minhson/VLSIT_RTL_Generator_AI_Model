# RTL rule check

Files: m_vlsit_csr_canfd.sv, m_vlsit_csr_sync.sv, m_canfd_bsp.sv, m_canfd_btl.sv, m_canfd_cdc.sv, m_canfd_crc.sv, m_canfd_dma.sv, m_canfd_eml.sv, m_canfd_flt.sv, m_canfd_irq.sv, m_canfd_mram.sv, m_canfd_pwr.sv, m_canfd_rst.sv, m_canfd_stuf.sv, m_canfd_sync_bit.sv, m_canfd_sync_hsk.sv, m_canfd_tdc.sv, m_canfd_ts.sv, m_canfd_wprot.sv

| Level | Rule | File:line | Finding |
|---|---|---|---|
| ERROR | NAM-07 | m_vlsit_csr_canfd.sv:119 | localparam 'LPARA_CFD_PNF_IDM_OFFSET_STRIDE' is 31 characters; the limit is 30 |
| ERROR | NAM-07 | m_vlsit_csr_canfd.sv:122 | localparam 'LPARA_CFD_PNF_DLC_OFFSET_STRIDE' is 31 characters; the limit is 30 |
| ERROR | NAM-07 | m_vlsit_csr_canfd.sv:131 | localparam 'LPARA_CFD_PNF_DM0_OFFSET_STRIDE' is 31 characters; the limit is 30 |
| ERROR | NAM-07 | m_vlsit_csr_canfd.sv:134 | localparam 'LPARA_CFD_PNF_DM1_OFFSET_STRIDE' is 31 characters; the limit is 30 |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:207 | clock input 'i_cfd_feat0_saf_clk' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:623 | reset input 'i_hw_wdata_cfd_srst_soft_rst' must be named i_rst_n_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:624 | reset input 'i_hw_we_cfd_srst_soft_rst' must be named i_rst_n_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:876 | clock input 'i_cfd_tt_clk_qgtp' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:877 | clock input 'i_cfd_tt_clk_qcs' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:879 | clock input 'i_hw_wdata_cfd_tt_clk_sgt' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:880 | clock input 'i_hw_we_cfd_tt_clk_sgt' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:882 | clock input 'i_hw_wdata_cfd_tt_clk_ecs' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:883 | clock input 'i_hw_we_cfd_tt_clk_ecs' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:1089 | clock input 'i_hw_wdata_cfd_saf_sts_clk_err' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:1090 | clock input 'i_hw_we_cfd_saf_sts_clk_err' must be named i_clk_<domain> |
| ERROR | NAM-TBL | m_vlsit_csr_canfd.sv:1149 | clock input 'i_cfd_saf_auto_auto_clk' must be named i_clk_<domain> |
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
| WARN | CMT-01 | m_canfd_dma.sv:55 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_dma.sv:57 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_dma.sv:61 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_dma.sv:64 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_dma.sv:66 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_dma.sv:69 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_dma.sv:84 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_dma.sv:90 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_dma.sv:95 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_dma.sv:100 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_dma.sv:105 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_pwr.sv:186 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_ts.sv:80 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_ts.sv:97 | no functional comment before this assign group |
| WARN | CMT-01 | m_canfd_wprot.sv:56 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2202 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2269 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2275 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2281 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2287 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2293 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2299 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2305 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2308 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2371 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2390 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2392 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2411 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2417 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2429 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2435 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2440 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2446 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2466 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2472 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:2478 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5128 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5131 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5151 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5158 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5159 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5173 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5178 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5180 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5197 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5203 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5204 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5218 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5223 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5224 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5238 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5243 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5244 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5258 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5263 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5264 | no functional comment before this process |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:5278 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:7128 | no functional comment before this assign group |
| WARN | CMT-01 | m_vlsit_csr_canfd.sv:7137 | no functional comment before this assign group |
| WARN | HIE-02 | m_canfd_bsp.sv:14 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | HIE-02 | m_canfd_btl.sv:12 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | HIE-02 | m_canfd_cdc.sv:12 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | HIE-02 | m_canfd_rst.sv:11 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | HIE-02 | m_canfd_sync_hsk.sv:12 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | HIE-02 | m_vlsit_csr_canfd.sv:14 | module has instances and also logic; a structural top should contain instances only (HIE-02) |
| WARN | NAM-08 | m_canfd_bsp.sv:103 | port 'o_tx_result_error' spells out 'error'; NAM-08 writes 'err' |
| WARN | NAM-08 | m_canfd_dma.sv:24 | port 'i_soft_reset' spells out 'reset'; NAM-08 writes 'rst' |
| WARN | NAM-08 | m_canfd_dma.sv:27 | port 'i_enable' spells out 'enable'; NAM-08 writes 'en' |
| WARN | NAM-08 | m_canfd_dma.sv:45 | port 'o_req_status' spells out 'status'; NAM-08 writes 'sts' |
| WARN | NAM-08 | m_canfd_dma.sv:47 | signal 'w_threshold_met' spells out 'threshold'; NAM-08 writes 'thr' |
| WARN | NAM-08 | m_canfd_irq.sv:23 | port 'i_soft_reset' spells out 'reset'; NAM-08 writes 'rst' |
| WARN | NAM-08 | m_canfd_irq.sv:31 | port 'i_enable' spells out 'enable'; NAM-08 writes 'en' |
| WARN | NAM-08 | m_canfd_irq.sv:33 | port 'i_line0_enable' spells out 'enable'; NAM-08 writes 'en' |
| WARN | NAM-08 | m_canfd_irq.sv:34 | port 'i_line1_enable' spells out 'enable'; NAM-08 writes 'en' |
| WARN | NAM-08 | m_canfd_irq.sv:39 | port 'o_status' spells out 'status'; NAM-08 writes 'sts' |
| WARN | NAM-08 | m_canfd_ts.sv:42 | port 'i_ts_enable' spells out 'enable'; NAM-08 writes 'en' |
| WARN | NAM-08 | m_canfd_ts.sv:56 | port 'i_soft_reset' spells out 'reset'; NAM-08 writes 'rst' |
| WARN | NAM-08 | m_canfd_ts.sv:87 | process label 'p_com_timestamp_source' spells out 'source'; NAM-08 writes 'src' |
| WARN | NAM-08 | m_canfd_wprot.sv:28 | port 'i_cfg_write_protected' spells out 'write'; NAM-08 writes 'wr' |
| WARN | NAM-08 | m_canfd_wprot.sv:48 | signal 'w_write_blocked' spells out 'write'; NAM-08 writes 'wr' |
| WARN | PAR-03 | m_canfd_bsp.sv:33 | literal 32'd32 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_bsp.sv:339 | literal 7'd2 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_bsp.sv:340 | literal 7'd3 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_bsp.sv:341 | literal 7'd4 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_bsp.sv:342 | literal 7'd5 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_bsp.sv:343 | literal 7'd6 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_bsp.sv:344 | literal 7'd7 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_bsp.sv:345 | literal 7'd8 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_flt.sv:47 | literal 2'd2 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_flt.sv:48 | literal 2'd3 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_flt.sv:57 | literal 2'd2 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_canfd_flt.sv:59 | literal 2'd3 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_vlsit_csr_canfd.sv:2202 | literal 8 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_vlsit_csr_canfd.sv:6852 | literal 32'd2 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_vlsit_csr_canfd.sv:6853 | literal 32'd2 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_vlsit_csr_canfd.sv:6856 | literal 32'd3 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_vlsit_csr_canfd.sv:6857 | literal 32'd3 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_vlsit_csr_canfd.sv:6860 | literal 32'd4 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_vlsit_csr_canfd.sv:6861 | literal 32'd4 may be a magic number (P10); name it with a parameter, localparam or enum member |
| WARN | PAR-03 | m_vlsit_csr_canfd.sv:6864 | literal 32'd5 may be a magic number (P10); name it with a parameter, localparam or enum member |

Rules failed: NAM-07, NAM-TBL
Rules warned: CMT-01, HIE-02, NAM-08, PAR-03
Rules clean: ARI-04, CMT-05, COM-02, COM-03, COM-04, COM-06, COM-07, ENM-01, ENM-03, ENM-04, ENM-05, ENM-06, FIL-01, FIL-02, FIL-03, FIL-04, FIL-05, FIL-06, HIE-01, HIE-03, HIE-05, NAM-09, P1, P11, P12, P13, P14, P17, P18, P19, P2, P20, P21, P22, P24, P25, P26, P27, P29, P3, P30, P4, P6, P7, PAR-01, PAR-02, R-019, R-027, R-032, R-035, R-036, R-038, R-071, R-072, SCP-01, SEC-8.1, SEQ-01, TYP-02, TYP-06
