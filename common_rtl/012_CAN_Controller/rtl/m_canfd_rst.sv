/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-08
 * Description  : Generates independently synchronized CAN and BUS resets, withholds CDC readiness
 *                until both domains are ready and sequences the BUS-side soft reset after drain.
 */
`timescale 1ns/1ps

module m_canfd_rst #(
  // Parameter Description: synchronizer structure used for the peer-ready levels.
  // Parameter values: 0 = two discrete DFF stages; 1 = VLSIT 2-FF synchronizer cell; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_CELL_TYPE = 32'd0,
  localparam logic [31:0] LPARA_RST_SYNC_TYPE_2 = 32'd2,
  localparam logic [31:0] LPARA_SRESET_IDLE = 32'd0,
  localparam logic [31:0] LPARA_SRESET_DRAIN = 32'd1,
  localparam logic [31:0] LPARA_SRESET_PULSE = 32'd2
) (
  // CAN clock and reset domain
  input  wire  i_clk_can,
  input  wire  i_rst_n_can,
  output logic o_rst_n_can,
  output logic o_ready_can,

  // BUS clock and reset domain
  input  wire  i_clk_bus,
  input  wire  i_rst_n_bus,
  output logic o_rst_n_bus,
  output logic o_ready_bus,

  // BUS-domain software reset request and drain completion inputs
  input  wire  i_srst_req_bus,
  input  wire  i_rx_fifo_empty_bus,
  input  wire  i_tx_hsk_idle_bus,
  output logic o_soft_rst_busy_bus,
  output logic o_soft_rst_pulse_bus,
  output logic o_soft_rst_done_bus
);

  // Local reset release from the shared reset synchronizer.
  m_vlsit_rst_sync #(
    .PARA_RST_SYNC_TYPE (LPARA_RST_SYNC_TYPE_2)
  ) u_vlsit_rst_sync_0 (
    .i_clk_dst   (i_clk_can),
    .i_rst_n_src (i_rst_n_can),
    .o_rst_n_dst (o_rst_n_can)
  );

  m_vlsit_rst_sync #(
    .PARA_RST_SYNC_TYPE (LPARA_RST_SYNC_TYPE_2)
  ) u_vlsit_rst_sync_1 (
    .i_clk_dst   (i_clk_bus),
    .i_rst_n_src (i_rst_n_bus),
    .o_rst_n_dst (o_rst_n_bus)
  );

  logic w_ready_can_sync;
  logic w_ready_bus_sync;
  logic reg_ready_can_local;
  logic reg_ready_bus_local;
  logic reg_o_ready_can;
  logic reg_o_ready_bus;
  logic [1:0] reg_srst_state;

  // Cross the local readiness indications into the opposite clock domain.
  m_canfd_sync_bit #(
    .PARA_CANFD_CELL_TYPE (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_bit_0 (
    .i_clk_dst   (i_clk_can),
    .i_rst_n_dst (o_rst_n_can),
    .i_data      (reg_ready_bus_local),
    .o_data      (w_ready_bus_sync)
  );

  m_canfd_sync_bit #(
    .PARA_CANFD_CELL_TYPE (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_bit_1 (
    .i_clk_dst   (i_clk_bus),
    .i_rst_n_dst (o_rst_n_bus),
    .i_data      (reg_ready_can_local),
    .o_data      (w_ready_can_sync)
  );

  // Drive the externally visible readiness from registered local-domain state.
  assign o_ready_can = reg_o_ready_can;
  assign o_ready_bus = reg_o_ready_bus;
  assign o_soft_rst_busy_bus = (reg_srst_state != 2'(LPARA_SRESET_IDLE));
  assign o_soft_rst_pulse_bus = (reg_srst_state == 2'(LPARA_SRESET_PULSE));
  assign o_soft_rst_done_bus = (reg_srst_state == 2'(LPARA_SRESET_PULSE));

  // CAN readiness requires local reset release and synchronized BUS readiness.
  always_ff @(posedge i_clk_can, negedge o_rst_n_can) begin : p_ff_ready_can
    if (!o_rst_n_can) begin
      reg_ready_can_local <= 1'b0;
      reg_o_ready_can <= 1'b0;
    end else begin
      reg_ready_can_local <= 1'b1;
      reg_o_ready_can <= w_ready_bus_sync;
    end
  end

  // BUS readiness requires local reset release and synchronized CAN readiness.
  always_ff @(posedge i_clk_bus, negedge o_rst_n_bus) begin : p_ff_ready_bus
    if (!o_rst_n_bus) begin
      reg_ready_bus_local <= 1'b0;
      reg_o_ready_bus <= 1'b0;
    end else begin
      reg_ready_bus_local <= 1'b1;
      reg_o_ready_bus <= w_ready_can_sync;
    end
  end

  // Drain BUS-side work, pulse the selected handler reset, then return to the idle state.
  always_ff @(posedge i_clk_bus, negedge o_rst_n_bus) begin : p_ff_srst_fsm
    if (!o_rst_n_bus) begin
      reg_srst_state <= 2'(LPARA_SRESET_IDLE);
    end else begin
      casez (reg_srst_state)
        2'(LPARA_SRESET_IDLE): begin
          if (i_srst_req_bus)
            reg_srst_state <= 2'(LPARA_SRESET_DRAIN);
        end
        2'(LPARA_SRESET_DRAIN): begin
          if (i_rx_fifo_empty_bus && i_tx_hsk_idle_bus)
            reg_srst_state <= 2'(LPARA_SRESET_PULSE);
        end
        2'(LPARA_SRESET_PULSE): begin
          reg_srst_state <= 2'(LPARA_SRESET_IDLE);
        end
        default: begin
          reg_srst_state <= 2'(LPARA_SRESET_IDLE);
        end
      endcase
    end
  end

endmodule


