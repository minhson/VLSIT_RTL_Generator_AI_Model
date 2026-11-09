/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-08
 * Description  : CAN/BUS clock-domain crossing hub. It snapshots quasi-static configuration,
 *                transfers stable status and frame bundles, moves CAN events and BUS commands,
 *                and buffers completed Rx frames in the shared Gray-pointer asynchronous FIFO.
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
  // Shared CAN/BUS record has four metadata words; both directions place payload at word 4.
  localparam logic [31:0] LPARA_CANFD_RXW = 32'd4 + (PARA_CANFD_DATA_MAX / 32'd4),
  localparam logic [31:0] LPARA_CANFD_FRAME_W = LPARA_CANFD_RXW * 32'd32,
  localparam logic [31:0] LPARA_AFIFO_ADDR_W = $clog2(PARA_CANFD_RXHOLD_DEPTH),
  localparam logic [31:0] LPARA_AFIFO_PTR_W = LPARA_AFIFO_ADDR_W + 32'd1,
  localparam logic [31:0] LPARA_AFIFO_FULL_THR = PARA_CANFD_RXHOLD_DEPTH,
  localparam logic [31:0] LPARA_AFIFO_EMPTY_THR = 32'd1,
  localparam logic [31:0] LPARA_AFIFO_CELL_TYPE = 32'd1,
  localparam logic [31:0] LPARA_EVENT_CELL_TYPE_DFF2 = 32'd1,
  localparam logic [31:0] LPARA_EVENT_CELL_TYPE_2FF = 32'd2,
  localparam logic [31:0] LPARA_EVENT_CELL_TYPE = (PARA_CANFD_CELL_TYPE == 32'd1) ?
                                                     LPARA_EVENT_CELL_TYPE_2FF : LPARA_EVENT_CELL_TYPE_DFF2,
  localparam logic [31:0] LPARA_AFIFO_RST_N_INACTIVE = 32'd1
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
  output logic                           o_tx_frame_valid_can,
  input  wire                            i_tx_frame_ready_can,
  output logic [LPARA_CANFD_FRAME_W-1:0] o_tx_frame_can,

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
  input  wire  [PARA_CANFD_PNF_W-1:0]    i_pnf_bus,
  output logic                           o_pnf_valid_can,
  input  wire                            i_pnf_ready_can,
  output logic [PARA_CANFD_PNF_W-1:0]    o_pnf_can,

  // Event pulses from CAN to BUS and commands from BUS to CAN
  input  wire  [PARA_CANFD_EVENT_W-1:0]  i_event_can,
  output logic [PARA_CANFD_EVENT_W-1:0]  o_event_bus,
  input  wire  [PARA_CANFD_CMD_W-1:0]    i_cmd_bus,
  output logic [PARA_CANFD_CMD_W-1:0]    o_cmd_can,

  // Wake-up request held in CAN until the synchronized BUS acknowledge arrives
  input  wire                            i_wake_can,
  output logic                           o_wake_bus,
  input  wire                            i_wake_ack_bus,
  output logic                           o_wake_ack_can
);

  logic w_init_can_sync;
  logic reg_init_can_d;
  logic [PARA_CANFD_CFG_W-1:0] reg_cfg_can;
  logic w_afifo_full;
  logic w_afifo_full_thr;
  logic w_afifo_empty;
  logic w_afifo_empty_thr;
  logic w_afifo_sw_rst_busy;
  logic w_afifo_sw_rst_busy_bus;
  logic [LPARA_CANFD_FRAME_W-1:0] w_afifo_rd_data;
  logic w_afifo_overflow;
  logic w_afifo_underflow;
  logic w_rx_frame_wr_en;
  logic w_rx_frame_rd_en;
  logic [PARA_CANFD_EVENT_W-1:0] w_event_can_gated;
  logic [PARA_CANFD_CMD_W-1:0] w_cmd_bus_gated;
  logic w_wake_ack_bus_gated;

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
    end else if (i_cdc_ready_can) begin
      reg_init_can_d <= w_init_can_sync;
      if (w_init_can_sync != reg_init_can_d)
        reg_cfg_can <= i_cfg_bus;
    end
  end

  // Expose the synchronized mode and its stable configuration snapshot to the CAN blocks.
  assign o_init_can = w_init_can_sync;
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

  // Transfer the bus-side Tx frame using a held bundle and a four-phase handshake.
  m_canfd_sync_hsk #(
    .PARA_CANFD_DATA_W     (LPARA_CANFD_FRAME_W),
    .PARA_CANFD_CELL_TYPE  (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_hsk_0 (
    .i_clk_src        (i_clk_bus),
    .i_rst_n_src      (i_rst_n_bus),
    .i_cdc_ready_src  (i_cdc_ready_bus),
    .i_valid_src      (i_tx_frame_valid_bus),
    .o_ready_src      (o_tx_frame_ready_bus),
    .i_data_src       (i_tx_frame_bus),
    .i_clk_dst        (i_clk_can),
    .i_rst_n_dst      (i_rst_n_can),
    .i_cdc_ready_dst  (i_cdc_ready_can),
    .o_valid_dst      (o_tx_frame_valid_can),
    .i_ready_dst      (i_tx_frame_ready_can),
    .o_data_dst       (o_tx_frame_can)
  );

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

  // Transfer software filter updates as complete bundles before replacing the CAN copy.
  m_canfd_sync_hsk #(
    .PARA_CANFD_DATA_W     (PARA_CANFD_PNF_W),
    .PARA_CANFD_CELL_TYPE  (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_hsk_2 (
    .i_clk_src        (i_clk_bus),
    .i_rst_n_src      (i_rst_n_bus),
    .i_cdc_ready_src  (i_cdc_ready_bus),
    .i_valid_src      (i_pnf_valid_bus),
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

  m_vlsit_event_sync #(
    .PARA_EVENT_SYNC_W         (PARA_CANFD_CMD_W),
    .PARA_EVENT_SYNC_CELL_TYPE (LPARA_EVENT_CELL_TYPE)
  ) u_vlsit_event_sync_1 (
    .i_clk_src   (i_clk_bus),
    .i_rst_n_src (i_rst_n_bus),
    .i_clk_dst   (i_clk_can),
    .i_rst_n_dst (i_rst_n_can),
    .i_event_src (w_cmd_bus_gated),
    .o_event_dst (o_cmd_can)
  );

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

endmodule
