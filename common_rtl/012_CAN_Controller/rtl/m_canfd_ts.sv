/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-09
 * Description  : Implements the CAN-clock timestamp counter and SOF captures plus the
 *                BUS-clock timeout counter selected by Rx FIFO or Tx-event activity.
 * DEC IDs      : DEC-068, DEC-089
 */
`timescale 1ns/1ps

module m_canfd_ts #(
  // Parameter Description: implemented timestamp counter width.
  // Parameter values: 16 or 32; default is 32.
  // Parameter unit: bit
  parameter logic [31:0] PARA_CANFD_TS_W = 32'd32,
  // Parameter Description: include the timestamp counter in this build.
  // Parameter values: 0 = disabled, 1 = enabled; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_TS_EN = 32'd1,
  // Parameter Description: allow the external timestamp source selection.
  // Parameter values: 0 = disabled, 1 = enabled; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_TS_EXT_EN = 32'd0,
  // Parameter Description: include the BUS timeout counter.
  // Parameter values: 0 = disabled, 1 = enabled; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_TOUT_EN = 32'd1,
  localparam logic [31:0] LPARA_CANFD_TS_W_EFF =
    (PARA_CANFD_TS_EN == 32'd1) ? PARA_CANFD_TS_W : 32'd1,
  localparam logic [31:0] LPARA_TIMEOUT_CONT = 32'd0,
  localparam logic [31:0] LPARA_TIMEOUT_RX0 = 32'd1,
  localparam logic [31:0] LPARA_TIMEOUT_TXE = 32'd2,
  localparam logic [31:0] LPARA_TIMEOUT_RX1 = 32'd3
) (
  // CAN timestamp clock and reset
  input  wire         i_clk_can,
  input  wire         i_rst_n_can,

  // Timestamp configuration and sample-point events
  input  wire         i_ts_enable,
  input  wire  [3:0]  i_ts_pres,
  input  wire  [1:0]  i_ts_sel,
  input  wire  [31:0] i_ts_ext,
  input  wire         i_rx_sof_sample,
  input  wire         i_tx_sof_sample,
  output logic [31:0] o_ts_count,
  output logic [31:0] o_rx_timestamp,
  output logic [31:0] o_tx_timestamp,
  output logic        o_ts_wrap_event,

  // BUS timeout clock and reset
  input  wire         i_clk_bus,
  input  wire         i_rst_n_bus,
  input  wire         i_soft_reset,

  // Timeout configuration and restart sources
  input  wire         i_tout_on,
  input  wire  [1:0]  i_tout_sel,
  input  wire  [15:0] i_tout_period,
  input  wire         i_rx0_new,
  input  wire         i_rx1_new,
  input  wire         i_txe_new,
  output logic [15:0] o_tout_count,
  output logic        o_tout_event
);

  logic [LPARA_CANFD_TS_W_EFF-1:0] reg_ts_count;
  logic [3:0] reg_ts_div;
  logic [31:0] reg_rx_timestamp;
  logic [31:0] reg_tx_timestamp;
  logic reg_ts_wrap_event;
  logic [15:0] reg_tout_count;
  logic reg_tout_event;
  logic [31:0] w_ts_selected;
  logic w_tout_restart;
  logic [15:0] w_tout_reload;

  assign o_rx_timestamp = reg_rx_timestamp;
  assign o_tx_timestamp = reg_tx_timestamp;
  assign o_ts_wrap_event = reg_ts_wrap_event;
  assign o_tout_count = reg_tout_count;
  assign o_tout_event = reg_tout_event;

  // Select the internal counter or the optional external vector for SOF capture.
  always_comb begin : p_com_timestamp_source
    w_ts_selected = 32'd0;
    if (PARA_CANFD_TS_EN == 32'd1) begin
      if ((i_ts_sel == 2'd1) && (PARA_CANFD_TS_EXT_EN == 32'd1))
        w_ts_selected = i_ts_ext;
      else
        w_ts_selected = 32'(reg_ts_count);
    end
  end

  assign o_ts_count = w_ts_selected;
  assign w_tout_reload = (i_tout_period == 16'd0) ? 16'd1 : i_tout_period;
  assign w_tout_restart = ((i_tout_sel == 2'(LPARA_TIMEOUT_RX0)) && i_rx0_new) ||
                           ((i_tout_sel == 2'(LPARA_TIMEOUT_TXE)) && i_txe_new) ||
                           ((i_tout_sel == 2'(LPARA_TIMEOUT_RX1)) && i_rx1_new);

  // Advance the free-running timestamp and capture it at the SOF sample point.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_timestamp
    if (!i_rst_n_can) begin
      reg_ts_count <= '0;
      reg_ts_div <= '0;
      reg_rx_timestamp <= '0;
      reg_tx_timestamp <= '0;
      reg_ts_wrap_event <= 1'b0;
    end else begin
      reg_ts_wrap_event <= 1'b0;
      if (i_rx_sof_sample)
        reg_rx_timestamp <= w_ts_selected;
      if (i_tx_sof_sample)
        reg_tx_timestamp <= w_ts_selected;
      if ((PARA_CANFD_TS_EN == 32'd1) && i_ts_enable && (i_ts_sel != 2'd1)) begin
        if (reg_ts_div >= i_ts_pres) begin
          reg_ts_div <= '0;
          if (&reg_ts_count)
            reg_ts_wrap_event <= 1'b1;
          reg_ts_count <= reg_ts_count + 1'b1;
        end else begin
          reg_ts_div <= reg_ts_div + 4'd1;
        end
      end else begin
        reg_ts_div <= '0;
      end
    end
  end

  // The continuous mode reloads at zero; event modes restart on the selected FIFO activity.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_timeout
    if (!i_rst_n_bus) begin
      reg_tout_count <= '0;
      reg_tout_event <= 1'b0;
    end else if (i_soft_reset) begin
      reg_tout_count <= '0;
      reg_tout_event <= 1'b0;
    end else begin
      reg_tout_event <= 1'b0;
      casez (1'b1)
        ((PARA_CANFD_TOUT_EN != 32'd1) || !i_tout_on): begin
          reg_tout_count <= '0;
        end
        ((i_tout_sel == 2'(LPARA_TIMEOUT_CONT))): begin
          if (reg_tout_count <= 16'd1) begin
            reg_tout_count <= w_tout_reload;
            reg_tout_event <= 1'b1;
          end else begin
            reg_tout_count <= reg_tout_count - 16'd1;
          end
        end
        (w_tout_restart): begin
          reg_tout_count <= w_tout_reload;
        end
        (reg_tout_count != 16'd0): begin
          reg_tout_count <= reg_tout_count - 16'd1;
          if (reg_tout_count == 16'd1)
            reg_tout_event <= 1'b1;
        end
        default: begin
          reg_tout_count <= reg_tout_count;
        end
      endcase
    end
  end

endmodule
