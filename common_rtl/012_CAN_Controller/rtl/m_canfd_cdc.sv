/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-11
 * Description  : CAN/BUS clock-domain crossing hub. It snapshots quasi-static configuration,
 *                transfers stable status and frame bundles, moves CAN events and BUS commands,
 *                transfers atomic timestamped Tx results, ordered TTCAN Tx triggers and
 *                trigger-RAM words, buffers completed Rx frames, carries the runtime TTCAN SGT
 *                command with its preset, and transfers accumulated TTCAN miss bitmaps to CSR.
 * DEC IDs      : DEC-110, DEC-112, DEC-113
 */
`timescale 1ns/1ps

module m_canfd_cdc #(
  // Parameter Description: maximum CAN data payload width used to size the frame record.
  // Parameter values: 8, 12, 16, 20, 24, 32, 48, or 64; default is 64.
  // Parameter unit: byte
  parameter logic [31:0] PARA_CANFD_DATA_MAX = 32'd64,
  // Parameter Description: depth of the transient CAN-to-BUS Rx frame FIFO.
  // Parameter values: power of two, 2 or greater; default is 2.
  // Parameter unit: entry
  parameter logic [31:0] PARA_CANFD_RXHOLD_DEPTH = 32'd2,
  // Parameter Description: synchronizer structure for single-bit controls and event pulses.
  // Parameter values: 0 = two discrete DFF stages; 1 = VLSIT 2-FF synchronizer cell; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_CELL_TYPE = 32'd0,
  // Parameter Description: packed CSR-derived configuration bundle width set by the structural top.
  // Parameter values: 1 or greater; default is 1.
  // Parameter unit: bit
  parameter logic [31:0] PARA_CANFD_CFG_W = 32'd1,
  // Parameter Description: packed CAN status bundle width set by the structural top.
  // Parameter values: 1 or greater; default is 1.
  // Parameter unit: bit
  parameter logic [31:0] PARA_CANFD_STS_W = 32'd1,
  // Parameter Description: packed partial-networking filter bundle width set by the structural top.
  // Parameter values: 1 or greater; default is 1.
  // Parameter unit: bit
  parameter logic [31:0] PARA_CANFD_PNF_W = 32'd1,
  // Parameter Description: number of CAN-to-BUS event bits in the HDS interrupt/event map.
  // Parameter values: 1 or greater; default is 32.
  // Parameter unit: bit
  parameter logic [31:0] PARA_CANFD_EVENT_W = 32'd32,
  // Parameter Description: number of BUS-to-CAN command event bits.
  // Parameter values: 1 or greater; default is 8.
  // Parameter unit: bit
  parameter logic [31:0] PARA_CANFD_CMD_W = 32'd8,
  // Parameter Description: implemented Tx-buffer count used to size the TTCAN miss bitmap.
  // Parameter values: 1 through 32; default is 32.
  // Parameter unit: buffer
  parameter logic [31:0] PARA_CANFD_TXBUF_MAX = 32'd32,
  // Parameter Description: maximum number of TTCAN trigger words; sizes the ordered trigger FIFO.
  // Parameter values: 1 through 64; default is 64.
  // Parameter unit: word
  parameter logic [31:0] PARA_CANFD_TRIG_NUM = 32'd64,
  // Shared CAN/BUS record has four metadata words; both directions place payload at word 4.
  localparam logic [31:0] LPARA_CANFD_RXW = 32'd4 + (PARA_CANFD_DATA_MAX / 32'd4),
  localparam logic [31:0] LPARA_CANFD_FRAME_W = LPARA_CANFD_RXW * 32'd32,
  localparam logic [31:0] LPARA_TX_FRAME_CDC_W = LPARA_CANFD_FRAME_W + 32'd39,
  localparam logic [31:0] LPARA_TX_RESULT_W = 32'd45,
  localparam logic [31:0] LPARA_TT_GPRE_W = 32'd16,
  localparam logic [31:0] LPARA_TT_IRQ_W = 32'd16,
  localparam logic [31:0] LPARA_TT_RAM_REQ_W = 32'd32,
  localparam logic [31:0] LPARA_TT_RAM_RSP_W = 32'd35,
  localparam logic [31:0] LPARA_TTB_W = PARA_CANFD_TXBUF_MAX,
  localparam logic [31:0] LPARA_TT_MISS_W = LPARA_TTB_W + 32'd64,
  localparam logic [31:0] LPARA_TT_TRIGGER_W = 32'd39,
  localparam logic [31:0] LPARA_TT_WINDOW_SEQ_W = 32'd32,
  localparam logic [31:0] LPARA_TT_TRIGGER_MIN_DEPTH = 32'd2,
  localparam logic [31:0] LPARA_TT_TRIGGER_DEPTH =
    (PARA_CANFD_TRIG_NUM <= LPARA_TT_TRIGGER_MIN_DEPTH) ? LPARA_TT_TRIGGER_MIN_DEPTH :
    (32'd1 << $clog2(PARA_CANFD_TRIG_NUM)),
  localparam logic [31:0] LPARA_TT_TRIGGER_ADDR_W = $clog2(LPARA_TT_TRIGGER_DEPTH),
  localparam logic [31:0] LPARA_TT_TRIGGER_PTR_W = LPARA_TT_TRIGGER_ADDR_W + 32'd1,
  localparam logic [31:0] LPARA_TT_TRIGGER_FULL_THR = LPARA_TT_TRIGGER_DEPTH,
  localparam logic [31:0] LPARA_TT_TRIGGER_EMPTY_THR = 32'd1,
  localparam logic [31:0] LPARA_AFIFO_ADDR_W = $clog2(PARA_CANFD_RXHOLD_DEPTH),
  localparam logic [31:0] LPARA_AFIFO_PTR_W = LPARA_AFIFO_ADDR_W + 32'd1,
  localparam logic [31:0] LPARA_AFIFO_FULL_THR = PARA_CANFD_RXHOLD_DEPTH,
  localparam logic [31:0] LPARA_AFIFO_EMPTY_THR = 32'd1,
  localparam logic [31:0] LPARA_AFIFO_CELL_TYPE = 32'd1,
  localparam logic [31:0] LPARA_EVENT_CELL_TYPE_DFF2 = 32'd1,
  localparam logic [31:0] LPARA_EVENT_CELL_TYPE_2FF = 32'd2,
  localparam logic [31:0] LPARA_EVENT_CELL_TYPE = (PARA_CANFD_CELL_TYPE == 32'd1) ?
                                                     LPARA_EVENT_CELL_TYPE_2FF : LPARA_EVENT_CELL_TYPE_DFF2,
  localparam logic [31:0] LPARA_AFIFO_RST_N_INACTIVE = 32'd1,
  localparam logic [31:0] LPARA_INIT_HOLD_CLK = 32'd3,
  localparam logic [31:0] LPARA_CMD_DONE_W = 32'd6,
  localparam logic [31:0] LPARA_FAULT_W = 32'd14,
  localparam logic [31:0] LPARA_RXB_W = 32'd64
) (
  // Clock, reset and readiness signals for both domains
  input  wire                            i_clk_can,
  input  wire                            i_rst_n_can,
  input  wire                            i_cdc_ready_can,
  input  wire                            i_clk_bus,
  input  wire                            i_rst_n_bus,
  input  wire                            i_cdc_ready_bus,

  // Program-before-use configuration snapshot from BUS to CAN
  input  wire                            i_init_bus,
  input  wire  [PARA_CANFD_CFG_W-1:0]    i_cfg_bus,
  output logic                           o_init_can,
  output logic [PARA_CANFD_CFG_W-1:0]    o_cfg_can,

  // Rx bundle words 0-2 are header, frame flags/DLC and SOF timestamp; word 3 is zero.
  // Payload starts at word 4; BUS-only filter and generation fields remain zero until Rx handling.
  input  wire                            i_rx_frame_valid_can,
  input  wire  [LPARA_CANFD_FRAME_W-1:0] i_rx_frame_can,
  output logic                           o_rx_overflow_can,
  output logic                           o_rx_full_can,
  input  wire                            i_rx_frame_pop_bus,
  output logic                           o_rx_frame_valid_bus,
  output logic                           o_rx_fifo_empty_bus,
  output logic [LPARA_CANFD_FRAME_W-1:0] o_rx_frame_bus,
  output logic                           o_rx_near_empty_bus,
  output logic                           o_rx_underflow_bus,

  // Tx bundle words 0-1 mirror the Tx RAM headers; words 2-3 are zero and payload starts at word 4.
  input  wire                            i_tx_frame_valid_bus,
  output logic                           o_tx_frame_ready_bus,
  input  wire  [LPARA_CANFD_FRAME_W-1:0] i_tx_frame_bus,
  input  wire                            i_tx_trigger_tag_valid_bus,
  input  wire  [5:0]                     i_tx_trigger_buf_bus,
  input  wire  [31:0]                    i_tx_trigger_window_seq_bus,
  output logic                           o_tx_frame_valid_can,
  input  wire                            i_tx_frame_ready_can,
  output logic [LPARA_CANFD_FRAME_W-1:0] o_tx_frame_can,
  output logic                           o_tx_trigger_tag_valid_can,
  output logic [5:0]                     o_tx_trigger_buf_can,
  output logic [31:0]                    o_tx_trigger_window_seq_can,

  // Atomic Tx result: timestamp, outcome, and trigger SOF/expiry status.
  input  wire                            i_tx_result_valid_can,
  output logic                           o_tx_result_ready_can,
  input  wire  [31:0]                    i_tx_result_timestamp_can,
  input  wire                            i_tx_result_success_can,
  input  wire                            i_tx_result_cancel_can,
  input  wire                            i_tx_result_err_can,
  input  wire                            i_tx_result_arb_lost_can,
  input  wire                            i_tx_result_trigger_valid_can,
  input  wire  [5:0]                     i_tx_result_trigger_buf_can,
  input  wire                            i_tx_res_trig_started_can,
  input  wire                            i_tx_res_trig_expired_can,
  output logic                           o_tx_result_valid_bus,
  input  wire                            i_tx_result_ready_bus,
  output logic [31:0]                    o_tx_result_timestamp_bus,
  output logic                           o_tx_result_success_bus,
  output logic                           o_tx_result_cancel_bus,
  output logic                           o_tx_result_err_bus,
  output logic                           o_tx_result_arb_lost_bus,
  output logic                           o_tx_result_trigger_valid_bus,
  output logic [5:0]                     o_tx_result_trigger_buf_bus,
  output logic                           o_tx_res_trig_started_bus,
  output logic                           o_tx_res_trig_expired_bus,

  // CAN status snapshot into BUS
  input  wire                            i_sts_valid_can,
  output logic                           o_sts_ready_can,
  input  wire  [PARA_CANFD_STS_W-1:0]    i_sts_can,
  output logic                           o_sts_valid_bus,
  input  wire                            i_sts_ready_bus,
  output logic [PARA_CANFD_STS_W-1:0]    o_sts_bus,

  // Runtime partial-networking filter update from BUS to CAN
  input  wire                            i_pnf_valid_bus,
  output logic                           o_pnf_ready_bus,
  output logic                           o_pnf_done_bus,
  input  wire  [PARA_CANFD_PNF_W-1:0]    i_pnf_bus,
  output logic                           o_pnf_valid_can,
  input  wire                            i_pnf_ready_can,
  output logic [PARA_CANFD_PNF_W-1:0]    o_pnf_can,

  // Event pulses from CAN to BUS and commands from BUS to CAN
  input  wire  [PARA_CANFD_EVENT_W-1:0]  i_event_can,
  output logic [PARA_CANFD_EVENT_W-1:0]  o_event_bus,

  // TTCAN's 16 detailed interrupt causes have dedicated CSR fields and cross independently.
  input  wire  [LPARA_TT_IRQ_W-1:0]      i_tt_irq_event_can,
  output logic [LPARA_TT_IRQ_W-1:0]      o_tt_irq_event_bus,

  // TDC timeout has its own CSR group and therefore uses a dedicated event crossing.
  input  wire                            i_tdc_timeout_event_can,
  output logic                           o_tdc_timeout_event_bus,

  // BUS-to-CAN command levels held by the CSR until the consumer has applied them (DEC-112)
  input  wire  [PARA_CANFD_CMD_W-1:0]    i_cmd_bus,
  output logic [PARA_CANFD_CMD_W-1:0]    o_cmd_can,

  // CAN-to-BUS done pulses that clear command bits: wake_ack, kick, nig, fgp, sgt, ecs
  input  wire  [LPARA_CMD_DONE_W-1:0]    i_cmd_done_can,
  output logic [LPARA_CMD_DONE_W-1:0]    o_cmd_done_bus,

  // Clock stop: request level to CAN, acknowledge level and INIT request pulse to BUS
  input  wire                            i_clk_stop_req_bus,
  output logic                           o_clk_stop_req_can,
  input  wire                            i_clk_stop_ack_can,
  output logic                           o_clk_stop_ack_bus,
  input  wire                            i_init_set_stop_can,
  output logic                           o_init_set_stop_bus,

  // Safety fault events of the CAN domain to BUS (CDC-008) and the Rx handoff overrun pulse to BUS
  input  wire  [LPARA_FAULT_W-1:0]       i_fault_event_can,
  output logic [LPARA_FAULT_W-1:0]       o_fault_event_can_bus,
  output logic                           o_rx_overflow_bus,

  // Rx buffer new-data pulses of the BUS domain to the CAN domain (TTCAN reception check)
  input  wire  [LPARA_RXB_W-1:0]         i_rxb_set_bus,
  output logic [LPARA_RXB_W-1:0]         o_rxb_set_can,

  // Runtime TTCAN set-global-time command and its atomic 16-bit preset payload
  input  wire                            i_tt_sgt_cmd_bus,
  input  wire  [15:0]                    i_tt_gpre_bus,
  output logic                           o_tt_sgt_cmd_can,
  output logic [15:0]                    o_tt_gpre_can,

  // Wake-up request held in CAN until the synchronized BUS acknowledge arrives
  input  wire                            i_wake_can,
  output logic                           o_wake_bus,
  input  wire                            i_wake_ack_bus,
  output logic                           o_wake_ack_can,

  // TTCAN trigger-list word-read request and atomic response (CDC-014)
  input  wire                            i_tt_ram_req_can,
  output logic                           o_tt_ram_req_ready_can,
  input  wire  [31:0]                    i_tt_ram_addr_can,
  output logic                           o_tt_ram_req_bus,
  output logic [31:0]                    o_tt_ram_addr_bus,
  input  wire                            i_tt_ram_ack_bus,
  input  wire  [31:0]                    i_tt_ram_rdata_bus,
  input  wire                            i_tt_ram_err_bus,
  input  wire                            i_tt_ram_err_cor_bus,
  input  wire                            i_tt_ram_err_unc_bus,
  output logic                           o_tt_ram_rsp_valid_can,
  input  wire                            i_tt_ram_rsp_ready_can,
  output logic [31:0]                    o_tt_ram_rdata_can,
  output logic                           o_tt_ram_err_can,
  output logic                           o_tt_ram_err_cor_can,
  output logic                           o_tt_ram_err_unc_can,

  // Ordered, window-tagged ordinary TTCAN Tx-trigger FIFO from CLK-CAN to CLK-BUS
  input  wire                            i_tt_trigger_valid_can,
  output logic                           o_tt_trigger_ready_can,
  input  wire  [5:0]                     i_tt_trigger_buf_can,
  input  wire                            i_tt_trigger_merged_can,
  input  wire  [31:0]                    i_tt_trigger_window_seq_can,
  output logic                           o_tt_trigger_valid_bus,
  input  wire                            i_tt_trigger_ready_bus,
  output logic [5:0]                     o_tt_trigger_buf_bus,
  output logic                           o_tt_trigger_merged_bus,
  output logic [31:0]                    o_tt_trigger_window_seq_bus,
  input  wire  [31:0]                    i_tt_window_seq_can,
  output logic [31:0]                    o_tt_window_seq_bus,
  output logic                           o_tt_window_seq_valid_bus,

  // Accumulated TTCAN miss bitmap update mask delivered to BUS-domain CSR logic (CDC-015)
  input  wire  [LPARA_TTB_W-1:0]         i_ttb_miss_set_can,
  input  wire  [63:0]                    i_ttr_miss_set_can,
  input  wire                            i_tt_miss_ready_bus,
  output logic                           o_tt_miss_valid_bus,
  output logic [LPARA_TTB_W-1:0]         o_ttb_miss_set_bus,
  output logic [63:0]                    o_ttr_miss_set_bus
);

  logic w_init_can_sync;
  logic reg_init_can_d;
  logic [1:0] reg_init_hold_cnt;
  logic [PARA_CANFD_CFG_W-1:0] reg_cfg_can;
  logic reg_pnf_busy_bus;
  logic [LPARA_CMD_DONE_W-1:0] w_cmd_done_can_gated;
  logic w_init_set_stop_can_gated;
  logic [LPARA_FAULT_W-1:0] w_fault_event_can_gated;
  logic w_rx_overflow_can_gated;
  logic [LPARA_RXB_W-1:0] w_rxb_set_bus_gated;
  logic w_pnf_valid_src;
  logic w_afifo_full;
  logic w_afifo_full_thr;
  logic w_afifo_empty;
  logic w_afifo_empty_thr;
  logic w_afifo_sw_rst_busy;
  logic w_afifo_sw_rst_busy_bus;
  logic [LPARA_CANFD_FRAME_W-1:0] w_afifo_rd_data;
  logic [LPARA_TX_FRAME_CDC_W-1:0] w_tx_frame_cdc_bus;
  logic [LPARA_TX_FRAME_CDC_W-1:0] w_tx_frame_cdc_can;
  logic w_afifo_overflow;
  logic w_afifo_underflow;
  logic w_rx_frame_wr_en;
  logic w_rx_frame_rd_en;
  logic [PARA_CANFD_EVENT_W-1:0] w_event_can_gated;
  logic [15:0] w_tt_irq_event_can_gated;
  logic w_tdc_timeout_event_can_gated;
  logic [PARA_CANFD_CMD_W-1:0] w_cmd_bus_gated;
  logic w_wake_ack_bus_gated;
  logic reg_tt_sgt_cmd_bus_d;
  logic reg_tt_sgt_pending_bus;
  logic [LPARA_TT_GPRE_W-1:0] reg_tt_gpre_hold_bus;
  logic w_tt_sgt_hsk_ready_bus;
  logic w_tt_sgt_hsk_valid_can;
  logic [LPARA_TT_GPRE_W-1:0] w_tt_gpre_hsk_can;
  logic [LPARA_TX_RESULT_W-1:0] w_tx_result_can;
  logic [LPARA_TX_RESULT_W-1:0] w_tx_result_bus;
  logic [LPARA_TT_RAM_REQ_W-1:0] w_tt_ram_req_bus;
  logic w_tt_ram_req_valid_bus;
  logic w_tt_ram_req_ready_bus;
  logic [LPARA_TT_RAM_RSP_W-1:0] reg_tt_ram_rsp_bus;
  logic reg_tt_ram_rsp_valid_bus;
  logic w_tt_ram_rsp_ready_bus;
  logic [LPARA_TT_RAM_RSP_W-1:0] w_tt_ram_rsp_can;
  logic [LPARA_TT_MISS_W-1:0] reg_tt_miss_pending_can;
  logic [LPARA_TT_MISS_W-1:0] w_tt_miss_data_bus;
  logic w_tt_miss_hsk_ready_can;
  logic w_tt_miss_valid_bus;
  logic w_tt_trigger_full;
  logic w_tt_trigger_empty;
  logic w_tt_trigger_sw_rst_busy;
  logic w_tt_trigger_sw_rst_busy_bus;
  logic w_tt_trigger_wr_en;
  logic w_tt_trigger_rd_en;
  logic [LPARA_TT_TRIGGER_W-1:0] w_tt_trigger_wr_data;
  logic [LPARA_TT_TRIGGER_W-1:0] w_tt_trigger_rd_data;
  logic [31:0] reg_tt_window_seq_hold_can;
  logic [31:0] reg_tt_window_seq_last_can;
  logic reg_tt_window_seq_pending_can;
  logic w_tt_window_seq_hsk_ready_can;
  logic w_tt_window_seq_valid_bus;
  logic [31:0] w_tt_window_seq_hsk_bus;
  logic [31:0] reg_tt_window_seq_bus;
  logic reg_tt_window_seq_valid_bus;

  // Synchronize INIT; the CAN domain captures the stable configuration when INIT changes.
  m_canfd_sync_bit #(
    .PARA_CANFD_CELL_TYPE (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_bit_0 (
    .i_clk_dst   (i_clk_can),
    .i_rst_n_dst (i_rst_n_can),
    .i_data      (i_init_bus),
    .o_data      (w_init_can_sync)
  );

  // Capture the asynchronous configuration bundle only when the synchronized INIT level changes.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_cfg_snapshot
    if (!i_rst_n_can) begin
      reg_init_can_d <= 1'b0;
      reg_cfg_can    <= '0;
      reg_init_hold_cnt <= 2'd0;
    end else if (i_cdc_ready_can) begin
      reg_init_can_d <= w_init_can_sync;
      if (w_init_can_sync != reg_init_can_d) begin
        reg_cfg_can <= i_cfg_bus;
        // INIT falls: INIT stays up three clocks so that the new snapshot is checked first
        if (!w_init_can_sync)
          reg_init_hold_cnt <= 2'(LPARA_INIT_HOLD_CLK);
      end else if (reg_init_hold_cnt != 2'd0) begin
        reg_init_hold_cnt <= reg_init_hold_cnt - 2'd1;
      end
    end
  end

  // Expose the synchronized mode and its stable configuration snapshot to the CAN blocks.
  assign o_init_can = w_init_can_sync || (reg_init_hold_cnt != 2'd0);
  assign o_cfg_can = reg_cfg_can;

  // Enqueue each completed CAN frame once and preserve the shared FIFO's overflow indication.
  assign w_rx_frame_wr_en = i_rx_frame_valid_can && i_cdc_ready_can;
  assign w_rx_frame_rd_en = i_rx_frame_pop_bus && i_cdc_ready_bus;

  m_vlsit_afifo_top #(
    .PARA_AFIFO_DEPTH         (PARA_CANFD_RXHOLD_DEPTH),
    .PARA_AFIFO_DATA_W        (LPARA_CANFD_FRAME_W),
    .PARA_AFIFO_CELL_TYPE     (LPARA_AFIFO_CELL_TYPE)
  ) u_vlsit_afifo_top (
    .i_clk_wr      (i_clk_can),
    .i_rst_n_wr    (i_rst_n_can),
    .i_wr_en       (w_rx_frame_wr_en),
    .i_wr_data     (i_rx_frame_can),
    .i_full_thr    (LPARA_AFIFO_PTR_W'(LPARA_AFIFO_FULL_THR)),
    .o_full        (w_afifo_full),
    .o_full_thr    (w_afifo_full_thr),
    .o_overflow    (w_afifo_overflow),
    .i_rst_n_sw    (LPARA_AFIFO_RST_N_INACTIVE[0]),
    .o_sw_rst_busy (w_afifo_sw_rst_busy),
    .i_clk_rd      (i_clk_bus),
    .i_rst_n_rd    (i_rst_n_bus),
    .i_rd_en       (w_rx_frame_rd_en),
    .i_empty_thr   (LPARA_AFIFO_PTR_W'(LPARA_AFIFO_EMPTY_THR)),
    .o_rd_data     (w_afifo_rd_data),
    .o_empty       (w_afifo_empty),
    .o_empty_thr   (w_afifo_empty_thr),
    .o_underflow   (w_afifo_underflow)
  );

  // Synchronize the FIFO write-domain reset-busy level before exposing read validity in BUS.
  m_canfd_sync_bit #(
    .PARA_CANFD_CELL_TYPE (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_bit_2 (
    .i_clk_dst   (i_clk_bus),
    .i_rst_n_dst (i_rst_n_bus),
    .i_data      (w_afifo_sw_rst_busy),
    .o_data      (w_afifo_sw_rst_busy_bus)
  );

  // Report FIFO occupancy events and present the first unread frame to the BUS consumer.
  assign o_rx_overflow_can = w_afifo_overflow;
  assign o_rx_full_can = w_afifo_full | w_afifo_full_thr;
  assign o_rx_frame_valid_bus = i_cdc_ready_bus && !w_afifo_empty && !w_afifo_sw_rst_busy_bus;
  assign o_rx_fifo_empty_bus = w_afifo_empty && !w_afifo_sw_rst_busy_bus;
  assign o_rx_frame_bus = w_afifo_rd_data;
  assign o_rx_near_empty_bus = w_afifo_empty_thr;
  assign o_rx_underflow_bus = w_afifo_underflow;

  // Queue ordinary TTCAN trigger descriptors in schedule order across the two clocks.
  assign o_tt_trigger_ready_can = i_cdc_ready_can && !w_tt_trigger_full;
  assign w_tt_trigger_wr_en = i_tt_trigger_valid_can && o_tt_trigger_ready_can;
  assign w_tt_trigger_wr_data = {i_tt_trigger_window_seq_can,
                                 i_tt_trigger_merged_can,
                                 i_tt_trigger_buf_can};
  // Remove an entry only when TXH accepts the descriptor at the BUS endpoint.
  assign w_tt_trigger_rd_en = i_tt_trigger_ready_bus && o_tt_trigger_valid_bus;

  m_vlsit_afifo_top #(
    .PARA_AFIFO_DEPTH         (LPARA_TT_TRIGGER_DEPTH),
    .PARA_AFIFO_DATA_W        (LPARA_TT_TRIGGER_W),
    .PARA_AFIFO_CELL_TYPE     (LPARA_AFIFO_CELL_TYPE)
  ) u_vlsit_afifo_top_1 (
    .i_clk_wr      (i_clk_can),
    .i_rst_n_wr    (i_rst_n_can),
    .i_wr_en       (w_tt_trigger_wr_en),
    .i_wr_data     (w_tt_trigger_wr_data),
    .i_full_thr    (LPARA_TT_TRIGGER_PTR_W'(LPARA_TT_TRIGGER_FULL_THR)),
    .o_full        (w_tt_trigger_full),
    .o_full_thr    (),
    .o_overflow    (),
    .i_rst_n_sw    (LPARA_AFIFO_RST_N_INACTIVE[0]),
    .o_sw_rst_busy (w_tt_trigger_sw_rst_busy),
    .i_clk_rd      (i_clk_bus),
    .i_rst_n_rd    (i_rst_n_bus),
    .i_rd_en       (w_tt_trigger_rd_en),
    .i_empty_thr   (LPARA_TT_TRIGGER_PTR_W'(LPARA_TT_TRIGGER_EMPTY_THR)),
    .o_rd_data     (w_tt_trigger_rd_data),
    .o_empty       (w_tt_trigger_empty),
    .o_empty_thr   (),
    .o_underflow   ()
  );

  // Wait for the write-side FIFO reset state before exposing queued descriptors in BUS.
  m_canfd_sync_bit #(
    .PARA_CANFD_CELL_TYPE (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_bit_3 (
    .i_clk_dst   (i_clk_bus),
    .i_rst_n_dst (i_rst_n_bus),
    .i_data      (w_tt_trigger_sw_rst_busy),
    .o_data      (w_tt_trigger_sw_rst_busy_bus)
  );

  // Expose the oldest queued trigger only after both FIFO domains are CDC-ready.
  assign o_tt_trigger_valid_bus = i_cdc_ready_bus && !w_tt_trigger_empty &&
                                  !w_tt_trigger_sw_rst_busy_bus;
  // Keep trigger fields aligned with the FIFO's oldest descriptor.
  assign {o_tt_trigger_window_seq_bus,
          o_tt_trigger_merged_bus,
          o_tt_trigger_buf_bus} = w_tt_trigger_rd_data;

  // Hold each current window sequence stable until the BUS endpoint captures it.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_tt_window_seq_src
    if (!i_rst_n_can) begin
      reg_tt_window_seq_hold_can <= '0;
      reg_tt_window_seq_last_can <= '0;
      reg_tt_window_seq_pending_can <= 1'b0;
    end else if (!i_cdc_ready_can) begin
      reg_tt_window_seq_hold_can <= '0;
      reg_tt_window_seq_last_can <= '0;
      reg_tt_window_seq_pending_can <= 1'b0;
    end else begin
      if (reg_tt_window_seq_pending_can && w_tt_window_seq_hsk_ready_can) begin
        reg_tt_window_seq_last_can <= reg_tt_window_seq_hold_can;
        reg_tt_window_seq_pending_can <= 1'b0;
      end
      if (!reg_tt_window_seq_pending_can &&
          (i_tt_window_seq_can != reg_tt_window_seq_last_can)) begin
        reg_tt_window_seq_hold_can <= i_tt_window_seq_can;
        reg_tt_window_seq_pending_can <= 1'b1;
      end
    end
  end

  m_canfd_sync_hsk #(
    .PARA_CANFD_DATA_W     (LPARA_TT_WINDOW_SEQ_W),
    .PARA_CANFD_CELL_TYPE  (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_hsk_8 (
    .i_clk_src        (i_clk_can),
    .i_rst_n_src      (i_rst_n_can),
    .i_cdc_ready_src  (i_cdc_ready_can),
    .i_valid_src      (reg_tt_window_seq_pending_can),
    .o_ready_src      (w_tt_window_seq_hsk_ready_can),
    .i_data_src       (reg_tt_window_seq_hold_can),
    .i_clk_dst        (i_clk_bus),
    .i_rst_n_dst      (i_rst_n_bus),
    .i_cdc_ready_dst  (i_cdc_ready_bus),
    .o_valid_dst      (w_tt_window_seq_valid_bus),
    .i_ready_dst      (1'b1),
    .o_data_dst       (w_tt_window_seq_hsk_bus)
  );

  // Retain the most recently captured window sequence for BUS-domain tag comparison.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_tt_window_seq_dst
    if (!i_rst_n_bus) begin
      reg_tt_window_seq_bus <= '0;
      reg_tt_window_seq_valid_bus <= 1'b0;
    end else if (!i_cdc_ready_bus) begin
      reg_tt_window_seq_bus <= '0;
      reg_tt_window_seq_valid_bus <= 1'b0;
    end else if (w_tt_window_seq_valid_bus) begin
      reg_tt_window_seq_bus <= w_tt_window_seq_hsk_bus;
      reg_tt_window_seq_valid_bus <= 1'b1;
    end
  end

  // Export the stable sequence snapshot and its post-reset validity indication.
  assign o_tt_window_seq_bus = reg_tt_window_seq_bus;
  assign o_tt_window_seq_valid_bus = reg_tt_window_seq_valid_bus;

  // Transfer the bus-side Tx frame using a held bundle and a four-phase handshake.
  assign w_tx_frame_cdc_bus = {i_tx_trigger_window_seq_bus,
                               i_tx_trigger_buf_bus,
                               i_tx_trigger_tag_valid_bus,
                               i_tx_frame_bus};
  m_canfd_sync_hsk #(
    .PARA_CANFD_DATA_W     (LPARA_TX_FRAME_CDC_W),
    .PARA_CANFD_CELL_TYPE  (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_hsk_0 (
    .i_clk_src        (i_clk_bus),
    .i_rst_n_src      (i_rst_n_bus),
    .i_cdc_ready_src  (i_cdc_ready_bus),
    .i_valid_src      (i_tx_frame_valid_bus),
    .o_ready_src      (o_tx_frame_ready_bus),
    .i_data_src       (w_tx_frame_cdc_bus),
    .i_clk_dst        (i_clk_can),
    .i_rst_n_dst      (i_rst_n_can),
    .i_cdc_ready_dst  (i_cdc_ready_can),
    .o_valid_dst      (o_tx_frame_valid_can),
    .i_ready_dst      (i_tx_frame_ready_can),
    .o_data_dst       (w_tx_frame_cdc_can)
  );
  // Decode the accepted CDC record without changing its payload layout.
  assign {o_tx_trigger_window_seq_can,
          o_tx_trigger_buf_can,
          o_tx_trigger_tag_valid_can,
          o_tx_frame_can} = w_tx_frame_cdc_can;

  // Transfer terminal status and SOF timestamp as one coherent CDC record.
  assign w_tx_result_can = {i_tx_result_timestamp_can,
                            i_tx_result_success_can,
                            i_tx_result_cancel_can,
                            i_tx_result_err_can,
                            i_tx_result_arb_lost_can,
                            i_tx_result_trigger_valid_can,
                            i_tx_result_trigger_buf_can,
                            i_tx_res_trig_started_can,
                            i_tx_res_trig_expired_can};
  m_canfd_sync_hsk #(
    .PARA_CANFD_DATA_W     (LPARA_TX_RESULT_W),
    .PARA_CANFD_CELL_TYPE  (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_hsk_3 (
    .i_clk_src        (i_clk_can),
    .i_rst_n_src      (i_rst_n_can),
    .i_cdc_ready_src  (i_cdc_ready_can),
    .i_valid_src      (i_tx_result_valid_can),
    .o_ready_src      (o_tx_result_ready_can),
    .i_data_src       (w_tx_result_can),
    .i_clk_dst        (i_clk_bus),
    .i_rst_n_dst      (i_rst_n_bus),
    .i_cdc_ready_dst  (i_cdc_ready_bus),
    .o_valid_dst      (o_tx_result_valid_bus),
    .i_ready_dst      (i_tx_result_ready_bus),
    .o_data_dst       (w_tx_result_bus)
  );
  // Expose the timestamp, terminal qualifier and trigger expiry record atomically.
  assign {o_tx_result_timestamp_bus,
          o_tx_result_success_bus,
          o_tx_result_cancel_bus,
          o_tx_result_err_bus,
          o_tx_result_arb_lost_bus,
          o_tx_result_trigger_valid_bus,
          o_tx_result_trigger_buf_bus,
          o_tx_res_trig_started_bus,
          o_tx_res_trig_expired_bus} = w_tx_result_bus;

  // Transfer CAN status snapshots into BUS only when the destination accepts the bundle.
  m_canfd_sync_hsk #(
    .PARA_CANFD_DATA_W     (PARA_CANFD_STS_W),
    .PARA_CANFD_CELL_TYPE  (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_hsk_1 (
    .i_clk_src        (i_clk_can),
    .i_rst_n_src      (i_rst_n_can),
    .i_cdc_ready_src  (i_cdc_ready_can),
    .i_valid_src      (i_sts_valid_can),
    .o_ready_src      (o_sts_ready_can),
    .i_data_src       (i_sts_can),
    .i_clk_dst        (i_clk_bus),
    .i_rst_n_dst      (i_rst_n_bus),
    .i_cdc_ready_dst  (i_cdc_ready_bus),
    .o_valid_dst      (o_sts_valid_bus),
    .i_ready_dst      (i_sts_ready_bus),
    .o_data_dst       (o_sts_bus)
  );

  // Track one filter bundle in flight: from the data take to the next ready of the handshake.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_pnf_busy
    if (!i_rst_n_bus) begin
      reg_pnf_busy_bus <= 1'b0;
    end else if (o_pnf_ready_bus && w_pnf_valid_src) begin
      reg_pnf_busy_bus <= 1'b1;
    end else if (o_pnf_ready_bus) begin
      reg_pnf_busy_bus <= 1'b0;
    end
  end

  // One-clock pulse when the bundle is copied to the CAN domain; it clears cfd_pn_cfg.pnf_upd.
  assign o_pnf_done_bus = reg_pnf_busy_bus && o_pnf_ready_bus;
  // A held request is not taken again in the clock of the done pulse, before the bit is cleared.
  assign w_pnf_valid_src = i_pnf_valid_bus && !reg_pnf_busy_bus;

  // Transfer software filter updates as complete bundles before replacing the CAN copy.
  m_canfd_sync_hsk #(
    .PARA_CANFD_DATA_W     (PARA_CANFD_PNF_W),
    .PARA_CANFD_CELL_TYPE  (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_hsk_2 (
    .i_clk_src        (i_clk_bus),
    .i_rst_n_src      (i_rst_n_bus),
    .i_cdc_ready_src  (i_cdc_ready_bus),
    .i_valid_src      (w_pnf_valid_src),
    .o_ready_src      (o_pnf_ready_bus),
    .i_data_src       (i_pnf_bus),
    .i_clk_dst        (i_clk_can),
    .i_rst_n_dst      (i_rst_n_can),
    .i_cdc_ready_dst  (i_cdc_ready_can),
    .o_valid_dst      (o_pnf_valid_can),
    .i_ready_dst      (i_pnf_ready_can),
    .o_data_dst       (o_pnf_can)
  );

  // Route CAN-side and BUS-side pulse vectors through the common event CDC primitive.
  // Suppress event requests until both reset domains have completed their ready exchange.
  assign w_event_can_gated = i_cdc_ready_can ? i_event_can : '0;
  assign w_tt_irq_event_can_gated = i_cdc_ready_can ? i_tt_irq_event_can : '0;
  assign w_tdc_timeout_event_can_gated = i_cdc_ready_can && i_tdc_timeout_event_can;
  assign w_cmd_bus_gated = i_cdc_ready_bus ? i_cmd_bus : '0;
  assign w_wake_ack_bus_gated = i_cdc_ready_bus && i_wake_ack_bus;

  m_vlsit_event_sync #(
    .PARA_EVENT_SYNC_W         (PARA_CANFD_EVENT_W),
    .PARA_EVENT_SYNC_CELL_TYPE (LPARA_EVENT_CELL_TYPE)
  ) u_vlsit_event_sync_0 (
    .i_clk_src   (i_clk_can),
    .i_rst_n_src (i_rst_n_can),
    .i_clk_dst   (i_clk_bus),
    .i_rst_n_dst (i_rst_n_bus),
    .i_event_src (w_event_can_gated),
    .o_event_dst (o_event_bus)
  );

  // Preserve the detailed TTCAN event causes in their separate CSR interrupt bank.
  m_vlsit_event_sync #(
    .PARA_EVENT_SYNC_W         (LPARA_TT_IRQ_W),
    .PARA_EVENT_SYNC_CELL_TYPE (LPARA_EVENT_CELL_TYPE)
  ) u_vlsit_event_sync_3 (
    .i_clk_src   (i_clk_can),
    .i_rst_n_src (i_rst_n_can),
    .i_clk_dst   (i_clk_bus),
    .i_rst_n_dst (i_rst_n_bus),
    .i_event_src (w_tt_irq_event_can_gated),
    .o_event_dst (o_tt_irq_event_bus)
  );

  // Transfer the dedicated TDC timeout event to its separate CSR interrupt group.
  m_vlsit_event_sync #(
    .PARA_EVENT_SYNC_W         (32'd1),
    .PARA_EVENT_SYNC_CELL_TYPE (LPARA_EVENT_CELL_TYPE)
  ) u_vlsit_event_sync_4 (
    .i_clk_src   (i_clk_can),
    .i_rst_n_src (i_rst_n_can),
    .i_event_src (w_tdc_timeout_event_can_gated),
    .i_clk_dst   (i_clk_bus),
    .i_rst_n_dst (i_rst_n_bus),
    .o_event_dst (o_tdc_timeout_event_bus)
  );

  // Done pulses of the commands and the clock-stop INIT request cross from CAN to BUS as events
  for (genvar gi_cmd = 0; gi_cmd < PARA_CANFD_CMD_W; gi_cmd++) begin : gen_cmd_level
    m_canfd_sync_bit #(
      .PARA_CANFD_CELL_TYPE (PARA_CANFD_CELL_TYPE)
    ) u_canfd_sync_bit_cmd (
      .i_clk_dst   (i_clk_can),
      .i_rst_n_dst (i_rst_n_can),
      .i_data      (w_cmd_bus_gated[gi_cmd]),
      .o_data      (o_cmd_can[gi_cmd])
    );
  end

  // The clock stop request reaches CAN and its acknowledge returns to BUS as levels.
  m_canfd_sync_bit #(
    .PARA_CANFD_CELL_TYPE (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_bit_stop_req (
    .i_clk_dst   (i_clk_can),
    .i_rst_n_dst (i_rst_n_can),
    .i_data      (i_clk_stop_req_bus),
    .o_data      (o_clk_stop_req_can)
  );

  m_canfd_sync_bit #(
    .PARA_CANFD_CELL_TYPE (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_bit_stop_ack (
    .i_clk_dst   (i_clk_bus),
    .i_rst_n_dst (i_rst_n_bus),
    .i_data      (i_clk_stop_ack_can),
    .o_data      (o_clk_stop_ack_bus)
  );

  // Done pulses of the commands and the clock-stop INIT request cross from CAN to BUS as events.
  assign w_cmd_done_can_gated = i_cdc_ready_can ? i_cmd_done_can : '0;
  assign w_init_set_stop_can_gated = i_cdc_ready_can && i_init_set_stop_can;

  m_vlsit_event_sync #(
    .PARA_EVENT_SYNC_W         (LPARA_CMD_DONE_W),
    .PARA_EVENT_SYNC_CELL_TYPE (LPARA_EVENT_CELL_TYPE)
  ) u_vlsit_event_sync_5 (
    .i_clk_src   (i_clk_can),
    .i_rst_n_src (i_rst_n_can),
    .i_clk_dst   (i_clk_bus),
    .i_rst_n_dst (i_rst_n_bus),
    .i_event_src (w_cmd_done_can_gated),
    .o_event_dst (o_cmd_done_bus)
  );

  m_vlsit_event_sync #(
    .PARA_EVENT_SYNC_W         (32'd1),
    .PARA_EVENT_SYNC_CELL_TYPE (LPARA_EVENT_CELL_TYPE)
  ) u_vlsit_event_sync_6 (
    .i_clk_src   (i_clk_can),
    .i_rst_n_src (i_rst_n_can),
    .i_clk_dst   (i_clk_bus),
    .i_rst_n_dst (i_rst_n_bus),
    .i_event_src (w_init_set_stop_can_gated),
    .o_event_dst (o_init_set_stop_bus)
  );

  // Safety fault pulses of the CAN domain and the Rx handoff overrun cross as events.
  assign w_fault_event_can_gated = i_cdc_ready_can ? i_fault_event_can : '0;
  assign w_rx_overflow_can_gated = i_cdc_ready_can && w_afifo_overflow;

  m_vlsit_event_sync #(
    .PARA_EVENT_SYNC_W         (LPARA_FAULT_W),
    .PARA_EVENT_SYNC_CELL_TYPE (LPARA_EVENT_CELL_TYPE)
  ) u_vlsit_event_sync_7 (
    .i_clk_src   (i_clk_can),
    .i_rst_n_src (i_rst_n_can),
    .i_clk_dst   (i_clk_bus),
    .i_rst_n_dst (i_rst_n_bus),
    .i_event_src (w_fault_event_can_gated),
    .o_event_dst (o_fault_event_can_bus)
  );

  m_vlsit_event_sync #(
    .PARA_EVENT_SYNC_W         (32'd1),
    .PARA_EVENT_SYNC_CELL_TYPE (LPARA_EVENT_CELL_TYPE)
  ) u_vlsit_event_sync_8 (
    .i_clk_src   (i_clk_can),
    .i_rst_n_src (i_rst_n_can),
    .i_clk_dst   (i_clk_bus),
    .i_rst_n_dst (i_rst_n_bus),
    .i_event_src (w_rx_overflow_can_gated),
    .o_event_dst (o_rx_overflow_bus)
  );

  // The Rx buffer new-data pulses of the BUS handler cross to the CAN domain as events.
  assign w_rxb_set_bus_gated = i_cdc_ready_bus ? i_rxb_set_bus : '0;

  m_vlsit_event_sync #(
    .PARA_EVENT_SYNC_W         (LPARA_RXB_W),
    .PARA_EVENT_SYNC_CELL_TYPE (LPARA_EVENT_CELL_TYPE)
  ) u_vlsit_event_sync_9 (
    .i_clk_src   (i_clk_bus),
    .i_rst_n_src (i_rst_n_bus),
    .i_clk_dst   (i_clk_can),
    .i_rst_n_dst (i_rst_n_can),
    .i_event_src (w_rxb_set_bus_gated),
    .o_event_dst (o_rxb_set_can)
  );

  // Capture the preset on the SGT command edge and hold it until CDC accepts the bundle.
  // The CSR command remains asserted until TT applies the preset and clears it through CDC-007.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_tt_sgt_src
    if (!i_rst_n_bus) begin
      reg_tt_sgt_cmd_bus_d <= 1'b0;
      reg_tt_sgt_pending_bus <= 1'b0;
      reg_tt_gpre_hold_bus <= '0;
    end else if (!i_cdc_ready_bus) begin
      reg_tt_sgt_cmd_bus_d <= 1'b0;
      reg_tt_sgt_pending_bus <= 1'b0;
      reg_tt_gpre_hold_bus <= '0;
    end else begin
      reg_tt_sgt_cmd_bus_d <= i_tt_sgt_cmd_bus;
      if (i_tt_sgt_cmd_bus && !reg_tt_sgt_cmd_bus_d && !reg_tt_sgt_pending_bus) begin
        reg_tt_sgt_pending_bus <= 1'b1;
        reg_tt_gpre_hold_bus <= i_tt_gpre_bus;
      end else if (reg_tt_sgt_pending_bus && w_tt_sgt_hsk_ready_bus) begin
        reg_tt_sgt_pending_bus <= 1'b0;
      end
    end
  end

  // Deliver the command only with its complete, stable preset value.
  m_canfd_sync_hsk #(
    .PARA_CANFD_DATA_W     (LPARA_TT_GPRE_W),
    .PARA_CANFD_CELL_TYPE  (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_hsk_6 (
    .i_clk_src        (i_clk_bus),
    .i_rst_n_src      (i_rst_n_bus),
    .i_cdc_ready_src  (i_cdc_ready_bus),
    .i_valid_src      (reg_tt_sgt_pending_bus),
    .o_ready_src      (w_tt_sgt_hsk_ready_bus),
    .i_data_src       (reg_tt_gpre_hold_bus),
    .i_clk_dst        (i_clk_can),
    .i_rst_n_dst      (i_rst_n_can),
    .i_cdc_ready_dst  (i_cdc_ready_can),
    .o_valid_dst      (w_tt_sgt_hsk_valid_can),
    .i_ready_dst      (1'b1),
    .o_data_dst       (w_tt_gpre_hsk_can)
  );

  // Present the command pulse and its matching stable preset as one CAN-domain transfer.
  assign o_tt_sgt_cmd_can = w_tt_sgt_hsk_valid_can;
  assign o_tt_gpre_can = w_tt_gpre_hsk_can;

  // Accumulate distinct miss bits while a prior bitmap update crosses to CLK-BUS.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_tt_miss_pending_can
    if (!i_rst_n_can) begin
      reg_tt_miss_pending_can <= '0;
    end else if (!i_cdc_ready_can) begin
      reg_tt_miss_pending_can <= '0;
    end else if (w_tt_miss_hsk_ready_can && (|reg_tt_miss_pending_can)) begin
      reg_tt_miss_pending_can <= {i_ttr_miss_set_can, i_ttb_miss_set_can};
    end else begin
      reg_tt_miss_pending_can <= reg_tt_miss_pending_can |
                                 {i_ttr_miss_set_can, i_ttb_miss_set_can};
    end
  end

  // Transfer accumulated sticky-set masks atomically; the CSR consumes the update on valid.
  m_canfd_sync_hsk #(
    .PARA_CANFD_DATA_W     (LPARA_TT_MISS_W),
    .PARA_CANFD_CELL_TYPE  (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_hsk_7 (
    .i_clk_src        (i_clk_can),
    .i_rst_n_src      (i_rst_n_can),
    .i_cdc_ready_src  (i_cdc_ready_can),
    .i_valid_src      (|reg_tt_miss_pending_can),
    .o_ready_src      (w_tt_miss_hsk_ready_can),
    .i_data_src       (reg_tt_miss_pending_can),
    .i_clk_dst        (i_clk_bus),
    .i_rst_n_dst      (i_rst_n_bus),
    .i_cdc_ready_dst  (i_cdc_ready_bus),
    .o_valid_dst      (w_tt_miss_valid_bus),
    .i_ready_dst      (i_tt_miss_ready_bus),
    .o_data_dst       (w_tt_miss_data_bus)
  );

  // Expose the destination valid and its matching masks to the BUS-domain CSR load interface.
  assign o_tt_miss_valid_bus = w_tt_miss_valid_bus;
  assign {o_ttr_miss_set_bus, o_ttb_miss_set_bus} = w_tt_miss_data_bus;

  // Keep wake-up state high until the BUS acknowledge crosses back to CAN.
  m_canfd_sync_bit #(
    .PARA_CANFD_CELL_TYPE (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_bit_1 (
    .i_clk_dst   (i_clk_bus),
    .i_rst_n_dst (i_rst_n_bus),
    .i_data      (i_wake_can),
    .o_data      (o_wake_bus)
  );

  m_vlsit_event_sync #(
    .PARA_EVENT_SYNC_W         (32'd1),
    .PARA_EVENT_SYNC_CELL_TYPE (LPARA_EVENT_CELL_TYPE)
  ) u_vlsit_event_sync_2 (
    .i_clk_src   (i_clk_bus),
    .i_rst_n_src (i_rst_n_bus),
    .i_clk_dst   (i_clk_can),
    .i_rst_n_dst (i_rst_n_can),
    .i_event_src (w_wake_ack_bus_gated),
    .o_event_dst (o_wake_ack_can)
  );

  // Transfer one full trigger word address to BUS; hold the request until its RAM read completes.
  m_canfd_sync_hsk #(
    .PARA_CANFD_DATA_W     (LPARA_TT_RAM_REQ_W),
    .PARA_CANFD_CELL_TYPE  (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_hsk_4 (
    .i_clk_src        (i_clk_can),
    .i_rst_n_src      (i_rst_n_can),
    .i_cdc_ready_src  (i_cdc_ready_can),
    .i_valid_src      (i_tt_ram_req_can),
    .o_ready_src      (o_tt_ram_req_ready_can),
    .i_data_src       (i_tt_ram_addr_can),
    .i_clk_dst        (i_clk_bus),
    .i_rst_n_dst      (i_rst_n_bus),
    .i_cdc_ready_dst  (i_cdc_ready_bus),
    .o_valid_dst      (w_tt_ram_req_valid_bus),
    .i_ready_dst      (w_tt_ram_req_ready_bus),
    .o_data_dst       (w_tt_ram_req_bus)
  );

  // Present the stable request to Message-RAM and retire it only on its matching acknowledge.
  assign o_tt_ram_req_bus = w_tt_ram_req_valid_bus;
  assign o_tt_ram_addr_bus = w_tt_ram_req_bus;
  assign w_tt_ram_req_ready_bus = w_tt_ram_req_valid_bus && i_tt_ram_ack_bus;

  // Capture the response at the BUS-side acknowledge, then hold it through the return handshake.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_tt_ram_rsp_bus
    if (!i_rst_n_bus) begin
      reg_tt_ram_rsp_bus       <= '0;
      reg_tt_ram_rsp_valid_bus <= 1'b0;
    end else if (!i_cdc_ready_bus) begin
      reg_tt_ram_rsp_bus       <= '0;
      reg_tt_ram_rsp_valid_bus <= 1'b0;
    end else begin
      if (reg_tt_ram_rsp_valid_bus && w_tt_ram_rsp_ready_bus)
        reg_tt_ram_rsp_valid_bus <= 1'b0;
      if (w_tt_ram_req_ready_bus) begin
        reg_tt_ram_rsp_bus       <= {i_tt_ram_err_unc_bus,
                                     i_tt_ram_err_cor_bus,
                                     i_tt_ram_err_bus,
                                     i_tt_ram_rdata_bus};
        reg_tt_ram_rsp_valid_bus <= 1'b1;
      end
    end
  end

  // Return the captured data and all error qualifiers as one atomic CAN-domain record.
  m_canfd_sync_hsk #(
    .PARA_CANFD_DATA_W     (LPARA_TT_RAM_RSP_W),
    .PARA_CANFD_CELL_TYPE  (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_hsk_5 (
    .i_clk_src        (i_clk_bus),
    .i_rst_n_src      (i_rst_n_bus),
    .i_cdc_ready_src  (i_cdc_ready_bus),
    .i_valid_src      (reg_tt_ram_rsp_valid_bus),
    .o_ready_src      (w_tt_ram_rsp_ready_bus),
    .i_data_src       (reg_tt_ram_rsp_bus),
    .i_clk_dst        (i_clk_can),
    .i_rst_n_dst      (i_rst_n_can),
    .i_cdc_ready_dst  (i_cdc_ready_can),
    .o_valid_dst      (o_tt_ram_rsp_valid_can),
    .i_ready_dst      (i_tt_ram_rsp_ready_can),
    .o_data_dst       (w_tt_ram_rsp_can)
  );

  // Expose the returned error qualifiers and data from the same captured response word.
  assign {o_tt_ram_err_unc_can,
          o_tt_ram_err_cor_can,
          o_tt_ram_err_can,
          o_tt_ram_rdata_can} = w_tt_ram_rsp_can;

endmodule
