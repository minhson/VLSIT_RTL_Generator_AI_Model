`timescale 1ns/1ps
// Review testbench (not part of the project): BTL + BSP + EML wired as a minimal CAN core.
// MODE 0: internal loopback, one frame.   MODE 1: dominant-stuck bus fault, then release and restart.
module tb_core;
  localparam int FRAME_W = 32 * (4 + 8 / 4);
  logic clk = 0, rst_n = 0;
  always #5 clk = ~clk;
  int mode;
  logic init, lbk_int, dar, fault;
  logic rx_pin;
  logic o_can_tx;
  // BTL <-> BSP
  logic sample, sample_val, tx_point, min_tq, rx_sync, data_phase, cfg_valid, cfg_fix;
  logic cfg_check, integ, hs_en, hs_edl, tx_dom, no_resync, rate_d, rate_n;
  // BSP <-> EML
  logic e_rx_err, e_rx_dom, e_tx_cnt, e_tx_bit, e_rx_bit, e_tx_s8, e_rx_s8, e_tx_ok, e_rx_ok, e_idle11;
  logic err_start, err_phase; logic [2:0] err_code;
  logic [8:0] tec; logic [7:0] rec; logic warn, passive, bus_off, rec_done, eml_fix, saf;
  logic [7:0] rec_cnt; logic [2:0] lec, dlec;
  logic restart_req;
  logic tx_ready, rx_valid, res_valid, res_ok, res_cancel, res_err;
  logic [FRAME_W-1:0] tx_frame, rx_frame;
  logic evt_ack, evt_crc, evt_stuff, evt_form, evt_pxe, evt_dom;
  logic sts_act, sts_init_ack, sts_rfdf, sts_rbrs, sts_resi, sts_pxe, sts_dom;
  logic tdc_frame, tdc_start;

  assign rx_pin = o_can_tx & ~fault;

  m_canfd_btl #(.PARA_CANFD_FD_EN(32'd1)) u_btl (
    .i_clk_can(clk), .i_rst_n_can(rst_n), .i_can_rx(rx_pin),
    .i_cfd_nbt_nbrp(9'd0), .i_cfd_nbt_nprop(9'd6), .i_cfd_nbt_nphs1(7'd5), .i_cfd_nbt_nphs2(7'd5),
    .i_cfd_nbt2_nsjw(7'd1), .i_cfd_nbt2_dsjw(7'd1),
    .i_cfd_dbt_dbrp(5'd0), .i_cfd_dbt_dprop(8'd3), .i_cfd_dbt_dphs1(7'd4), .i_cfd_dbt_dphs2(7'd4),
    .i_cfd_ctrl_efbi(1'b0), .i_cfg_check(cfg_check),
    .i_bus_integrating(integ), .i_hard_sync_en(hs_en), .i_hs_edl(hs_edl), .i_tx_dom(tx_dom),
    .i_no_resync(no_resync), .i_rate_data_candidate(rate_d), .i_rate_nom_candidate(rate_n),
    .o_sample(sample), .o_sample_val(sample_val), .o_tx_point(tx_point), .o_min_tq_tick(min_tq),
    .o_rx_sync(rx_sync), .o_data_phase(data_phase), .o_timing_cfg_valid(cfg_valid), .o_cfg_fix_event(cfg_fix));

  m_canfd_bsp #(.PARA_CANFD_FD_EN(32'd1), .PARA_CANFD_DATA_MAX(32'd8)) u_bsp (
    .i_clk_can(clk), .i_rst_n_can(rst_n), .i_cdc_ready_can(1'b1),
    .i_cfd_ctrl_init(init), .i_cfd_ctrl_fdoe(1'b0), .i_cfd_ctrl_brse(1'b0), .i_cfd_ctrl_niso(1'b0),
    .i_cfd_ctrl_pxd(1'b0), .i_cfd_ctrl_mon(1'b0), .i_cfd_ctrl_rest(1'b0), .i_cfd_ctrl_lbk_int(lbk_int),
    .i_cfd_ctrl_lbk_ext(1'b0), .i_cfd_ctrl_dar(dar), .i_cfd_ctrl_tdc_ena(1'b0), .i_cfd_ctrl_ovl_en(1'b0),
    .i_cfd_dom_cfg_dom_lim(8'd0), .i_tx_permit(1'b1), .i_rx_frame_full_can(1'b0),
    .i_err_passive(passive), .i_bus_off(bus_off),
    .i_sample(sample), .i_sample_val(sample_val), .i_rx_sync(rx_sync), .i_tx_point(tx_point),
    .i_data_phase(data_phase), .i_min_tq_tick(min_tq), .i_timing_cfg_valid(cfg_valid), .i_btl_cfg_fix_event(cfg_fix),
    .i_tdc_active(1'b0), .i_tdc_bit_err(1'b0),
    .i_tx_frame_valid_can(1'b1), .i_tx_frame_can(tx_frame), .o_tx_frame_ready_can(tx_ready),
    .o_rx_frame_valid_can(rx_valid), .o_rx_frame_can(rx_frame), .o_can_tx(o_can_tx),
    .o_tx_result_valid(res_valid), .o_tx_result_success(res_ok), .o_tx_result_cancel(res_cancel), .o_tx_result_error(res_err),
    .o_evt_rx_err(e_rx_err), .o_evt_rx_dom_after_flag(e_rx_dom), .o_evt_tx_err_count(e_tx_cnt),
    .o_evt_tx_bit_err_flag(e_tx_bit), .o_evt_rx_bit_err_flag(e_rx_bit), .o_evt_tx_dom_seq8(e_tx_s8),
    .o_evt_rx_dom_seq8(e_rx_s8), .o_evt_tx_success(e_tx_ok), .o_evt_rx_success(e_rx_ok), .o_evt_idle11(e_idle11),
    .o_err_start(err_start), .o_err_phase_data(err_phase), .o_err_code(err_code),
    .o_sts_act(sts_act), .o_sts_init_ack(sts_init_ack), .o_sts_rfdf(sts_rfdf), .o_sts_rbrs(sts_rbrs),
    .o_sts_resi(sts_resi), .o_sts_pxe(sts_pxe), .o_sts_dom_stk(sts_dom),
    .o_evt_crc_err(evt_crc), .o_evt_stuff_err(evt_stuff), .o_evt_form_err(evt_form), .o_evt_ack_err(evt_ack),
    .o_evt_pxe(evt_pxe), .o_evt_dom_to(evt_dom),
    .o_cfg_check(cfg_check), .o_bus_integrating(integ), .o_hard_sync_en(hs_en), .o_hs_edl(hs_edl),
    .o_tx_dom(tx_dom), .o_no_resync(no_resync), .o_rate_data_candidate(rate_d), .o_rate_nom_candidate(rate_n),
    .o_tdc_frame_active(tdc_frame), .o_tdc_measure_start(tdc_start));

  m_canfd_eml u_eml (
    .i_clk_can(clk), .i_rst_n_can(rst_n),
    .i_evt_rx_err(e_rx_err), .i_evt_rx_dom_after_flag(e_rx_dom), .i_evt_tx_err_count(e_tx_cnt),
    .i_evt_tx_bit_err_flag(e_tx_bit), .i_evt_rx_bit_err_flag(e_rx_bit), .i_evt_tx_dom_seq8(e_tx_s8),
    .i_evt_rx_dom_seq8(e_rx_s8), .i_evt_tx_success(e_tx_ok), .i_evt_rx_success(e_rx_ok),
    .i_bo_cnt(8'd129), .i_restart_req(restart_req), .i_evt_idle11(e_idle11),
    .i_err_start(err_start), .i_err_phase_data(err_phase), .i_err_code(err_code),
    .o_tec(tec), .o_rec(rec), .o_err_warning(warn), .o_err_passive(passive), .o_bus_off(bus_off),
    .o_recovery_count(rec_cnt), .o_recovery_done(rec_done), .o_cfg_fix_event(eml_fix),
    .o_lec(lec), .o_dlec(dlec), .o_saf_fault(saf));

  // Tx element: id 0x123, 2 data bytes 0xA5 0x5A
  always_comb begin
    tx_frame = '0;
    tx_frame[28:0] = 29'h123;
    tx_frame[48 +: 4] = 4'd2;
    tx_frame[128 +: 8] = 8'hA5;
    tx_frame[136 +: 8] = 8'h5A;
  end

  int n_ack, n_err_tx_cnt, n_err_tx_bit, n_ok, n_rx;
  logic [8:0] tec_prev;
  always_ff @(posedge clk) begin
    if (evt_ack) n_ack++;
    if (e_tx_cnt) n_err_tx_cnt++;
    if (e_tx_bit) n_err_tx_bit++;
    if (res_ok) n_ok++;
    if (rx_valid) n_rx++;
    if (e_tx_cnt && e_tx_bit) $display("[%0t] SAME-CYCLE tx_err_count and tx_bit_err_flag (TEC before=%0d)", $time, tec);
    tec_prev <= tec;
    if (mode == 1 && tec != tec_prev) $display("[%0t] TEC %0d -> %0d  bus_off=%0b passive=%0b", $time, tec_prev, tec, bus_off, passive);
  end

  initial begin
    if (!$value$plusargs("MODE=%d", mode)) mode = 0;
    init = 1; lbk_int = (mode == 0); dar = (mode == 0); fault = 0; restart_req = 0;
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (20) @(posedge clk);
    init = 0;
    if (mode == 0) begin
      repeat (6000) @(posedge clk);
      $display("MODE0 internal loopback, DAR=1: tx_ok=%0d rx_valid=%0d ack_err=%0d tec=%0d bus_off=%0b", n_ok, n_rx, n_ack, tec, bus_off);
    end else begin
      // let integration finish, then hold the bus dominant so every transmit attempt fails with a bit error
      repeat (800) @(posedge clk);
      fault = 1;
      repeat (200000) @(posedge clk);
      $display("fault window: tec=%0d bus_off=%0b n_tx_err_count=%0d n_tx_bit_err=%0d", tec, bus_off, n_err_tx_cnt, n_err_tx_bit);
      fault = 0;
      repeat (50) @(posedge clk);
      restart_req = 1; repeat (3) @(posedge clk); restart_req = 0;
      repeat (900000) @(posedge clk);
      $display("after restart + 900k clocks (about %0d bit times): bus_off=%0b tec=%0d recovery_count=%0d done=%0b", 900000/20, bus_off, tec, rec_cnt, rec_done);
    end
    $finish;
  end
endmodule
