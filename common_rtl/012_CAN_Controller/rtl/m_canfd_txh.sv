/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-10
 * Description  : Services Tx-buffer requests, fetches valid elements from Message RAM,
 *                submits frame records to the CAN-domain CDC, and records terminal results.
 * HDS           : REQ-MSG-001, REQ-MSG-006..010, REQ-MSG-016, REQ-MSG-020..021,
 *                 REQ-TT-006/009; CDC-006/013/016/017, DEC-027..030, DEC-063, DEC-069,
 *                 DEC-022, DEC-073, DEC-086, DEC-089, DEC-091, DEC-101..103
 */
`timescale 1ns/1ps

module m_canfd_txh #(
  // Parameter Description: maximum payload size carried by the Tx frame bundle.
  // Parameter values: 8, 12, 16, 20, 24, 32, 48, or 64; default is 64.
  // Parameter unit: byte
  parameter logic [31:0] PARA_CANFD_DATA_MAX = 32'd64,
  // Parameter Description: maximum number of Tx buffers implemented in this build.
  // Parameter values: 1 through 32; default is 32.
  // Parameter unit: buffer
  parameter logic [31:0] PARA_CANFD_TXBUF_MAX = 32'd32,
  // Parameter Description: maximum number of Tx event FIFO elements implemented.
  // Parameter values: 1 through 32; default is 32.
  // Parameter unit: element
  parameter logic [31:0] PARA_CANFD_TXE_MAX = 32'd32,
  // Parameter Description: external Message-RAM word-address width.
  // Parameter values: 8 through 14; default is 14.
  // Parameter unit: bit
  parameter logic [31:0] PARA_CANFD_MRAM_AW = 32'd14,
  // Parameter Description: include Tx-event element writes.
  // Parameter values: 0 = disabled, 1 = enabled; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_TXEVT_EN = 32'd1,
  // Parameter Description: include trigger-transmit confirmation handling.
  // Parameter values: 0 = disabled, 1 = enabled; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_TRTX_EN = 32'd1,
  // Parameter Description: select prefetch mode for the next Tx candidate.
  // Parameter values: 0 = re-scan, 1 = prefetch; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_TX_PREFETCH = 32'd1,
  localparam logic [31:0] LPARA_FRAME_WORDS = 32'd4 + PARA_CANFD_DATA_MAX / 32'd4,
  localparam logic [31:0] LPARA_FRAME_W = LPARA_FRAME_WORDS * 32'd32,
  localparam logic [31:0] LPARA_TXBUF_IDX_W = (PARA_CANFD_TXBUF_MAX <= 32'd2) ? 32'd1 : $clog2(PARA_CANFD_TXBUF_MAX),
  localparam logic [31:0] LPARA_STATE_IDLE = 32'd0,
  localparam logic [31:0] LPARA_STATE_CACHE_W0_REQ = 32'd1,
  localparam logic [31:0] LPARA_STATE_CACHE_W0_WAIT = 32'd2,
  localparam logic [31:0] LPARA_STATE_CACHE_W1_REQ = 32'd3,
  localparam logic [31:0] LPARA_STATE_CACHE_W1_WAIT = 32'd4,
  localparam logic [31:0] LPARA_STATE_FETCH_REQ = 32'd5,
  localparam logic [31:0] LPARA_STATE_FETCH_WAIT = 32'd6,
  localparam logic [31:0] LPARA_STATE_SEND = 32'd7,
  localparam logic [31:0] LPARA_STATE_RESULT = 32'd8,
  localparam logic [31:0] LPARA_STATE_EVT_W0_REQ = 32'd9,
  localparam logic [31:0] LPARA_STATE_EVT_W0_WAIT = 32'd10,
  localparam logic [31:0] LPARA_STATE_EVT_W1_REQ = 32'd11,
  localparam logic [31:0] LPARA_STATE_EVT_W1_WAIT = 32'd12,
  localparam logic [31:0] LPARA_STATE_EVT_W2_REQ = 32'd13,
  localparam logic [31:0] LPARA_STATE_EVT_W2_WAIT = 32'd14
) (
  // BUS clock, reset, readiness and coordinated soft reset
  input  wire                      i_clk_bus,
  input  wire                      i_rst_n_bus,
  input  wire                      i_cdc_ready_bus,
  input  wire                      i_srst_req_bus,

  // Tx element and event FIFO section configuration
  input  wire  [2:0]               i_cfd_esz_txb_dsz,
  input  wire                      i_cfd_txb_cfg_qmode,
  input  wire  [5:0]               i_cfd_txb_cfg_fifo_num,
  input  wire  [5:0]               i_cfd_txb_cfg_ded_num,
  input  wire  [15:0]              i_cfd_txb_cfg_start,
  input  wire                      i_cfd_txe_cfg_mm16,
  input  wire  [5:0]               i_cfd_txe_cfg_wm,
  input  wire  [5:0]               i_cfd_txe_cfg_num,
  input  wire  [15:0]              i_cfd_txe_cfg_start,

  // Software Tx commands, current status and interrupt enables
  input  wire  [31:0]              i_cfd_txb_req_req,
  input  wire  [31:0]              i_cfd_ttb_per_per,
  input  wire  [31:0]              i_cfd_txb_cancel_creq,
  input  wire  [31:0]              i_cfd_txb_trtx_conf,
  input  wire  [31:0]              i_cfd_txb_done_done,
  input  wire  [31:0]              i_cfd_txb_cdone_cdn,
  input  wire  [31:0]              i_cfd_txb_fail_fail,
  input  wire  [31:0]              i_cfd_txb_ie_done_ie,
  input  wire  [31:0]              i_cfd_txb_cie_canc_ie,
  input  wire  [7:0]               i_cfd_txr_cfg_retry_max,
  input  wire                      i_cfd_txp_cfg_exp_en,
  input  wire                      i_cfd_txp_cfg_prio_mode,
  input  wire                      i_cfd_ctrl_dar,

  // Controller-state gates for starting a new frame
  input  wire                      i_cfd_ctrl_init,
  input  wire                      i_cfd_ctrl_mon,
  input  wire                      i_cfd_ctrl_rest,
  input  wire                      i_cfd_sts_bus_off,
  input  wire                      i_tx_permit,

  // Tx frame CDC handshake and coherent result record
  input  wire                      i_tx_frame_ready_bus,
  input  wire                      i_tx_result_valid,
  input  wire                      i_tx_result_success,
  input  wire                      i_tx_result_cancel,
  input  wire                      i_tx_result_err,
  input  wire                      i_tx_result_arb_lost,
  input  wire  [31:0]              i_tx_result_timestamp,
  input  wire                      i_tx_result_trigger_valid,
  input  wire  [5:0]               i_tx_result_trigger_buf,
  input  wire                      i_tx_result_trigger_started,
  input  wire                      i_tx_result_trigger_expired,

  // Ordered TTCAN trigger descriptor and current coherent window sequence.
  input  wire                      i_tt_trigger_valid_bus,
  output logic                     o_tt_trigger_ready_bus,
  input  wire  [5:0]               i_tt_trigger_buf_bus,
  input  wire                      i_tt_trigger_merged_bus,
  input  wire  [31:0]              i_tt_trigger_window_seq_bus,
  input  wire  [31:0]              i_tt_window_seq_bus,
  input  wire                      i_tt_window_seq_valid_bus,

  // Tx-event FIFO acknowledgement from software
  input  wire                      i_cfd_txe_ack_ack_go,
  input  wire  [5:0]               i_cfd_txe_ack_ack_idx,

  // Tx-client response from the shared Message-RAM arbiter
  input  wire                      i_tx_ram_ack,
  input  wire  [31:0]              i_tx_ram_rdata,
  input  wire                      i_tx_ram_err,

  // Tx frame record to the CAN-domain CDC
  output logic                     o_tx_frame_valid_bus,
  output logic [LPARA_FRAME_W-1:0] o_tx_frame_bus,
  output logic                     o_tx_result_ready_bus,
  output logic                     o_idle_bus,
  output logic                     o_tx_trigger_tag_valid_bus,
  output logic [5:0]               o_tx_trigger_buf_bus,
  output logic [31:0]              o_tx_trigger_window_seq_bus,

  // Single-word Message-RAM Tx client
  output logic                     o_tx_ram_req,
  output logic                     o_tx_ram_we,
  output logic [31:0]              o_tx_ram_addr,
  output logic [31:0]              o_tx_ram_wdata,

  // CSR command and sticky-status hardware updates
  output logic                     o_req_hw_we,
  output logic [31:0]              o_req_hw_wdata,
  output logic                     o_cancel_hw_we,
  output logic [31:0]              o_cancel_hw_wdata,
  output logic                     o_confirm_hw_we,
  output logic [31:0]              o_confirm_hw_wdata,
  output logic                     o_done_hw_we,
  output logic [31:0]              o_done_hw_wdata,
  output logic                     o_cdone_hw_we,
  output logic [31:0]              o_cdone_hw_wdata,
  output logic                     o_fail_hw_we,
  output logic [31:0]              o_fail_hw_wdata,
  output logic [31:0]              o_cfd_txb_dreq_data_req,

  // Tx FIFO and Tx-event FIFO status inputs to the CSR register file
  output logic                     o_cfd_txf_sts_full,
  output logic [4:0]               o_cfd_txf_sts_pidx,
  output logic [4:0]               o_cfd_txf_sts_gidx,
  output logic [5:0]               o_cfd_txf_sts_free,
  output logic                     o_cfd_txe_sts_full,
  output logic [5:0]               o_cfd_txe_sts_pidx,
  output logic [5:0]               o_cfd_txe_sts_gidx,
  output logic [5:0]               o_cfd_txe_sts_fill,
  output logic                     o_txe_ack_hw_we,
  output logic                     o_txe_ack_hw_wdata,

  // Interrupt and Message-RAM fault events
  output logic                     o_evt_tx_done,
  output logic                     o_evt_tx_can,
  output logic                     o_evt_txe_new,
  output logic                     o_evt_txe_watermark,
  output logic                     o_evt_txe_full,
  output logic                     o_evt_txe_lost,
  output logic                     o_evt_ram_flt,
  output logic [31:0]              o_tx_fault_addr,
  output logic [31:0]              o_ttb_miss_set_bus
);

  typedef enum logic [3:0] {
    ENUM_STATE_IDLE         = LPARA_STATE_IDLE[3:0],
    ENUM_STATE_CACHE_W0_REQ = LPARA_STATE_CACHE_W0_REQ[3:0],
    ENUM_STATE_CACHE_W0_WAIT= LPARA_STATE_CACHE_W0_WAIT[3:0],
    ENUM_STATE_CACHE_W1_REQ = LPARA_STATE_CACHE_W1_REQ[3:0],
    ENUM_STATE_CACHE_W1_WAIT= LPARA_STATE_CACHE_W1_WAIT[3:0],
    ENUM_STATE_FETCH_REQ    = LPARA_STATE_FETCH_REQ[3:0],
    ENUM_STATE_FETCH_WAIT   = LPARA_STATE_FETCH_WAIT[3:0],
    ENUM_STATE_SEND         = LPARA_STATE_SEND[3:0],
    ENUM_STATE_RESULT       = LPARA_STATE_RESULT[3:0],
    ENUM_STATE_EVT_W0_REQ   = LPARA_STATE_EVT_W0_REQ[3:0],
    ENUM_STATE_EVT_W0_WAIT  = LPARA_STATE_EVT_W0_WAIT[3:0],
    ENUM_STATE_EVT_W1_REQ   = LPARA_STATE_EVT_W1_REQ[3:0],
    ENUM_STATE_EVT_W1_WAIT  = LPARA_STATE_EVT_W1_WAIT[3:0],
    ENUM_STATE_EVT_W2_REQ   = LPARA_STATE_EVT_W2_REQ[3:0],
    ENUM_STATE_EVT_W2_WAIT  = LPARA_STATE_EVT_W2_WAIT[3:0]
  } txh_state_type_def;

  txh_state_type_def reg_state;
  logic [31:0] reg_header0 [0:PARA_CANFD_TXBUF_MAX-1];
  logic [31:0] reg_header1 [0:PARA_CANFD_TXBUF_MAX-1];
  logic [PARA_CANFD_TXBUF_MAX-1:0] reg_cache_valid;
  logic [PARA_CANFD_TXBUF_MAX-1:0] reg_confirmed;
  logic [PARA_CANFD_TXBUF_MAX-1:0] reg_late_cancel;
  logic reg_tt_trigger_pending;
  logic [5:0] reg_tt_trigger_buf;
  logic reg_tt_trigger_merged;
  logic [31:0] reg_tt_trigger_seq;
  logic reg_active_tt_trigger;
  logic reg_active_tt_merged;
  logic [31:0] reg_active_tt_seq;
  logic reg_active_tt_started;
  logic [7:0] reg_retry_count [0:PARA_CANFD_TXBUF_MAX-1];
  logic [31:0] reg_req_clear_pending;
  logic [31:0] reg_cancel_clear_pending;
  logic [31:0] reg_confirm_clear_pending;
  logic [31:0] reg_done_set;
  logic [31:0] reg_cdone_set;
  logic [31:0] reg_fail_set;
  logic [31:0] reg_req_prev;
  logic [LPARA_FRAME_W-1:0] reg_tx_frame;
  logic [LPARA_TXBUF_IDX_W-1:0] reg_active_idx;
  logic [LPARA_TXBUF_IDX_W-1:0] reg_cache_idx;
  logic [5:0] reg_fifo_pidx;
  logic [5:0] reg_fifo_gidx;
  logic [5:0] reg_txe_pidx;
  logic [5:0] reg_txe_gidx;
  logic [5:0] reg_txe_fill;
  logic [31:0] reg_element_base;
  logic [31:0] reg_event_base;
  logic [5:0] reg_payload_words;
  logic [5:0] reg_payload_word_idx;
  logic [31:0] reg_event_word0;
  logic [31:0] reg_event_word1;
  logic [31:0] reg_event_word2;
  logic [31:0] reg_active_header0;
  logic [31:0] reg_active_header1;
  logic [6:0] w_txb_total_cfg;
  logic [5:0] w_element_words_cfg;
  logic [32:0] w_element_end_ext;
  logic [32:0] w_req_base_ext;
  logic [32:0] w_req_end_ext;
  logic [32:0] w_selected_base_ext;
  logic [32:0] w_event_base_ext;
  logic [32:0] w_event_end_ext;
  logic [32:0] w_event_cfg_end_ext;
  logic [6:0] w_selected_payload_bytes;
  logic [3:0] w_selected_payload_dlc;
  logic w_req_scan_valid;
  logic [LPARA_TXBUF_IDX_W-1:0] w_req_scan_idx;
  logic w_cancel_scan_valid;
  logic [LPARA_TXBUF_IDX_W-1:0] w_cancel_scan_idx;
  logic w_fifo_head_valid;
  logic [LPARA_TXBUF_IDX_W-1:0] w_fifo_head_idx;
  logic w_selected_valid;
  logic [LPARA_TXBUF_IDX_W-1:0] w_selected_idx;
  logic [5:0] w_fifo_used_count;
  logic [5:0] w_fifo_free_count;
  logic [5:0] w_fifo_nxt_pidx;
  logic w_fifo_new_req_valid;
  logic w_event_pop_valid;
  logic [5:0] w_event_pop_count;
  logic w_event_push;
  logic w_event_space;
  logic w_txe_cfg_valid;
  logic w_tx_gate;
  logic w_tt_desc_stale;
  logic w_tt_desc_current;
  logic w_tt_active_expired;
  logic w_tt_pending_expired;
  logic w_tx_late_cancel;
  logic w_tt_no_retry;
  logic w_tx_retry_limit_hit;
  logic [31:0] reg_ttb_miss_set;
  logic w_cfg_span_valid;
  logic w_event_span_valid;
  logic [7:0] w_retry_limit;
  logic w_retry_limit_finite;
  logic reg_evt_tx_done;
  logic reg_evt_tx_can;
  logic reg_evt_txe_new;
  logic reg_evt_txe_watermark;
  logic reg_evt_txe_full;
  logic reg_evt_txe_lost;
  logic reg_evt_ram_flt;
  logic [31:0] reg_fault_addr;

  // Sequence ordering is modulo 2^32; fewer than 2^31 windows can be outstanding.
  function automatic logic f_seq_after(input logic [31:0] i_current_seq,
                                       input logic [31:0] i_tagged_seq);
    logic [31:0] w_seq_diff;
    begin
      w_seq_diff = i_current_seq - i_tagged_seq;
      f_seq_after = (w_seq_diff != 32'd0) && !w_seq_diff[31];
    end
  endfunction

  function automatic logic [6:0] f_dlc_bytes(input logic [3:0] i_dlc, input logic i_fdf);
    begin
      f_dlc_bytes = 7'd0;
      casez (i_fdf)
        1'b0: begin
          casez (i_dlc)
            4'd0: f_dlc_bytes = 7'd0;
            4'd1: f_dlc_bytes = 7'd1;
            4'd2: f_dlc_bytes = 7'd2;
            4'd3: f_dlc_bytes = 7'd3;
            4'd4: f_dlc_bytes = 7'd4;
            4'd5: f_dlc_bytes = 7'd5;
            4'd6: f_dlc_bytes = 7'd6;
            4'd7: f_dlc_bytes = 7'd7;
            default: f_dlc_bytes = 7'd8;
          endcase
        end
        1'b1: begin
          casez (i_dlc)
            4'd0: f_dlc_bytes = 7'd0;
            4'd1: f_dlc_bytes = 7'd1;
            4'd2: f_dlc_bytes = 7'd2;
            4'd3: f_dlc_bytes = 7'd3;
            4'd4: f_dlc_bytes = 7'd4;
            4'd5: f_dlc_bytes = 7'd5;
            4'd6: f_dlc_bytes = 7'd6;
            4'd7: f_dlc_bytes = 7'd7;
            4'd8: f_dlc_bytes = 7'd8;
            4'd9: f_dlc_bytes = 7'd12;
            4'd10: f_dlc_bytes = 7'd16;
            4'd11: f_dlc_bytes = 7'd20;
            4'd12: f_dlc_bytes = 7'd24;
            4'd13: f_dlc_bytes = 7'd32;
            4'd14: f_dlc_bytes = 7'd48;
            default: f_dlc_bytes = 7'd64;
          endcase
        end
        default: f_dlc_bytes = 7'd0;
      endcase
    end
  endfunction

  function automatic logic [3:0] f_max_dlc(input logic [31:0] i_max_bytes);
    begin
      casez (i_max_bytes)
        32'd8:  f_max_dlc = 4'd8;
        32'd12: f_max_dlc = 4'd9;
        32'd16: f_max_dlc = 4'd10;
        32'd20: f_max_dlc = 4'd11;
        32'd24: f_max_dlc = 4'd12;
        32'd32: f_max_dlc = 4'd13;
        32'd48: f_max_dlc = 4'd14;
        default: f_max_dlc = 4'd15;
      endcase
    end
  endfunction

  // Return the lowest-numbered request whose two-word header is not cached.
  function automatic logic [5:0] f_first_uncached_request;
    logic [5:0] w_result;
    begin
      w_result = '0;
      for (int unsigned w_idx = 0; w_idx < PARA_CANFD_TXBUF_MAX; w_idx++) begin
        if (i_cfd_txb_req_req[w_idx] && !reg_cache_valid[w_idx] && !w_result[5]) begin
          w_result = {1'b1, 5'(w_idx)};
        end
      end
      f_first_uncached_request = w_result;
    end
  endfunction

  // Return the lowest-numbered pending cancellation when the handler is idle.
  function automatic logic [5:0] f_first_pending_cancel;
    logic [5:0] w_result;
    begin
      w_result = '0;
      for (int unsigned w_idx = 0; w_idx < PARA_CANFD_TXBUF_MAX; w_idx++) begin
        if (i_cfd_txb_req_req[w_idx] && i_cfd_txb_cancel_creq[w_idx] && !w_result[5])
          w_result = {1'b1, 5'(w_idx)};
      end
      f_first_pending_cancel = w_result;
    end
  endfunction

  // Return Tx FIFO occupancy and the next put index from new requests.
  function automatic logic [12:0] f_fifo_request_stats;
    logic [5:0] w_used;
    logic [5:0] w_nxt_put;
    logic w_new_req;
    begin
      w_used = '0;
      w_nxt_put = reg_fifo_pidx;
      w_new_req = 1'b0;
      for (int unsigned w_idx = 0; w_idx < PARA_CANFD_TXBUF_MAX; w_idx++) begin
        if ((w_idx >= 32'(i_cfd_txb_cfg_ded_num)) &&
            (w_idx < 32'(w_txb_total_cfg)) && i_cfd_txb_req_req[w_idx]) begin
          w_used = w_used + 6'd1;
          if (!reg_req_prev[w_idx]) begin
            w_new_req = 1'b1;
            w_nxt_put = 6'((w_idx - 32'(i_cfd_txb_cfg_ded_num) + 1) %
                           ((i_cfd_txb_cfg_fifo_num == 6'd0) ? 32'd1 : 32'(i_cfd_txb_cfg_fifo_num)));
          end
        end
      end
      f_fifo_request_stats = {w_used, w_new_req, w_nxt_put};
    end
  endfunction

  // Return the FIFO head by get index; an unconfirmed head blocks later entries.
  function automatic logic [5:0] f_fifo_head;
    logic [5:0] w_result;
    logic [4:0] w_idx;
    begin
      w_result = '0;
      w_idx = '0;
      if (i_cfd_txb_cfg_fifo_num != 6'd0) begin
        for (int unsigned w_step = 0; w_step < PARA_CANFD_TXBUF_MAX; w_step++) begin
          if (w_step < i_cfd_txb_cfg_fifo_num) begin
            w_idx = 5'(i_cfd_txb_cfg_ded_num +
                       ((reg_fifo_gidx + 6'(w_step)) % i_cfd_txb_cfg_fifo_num));
            if (i_cfd_txb_req_req[LPARA_TXBUF_IDX_W'(w_idx)] && !w_result[5])
              w_result = {1'b1, 5'(w_idx)};
          end
        end
      end
      f_fifo_head = w_result;
    end
  endfunction

  // Select the eligible candidate with the lowest arbitration key.
  function automatic logic [5:0] f_select_candidate(input logic i_head_valid,
                                                    input logic [4:0] i_head_idx);
    logic [5:0] w_result;
    logic w_candidate;
    logic w_candidate_exp;
    logic w_best_exp;
    logic w_candidate_better;
    logic [28:0] w_candidate_id;
    logic [28:0] w_best_id;
    logic w_candidate_xtd;
    logic w_best_xtd;
    logic [4:0] w_candidate_prio;
    logic [4:0] w_best_prio;
    logic [29:0] w_candidate_key;
    logic [29:0] w_best_key;
    begin
      w_result = '0;
      w_candidate = 1'b0;
      w_candidate_exp = 1'b0;
      w_best_exp = 1'b0;
      w_candidate_better = 1'b0;
      w_candidate_id = '0;
      w_best_id = '0;
      w_candidate_xtd = 1'b0;
      w_best_xtd = 1'b0;
      w_candidate_prio = '0;
      w_best_prio = '0;
      w_candidate_key = '0;
      w_best_key = '0;
      for (int unsigned w_idx = 0; w_idx < PARA_CANFD_TXBUF_MAX; w_idx++) begin
        w_candidate = 1'b0;
        if ((w_idx < 32'(w_txb_total_cfg)) && (w_txb_total_cfg <= 7'(PARA_CANFD_TXBUF_MAX)) &&
            i_cfd_txb_req_req[w_idx] && reg_cache_valid[w_idx] &&
            (!reg_header1[w_idx][22] || reg_confirmed[w_idx] || i_cfd_txb_trtx_conf[w_idx])) begin
          if (w_idx < 32'(i_cfd_txb_cfg_ded_num))
            w_candidate = 1'b1;
          else if (i_cfd_txb_cfg_qmode)
            w_candidate = 1'b1;
          else
            w_candidate = i_head_valid && (i_head_idx == 5'(w_idx));
        end
        if (w_candidate) begin
          w_candidate_exp = i_cfd_txp_cfg_exp_en && (i_cfd_txb_cfg_ded_num != 6'd0) && (w_idx == 0);
          w_candidate_id = reg_header0[w_idx][28:0];
          w_candidate_xtd = reg_header0[w_idx][30];
          w_candidate_prio = reg_header1[w_idx][31:27];
          w_candidate_key = {w_candidate_id, w_candidate_xtd};
          w_candidate_better = !w_result[5];
          if (w_result[5]) begin
            w_best_exp = i_cfd_txp_cfg_exp_en && (i_cfd_txb_cfg_ded_num != 6'd0) && (w_result[4:0] == 5'd0);
            w_best_id = reg_header0[w_result[4:0]][28:0];
            w_best_xtd = reg_header0[w_result[4:0]][30];
            w_best_prio = reg_header1[w_result[4:0]][31:27];
            w_best_key = {w_best_id, w_best_xtd};
            casez ({w_candidate_exp, w_best_exp, i_cfd_txp_cfg_prio_mode,
                    (w_candidate_prio < w_best_prio), (w_candidate_prio == w_best_prio),
                    (w_candidate_key < w_best_key), (w_candidate_key == w_best_key),
                    (w_idx < 32'(w_result[4:0]))})
              8'b10??????: w_candidate_better = 1'b1;
              8'b01??????: w_candidate_better = 1'b0;
              8'b0011????: w_candidate_better = 1'b1;
              8'b00101???: w_candidate_better = (w_idx < 32'(w_result[4:0]));
              8'b000??1??: w_candidate_better = 1'b1;
              8'b000??01?: w_candidate_better = (w_idx < 32'(w_result[4:0]));
              default:    w_candidate_better = 1'b0;
            endcase
          end
          if (w_candidate_better)
              w_result = {1'b1, 5'(w_idx)};
        end
      end
      f_select_candidate = w_result;
    end
  endfunction

  // Build the software-visible data-request vector for pending trigger-transmit buffers.
  function automatic logic [31:0] f_data_request_vector;
    logic [31:0] w_result;
    begin
      w_result = '0;
      for (int unsigned w_idx = 0; w_idx < PARA_CANFD_TXBUF_MAX; w_idx++) begin
        w_result[w_idx] = i_cfd_txb_req_req[w_idx] && reg_cache_valid[w_idx] &&
                          reg_header1[w_idx][22] && !reg_confirmed[w_idx] &&
                          !i_cfd_txb_trtx_conf[w_idx] && (PARA_CANFD_TRTX_EN == 32'd1);
      end
      f_data_request_vector = w_result;
    end
  endfunction

  // Derive the configured element size and guard the complete Tx section before any RAM request.
  always_comb begin : p_com_tx_element_size
    w_txb_total_cfg = {1'b0, i_cfd_txb_cfg_ded_num} + {1'b0, i_cfd_txb_cfg_fifo_num};
    w_element_words_cfg = 6'd4;
    casez (i_cfd_esz_txb_dsz)
      3'd0: w_element_words_cfg = 6'd4;
      3'd1: w_element_words_cfg = 6'd5;
      3'd2: w_element_words_cfg = 6'd6;
      3'd3: w_element_words_cfg = 6'd7;
      3'd4: w_element_words_cfg = 6'd8;
      3'd5: w_element_words_cfg = 6'd10;
      3'd6: w_element_words_cfg = 6'd14;
      default: w_element_words_cfg = 6'd18;
    endcase
    w_txb_total_cfg = {1'b0, i_cfd_txb_cfg_ded_num} + {1'b0, i_cfd_txb_cfg_fifo_num};
    w_element_end_ext = {16'd0, i_cfd_txb_cfg_start} +
                        (33'(w_txb_total_cfg) * 33'(w_element_words_cfg));
    w_cfg_span_valid = (w_element_end_ext <= (33'd1 << PARA_CANFD_MRAM_AW)) &&
                       (w_txb_total_cfg <= 7'(PARA_CANFD_TXBUF_MAX));
  end

  // Find un-cached requests and pending cancels, and derive the oldest FIFO head.
  always_comb begin : p_com_tx_req_scan
    logic [5:0] w_req_scan_result;
    logic [5:0] w_cancel_scan_result;
    logic [12:0] w_fifo_stats_result;
    logic [5:0] w_fifo_head_result;

    w_req_scan_result = f_first_uncached_request();
    w_cancel_scan_result = f_first_pending_cancel();
    w_fifo_stats_result = f_fifo_request_stats();
    w_fifo_head_result = f_fifo_head();
    w_req_scan_valid = w_req_scan_result[5];
    w_req_scan_idx = LPARA_TXBUF_IDX_W'(w_req_scan_result[4:0]);
    w_cancel_scan_valid = w_cancel_scan_result[5];
    w_cancel_scan_idx = LPARA_TXBUF_IDX_W'(w_cancel_scan_result[4:0]);
    w_fifo_used_count = w_fifo_stats_result[12:7];
    w_fifo_new_req_valid = w_fifo_stats_result[6];
    w_fifo_nxt_pidx = w_fifo_stats_result[5:0];
    w_fifo_head_valid = w_fifo_head_result[5];
    w_fifo_head_idx = LPARA_TXBUF_IDX_W'(w_fifo_head_result[4:0]);

    if (reg_active_tt_trigger && (32'(reg_active_idx) < PARA_CANFD_TXBUF_MAX)) begin
      if (!reg_cache_valid[reg_active_idx]) begin
        w_req_scan_valid = 1'b1;
        w_req_scan_idx = reg_active_idx;
      end else begin
        w_req_scan_valid = 1'b0;
      end
    end else if (reg_tt_trigger_pending &&
                 (32'(reg_tt_trigger_buf) < PARA_CANFD_TXBUF_MAX)) begin
      if (!reg_cache_valid[LPARA_TXBUF_IDX_W'(reg_tt_trigger_buf)]) begin
        w_req_scan_valid = 1'b1;
        w_req_scan_idx = LPARA_TXBUF_IDX_W'(reg_tt_trigger_buf);
      end else begin
        w_req_scan_valid = 1'b0;
      end
    end
    if (i_tt_trigger_valid_bus && o_tt_trigger_ready_bus)
      w_req_scan_valid = 1'b0;
  end

  // Select the lowest arbitration key among eligible buffers.
  always_comb begin : p_com_tx_candidate_sel
    logic [5:0] w_candidate_result;

    w_candidate_result = f_select_candidate(w_fifo_head_valid, 5'(w_fifo_head_idx));
    w_selected_valid = w_candidate_result[5];
    w_selected_idx = LPARA_TXBUF_IDX_W'(w_candidate_result[4:0]);
    if (reg_active_tt_trigger && (32'(reg_active_idx) < PARA_CANFD_TXBUF_MAX)) begin
      w_selected_idx = reg_active_idx;
      w_selected_valid = reg_cache_valid[reg_active_idx] &&
                         (i_cfd_txb_req_req[reg_active_idx] ||
                          i_cfd_ttb_per_per[reg_active_idx]);
    end else if (reg_tt_trigger_pending &&
                 (32'(reg_tt_trigger_buf) < PARA_CANFD_TXBUF_MAX)) begin
      w_selected_idx = LPARA_TXBUF_IDX_W'(reg_tt_trigger_buf);
      w_selected_valid = reg_cache_valid[LPARA_TXBUF_IDX_W'(reg_tt_trigger_buf)] &&
                          (i_cfd_txb_req_req[5'(reg_tt_trigger_buf)] ||
                           i_cfd_ttb_per_per[5'(reg_tt_trigger_buf)]);
    end
    if (i_tt_trigger_valid_bus && o_tt_trigger_ready_bus)
      w_selected_valid = 1'b0;
    w_selected_payload_bytes = 7'd0;
    w_selected_payload_dlc = 4'd0;

    if (w_selected_valid) begin
      w_selected_payload_bytes = f_dlc_bytes(reg_header1[w_selected_idx][19:16],
                                              reg_header1[w_selected_idx][21]);
      w_selected_payload_dlc = reg_header1[w_selected_idx][19:16];
      if (!reg_header1[w_selected_idx][21] && (w_selected_payload_dlc > 4'd8)) begin
        w_selected_payload_dlc = 4'd8;
        w_selected_payload_bytes = 7'd8;
      end
      if (reg_header0[w_selected_idx][29])
        w_selected_payload_bytes = 7'd0;
      if (!reg_header0[w_selected_idx][29] &&
          (w_selected_payload_bytes > 7'((w_element_words_cfg - 6'd2) * 6'd4))) begin
        w_selected_payload_bytes = 7'((w_element_words_cfg - 6'd2) * 6'd4);
        w_selected_payload_dlc = f_max_dlc(32'(w_selected_payload_bytes));
      end
      if (w_selected_payload_bytes > 7'(PARA_CANFD_DATA_MAX)) begin
        w_selected_payload_bytes = 7'(PARA_CANFD_DATA_MAX);
        w_selected_payload_dlc = f_max_dlc(PARA_CANFD_DATA_MAX);
      end
    end
  end

  // Validate event FIFO consumption and compute its current storage availability.
  always_comb begin : p_com_tx_event_sts
    w_event_pop_valid = 1'b0;
    w_event_pop_count = 6'd0;
    w_event_push = (reg_state == ENUM_STATE_EVT_W2_WAIT) && i_tx_ram_ack && !i_tx_ram_err;
    if (i_cfd_txe_ack_ack_go && (reg_txe_fill != 6'd0) && (i_cfd_txe_cfg_num != 6'd0)) begin
      if (i_cfd_txe_ack_ack_idx >= reg_txe_gidx)
        w_event_pop_count = i_cfd_txe_ack_ack_idx - reg_txe_gidx + 6'd1;
      else
        w_event_pop_count = i_cfd_txe_cfg_num - reg_txe_gidx + i_cfd_txe_ack_ack_idx + 6'd1;
      w_event_pop_valid = (w_event_pop_count <= reg_txe_fill) &&
                          (i_cfd_txe_ack_ack_idx < i_cfd_txe_cfg_num);
    end
    w_txe_cfg_valid = (i_cfd_txe_cfg_num != 6'd0) &&
                      (i_cfd_txe_cfg_num <= 6'(PARA_CANFD_TXE_MAX));
    w_event_space = (PARA_CANFD_TXEVT_EN == 32'd1) && w_txe_cfg_valid &&
                    ((reg_txe_fill < i_cfd_txe_cfg_num) || w_event_pop_valid);
  end

  // Drive RAM and CSR interfaces from the FSM and retained state.
  always_comb begin : p_com_tx_outputs
    o_tx_frame_valid_bus = (reg_state == ENUM_STATE_SEND) && !w_tt_active_expired;
    o_tx_frame_bus = reg_tx_frame;
    o_tx_result_ready_bus = (reg_state == ENUM_STATE_RESULT) && i_cdc_ready_bus;
    o_idle_bus = (reg_state == ENUM_STATE_IDLE) && !reg_tt_trigger_pending &&
                 !reg_active_tt_trigger;
    o_tx_trigger_tag_valid_bus = reg_active_tt_trigger && o_tx_frame_valid_bus;
    o_tx_trigger_buf_bus = 6'(reg_active_idx);
    o_tx_trigger_window_seq_bus = reg_active_tt_seq;
    o_tx_ram_req = 1'b0;
    o_tx_ram_we = 1'b0;
    o_tx_ram_addr = '0;
    o_tx_ram_wdata = '0;
    casez (reg_state)
      ENUM_STATE_CACHE_W0_REQ: begin
        o_tx_ram_req = 1'b1;
        o_tx_ram_addr = reg_element_base;
      end
      ENUM_STATE_CACHE_W1_REQ: begin
        o_tx_ram_req = 1'b1;
        o_tx_ram_addr = reg_element_base + 32'd1;
      end
      ENUM_STATE_FETCH_REQ: begin
        o_tx_ram_req = 1'b1;
        o_tx_ram_addr = reg_element_base + 32'd2 + {26'd0, reg_payload_word_idx};
      end
      ENUM_STATE_EVT_W0_REQ: begin
        o_tx_ram_req = 1'b1;
        o_tx_ram_we = 1'b1;
        o_tx_ram_addr = reg_event_base;
        o_tx_ram_wdata = reg_event_word0;
      end
      ENUM_STATE_EVT_W1_REQ: begin
        o_tx_ram_req = 1'b1;
        o_tx_ram_we = 1'b1;
        o_tx_ram_addr = reg_event_base + 32'd1;
        o_tx_ram_wdata = reg_event_word1;
      end
      ENUM_STATE_EVT_W2_REQ: begin
        o_tx_ram_req = 1'b1;
        o_tx_ram_we = 1'b1;
        o_tx_ram_addr = reg_event_base + 32'd2;
        o_tx_ram_wdata = reg_event_word2;
      end
      default: begin
        o_tx_ram_req = 1'b0;
        o_tx_ram_we = 1'b0;
        o_tx_ram_addr = '0;
        o_tx_ram_wdata = '0;
      end
    endcase

    o_req_hw_we = |reg_req_clear_pending;
    o_req_hw_wdata = i_cfd_txb_req_req & ~reg_req_clear_pending;
    o_cancel_hw_we = |reg_cancel_clear_pending;
    o_cancel_hw_wdata = i_cfd_txb_cancel_creq & ~reg_cancel_clear_pending;
    o_confirm_hw_we = |reg_confirm_clear_pending;
    o_confirm_hw_wdata = i_cfd_txb_trtx_conf & ~reg_confirm_clear_pending;
    o_done_hw_we = |reg_done_set;
    o_done_hw_wdata = i_cfd_txb_done_done | reg_done_set;
    o_cdone_hw_we = |reg_cdone_set;
    o_cdone_hw_wdata = i_cfd_txb_cdone_cdn | reg_cdone_set;
    o_fail_hw_we = |reg_fail_set;
    o_fail_hw_wdata = i_cfd_txb_fail_fail | reg_fail_set;
    o_cfd_txb_dreq_data_req = f_data_request_vector();
    o_cfd_txf_sts_full = (i_cfd_txb_cfg_fifo_num != 6'd0) && (w_fifo_free_count == 6'd0);
    o_cfd_txf_sts_pidx = 5'(reg_fifo_pidx);
    o_cfd_txf_sts_gidx = 5'(reg_fifo_gidx);
    o_cfd_txf_sts_free = w_fifo_free_count;
    o_cfd_txe_sts_full = w_txe_cfg_valid && (reg_txe_fill >= i_cfd_txe_cfg_num);
    o_cfd_txe_sts_pidx = reg_txe_pidx;
    o_cfd_txe_sts_gidx = reg_txe_gidx;
    o_cfd_txe_sts_fill = reg_txe_fill;
    o_txe_ack_hw_we = i_cfd_txe_ack_ack_go;
    o_txe_ack_hw_wdata = 1'b0;
    o_evt_tx_done = reg_evt_tx_done;
    o_evt_tx_can = reg_evt_tx_can;
    o_evt_txe_new = reg_evt_txe_new;
    o_evt_txe_watermark = reg_evt_txe_watermark;
    o_evt_txe_full = reg_evt_txe_full;
    o_evt_txe_lost = reg_evt_txe_lost;
    o_evt_ram_flt = reg_evt_ram_flt;
    o_tx_fault_addr = reg_fault_addr;
    o_ttb_miss_set_bus = reg_ttb_miss_set;
  end

  // Derive FIFO availability, Tx-result qualifiers and operation-specific range checks.
  always_comb begin : p_com_tx_checks
    w_fifo_free_count = (i_cfd_txb_cfg_fifo_num > w_fifo_used_count) ?
                        (i_cfd_txb_cfg_fifo_num - w_fifo_used_count) : 6'd0;
    w_tx_gate = i_cdc_ready_bus && !i_srst_req_bus && !i_cfd_ctrl_init &&
                !i_cfd_ctrl_mon && !i_cfd_ctrl_rest && !i_cfd_sts_bus_off && i_tx_permit;
    w_tt_desc_stale = i_tt_window_seq_valid_bus &&
                      f_seq_after(i_tt_window_seq_bus, i_tt_trigger_window_seq_bus);
    w_tt_desc_current = i_tt_window_seq_valid_bus &&
                        (i_tt_window_seq_bus == i_tt_trigger_window_seq_bus) && i_tx_permit;
    w_tt_active_expired = reg_active_tt_trigger && i_tt_window_seq_valid_bus &&
                          (f_seq_after(i_tt_window_seq_bus, reg_active_tt_seq) ||
                           ((i_tt_window_seq_bus == reg_active_tt_seq) && !i_tx_permit));
    w_tt_pending_expired = reg_tt_trigger_pending && i_tt_window_seq_valid_bus &&
                           (f_seq_after(i_tt_window_seq_bus, reg_tt_trigger_seq) ||
                            ((i_tt_window_seq_bus == reg_tt_trigger_seq) && !i_tx_permit));
    w_tx_late_cancel = reg_late_cancel[reg_active_idx] ||
                       i_cfd_txb_cancel_creq[reg_active_idx];
    w_tt_no_retry = reg_active_tt_trigger &&
                    (!reg_active_tt_merged || i_tx_result_trigger_expired ||
                     w_tt_active_expired);
    o_tt_trigger_ready_bus = (reg_state == ENUM_STATE_IDLE) && !reg_tt_trigger_pending &&
                             !reg_active_tt_trigger && !i_srst_req_bus &&
                             i_cdc_ready_bus && i_tt_window_seq_valid_bus &&
                             ((i_tt_window_seq_bus == i_tt_trigger_window_seq_bus) ||
                              w_tt_desc_stale);
    w_retry_limit = 8'd0;
    w_retry_limit_finite = 1'b1;
    casez (reg_active_header1[26:24])
      3'd0: begin
        w_retry_limit = i_cfd_txr_cfg_retry_max;
        w_retry_limit_finite = (i_cfd_txr_cfg_retry_max != 8'd0);
      end
      3'd1: w_retry_limit = 8'd0;
      3'd2: w_retry_limit = 8'd1;
      3'd3: w_retry_limit = 8'd2;
      3'd4: w_retry_limit = 8'd3;
      3'd5: w_retry_limit = 8'd7;
      3'd6: w_retry_limit = 8'd15;
      default: begin
        w_retry_limit = 8'd0;
        w_retry_limit_finite = 1'b0;
      end
    endcase
    w_tx_retry_limit_hit = i_cfd_ctrl_dar ||
                           (w_retry_limit_finite &&
                            (({1'b0, reg_retry_count[reg_active_idx]} + 9'd1) >
                             {1'b0, w_retry_limit}));
    w_req_base_ext = {17'd0, i_cfd_txb_cfg_start} +
                     (33'(w_req_scan_idx) * 33'(w_element_words_cfg));
    w_req_end_ext = w_req_base_ext + 33'(w_element_words_cfg);
    w_selected_base_ext = {17'd0, i_cfd_txb_cfg_start} +
                          (33'(w_selected_idx) * 33'(w_element_words_cfg));
    w_event_base_ext = {17'd0, i_cfd_txe_cfg_start} + (33'(reg_txe_pidx) * 33'd3);
    w_event_end_ext = w_event_base_ext + 33'd3;
    w_event_cfg_end_ext = {17'd0, i_cfd_txe_cfg_start} +
                          (33'(i_cfd_txe_cfg_num) * 33'd3);
    w_event_span_valid = w_txe_cfg_valid &&
                         (w_event_cfg_end_ext <= (33'd1 << PARA_CANFD_MRAM_AW)) &&
                         (w_event_end_ext <= (33'd1 << PARA_CANFD_MRAM_AW));
  end

  // Own request caching, candidate fetch, frame handoff, retry disposition, and Tx-event writes.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_canfd_txh
    if (!i_rst_n_bus) begin
      reg_state <= ENUM_STATE_IDLE;
      reg_cache_valid <= '0;
      reg_confirmed <= '0;
      reg_req_clear_pending <= '0;
      reg_cancel_clear_pending <= '0;
      reg_confirm_clear_pending <= '0;
      reg_done_set <= '0;
      reg_cdone_set <= '0;
      reg_fail_set <= '0;
      reg_req_prev <= '0;
      reg_tx_frame <= '0;
      reg_active_idx <= '0;
      reg_cache_idx <= '0;
      reg_fifo_pidx <= '0;
      reg_fifo_gidx <= '0;
      reg_txe_pidx <= '0;
      reg_txe_gidx <= '0;
      reg_txe_fill <= '0;
      reg_element_base <= '0;
      reg_event_base <= '0;
      reg_payload_words <= '0;
      reg_payload_word_idx <= '0;
      reg_event_word0 <= '0;
      reg_event_word1 <= '0;
      reg_event_word2 <= '0;
      reg_active_header0 <= '0;
      reg_active_header1 <= '0;
      reg_late_cancel <= '0;
      reg_tt_trigger_pending <= 1'b0;
      reg_tt_trigger_buf <= '0;
      reg_tt_trigger_merged <= 1'b0;
      reg_tt_trigger_seq <= '0;
      reg_active_tt_trigger <= 1'b0;
      reg_active_tt_merged <= 1'b0;
      reg_active_tt_seq <= '0;
      reg_active_tt_started <= 1'b0;
      reg_ttb_miss_set <= '0;
      reg_evt_tx_done <= 1'b0;
      reg_evt_tx_can <= 1'b0;
      reg_evt_txe_new <= 1'b0;
      reg_evt_txe_watermark <= 1'b0;
      reg_evt_txe_full <= 1'b0;
      reg_evt_txe_lost <= 1'b0;
      reg_evt_ram_flt <= 1'b0;
      reg_fault_addr <= '0;
      for (int unsigned w_reset_idx = 0; w_reset_idx < PARA_CANFD_TXBUF_MAX; w_reset_idx++) begin
        reg_header0[w_reset_idx] <= '0;
        reg_header1[w_reset_idx] <= '0;
        reg_retry_count[w_reset_idx] <= '0;
      end
    end else begin
      reg_req_prev <= i_cfd_txb_req_req;
      reg_evt_tx_done <= 1'b0;
      reg_evt_tx_can <= 1'b0;
      reg_evt_txe_new <= 1'b0;
      reg_evt_txe_watermark <= 1'b0;
      reg_evt_txe_full <= 1'b0;
      reg_evt_txe_lost <= 1'b0;
      reg_evt_ram_flt <= 1'b0;
      reg_done_set <= '0;
      reg_cdone_set <= '0;
      reg_fail_set <= '0;
      reg_ttb_miss_set <= '0;

      // Capture only descriptors whose sequence is current; stale ones become sticky misses.
      if (i_tt_trigger_valid_bus && o_tt_trigger_ready_bus) begin
        if (w_tt_desc_current &&
            (32'(i_tt_trigger_buf_bus) < PARA_CANFD_TXBUF_MAX) &&
            (i_cfd_txb_req_req[5'(i_tt_trigger_buf_bus)] ||
             i_cfd_ttb_per_per[5'(i_tt_trigger_buf_bus)])) begin
          reg_tt_trigger_pending <= 1'b1;
          reg_tt_trigger_buf <= i_tt_trigger_buf_bus;
          reg_tt_trigger_merged <= i_tt_trigger_merged_bus;
          reg_tt_trigger_seq <= i_tt_trigger_window_seq_bus;
        end else if (i_tt_trigger_buf_bus < 6'd32) begin
          reg_ttb_miss_set[5'(i_tt_trigger_buf_bus)] <= 1'b1;
        end
      end

      // Clear local state after the request drops; hold pending CSR updates.
      for (int unsigned w_clean_idx = 0; w_clean_idx < PARA_CANFD_TXBUF_MAX; w_clean_idx++) begin
        if (!i_cfd_txb_req_req[w_clean_idx] && !i_cfd_ttb_per_per[w_clean_idx]) begin
          reg_cache_valid[w_clean_idx] <= 1'b0;
          reg_confirmed[w_clean_idx] <= 1'b0;
          reg_retry_count[w_clean_idx] <= '0;
          reg_req_clear_pending[w_clean_idx] <= 1'b0;
          reg_cancel_clear_pending[w_clean_idx] <= 1'b0;
          reg_confirm_clear_pending[w_clean_idx] <= 1'b0;
        end
        if (i_cfd_txb_cancel_creq[w_clean_idx] == 1'b0)
          reg_cancel_clear_pending[w_clean_idx] <= 1'b0;
        if (i_cfd_txb_trtx_conf[w_clean_idx] == 1'b0)
          reg_confirm_clear_pending[w_clean_idx] <= 1'b0;
        if (i_cfd_txb_trtx_conf[w_clean_idx]) begin
          reg_confirmed[w_clean_idx] <= 1'b1;
          reg_confirm_clear_pending[w_clean_idx] <= 1'b1;
        end
      end

      // Maintain event FIFO count and wrap-safe software read pointer.
      if (w_event_pop_valid) begin
        if (i_cfd_txe_ack_ack_idx == (i_cfd_txe_cfg_num - 6'd1))
          reg_txe_gidx <= '0;
        else
          reg_txe_gidx <= i_cfd_txe_ack_ack_idx + 6'd1;
      end
      if (w_event_pop_valid && !w_event_push)
        reg_txe_fill <= reg_txe_fill - w_event_pop_count;
      else if (w_event_push && !w_event_pop_valid)
        reg_txe_fill <= reg_txe_fill + 6'd1;

      // Derive put index from each newly asserted FIFO-buffer request.
      if (w_fifo_new_req_valid)
        reg_fifo_pidx <= w_fifo_nxt_pidx;

      casez (reg_state)
        ENUM_STATE_IDLE: begin
          reg_late_cancel <= '0;
          casez ({i_srst_req_bus, (reg_active_tt_trigger && w_tt_active_expired),
                  (reg_tt_trigger_pending && w_tt_pending_expired),
                  w_cancel_scan_valid, w_req_scan_valid,
                  (w_selected_valid && w_tx_gate)})
            6'b1?????: begin
              reg_cache_valid <= '0;
              reg_confirmed <= '0;
              reg_tt_trigger_pending <= 1'b0;
              reg_active_tt_trigger <= 1'b0;
              reg_active_tt_started <= 1'b0;
              for (int unsigned w_srst_idx = 0; w_srst_idx < PARA_CANFD_TXBUF_MAX; w_srst_idx++)
                reg_retry_count[w_srst_idx] <= '0;
              reg_fifo_pidx <= '0;
              reg_fifo_gidx <= '0;
              reg_txe_pidx <= '0;
              reg_txe_gidx <= '0;
              reg_txe_fill <= '0;
            end
            6'b01????: begin
              if (!reg_active_tt_started)
                reg_ttb_miss_set[5'(reg_active_idx)] <= 1'b1;
              reg_active_tt_trigger <= 1'b0;
              reg_active_tt_started <= 1'b0;
              reg_retry_count[reg_active_idx] <= '0;
            end
            6'b001???: begin
              if (reg_tt_trigger_buf < 6'd32)
                reg_ttb_miss_set[5'(reg_tt_trigger_buf)] <= 1'b1;
              reg_tt_trigger_pending <= 1'b0;
            end
            6'b0001??: begin
              reg_req_clear_pending[w_cancel_scan_idx] <= 1'b1;
              reg_cancel_clear_pending[w_cancel_scan_idx] <= 1'b1;
              reg_cache_valid[w_cancel_scan_idx] <= 1'b0;
              reg_confirmed[w_cancel_scan_idx] <= 1'b0;
              if (reg_tt_trigger_pending &&
                  (reg_tt_trigger_buf == 6'(w_cancel_scan_idx)))
                reg_tt_trigger_pending <= 1'b0;
              if (reg_active_tt_trigger &&
                  (reg_active_idx == w_cancel_scan_idx)) begin
                reg_active_tt_trigger <= 1'b0;
                reg_active_tt_started <= 1'b0;
              end
              reg_cdone_set[w_cancel_scan_idx] <= 1'b1;
              if (i_cfd_txb_cie_canc_ie[w_cancel_scan_idx])
                reg_evt_tx_can <= 1'b1;
            end
            6'b00001?: begin
              reg_cache_idx <= w_req_scan_idx;
              reg_element_base <= 32'(w_req_base_ext);
              if (!w_cfg_span_valid ||
                  (w_req_end_ext > (33'd1 << PARA_CANFD_MRAM_AW))) begin
                reg_req_clear_pending[w_req_scan_idx] <= 1'b1;
                reg_cache_valid[w_req_scan_idx] <= 1'b0;
                reg_cdone_set[w_req_scan_idx] <= 1'b1;
                reg_evt_ram_flt <= 1'b1;
                reg_fault_addr <= 32'(w_req_base_ext);
                if (i_cfd_txb_cie_canc_ie[w_req_scan_idx])
                  reg_evt_tx_can <= 1'b1;
              end else begin
                reg_state <= ENUM_STATE_CACHE_W0_REQ;
              end
            end
            6'b000001: begin
              reg_active_idx <= w_selected_idx;
              reg_active_header0 <= reg_header0[w_selected_idx];
              reg_active_header1 <= reg_header1[w_selected_idx];
              if (reg_tt_trigger_pending &&
                  (reg_tt_trigger_buf == 6'(w_selected_idx))) begin
                reg_active_tt_trigger <= 1'b1;
                reg_active_tt_merged <= reg_tt_trigger_merged;
                reg_active_tt_seq <= reg_tt_trigger_seq;
                reg_active_tt_started <= 1'b0;
                reg_tt_trigger_pending <= 1'b0;
              end else if (!reg_active_tt_trigger) begin
                reg_active_tt_trigger <= 1'b0;
                reg_active_tt_merged <= 1'b0;
                reg_active_tt_seq <= '0;
                reg_active_tt_started <= 1'b0;
              end
              reg_element_base <= 32'(w_selected_base_ext);
              reg_payload_words <= 6'((w_selected_payload_bytes + 7'd3) / 7'd4);
              reg_payload_word_idx <= '0;
              reg_tx_frame <= '0;
              reg_tx_frame[31:0] <= reg_header0[w_selected_idx];
              reg_tx_frame[63:32] <= {reg_header1[w_selected_idx][31:20], w_selected_payload_dlc,
                                       reg_header1[w_selected_idx][15:0]};
              if ((reg_header1[w_selected_idx][22] == 1'b1) &&
                  !reg_confirmed[w_selected_idx] && i_cfd_txb_trtx_conf[w_selected_idx]) begin
                reg_confirmed[w_selected_idx] <= 1'b1;
                reg_confirm_clear_pending[w_selected_idx] <= 1'b1;
              end
              if (w_selected_base_ext[32] ||
                  ((w_selected_base_ext + 33'(w_element_words_cfg)) > (33'd1 << PARA_CANFD_MRAM_AW))) begin
                reg_req_clear_pending[w_selected_idx] <= 1'b1;
                reg_cdone_set[w_selected_idx] <= 1'b1;
                reg_cache_valid[w_selected_idx] <= 1'b0;
                reg_active_tt_trigger <= 1'b0;
                reg_active_tt_started <= 1'b0;
                reg_evt_ram_flt <= 1'b1;
                reg_fault_addr <= 32'(w_selected_base_ext);
                reg_state <= ENUM_STATE_IDLE;
              end else if (w_selected_payload_bytes == 7'd0)
                reg_state <= ENUM_STATE_SEND;
              else
                reg_state <= ENUM_STATE_FETCH_REQ;
            end
            default: begin
              reg_state <= reg_state;
            end
          endcase
        end

        ENUM_STATE_CACHE_W0_REQ: reg_state <= ENUM_STATE_CACHE_W0_WAIT;
        ENUM_STATE_CACHE_W0_WAIT: begin
          if (i_tx_ram_ack) begin
            if (i_tx_ram_err) begin
              if (reg_tt_trigger_pending && w_tt_pending_expired &&
                  (reg_tt_trigger_buf < 6'd32))
                reg_ttb_miss_set[5'(reg_tt_trigger_buf)] <= 1'b1;
              reg_req_clear_pending[reg_cache_idx] <= 1'b1;
              reg_cdone_set[reg_cache_idx] <= 1'b1;
              reg_cache_valid[reg_cache_idx] <= 1'b0;
              reg_evt_ram_flt <= 1'b1;
              reg_fault_addr <= reg_element_base;
              if (i_cfd_txb_cie_canc_ie[reg_cache_idx])
                reg_evt_tx_can <= 1'b1;
              if (reg_tt_trigger_pending &&
                  (reg_tt_trigger_buf == 6'(reg_cache_idx)))
                reg_tt_trigger_pending <= 1'b0;
              reg_active_tt_trigger <= 1'b0;
              reg_active_tt_started <= 1'b0;
              reg_state <= ENUM_STATE_IDLE;
            end else if (reg_tt_trigger_pending && w_tt_pending_expired) begin
              if (reg_tt_trigger_buf < 6'd32)
                reg_ttb_miss_set[5'(reg_tt_trigger_buf)] <= 1'b1;
              reg_tt_trigger_pending <= 1'b0;
              reg_state <= ENUM_STATE_IDLE;
            end else begin
              if (i_cfd_txb_cancel_creq[reg_cache_idx]) begin
                reg_req_clear_pending[reg_cache_idx] <= 1'b1;
                reg_cancel_clear_pending[reg_cache_idx] <= 1'b1;
                reg_cdone_set[reg_cache_idx] <= 1'b1;
                reg_cache_valid[reg_cache_idx] <= 1'b0;
                if (i_cfd_txb_cie_canc_ie[reg_cache_idx])
                  reg_evt_tx_can <= 1'b1;
                reg_state <= ENUM_STATE_IDLE;
              end else begin
                reg_header0[reg_cache_idx] <= i_tx_ram_rdata;
                reg_state <= ENUM_STATE_CACHE_W1_REQ;
              end
            end
          end
        end
        ENUM_STATE_CACHE_W1_REQ: reg_state <= ENUM_STATE_CACHE_W1_WAIT;
        ENUM_STATE_CACHE_W1_WAIT: begin
          if (i_tx_ram_ack) begin
            casez ({i_tx_ram_err, i_cfd_txb_cancel_creq[reg_cache_idx],
                    (reg_tt_trigger_pending && w_tt_pending_expired),
                    i_cfd_txb_req_req[reg_cache_idx]})
              4'b1???: begin
                if (reg_tt_trigger_pending && w_tt_pending_expired &&
                    (reg_tt_trigger_buf < 6'd32))
                  reg_ttb_miss_set[5'(reg_tt_trigger_buf)] <= 1'b1;
                reg_req_clear_pending[reg_cache_idx] <= 1'b1;
                reg_cdone_set[reg_cache_idx] <= 1'b1;
                reg_cache_valid[reg_cache_idx] <= 1'b0;
                reg_evt_ram_flt <= 1'b1;
                reg_fault_addr <= reg_element_base + 32'd1;
                if (i_cfd_txb_cie_canc_ie[reg_cache_idx])
                  reg_evt_tx_can <= 1'b1;
                if (reg_tt_trigger_pending &&
                    (reg_tt_trigger_buf == 6'(reg_cache_idx)))
                  reg_tt_trigger_pending <= 1'b0;
                reg_active_tt_trigger <= 1'b0;
                reg_active_tt_started <= 1'b0;
                reg_state <= ENUM_STATE_IDLE;
              end
              4'b01??: begin
                reg_req_clear_pending[reg_cache_idx] <= 1'b1;
                reg_cancel_clear_pending[reg_cache_idx] <= 1'b1;
                reg_cdone_set[reg_cache_idx] <= 1'b1;
                reg_cache_valid[reg_cache_idx] <= 1'b0;
                if (i_cfd_txb_cie_canc_ie[reg_cache_idx])
                  reg_evt_tx_can <= 1'b1;
                if (reg_tt_trigger_pending &&
                    (reg_tt_trigger_buf == 6'(reg_cache_idx)))
                  reg_tt_trigger_pending <= 1'b0;
                reg_state <= ENUM_STATE_IDLE;
              end
              4'b001?: begin
                if (reg_tt_trigger_buf < 6'd32)
                  reg_ttb_miss_set[5'(reg_tt_trigger_buf)] <= 1'b1;
                reg_tt_trigger_pending <= 1'b0;
                reg_state <= ENUM_STATE_IDLE;
              end
              4'b0001: begin
                reg_header1[reg_cache_idx] <= i_tx_ram_rdata;
                reg_cache_valid[reg_cache_idx] <= 1'b1;
                reg_confirmed[reg_cache_idx] <= !i_tx_ram_rdata[22] ||
                                                 (PARA_CANFD_TRTX_EN == 32'd0) ||
                                                 i_cfd_txb_trtx_conf[reg_cache_idx];
                reg_state <= ENUM_STATE_IDLE;
              end
              default: reg_state <= ENUM_STATE_IDLE;
            endcase
          end
        end

        ENUM_STATE_FETCH_REQ: reg_state <= ENUM_STATE_FETCH_WAIT;
        ENUM_STATE_FETCH_WAIT: begin
          if (i_tx_ram_ack) begin
            casez ({i_tx_ram_err, (reg_active_tt_trigger && w_tt_active_expired),
                    i_cfd_txb_cancel_creq[reg_active_idx]})
              3'b1??: begin
                if (reg_active_tt_trigger && w_tt_active_expired &&
                    !reg_active_tt_started)
                  reg_ttb_miss_set[5'(reg_active_idx)] <= 1'b1;
                reg_req_clear_pending[reg_active_idx] <= 1'b1;
                reg_cdone_set[reg_active_idx] <= 1'b1;
                reg_cache_valid[reg_active_idx] <= 1'b0;
                reg_evt_ram_flt <= 1'b1;
                reg_fault_addr <= reg_element_base + 32'd2 + {26'd0, reg_payload_word_idx};
                if (i_cfd_txb_cie_canc_ie[reg_active_idx])
                  reg_evt_tx_can <= 1'b1;
                reg_active_tt_trigger <= 1'b0;
                reg_active_tt_started <= 1'b0;
                reg_state <= ENUM_STATE_IDLE;
              end
              3'b01?: begin
                if (!reg_active_tt_started)
                  reg_ttb_miss_set[5'(reg_active_idx)] <= 1'b1;
                reg_active_tt_trigger <= 1'b0;
                reg_active_tt_started <= 1'b0;
                reg_retry_count[reg_active_idx] <= '0;
                reg_state <= ENUM_STATE_IDLE;
              end
              3'b001: begin
                reg_req_clear_pending[reg_active_idx] <= 1'b1;
                reg_cancel_clear_pending[reg_active_idx] <= 1'b1;
                reg_cdone_set[reg_active_idx] <= 1'b1;
                reg_cache_valid[reg_active_idx] <= 1'b0;
                reg_confirmed[reg_active_idx] <= 1'b0;
                if (i_cfd_txb_cie_canc_ie[reg_active_idx])
                  reg_evt_tx_can <= 1'b1;
                reg_active_tt_trigger <= 1'b0;
                reg_active_tt_started <= 1'b0;
                reg_state <= ENUM_STATE_IDLE;
              end
              3'b000: begin
                reg_tx_frame[128 + (reg_payload_word_idx * 32) +: 32] <= i_tx_ram_rdata;
                if ((reg_payload_word_idx + 6'd1) >= reg_payload_words)
                  reg_state <= ENUM_STATE_SEND;
                else begin
                  reg_payload_word_idx <= reg_payload_word_idx + 6'd1;
                  reg_state <= ENUM_STATE_FETCH_REQ;
                end
              end
              default: reg_state <= reg_state;
            endcase
          end
        end

        ENUM_STATE_SEND: begin
          if (reg_active_tt_trigger && w_tt_active_expired) begin
            if (!reg_active_tt_started)
              reg_ttb_miss_set[5'(reg_active_idx)] <= 1'b1;
            reg_active_tt_trigger <= 1'b0;
            reg_active_tt_started <= 1'b0;
            reg_retry_count[reg_active_idx] <= '0;
            reg_state <= ENUM_STATE_IDLE;
          end else if (i_cfd_txb_cancel_creq[reg_active_idx]) begin
            reg_late_cancel[reg_active_idx] <= 1'b1;
            reg_cancel_clear_pending[reg_active_idx] <= 1'b1;
          end
          if (o_tx_frame_valid_bus && i_tx_frame_ready_bus) begin
            reg_state <= ENUM_STATE_RESULT;
          end
        end

        ENUM_STATE_RESULT: begin
          if (i_cfd_txb_cancel_creq[reg_active_idx]) begin
            reg_late_cancel[reg_active_idx] <= 1'b1;
            reg_cancel_clear_pending[reg_active_idx] <= 1'b1;
          end
          if (i_tx_result_valid && reg_active_tt_trigger &&
              i_tx_result_trigger_valid &&
              (i_tx_result_trigger_buf == 6'(reg_active_idx)) &&
              i_tx_result_trigger_started)
            reg_active_tt_started <= 1'b1;
          if (i_tx_result_valid && reg_active_tt_trigger &&
              i_tx_result_trigger_valid &&
              (i_tx_result_trigger_buf == 6'(reg_active_idx)) &&
              i_tx_result_trigger_expired && !i_tx_result_trigger_started &&
              !i_tx_result_success && !i_tx_result_cancel &&
              !i_tx_result_err && !i_tx_result_arb_lost) begin
            if (!reg_active_tt_started)
              reg_ttb_miss_set[5'(reg_active_idx)] <= 1'b1;
            reg_active_tt_trigger <= 1'b0;
            reg_active_tt_started <= 1'b0;
            reg_retry_count[reg_active_idx] <= '0;
            reg_state <= ENUM_STATE_IDLE;
          end else begin
            casez ({i_tx_result_valid, i_tx_result_success, i_tx_result_cancel,
                    i_tx_result_err, i_tx_result_arb_lost})
            5'b11000: begin
              reg_active_tt_trigger <= 1'b0;
              reg_active_tt_started <= 1'b0;
              reg_req_clear_pending[reg_active_idx] <= 1'b1;
              reg_cache_valid[reg_active_idx] <= 1'b0;
              reg_confirmed[reg_active_idx] <= 1'b0;
              reg_retry_count[reg_active_idx] <= '0;
              reg_done_set[reg_active_idx] <= 1'b1;
              if (i_cfd_txb_ie_done_ie[reg_active_idx])
                reg_evt_tx_done <= 1'b1;
              if ((6'(reg_active_idx) >= i_cfd_txb_cfg_ded_num) && !i_cfd_txb_cfg_qmode &&
                  (i_cfd_txb_cfg_fifo_num != 6'd0)) begin
                if ((6'(reg_active_idx) - i_cfd_txb_cfg_ded_num + 6'd1) >= i_cfd_txb_cfg_fifo_num)
                  reg_fifo_gidx <= '0;
                else
                  reg_fifo_gidx <= 6'(reg_active_idx) - i_cfd_txb_cfg_ded_num + 6'd1;
              end
              if ((PARA_CANFD_TXEVT_EN == 32'd1) && reg_active_header1[23]) begin
                if (!w_event_space) begin
                  reg_evt_txe_lost <= 1'b1;
                  if (i_cfd_txe_cfg_num != 6'd0 && reg_txe_fill >= i_cfd_txe_cfg_num)
                    reg_evt_txe_full <= 1'b1;
                  reg_state <= ENUM_STATE_IDLE;
                end else begin
                  if (!w_event_span_valid || (w_event_end_ext > (33'd1 << PARA_CANFD_MRAM_AW))) begin
                    reg_evt_txe_lost <= 1'b1;
                    reg_evt_ram_flt <= 1'b1;
                    reg_fault_addr <= 32'(w_event_base_ext);
                    reg_state <= ENUM_STATE_IDLE;
                  end else begin
                    reg_event_base <= 32'(w_event_base_ext);
                    reg_event_word0 <= reg_active_header0;
                    reg_event_word1 <= {8'd0,
                                         ((reg_late_cancel[reg_active_idx] ||
                                           i_cfd_txb_cancel_creq[reg_active_idx]) ? 2'b10 : 2'b01),
                                         reg_active_header1[21:16],
                                         (i_cfd_txe_cfg_mm16 ? reg_active_header1[15:0] :
                                          {8'd0, reg_active_header1[7:0]})};
                    reg_event_word2 <= i_tx_result_timestamp;
                    reg_state <= ENUM_STATE_EVT_W0_REQ;
                  end
                end
              end else
                reg_state <= ENUM_STATE_IDLE;
            end
            5'b10100: begin
              reg_active_tt_trigger <= 1'b0;
              reg_active_tt_started <= 1'b0;
              reg_req_clear_pending[reg_active_idx] <= 1'b1;
              reg_cancel_clear_pending[reg_active_idx] <= 1'b1;
              reg_cache_valid[reg_active_idx] <= 1'b0;
              reg_confirmed[reg_active_idx] <= 1'b0;
              reg_cdone_set[reg_active_idx] <= 1'b1;
              if (i_cfd_txb_cie_canc_ie[reg_active_idx])
                reg_evt_tx_can <= 1'b1;
              reg_state <= ENUM_STATE_IDLE;
            end
            // DEC-091: late cancellation reports cancellation and suppresses retry.
            5'b10010: begin
              casez ({w_tx_late_cancel, w_tt_no_retry, w_tx_retry_limit_hit})
                3'b1??: begin
                  reg_active_tt_trigger <= 1'b0;
                  reg_active_tt_started <= 1'b0;
                  reg_req_clear_pending[reg_active_idx] <= 1'b1;
                  reg_cancel_clear_pending[reg_active_idx] <= 1'b1;
                  reg_cache_valid[reg_active_idx] <= 1'b0;
                  reg_confirmed[reg_active_idx] <= 1'b0;
                  reg_retry_count[reg_active_idx] <= '0;
                  reg_cdone_set[reg_active_idx] <= 1'b1;
                  if (i_cfd_txb_cie_canc_ie[reg_active_idx])
                    reg_evt_tx_can <= 1'b1;
                  reg_state <= ENUM_STATE_IDLE;
                end
                3'b01?: begin
                  reg_active_tt_trigger <= 1'b0;
                  reg_active_tt_started <= 1'b0;
                  reg_retry_count[reg_active_idx] <= '0;
                  reg_state <= ENUM_STATE_IDLE;
                end
                3'b001: begin
                  reg_active_tt_trigger <= 1'b0;
                  reg_active_tt_started <= 1'b0;
                  reg_req_clear_pending[reg_active_idx] <= 1'b1;
                  reg_cache_valid[reg_active_idx] <= 1'b0;
                  reg_confirmed[reg_active_idx] <= 1'b0;
                  reg_retry_count[reg_active_idx] <= '0;
                  reg_cdone_set[reg_active_idx] <= 1'b1;
                  reg_fail_set[reg_active_idx] <= 1'b1;
                  if (i_cfd_txb_cie_canc_ie[reg_active_idx])
                    reg_evt_tx_can <= 1'b1;
                  reg_state <= ENUM_STATE_IDLE;
                end
                3'b000: begin
                  reg_retry_count[reg_active_idx] <= reg_retry_count[reg_active_idx] + 8'd1;
                  reg_state <= ENUM_STATE_IDLE;
                end
                default: reg_state <= reg_state;
              endcase
            end
            // Arbitration loss is not a protocol error. Replay only after TXH decides.
            5'b10001: begin
              if (reg_late_cancel[reg_active_idx] ||
                  i_cfd_txb_cancel_creq[reg_active_idx] || i_cfd_ctrl_dar) begin
                reg_active_tt_trigger <= 1'b0;
                reg_active_tt_started <= 1'b0;
                reg_req_clear_pending[reg_active_idx] <= 1'b1;
                reg_cancel_clear_pending[reg_active_idx] <= 1'b1;
                reg_cache_valid[reg_active_idx] <= 1'b0;
                reg_confirmed[reg_active_idx] <= 1'b0;
                reg_retry_count[reg_active_idx] <= '0;
                reg_cdone_set[reg_active_idx] <= 1'b1;
                if (i_cfd_txb_cie_canc_ie[reg_active_idx])
                  reg_evt_tx_can <= 1'b1;
                reg_state <= ENUM_STATE_IDLE;
              end else if (w_tt_no_retry) begin
                reg_active_tt_trigger <= 1'b0;
                reg_active_tt_started <= 1'b0;
                reg_retry_count[reg_active_idx] <= '0;
                reg_state <= ENUM_STATE_IDLE;
              end else begin
                // Preserve the selected frame and retry count; BSP accepts it after bus idle.
                reg_state <= ENUM_STATE_SEND;
              end
            end
            default: begin
              reg_state <= reg_state;
            end
          endcase
        end
        end

        ENUM_STATE_EVT_W0_REQ: reg_state <= ENUM_STATE_EVT_W0_WAIT;
        ENUM_STATE_EVT_W0_WAIT: begin
          if (i_tx_ram_ack) begin
            if (i_tx_ram_err) begin
              reg_evt_txe_lost <= 1'b1;
              reg_evt_ram_flt <= 1'b1;
              reg_fault_addr <= reg_event_base;
              reg_state <= ENUM_STATE_IDLE;
            end else
              reg_state <= ENUM_STATE_EVT_W1_REQ;
          end
        end
        ENUM_STATE_EVT_W1_REQ: reg_state <= ENUM_STATE_EVT_W1_WAIT;
        ENUM_STATE_EVT_W1_WAIT: begin
          if (i_tx_ram_ack) begin
            if (i_tx_ram_err) begin
              reg_evt_txe_lost <= 1'b1;
              reg_evt_ram_flt <= 1'b1;
              reg_fault_addr <= reg_event_base + 32'd1;
              reg_state <= ENUM_STATE_IDLE;
            end else
              reg_state <= ENUM_STATE_EVT_W2_REQ;
          end
        end
        ENUM_STATE_EVT_W2_REQ: reg_state <= ENUM_STATE_EVT_W2_WAIT;
        ENUM_STATE_EVT_W2_WAIT: begin
          if (i_tx_ram_ack) begin
            if (i_tx_ram_err) begin
              reg_evt_txe_lost <= 1'b1;
              reg_evt_ram_flt <= 1'b1;
              reg_fault_addr <= reg_event_base + 32'd2;
            end else begin
              reg_evt_txe_new <= 1'b1;
              if (reg_txe_pidx == (i_cfd_txe_cfg_num - 6'd1))
                reg_txe_pidx <= '0;
              else
                reg_txe_pidx <= reg_txe_pidx + 6'd1;
              if (((reg_txe_fill + 6'd1) >= i_cfd_txe_cfg_wm) &&
                  (i_cfd_txe_cfg_wm != 6'd0) && (reg_txe_fill < i_cfd_txe_cfg_wm))
                reg_evt_txe_watermark <= 1'b1;
              if ((reg_txe_fill + 6'd1) >= i_cfd_txe_cfg_num)
                reg_evt_txe_full <= 1'b1;
            end
            reg_state <= ENUM_STATE_IDLE;
          end
        end
        default: begin
          reg_state <= ENUM_STATE_IDLE;
          reg_cache_valid <= '0;
        end
      endcase
    end
  end

endmodule
