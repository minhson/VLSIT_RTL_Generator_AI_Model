/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-09
 * Description  : Filters completed Rx frames, writes selected frames to external Message RAM,
 *                and updates the software-visible Rx FIFO and dedicated-buffer state.
 * HDS           : REQ-MSG-001..005, REQ-MSG-010..014, REQ-MSG-021; DEC-063, DEC-073, DEC-086
 */
`timescale 1ns/1ps

module m_canfd_rxh #(
  // Parameter Description: maximum payload size represented by the CDC frame bundle.
  // Parameter values: 8, 12, 16, 20, 24, 32, 48, or 64; default is 64.
  // Parameter unit: byte
  parameter logic [31:0] PARA_CANFD_DATA_MAX = 32'd64,
  // Parameter Description: number of Rx FIFO instances present in this build.
  // Parameter values: 1 or 2; default is 2.
  // Parameter unit: FIFO
  parameter logic [31:0] PARA_CANFD_RXFIFO_NUM = 32'd2,
  // Parameter Description: maximum number of elements implemented in each Rx FIFO.
  // Parameter values: 2 through 64; default is 64.
  // Parameter unit: element
  parameter logic [31:0] PARA_CANFD_RXF_MAX = 32'd64,
  // Parameter Description: maximum number of dedicated Rx buffers implemented.
  // Parameter values: 0 through 64; default is 64.
  // Parameter unit: buffer
  parameter logic [31:0] PARA_CANFD_RXBUF_MAX = 32'd64,
  // Parameter Description: external Message-RAM word-address width.
  // Parameter values: 8 through 14; default is 14.
  // Parameter unit: bit
  parameter logic [31:0] PARA_CANFD_MRAM_AW = 32'd14,
  // Parameter Description: enable storage of received remote frames.
  // Parameter values: 0 = disabled, 1 = enabled; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_RTR_EN = 32'd1,
  // Parameter Description: enable receive timestamp storage.
  // Parameter values: 0 = disabled, 1 = enabled; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_TS_EN = 32'd1,
  // Parameter Description: width of the receive timestamp in the frame bundle.
  // Parameter values: 16 or 32; default is 32.
  // Parameter unit: bit
  parameter logic [31:0] PARA_CANFD_TS_W = 32'd32,
  localparam logic [31:0] LPARA_DATA_WORDS = PARA_CANFD_DATA_MAX / 32'd4,
  localparam logic [31:0] LPARA_DATA_IDX_W = $clog2(LPARA_DATA_WORDS),
  localparam logic [31:0] LPARA_RXBUF_ARRAY_NUM = (PARA_CANFD_RXBUF_MAX == 32'd0) ? 32'd1 : PARA_CANFD_RXBUF_MAX,
  localparam logic [31:0] LPARA_STATE_IDLE = 32'd0,
  localparam logic [31:0] LPARA_STATE_FILTER_ISSUE0 = 32'd1,
  localparam logic [31:0] LPARA_STATE_FILTER_WAIT0 = 32'd2,
  localparam logic [31:0] LPARA_STATE_FILTER_ISSUE1 = 32'd3,
  localparam logic [31:0] LPARA_STATE_FILTER_WAIT1 = 32'd4,
  localparam logic [31:0] LPARA_STATE_FILTER_EVAL = 32'd5,
  localparam logic [31:0] LPARA_STATE_SEL = 32'd6,
  localparam logic [31:0] LPARA_STATE_STORE_CHECK = 32'd7,
  localparam logic [31:0] LPARA_STATE_STORE_DATA_ISSUE = 32'd8,
  localparam logic [31:0] LPARA_STATE_STORE_DATA_WAIT = 32'd9,
  localparam logic [31:0] LPARA_STATE_STORE_TS_ISSUE = 32'd10,
  localparam logic [31:0] LPARA_STATE_STORE_TS_WAIT = 32'd11,
  localparam logic [31:0] LPARA_STATE_STORE_W1_ISSUE = 32'd12,
  localparam logic [31:0] LPARA_STATE_STORE_W1_WAIT = 32'd13,
  localparam logic [31:0] LPARA_STATE_STORE_W0_ISSUE = 32'd14,
  localparam logic [31:0] LPARA_STATE_STORE_W0_WAIT = 32'd15,
  localparam logic [31:0] LPARA_STATE_POP = 32'd16,
  localparam logic [31:0] LPARA_TARGET_REJECT = 32'd0,
  localparam logic [31:0] LPARA_TARGET_FIFO0 = 32'd1,
  localparam logic [31:0] LPARA_TARGET_FIFO1 = 32'd2,
  localparam logic [31:0] LPARA_TARGET_BUF = 32'd3
) (
  // Clock, reset, readiness and coordinated soft reset
  input  wire                            i_clk_bus,
  input  wire                            i_rst_n_bus,
  input  wire                            i_cdc_ready_bus,
  input  wire                            i_srst_req_bus,

  // Completed frame fields at the head of the asynchronous Rx frame FIFO
  input  wire                            i_rx_frame_valid_bus,
  input  wire  [31:0]                    i_rx_frame_word0,
  input  wire  [5:0]                     i_rx_frame_flags_dlc,
  input  wire  [31:0]                    i_rx_frame_timestamp,
  input  wire  [LPARA_DATA_WORDS*32-1:0] i_rx_frame_payload,
  output logic                           o_rx_frame_pop,

  // Acceptance-filter controls
  input  wire  [1:0]                     i_cfd_gfc_anfs,
  input  wire  [1:0]                     i_cfd_gfc_anfe,
  input  wire                            i_cfd_gfc_rrfs,
  input  wire                            i_cfd_gfc_rrfe,
  input  wire  [28:0]                    i_cfd_xidam_xidam,
  input  wire  [15:0]                    i_cfd_sf_cfg_sf_start,
  input  wire  [7:0]                     i_cfd_sf_cfg_sf_num,
  input  wire  [15:0]                    i_cfd_ef_cfg_ef_start,
  input  wire  [6:0]                     i_cfd_ef_cfg_ef_num,

  // Rx FIFO and dedicated-buffer section controls
  input  wire  [15:0]                    i_cfd_rxf0_cfg_start,
  input  wire  [6:0]                     i_cfd_rxf0_cfg_num,
  input  wire  [6:0]                     i_cfd_rxf0_cfg_wm,
  input  wire                            i_cfd_rxf0_cfg_ovw,
  input  wire  [15:0]                    i_cfd_rxf1_cfg_start,
  input  wire  [6:0]                     i_cfd_rxf1_cfg_num,
  input  wire  [6:0]                     i_cfd_rxf1_cfg_wm,
  input  wire                            i_cfd_rxf1_cfg_ovw,
  input  wire  [15:0]                    i_cfd_rxb_cfg_start,
  input  wire  [6:0]                     i_cfd_rxb_cfg_num,
  input  wire  [2:0]                     i_cfd_esz_rxf0_dsz,
  input  wire  [2:0]                     i_cfd_esz_rxf1_dsz,
  input  wire  [2:0]                     i_cfd_esz_rxb_dsz,

  // Software acknowledge commands for the two message-RAM Rx FIFOs
  input  wire  [5:0]                     i_cfd_rxf0_ack_ack_idx,
  input  wire                            i_cfd_rxf0_ack_ack_go,
  input  wire  [5:0]                     i_cfd_rxf1_ack_ack_idx,
  input  wire                            i_cfd_rxf1_ack_ack_go,
  output logic                           o_cfd_rxf0_ack_clear,
  output logic                           o_cfd_rxf1_ack_clear,

  // Message-RAM FIFO status fields
  output logic [5:0]                     o_cfd_rxf0_sts_gidx,
  output logic [5:0]                     o_cfd_rxf0_sts_pidx,
  output logic [6:0]                     o_cfd_rxf0_sts_fill,
  output logic                           o_cfd_rxf0_sts_full,
  output logic                           o_cfd_rxf0_sts_lost,
  output logic [5:0]                     o_cfd_rxf1_sts_gidx,
  output logic [5:0]                     o_cfd_rxf1_sts_pidx,
  output logic [6:0]                     o_cfd_rxf1_sts_fill,
  output logic                           o_cfd_rxf1_sts_full,
  output logic                           o_cfd_rxf1_sts_lost,
  input  wire                            i_cfd_irq_raw_rx0_lst,
  input  wire                            i_cfd_irq_raw_rx1_lst,

  // Message-arrival events used to set sticky CSR interrupt fields
  output logic                           o_cfd_irq_rx0_new,
  output logic                           o_cfd_irq_rx0_wm,
  output logic                           o_cfd_irq_rx0_ful,
  output logic                           o_cfd_irq_rx0_lst,
  output logic                           o_cfd_irq_rx1_new,
  output logic                           o_cfd_irq_rx1_wm,
  output logic                           o_cfd_irq_rx1_ful,
  output logic                           o_cfd_irq_rx1_lst,
  output logic [31:0]                    o_cfd_rxb_nd0_set,
  output logic [31:0]                    o_cfd_rxb_nd1_set,
  output logic                           o_cfd_hpm_sts_hp_vld_set,
  output logic                           o_cfd_hpm_sts_hp_fifo,
  output logic [5:0]                     o_cfd_hpm_sts_hp_idx,
  output logic [6:0]                     o_cfd_hpm_sts_hp_fidx,
  output logic                           o_cfd_irq_hpm,

  // Handler diagnostics and locally detected element-span fault
  output logic                           o_cfd_rx_ram_flt_event,
  output logic [31:0]                    o_cfd_rx_fault_addr,
  output logic                           o_cfd_rx_sts_flt_busy,
  output logic [15:0]                    o_cfd_rx_sts_flt_peak,

  // Single-word client connection to m_canfd_mram
  output logic                           o_rx_ram_req,
  output logic                           o_rx_ram_we,
  output logic [31:0]                    o_rx_ram_addr,
  output logic [31:0]                    o_rx_ram_wdata,
  input  wire                            i_rx_ram_ack,
  input  wire  [31:0]                    i_rx_ram_rdata,
  input  wire                            i_rx_ram_err);

  typedef enum logic [4:0] {
    ENUM_STATE_IDLE = LPARA_STATE_IDLE[4:0],
    ENUM_STATE_FILTER_ISSUE0 = LPARA_STATE_FILTER_ISSUE0[4:0],
    ENUM_STATE_FILTER_WAIT0 = LPARA_STATE_FILTER_WAIT0[4:0],
    ENUM_STATE_FILTER_ISSUE1 = LPARA_STATE_FILTER_ISSUE1[4:0],
    ENUM_STATE_FILTER_WAIT1 = LPARA_STATE_FILTER_WAIT1[4:0],
    ENUM_STATE_FILTER_EVAL = LPARA_STATE_FILTER_EVAL[4:0],
    ENUM_STATE_SEL = LPARA_STATE_SEL[4:0],
    ENUM_STATE_STORE_CHECK = LPARA_STATE_STORE_CHECK[4:0],
    ENUM_STATE_STORE_DATA_ISSUE = LPARA_STATE_STORE_DATA_ISSUE[4:0],
    ENUM_STATE_STORE_DATA_WAIT = LPARA_STATE_STORE_DATA_WAIT[4:0],
    ENUM_STATE_STORE_TS_ISSUE = LPARA_STATE_STORE_TS_ISSUE[4:0],
    ENUM_STATE_STORE_TS_WAIT = LPARA_STATE_STORE_TS_WAIT[4:0],
    ENUM_STATE_STORE_W1_ISSUE = LPARA_STATE_STORE_W1_ISSUE[4:0],
    ENUM_STATE_STORE_W1_WAIT = LPARA_STATE_STORE_W1_WAIT[4:0],
    ENUM_STATE_STORE_W0_ISSUE = LPARA_STATE_STORE_W0_ISSUE[4:0],
    ENUM_STATE_STORE_W0_WAIT = LPARA_STATE_STORE_W0_WAIT[4:0],
    ENUM_STATE_POP = LPARA_STATE_POP[4:0]
  } rxh_state_type_def;

  typedef enum logic [1:0] {
    ENUM_TARGET_REJECT = LPARA_TARGET_REJECT[1:0],
    ENUM_TARGET_FIFO0 = LPARA_TARGET_FIFO0[1:0],
    ENUM_TARGET_FIFO1 = LPARA_TARGET_FIFO1[1:0],
    ENUM_TARGET_BUF = LPARA_TARGET_BUF[1:0]
  } rxh_target_type_def;

  logic [31:0] reg_frame_word0;
  logic [5:0] reg_frame_flags;
  logic [31:0] reg_frame_timestamp;
  logic [LPARA_DATA_WORDS*32-1:0] reg_frame_payload;
  logic [31:0] w_frame_payload [0:LPARA_DATA_WORDS-1];
  logic [31:0] w_frame_word0;
  logic [5:0] w_frame_flags;
  logic [31:0] w_frame_timestamp;
  logic [28:0] w_frame_id;
  logic [28:0] w_filter_id;
  logic [6:0] w_frame_payload_bytes;
  logic [5:0] w_frame_payload_words;
  logic [6:0] w_store_bytes;
  logic [5:0] w_store_words;
  logic [31:0] w_store_end_ext;
  logic [32:0] w_store_span_end;
  logic [31:0] w_store_word1;
  logic [31:0] w_store_data;
  logic [28:0] w_filter_id1;
  logic [28:0] w_filter_id2;
  logic [1:0] w_filter_type;
  logic w_filter_en;
  logic w_filter_match;
  logic w_filter_elem_xtd;
  logic [6:0] w_ack0_count;
  logic [6:0] w_ack1_count;

  rxh_state_type_def reg_state;
  rxh_target_type_def reg_store_target;
  logic [7:0] reg_filter_count;
  logic [6:0] reg_filter_idx;
  logic [15:0] reg_filter_start;
  logic reg_filter_xtd;
  logic [31:0] reg_filter_word0;
  logic [28:0] reg_elem_id1;
  logic [28:0] reg_elem_id2;
  logic [1:0] reg_elem_type;
  logic [2:0] reg_elem_action;
  logic reg_elem_en;
  logic reg_anmf;
  logic reg_high_prio;
  logic reg_store_was_full;
  logic [5:0] reg_store_idx;
  logic [6:0] reg_store_num;
  logic [6:0] reg_store_wm;
  logic [2:0] reg_store_dsz;
  logic [5:0] reg_store_data_words;
  logic [6:0] reg_store_filter_idx;
  logic [1:0] reg_store_generation;
  logic [31:0] reg_store_base;
  logic [5:0] reg_data_word_idx;
  logic [15:0] reg_elapsed;
  logic [5:0] reg_rxf0_gidx;
  logic [5:0] reg_rxf0_pidx;
  logic [6:0] reg_rxf0_fill;
  logic [5:0] reg_rxf1_gidx;
  logic [5:0] reg_rxf1_pidx;
  logic [6:0] reg_rxf1_fill;
  logic reg_ram_req;
  logic reg_ram_we;
  logic [31:0] reg_ram_addr;
  logic [31:0] reg_ram_wdata;
  logic [15:0] reg_flt_peak;
  logic [5:0] reg_elem_buf_idx;
  logic [1:0] reg_gen_rxf0 [0:PARA_CANFD_RXF_MAX-1];
  logic [1:0] reg_gen_rxf1 [0:PARA_CANFD_RXF_MAX-1];
  logic [1:0] reg_gen_rxb [0:LPARA_RXBUF_ARRAY_NUM-1];
  logic reg_rx_frame_pop;
  logic reg_irq_rx0_new;
  logic reg_irq_rx0_wm;
  logic reg_irq_rx0_ful;
  logic reg_irq_rx0_lst;
  logic reg_irq_rx1_new;
  logic reg_irq_rx1_wm;
  logic reg_irq_rx1_ful;
  logic reg_irq_rx1_lst;
  logic [31:0] reg_rxb_nd0_set;
  logic [31:0] reg_rxb_nd1_set;
  logic reg_hpm_vld_set;
  logic reg_hpm_fifo;
  logic [5:0] reg_hpm_idx;
  logic [6:0] reg_hpm_fidx;
  logic reg_irq_hpm;
  logic reg_rx_ram_flt_event;
  logic [31:0] reg_rx_fault_addr;

  // Payload words are named individually at elaboration to keep the variable-index mux in range.
  generate
    for (genvar g_payload_word = 0; g_payload_word < LPARA_DATA_WORDS; g_payload_word = g_payload_word + 32'd1) begin : gen_payload_words
      // Extract one payload word from the packed four-word-metadata frame record.
      assign w_frame_payload[g_payload_word] = reg_frame_payload[g_payload_word*32 +: 32];
    end
  endgenerate

  // Decode the frame, element sizes, filter operands and word being written.
  function automatic logic [6:0] f_dsz_bytes(input logic [2:0] i_dsz);
    begin
      casez (i_dsz)
        3'd0: f_dsz_bytes = 7'd8;
        3'd1: f_dsz_bytes = 7'd12;
        3'd2: f_dsz_bytes = 7'd16;
        3'd3: f_dsz_bytes = 7'd20;
        3'd4: f_dsz_bytes = 7'd24;
        3'd5: f_dsz_bytes = 7'd32;
        3'd6: f_dsz_bytes = 7'd48;
        3'd7: f_dsz_bytes = 7'd64;
        default: f_dsz_bytes = 7'bx;
      endcase
    end
  endfunction

  function automatic logic [6:0] f_dlc_bytes(input logic [3:0] i_dlc);
    begin
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
        4'd15: f_dlc_bytes = 7'd64;
        default: f_dlc_bytes = 7'bx;
      endcase
    end
  endfunction

  function automatic logic [5:0] f_index_inc(input logic [5:0] i_index, input logic [6:0] i_num);
    begin
      if ((i_num == 7'd0) || ({1'b0, i_index} + 7'd1 >= i_num))
        f_index_inc = 6'd0;
      else
        f_index_inc = i_index + 6'd1;
    end
  endfunction

  function automatic logic [6:0] f_ack_count(input logic [5:0] i_gidx, input logic [5:0] i_ack_idx, input logic [6:0] i_num);
    begin
      if (i_ack_idx >= i_gidx)
        f_ack_count = {1'b0, i_ack_idx} - {1'b0, i_gidx} + 7'd1;
      else
        f_ack_count = i_num - {1'b0, i_gidx} + {1'b0, i_ack_idx} + 7'd1;
    end
  endfunction

  // Decode frame fields and prepare the filter operands and current RAM write word.
  always_comb begin : p_com_rxh_decode
    w_frame_word0 = reg_frame_word0;
    w_frame_timestamp = reg_frame_timestamp;
    w_frame_flags = reg_frame_flags;
    w_frame_id = w_frame_word0[28:0];
    w_filter_id = w_frame_word0[30] ? (w_frame_id & i_cfd_xidam_xidam) : w_frame_id;
    w_frame_payload_bytes = f_dlc_bytes(w_frame_flags[3:0]);
    if (!w_frame_flags[5] && (w_frame_payload_bytes > 7'd8))
      w_frame_payload_bytes = 7'd8;
    if (w_frame_payload_bytes > 7'(PARA_CANFD_DATA_MAX))
      w_frame_payload_bytes = 7'(PARA_CANFD_DATA_MAX);
    if (w_frame_word0[29])
      w_frame_payload_bytes = 7'd0;
    w_frame_payload_words = 6'((w_frame_payload_bytes + 7'd3) >> 2);
    w_store_bytes = f_dsz_bytes(reg_store_dsz);
    w_store_words = 6'(32'd3 + (32'(w_store_bytes) >> 2));
    w_store_span_end = {1'b0, reg_store_base} + {27'd0, w_store_words} - 33'd1;
    w_store_end_ext = w_store_span_end[31:0];

    w_filter_id1 = reg_elem_id1;
    w_filter_id2 = reg_elem_id2;
    w_filter_type = reg_elem_type;
    w_filter_en = reg_elem_en;
    w_filter_elem_xtd = reg_filter_xtd;
    w_ack0_count = f_ack_count(reg_rxf0_gidx, i_cfd_rxf0_ack_ack_idx, i_cfd_rxf0_cfg_num);
    w_ack1_count = f_ack_count(reg_rxf1_gidx, i_cfd_rxf1_ack_ack_idx, i_cfd_rxf1_cfg_num);

    w_store_word1 = 32'd0;
    w_store_word1[31] = reg_anmf;
    w_store_word1[30:24] = reg_store_filter_idx;
    w_store_word1[23:22] = reg_store_generation;
    w_store_word1[21:16] = w_frame_flags;

    w_store_data = 32'd0;
    if ((32'(reg_data_word_idx) < LPARA_DATA_WORDS) && (reg_data_word_idx < w_frame_payload_words))
      w_store_data = w_frame_payload[reg_data_word_idx[LPARA_DATA_IDX_W-1:0]];
  end

  // Apply the selected standard or extended element comparison.
  m_canfd_flt u_canfd_flt (
    .i_id       (w_filter_id),
    .i_xtd      (reg_filter_xtd),
    .i_elem_en  (w_filter_en),
    .i_elem_type(w_filter_type),
    .i_elem_id1 (w_filter_id1),
    .i_elem_id2 (w_filter_id2),
    .i_elem_xtd (w_filter_elem_xtd),
    .o_match    (w_filter_match)
  );

  // Expose live FIFO indexes and the sticky lost state owned by the CSR raw interrupt bits.
  assign o_rx_frame_pop = reg_rx_frame_pop;
  assign o_cfd_rxf0_ack_clear = (reg_state == ENUM_STATE_IDLE) &&
                                !i_srst_req_bus && i_cfd_rxf0_ack_ack_go;
  assign o_cfd_rxf1_ack_clear = (reg_state == ENUM_STATE_IDLE) &&
                                !i_srst_req_bus && !i_cfd_rxf0_ack_ack_go &&
                                (PARA_CANFD_RXFIFO_NUM > 32'd1) && i_cfd_rxf1_ack_ack_go;
  assign o_cfd_irq_rx0_new = reg_irq_rx0_new;
  assign o_cfd_irq_rx0_wm = reg_irq_rx0_wm;
  assign o_cfd_irq_rx0_ful = reg_irq_rx0_ful;
  assign o_cfd_irq_rx0_lst = reg_irq_rx0_lst;
  assign o_cfd_irq_rx1_new = reg_irq_rx1_new;
  assign o_cfd_irq_rx1_wm = reg_irq_rx1_wm;
  assign o_cfd_irq_rx1_ful = reg_irq_rx1_ful;
  assign o_cfd_irq_rx1_lst = reg_irq_rx1_lst;
  assign o_cfd_rxb_nd0_set = reg_rxb_nd0_set;
  assign o_cfd_rxb_nd1_set = reg_rxb_nd1_set;
  assign o_cfd_hpm_sts_hp_vld_set = reg_hpm_vld_set;
  assign o_cfd_hpm_sts_hp_fifo = reg_hpm_fifo;
  assign o_cfd_hpm_sts_hp_idx = reg_hpm_idx;
  assign o_cfd_hpm_sts_hp_fidx = reg_hpm_fidx;
  assign o_cfd_irq_hpm = reg_irq_hpm;
  assign o_cfd_rx_ram_flt_event = reg_rx_ram_flt_event;
  assign o_cfd_rx_fault_addr = reg_rx_fault_addr;
  assign o_cfd_rxf0_sts_gidx = reg_rxf0_gidx;
  assign o_cfd_rxf0_sts_pidx = reg_rxf0_pidx;
  assign o_cfd_rxf0_sts_fill = reg_rxf0_fill;
  assign o_cfd_rxf0_sts_full = (i_cfd_rxf0_cfg_num != 7'd0) && (reg_rxf0_fill >= i_cfd_rxf0_cfg_num);
  assign o_cfd_rxf0_sts_lost = i_cfd_irq_raw_rx0_lst;
  assign o_cfd_rxf1_sts_gidx = (PARA_CANFD_RXFIFO_NUM > 32'd1) ? reg_rxf1_gidx : 6'd0;
  assign o_cfd_rxf1_sts_pidx = (PARA_CANFD_RXFIFO_NUM > 32'd1) ? reg_rxf1_pidx : 6'd0;
  assign o_cfd_rxf1_sts_fill = (PARA_CANFD_RXFIFO_NUM > 32'd1) ? reg_rxf1_fill : 7'd0;
  assign o_cfd_rxf1_sts_full = (PARA_CANFD_RXFIFO_NUM > 32'd1) &&
                               (i_cfd_rxf1_cfg_num != 7'd0) &&
                               (reg_rxf1_fill >= i_cfd_rxf1_cfg_num);
  assign o_cfd_rxf1_sts_lost = (PARA_CANFD_RXFIFO_NUM > 32'd1) && i_cfd_irq_raw_rx1_lst;
  assign o_cfd_rx_sts_flt_busy = (reg_state != ENUM_STATE_IDLE) && (reg_state != ENUM_STATE_POP);

  // Hold the Rx client request fields stable until the Message-RAM arbiter acknowledges them.
  assign o_rx_ram_req = reg_ram_req;
  assign o_rx_ram_we = reg_ram_we;
  assign o_rx_ram_addr = reg_ram_addr;
  assign o_rx_ram_wdata = reg_ram_wdata;

  // Report the maximum observed BUS-clock service interval since reset.
  assign o_cfd_rx_sts_flt_peak = reg_flt_peak;

  // Sequence filtering, storage and software-visible status updates in the BUS domain.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_rxh_ctrl
    if (!i_rst_n_bus) begin
      reg_state <= ENUM_STATE_IDLE;
      reg_store_target <= ENUM_TARGET_REJECT;
      reg_frame_word0 <= '0;
      reg_frame_flags <= '0;
      reg_frame_timestamp <= '0;
      reg_frame_payload <= '0;
      reg_filter_count <= '0;
      reg_filter_idx <= '0;
      reg_filter_start <= '0;
      reg_filter_xtd <= 1'b0;
      reg_filter_word0 <= '0;
      reg_elem_id1 <= '0;
      reg_elem_id2 <= '0;
      reg_elem_type <= '0;
      reg_elem_action <= '0;
      reg_elem_buf_idx <= '0;
      reg_elem_en <= 1'b0;
      reg_anmf <= 1'b0;
      reg_high_prio <= 1'b0;
      reg_store_was_full <= 1'b0;
      reg_store_idx <= '0;
      reg_store_num <= '0;
      reg_store_wm <= '0;
      reg_store_dsz <= '0;
      reg_store_data_words <= '0;
      reg_store_filter_idx <= '0;
      reg_store_generation <= '0;
      reg_store_base <= '0;
      reg_data_word_idx <= '0;
      reg_elapsed <= '0;
      reg_rxf0_gidx <= '0;
      reg_rxf0_pidx <= '0;
      reg_rxf0_fill <= '0;
      reg_rxf1_gidx <= '0;
      reg_rxf1_pidx <= '0;
      reg_rxf1_fill <= '0;
      reg_flt_peak <= '0;
      reg_ram_req <= 1'b0;
      reg_ram_we <= 1'b0;
      reg_ram_addr <= '0;
      reg_ram_wdata <= '0;
      reg_rx_frame_pop <= 1'b0;
      reg_irq_rx0_new <= 1'b0;
      reg_irq_rx0_wm <= 1'b0;
      reg_irq_rx0_ful <= 1'b0;
      reg_irq_rx0_lst <= 1'b0;
      reg_irq_rx1_new <= 1'b0;
      reg_irq_rx1_wm <= 1'b0;
      reg_irq_rx1_ful <= 1'b0;
      reg_irq_rx1_lst <= 1'b0;
      reg_rxb_nd0_set <= '0;
      reg_rxb_nd1_set <= '0;
      reg_hpm_vld_set <= 1'b0;
      reg_hpm_fifo <= 1'b0;
      reg_hpm_idx <= '0;
      reg_hpm_fidx <= '0;
      reg_irq_hpm <= 1'b0;
      reg_rx_ram_flt_event <= 1'b0;
      reg_rx_fault_addr <= '0;
      for (int unsigned w_gen_idx = 0; w_gen_idx < PARA_CANFD_RXF_MAX; w_gen_idx++) begin
        reg_gen_rxf0[w_gen_idx] <= '0;
        reg_gen_rxf1[w_gen_idx] <= '0;
      end
      for (int unsigned w_buf_idx = 0; w_buf_idx < LPARA_RXBUF_ARRAY_NUM; w_buf_idx++)
        reg_gen_rxb[w_buf_idx] <= '0;
    end else begin
      reg_rx_frame_pop <= 1'b0;
      reg_irq_rx0_new <= 1'b0;
      reg_irq_rx0_wm <= 1'b0;
      reg_irq_rx0_ful <= 1'b0;
      reg_irq_rx0_lst <= 1'b0;
      reg_irq_rx1_new <= 1'b0;
      reg_irq_rx1_wm <= 1'b0;
      reg_irq_rx1_ful <= 1'b0;
      reg_irq_rx1_lst <= 1'b0;
      reg_rxb_nd0_set <= '0;
      reg_rxb_nd1_set <= '0;
      reg_hpm_vld_set <= 1'b0;
      reg_irq_hpm <= 1'b0;
      reg_rx_ram_flt_event <= 1'b0;

      if (reg_state != ENUM_STATE_IDLE && reg_state != ENUM_STATE_POP && reg_elapsed != 16'hFFFF)
        reg_elapsed <= reg_elapsed + 16'd1;

      casez (reg_state)
        ENUM_STATE_IDLE: begin
          reg_ram_req <= 1'b0;
          reg_ram_we <= 1'b0;
          casez ({i_srst_req_bus, i_cfd_rxf0_ack_ack_go,
                  i_cfd_rxf1_ack_ack_go && (PARA_CANFD_RXFIFO_NUM > 32'd1),
                  i_rx_frame_valid_bus && i_cdc_ready_bus})
            4'b1???: begin
              if (i_rx_frame_valid_bus && i_cdc_ready_bus) begin
                // Drain completed frames while a coordinated message-handler reset is pending.
                reg_rx_frame_pop <= 1'b1;
              end else begin
                reg_rxf0_gidx <= '0;
                reg_rxf0_pidx <= '0;
                reg_rxf0_fill <= '0;
                reg_rxf1_gidx <= '0;
                reg_rxf1_pidx <= '0;
                reg_rxf1_fill <= '0;
                reg_flt_peak <= '0;
                reg_elapsed <= '0;
              end
            end
            4'b01??: begin
              if (({1'b0, i_cfd_rxf0_ack_ack_idx} < i_cfd_rxf0_cfg_num) &&
                  !(w_ack0_count > reg_rxf0_fill)) begin
                reg_rxf0_gidx <= f_index_inc(i_cfd_rxf0_ack_ack_idx, i_cfd_rxf0_cfg_num);
                reg_rxf0_fill <= reg_rxf0_fill - w_ack0_count;
              end
            end
            4'b001?: begin
              if (({1'b0, i_cfd_rxf1_ack_ack_idx} < i_cfd_rxf1_cfg_num) &&
                  !(w_ack1_count > reg_rxf1_fill)) begin
                reg_rxf1_gidx <= f_index_inc(i_cfd_rxf1_ack_ack_idx, i_cfd_rxf1_cfg_num);
                reg_rxf1_fill <= reg_rxf1_fill - w_ack1_count;
              end
            end
            4'b0001: begin
              reg_frame_word0 <= i_rx_frame_word0;
              reg_frame_flags <= i_rx_frame_flags_dlc;
              reg_frame_timestamp <= i_rx_frame_timestamp;
              reg_frame_payload <= i_rx_frame_payload;
              reg_elapsed <= '0;
              if (i_rx_frame_word0[29] &&
                  ((PARA_CANFD_RTR_EN == 32'd0) ||
                   (i_rx_frame_word0[30] ? i_cfd_gfc_rrfe : i_cfd_gfc_rrfs))) begin
                reg_state <= ENUM_STATE_POP;
              end else begin
                reg_filter_idx <= '0;
                if (i_rx_frame_word0[30]) begin
                  reg_filter_xtd <= 1'b1;
                  reg_filter_count <= {1'b0, i_cfd_ef_cfg_ef_num};
                  reg_filter_start <= i_cfd_ef_cfg_ef_start;
                  if (i_cfd_ef_cfg_ef_num == 7'd0) begin
                    reg_anmf <= 1'b1;
                    reg_store_filter_idx <= '0;
                    reg_elem_action <= {1'b0, i_cfd_gfc_anfe};
                    reg_state <= ENUM_STATE_SEL;
                  end else begin
                    reg_state <= ENUM_STATE_FILTER_ISSUE0;
                  end
                end else begin
                  reg_filter_xtd <= 1'b0;
                  reg_filter_count <= i_cfd_sf_cfg_sf_num;
                  reg_filter_start <= i_cfd_sf_cfg_sf_start;
                  if (i_cfd_sf_cfg_sf_num == 8'd0) begin
                    reg_anmf <= 1'b1;
                    reg_store_filter_idx <= '0;
                    reg_elem_action <= {1'b0, i_cfd_gfc_anfs};
                    reg_state <= ENUM_STATE_SEL;
                  end else begin
                    reg_state <= ENUM_STATE_FILTER_ISSUE0;
                  end
                end
              end
            end
            default: begin
              reg_state <= reg_state;
            end
          endcase
        end

        ENUM_STATE_FILTER_ISSUE0: begin
          reg_ram_req <= 1'b1;
          reg_ram_we <= 1'b0;
          reg_ram_addr <= $bits(reg_ram_addr)'(reg_filter_start) +
                          ($bits(reg_ram_addr)'(reg_filter_idx) *
                           (reg_filter_xtd ? 32'd2 : 32'd1));
          reg_state <= ENUM_STATE_FILTER_WAIT0;
        end

        ENUM_STATE_FILTER_WAIT0: begin
          if (i_rx_ram_ack) begin
            reg_ram_req <= 1'b0;
            if (i_rx_ram_err) begin
              reg_state <= ENUM_STATE_POP;
            end else begin
              reg_filter_word0 <= i_rx_ram_rdata;
              if (reg_filter_xtd) begin
                reg_state <= ENUM_STATE_FILTER_ISSUE1;
              end else begin
                reg_elem_action <= i_rx_ram_rdata[31:29];
                reg_elem_type <= i_rx_ram_rdata[28:27];
                reg_elem_id1 <= {i_rx_ram_rdata[10:0], 18'd0};
                reg_elem_id2 <= {i_rx_ram_rdata[26:16], 18'd0};
                reg_elem_buf_idx <= i_rx_ram_rdata[21:16];
                reg_elem_en <= (i_rx_ram_rdata[31:29] != 3'd0);
                reg_store_filter_idx <= reg_filter_idx;
                reg_state <= ENUM_STATE_FILTER_EVAL;
              end
            end
          end
        end

        ENUM_STATE_FILTER_ISSUE1: begin
          reg_ram_req <= 1'b1;
          reg_ram_we <= 1'b0;
          reg_ram_addr <= $bits(reg_ram_addr)'(reg_filter_start) +
                          ($bits(reg_ram_addr)'(reg_filter_idx) * 32'd2) + 32'd1;
          reg_state <= ENUM_STATE_FILTER_WAIT1;
        end

        ENUM_STATE_FILTER_WAIT1: begin
          if (i_rx_ram_ack) begin
            reg_ram_req <= 1'b0;
            if (i_rx_ram_err) begin
              reg_state <= ENUM_STATE_POP;
            end else begin
              reg_elem_action <= reg_filter_word0[31:29];
              reg_elem_type <= i_rx_ram_rdata[31:30];
              reg_elem_id1 <= reg_filter_word0[28:0];
              reg_elem_id2 <= i_rx_ram_rdata[28:0];
              reg_elem_buf_idx <= i_rx_ram_rdata[5:0];
              reg_elem_en <= (reg_filter_word0[31:29] != 3'd0);
              reg_store_filter_idx <= reg_filter_idx;
              reg_state <= ENUM_STATE_FILTER_EVAL;
            end
          end
        end

        ENUM_STATE_FILTER_EVAL: begin
          if (w_filter_match) begin
            reg_anmf <= 1'b0;
            reg_state <= ENUM_STATE_SEL;
          end else if ({1'b0, reg_filter_idx} + 8'd1 >= reg_filter_count) begin
            reg_anmf <= 1'b1;
            reg_store_filter_idx <= '0;
            if (reg_filter_xtd)
              reg_elem_action <= {1'b0, i_cfd_gfc_anfe};
            else
              reg_elem_action <= {1'b0, i_cfd_gfc_anfs};
            reg_state <= ENUM_STATE_SEL;
          end else begin
            reg_filter_idx <= reg_filter_idx + 7'd1;
            reg_state <= ENUM_STATE_FILTER_ISSUE0;
          end
        end

        ENUM_STATE_SEL: begin
          reg_high_prio <= 1'b0;
          reg_store_was_full <= 1'b0;
          reg_store_filter_idx <= reg_anmf ? 7'd0 : reg_filter_idx;
          casez (reg_elem_action)
            3'd1, 3'd4: begin
              reg_store_target <= ENUM_TARGET_FIFO0;
              reg_store_num <= i_cfd_rxf0_cfg_num;
              reg_store_wm <= i_cfd_rxf0_cfg_wm;
              reg_store_dsz <= i_cfd_esz_rxf0_dsz;
              reg_store_idx <= reg_rxf0_pidx;
              reg_store_base <= $bits(reg_store_base)'(i_cfd_rxf0_cfg_start) +
                                ($bits(reg_store_base)'(reg_rxf0_pidx) *
                                 (32'd3 + (32'(f_dsz_bytes(i_cfd_esz_rxf0_dsz)) >> 2)));
              reg_store_data_words <= 6'(32'(f_dsz_bytes(i_cfd_esz_rxf0_dsz)) >> 2);
              reg_high_prio <= (reg_elem_action == 3'd4);
              reg_store_filter_idx <= reg_anmf ? 7'd0 : reg_filter_idx;
              if ((i_cfd_rxf0_cfg_num == 7'd0) || (32'(i_cfd_rxf0_cfg_num) > PARA_CANFD_RXF_MAX) ||
                  (reg_rxf0_fill >= i_cfd_rxf0_cfg_num)) begin
                if ((i_cfd_rxf0_cfg_num != 7'd0) && i_cfd_rxf0_cfg_ovw &&
                    !(32'(i_cfd_rxf0_cfg_num) > PARA_CANFD_RXF_MAX)) begin
                  reg_store_was_full <= 1'b1;
                  reg_store_generation <= reg_gen_rxf0[reg_rxf0_pidx] + 2'd1;
                  reg_state <= ENUM_STATE_STORE_CHECK;
                end else begin
                  reg_irq_rx0_lst <= 1'b1;
                  reg_state <= ENUM_STATE_POP;
                end
              end else begin
                reg_store_generation <= reg_gen_rxf0[reg_rxf0_pidx] + 2'd1;
                reg_state <= ENUM_STATE_STORE_CHECK;
              end
            end
            3'd2, 3'd5: begin
              reg_store_target <= ENUM_TARGET_FIFO1;
              reg_store_num <= i_cfd_rxf1_cfg_num;
              reg_store_wm <= i_cfd_rxf1_cfg_wm;
              reg_store_dsz <= i_cfd_esz_rxf1_dsz;
              reg_store_idx <= reg_rxf1_pidx;
              reg_store_base <= $bits(reg_store_base)'(i_cfd_rxf1_cfg_start) +
                                ($bits(reg_store_base)'(reg_rxf1_pidx) *
                                 (32'd3 + (32'(f_dsz_bytes(i_cfd_esz_rxf1_dsz)) >> 2)));
              reg_store_data_words <= 6'(32'(f_dsz_bytes(i_cfd_esz_rxf1_dsz)) >> 2);
              reg_high_prio <= (reg_elem_action == 3'd5);
              reg_store_filter_idx <= reg_anmf ? 7'd0 : reg_filter_idx;
              if ((PARA_CANFD_RXFIFO_NUM == 32'd1) || (i_cfd_rxf1_cfg_num == 7'd0) ||
                  (32'(i_cfd_rxf1_cfg_num) > PARA_CANFD_RXF_MAX) ||
                  (reg_rxf1_fill >= i_cfd_rxf1_cfg_num)) begin
                if ((PARA_CANFD_RXFIFO_NUM > 32'd1) && (i_cfd_rxf1_cfg_num != 7'd0) &&
                    i_cfd_rxf1_cfg_ovw && !(32'(i_cfd_rxf1_cfg_num) > PARA_CANFD_RXF_MAX) &&
                    (reg_rxf1_fill >= i_cfd_rxf1_cfg_num)) begin
                  reg_store_was_full <= 1'b1;
                  reg_store_generation <= reg_gen_rxf1[reg_rxf1_pidx] + 2'd1;
                  reg_state <= ENUM_STATE_STORE_CHECK;
                end else begin
                  if (PARA_CANFD_RXFIFO_NUM > 32'd1)
                    reg_irq_rx1_lst <= 1'b1;
                  reg_state <= ENUM_STATE_POP;
                end
              end else begin
                reg_store_generation <= reg_gen_rxf1[reg_rxf1_pidx] + 2'd1;
                reg_state <= ENUM_STATE_STORE_CHECK;
              end
            end
            3'd6: begin
              reg_store_target <= ENUM_TARGET_BUF;
              reg_store_num <= i_cfd_rxb_cfg_num;
              reg_store_wm <= '0;
              reg_store_dsz <= i_cfd_esz_rxb_dsz;
              reg_store_idx <= reg_elem_buf_idx;
              reg_store_base <= $bits(reg_store_base)'(i_cfd_rxb_cfg_start) +
                                ($bits(reg_store_base)'(reg_elem_buf_idx) *
                                 (32'd3 + (32'(f_dsz_bytes(i_cfd_esz_rxb_dsz)) >> 2)));
              reg_store_data_words <= 6'(32'(f_dsz_bytes(i_cfd_esz_rxb_dsz)) >> 2);
              reg_store_filter_idx <= reg_anmf ? 7'd0 : reg_filter_idx;
              if (({1'b0, reg_elem_buf_idx} >= i_cfd_rxb_cfg_num) ||
                  (32'(reg_elem_buf_idx) >= PARA_CANFD_RXBUF_MAX)) begin
                reg_state <= ENUM_STATE_POP;
              end else begin
                reg_store_generation <= reg_gen_rxb[reg_elem_buf_idx] + 2'd1;
                reg_state <= ENUM_STATE_STORE_CHECK;
              end
            end
            default: begin
              reg_store_target <= ENUM_TARGET_REJECT;
              reg_state <= ENUM_STATE_POP;
            end
          endcase
        end

        ENUM_STATE_STORE_CHECK: begin
          if ((|reg_store_base[31:PARA_CANFD_MRAM_AW]) ||
              (|w_store_span_end[32:PARA_CANFD_MRAM_AW])) begin
            reg_rx_ram_flt_event <= 1'b1;
            reg_rx_fault_addr <= w_store_end_ext;
            if (reg_store_target == ENUM_TARGET_FIFO0)
              reg_irq_rx0_lst <= 1'b1;
            if (reg_store_target == ENUM_TARGET_FIFO1)
              reg_irq_rx1_lst <= 1'b1;
            reg_state <= ENUM_STATE_POP;
          end else begin
            reg_data_word_idx <= '0;
            reg_state <= ENUM_STATE_STORE_DATA_ISSUE;
          end
        end

        ENUM_STATE_STORE_DATA_ISSUE: begin
          reg_ram_req <= 1'b1;
          reg_ram_we <= 1'b1;
          reg_ram_addr <= reg_store_base + 32'd3 + 32'(reg_data_word_idx);
          reg_ram_wdata <= w_store_data;
          reg_state <= ENUM_STATE_STORE_DATA_WAIT;
        end

        ENUM_STATE_STORE_DATA_WAIT: begin
          if (i_rx_ram_ack) begin
            reg_ram_req <= 1'b0;
            if (i_rx_ram_err) begin
              if (reg_store_target == ENUM_TARGET_FIFO0)
                reg_irq_rx0_lst <= 1'b1;
              if (reg_store_target == ENUM_TARGET_FIFO1)
                reg_irq_rx1_lst <= 1'b1;
              reg_state <= ENUM_STATE_POP;
            end else if ({1'b0, reg_data_word_idx} + 7'd1 < {1'b0, reg_store_data_words}) begin
              reg_data_word_idx <= reg_data_word_idx + 6'd1;
              reg_state <= ENUM_STATE_STORE_DATA_ISSUE;
            end else begin
              reg_state <= ENUM_STATE_STORE_TS_ISSUE;
            end
          end
        end

        ENUM_STATE_STORE_TS_ISSUE: begin
          reg_ram_req <= 1'b1;
          reg_ram_we <= 1'b1;
          reg_ram_addr <= reg_store_base + 32'd2;
          reg_ram_wdata <= (PARA_CANFD_TS_EN == 32'd1) ?
                           ((PARA_CANFD_TS_W == 32'd16) ? {16'd0, w_frame_timestamp[15:0]} : w_frame_timestamp) :
                           32'd0;
          reg_state <= ENUM_STATE_STORE_TS_WAIT;
        end

        ENUM_STATE_STORE_TS_WAIT: begin
          if (i_rx_ram_ack) begin
            reg_ram_req <= 1'b0;
            if (i_rx_ram_err) begin
              if (reg_store_target == ENUM_TARGET_FIFO0)
                reg_irq_rx0_lst <= 1'b1;
              if (reg_store_target == ENUM_TARGET_FIFO1)
                reg_irq_rx1_lst <= 1'b1;
              reg_state <= ENUM_STATE_POP;
            end else begin
              reg_state <= ENUM_STATE_STORE_W1_ISSUE;
            end
          end
        end

        ENUM_STATE_STORE_W1_ISSUE: begin
          reg_ram_req <= 1'b1;
          reg_ram_we <= 1'b1;
          reg_ram_addr <= reg_store_base + 32'd1;
          reg_ram_wdata <= w_store_word1;
          reg_state <= ENUM_STATE_STORE_W1_WAIT;
        end

        ENUM_STATE_STORE_W1_WAIT: begin
          if (i_rx_ram_ack) begin
            reg_ram_req <= 1'b0;
            if (i_rx_ram_err) begin
              if (reg_store_target == ENUM_TARGET_FIFO0)
                reg_irq_rx0_lst <= 1'b1;
              if (reg_store_target == ENUM_TARGET_FIFO1)
                reg_irq_rx1_lst <= 1'b1;
              reg_state <= ENUM_STATE_POP;
            end else begin
              reg_state <= ENUM_STATE_STORE_W0_ISSUE;
            end
          end
        end

        ENUM_STATE_STORE_W0_ISSUE: begin
          reg_ram_req <= 1'b1;
          reg_ram_we <= 1'b1;
          reg_ram_addr <= reg_store_base;
          reg_ram_wdata <= w_frame_word0;
          reg_state <= ENUM_STATE_STORE_W0_WAIT;
        end

        ENUM_STATE_STORE_W0_WAIT: begin
          if (i_rx_ram_ack) begin
            reg_ram_req <= 1'b0;
            if (i_rx_ram_err) begin
              if (reg_store_target == ENUM_TARGET_FIFO0)
                reg_irq_rx0_lst <= 1'b1;
              if (reg_store_target == ENUM_TARGET_FIFO1)
                reg_irq_rx1_lst <= 1'b1;
              reg_state <= ENUM_STATE_POP;
            end else begin
              casez (reg_store_target)
                ENUM_TARGET_FIFO0: begin
                  reg_gen_rxf0[reg_store_idx] <= reg_store_generation;
                  reg_rxf0_pidx <= f_index_inc(reg_rxf0_pidx, reg_store_num);
                  if (reg_store_was_full) begin
                    reg_rxf0_gidx <= f_index_inc(reg_rxf0_gidx, reg_store_num);
                    reg_irq_rx0_lst <= 1'b1;
                  end else begin
                    reg_rxf0_fill <= reg_rxf0_fill + 7'd1;
                    if ((reg_rxf0_fill + 7'd1) == reg_store_num)
                      reg_irq_rx0_ful <= 1'b1;
                    if ((reg_store_wm != 7'd0) && (reg_rxf0_fill < reg_store_wm) &&
                        ((reg_rxf0_fill + 7'd1) >= reg_store_wm))
                      reg_irq_rx0_wm <= 1'b1;
                  end
                  reg_irq_rx0_new <= 1'b1;
                  if (reg_high_prio) begin
                    reg_hpm_vld_set <= 1'b1;
                    reg_hpm_fifo <= 1'b0;
                    reg_hpm_idx <= reg_store_idx;
                    reg_hpm_fidx <= reg_store_filter_idx;
                    reg_irq_hpm <= 1'b1;
                  end
                end
                ENUM_TARGET_FIFO1: begin
                  reg_gen_rxf1[reg_store_idx] <= reg_store_generation;
                  reg_rxf1_pidx <= f_index_inc(reg_rxf1_pidx, reg_store_num);
                  if (reg_store_was_full) begin
                    reg_rxf1_gidx <= f_index_inc(reg_rxf1_gidx, reg_store_num);
                    reg_irq_rx1_lst <= 1'b1;
                  end else begin
                    reg_rxf1_fill <= reg_rxf1_fill + 7'd1;
                    if ((reg_rxf1_fill + 7'd1) == reg_store_num)
                      reg_irq_rx1_ful <= 1'b1;
                    if ((reg_store_wm != 7'd0) && (reg_rxf1_fill < reg_store_wm) &&
                        ((reg_rxf1_fill + 7'd1) >= reg_store_wm))
                      reg_irq_rx1_wm <= 1'b1;
                  end
                  reg_irq_rx1_new <= 1'b1;
                  if (reg_high_prio) begin
                    reg_hpm_vld_set <= 1'b1;
                    reg_hpm_fifo <= 1'b1;
                    reg_hpm_idx <= reg_store_idx;
                    reg_hpm_fidx <= reg_store_filter_idx;
                    reg_irq_hpm <= 1'b1;
                  end
                end
                ENUM_TARGET_BUF: begin
                  reg_gen_rxb[reg_store_idx] <= reg_store_generation;
                  if (reg_store_idx < 6'd32)
                    reg_rxb_nd0_set[reg_store_idx[4:0]] <= 1'b1;
                  else
                    reg_rxb_nd1_set[reg_store_idx[4:0]] <= 1'b1;
                end
                default: begin
                  reg_rxf0_fill <= reg_rxf0_fill;
                end
              endcase
              if (reg_elapsed > reg_flt_peak)
                reg_flt_peak <= reg_elapsed;
              reg_state <= ENUM_STATE_POP;
            end
          end
        end

        ENUM_STATE_POP: begin
          reg_rx_frame_pop <= 1'b1;
          if (reg_elapsed > reg_flt_peak)
            reg_flt_peak <= reg_elapsed;
          reg_state <= ENUM_STATE_IDLE;
        end

        default: begin
          reg_ram_req <= 1'b0;
          reg_state <= ENUM_STATE_IDLE;
        end
      endcase
    end
  end

endmodule
