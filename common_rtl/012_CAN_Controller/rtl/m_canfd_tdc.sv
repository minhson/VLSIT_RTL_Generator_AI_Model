/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-08
 * Description  : Measures the CAN-FD transmitter loop delay, delays eligible Tx-bit
 *                points to the secondary sample point, and reports Tx bit errors.
 */
`timescale 1ns/1ps

module m_canfd_tdc #(
  localparam logic [31:0] LPARA_TDC_TDCO_MIN = 32'd1,
  localparam logic [31:0] LPARA_TDC_TDCO_MAX = 32'd160,
  localparam logic [31:0] LPARA_TDC_TIMEOUT_PREV = 32'd126,
  localparam logic [31:0] LPARA_TDC_TIMEOUT_MAX = 32'd127,
  localparam logic [31:0] LPARA_TDC_HIST_MAX_TQ = 32'd287
) (
  // CAN clock and reset
  input  wire        i_clk_can,
  input  wire        i_rst_n_can,

  // BTL minimum-tq timebase and primary sample point
  input  wire        i_min_tq_tick,
  input  wire        i_sample,
  input  wire        i_rx_sync,

  // Transmit bit boundary and frame-qualified TDC controls
  input  wire        i_tx_point,
  input  wire        i_tx_bit,
  input  wire        i_tdc_frame_active,
  input  wire        i_tdc_measure_start,

  // TDC configuration from the CAN-domain snapshot
  input  wire  [7:0] i_cfd_tdc_tdco,
  input  wire  [6:0] i_cfd_tdc_tdcf,

  // TDC status and error events
  output logic       o_tdc_active,
  output logic       o_tdc_bit_err,
  output logic       o_tdc_timeout,
  output logic [6:0] o_tdcv
);

  logic [286:0] reg_tx_point_hist;
  logic [286:0] reg_tx_bit_hist;
  logic reg_tdc_measure_active;
  logic reg_tdc_measure_done;
  logic reg_tdc_rx_armed;
  logic [6:0] reg_tdc_measure_count;
  logic [6:0] reg_tdcv;
  logic reg_tdc_err_pending;
  logic reg_tdc_bit_err;
  logic reg_tdc_timeout;

  logic [8:0] w_tdc_delay_tq;
  logic [8:0] w_tdc_hist_idx;
  logic [8:0] w_tdcf_ext;
  logic [8:0] w_measure_count_at_tick;
  logic [8:0] w_measure_ssp_at_tick;
  logic w_tdc_delay_valid;
  logic w_tdc_filter_en;
  logic w_tdc_echo_qual;
  logic w_tx_point_qual;
  logic w_ssp_event;
  logic w_ssp_mismatch;

  // Calculate the total delay in a 9-bit expression to preserve the full legal sum.
  assign w_tdc_delay_tq = $bits(w_tdc_delay_tq)'(reg_tdcv) +
                          $bits(w_tdc_delay_tq)'(i_cfd_tdc_tdco);

  // Reject values outside the programmed range before indexing the history vector.
  assign w_tdc_delay_valid = (i_cfd_tdc_tdco >= LPARA_TDC_TDCO_MIN[7:0]) &&
                             (i_cfd_tdc_tdco <= LPARA_TDC_TDCO_MAX[7:0]) &&
                             (w_tdc_delay_tq >= LPARA_TDC_TDCO_MIN[8:0]) &&
                             (w_tdc_delay_tq <= LPARA_TDC_HIST_MAX_TQ[8:0]);

  // Select the history entry one minimum-tq interval before the due comparison tick.
  assign w_tdc_hist_idx = w_tdc_delay_valid ?
                          $bits(w_tdc_hist_idx)'(w_tdc_delay_tq - LPARA_TDC_TDCO_MIN[8:0]) : 9'd0;

  // Extend the filter threshold to match the measured delay arithmetic.
  assign w_tdcf_ext = $bits(w_tdcf_ext)'(i_cfd_tdc_tdcf);

  // Advance the provisional delay by one tq for a candidate sample on this tick.
  assign w_measure_count_at_tick = $bits(w_measure_count_at_tick)'(reg_tdc_measure_count) +
                                   LPARA_TDC_TDCO_MIN[8:0];

  // Add the configured offset to the current measurement count for the filter test.
  assign w_measure_ssp_at_tick = w_measure_count_at_tick +
                                 $bits(w_measure_ssp_at_tick)'(i_cfd_tdc_tdco);

  // Enable the product filter only when its minimum SSP threshold exceeds TDCO.
  assign w_tdc_filter_en = w_tdcf_ext > $bits(w_tdcf_ext)'(i_cfd_tdc_tdco);

  // Accept the echo level immediately without filtering, or after the filter threshold.
  assign w_tdc_echo_qual = reg_tdc_rx_armed && !i_rx_sync &&
                           (!w_tdc_filter_en || (w_measure_ssp_at_tick >= w_tdcf_ext));

  // Exclude control-phase transmit points from the delayed SSP checks.
  assign w_tx_point_qual = i_tx_point && i_tdc_frame_active;

  // Enable SSP checks only after a valid measurement and within the qualified data phase.
  assign o_tdc_active = i_tdc_frame_active && reg_tdc_measure_done && w_tdc_delay_valid;

  // A stored point tag schedules the compare at the configured delay tap.
  assign w_ssp_event = i_min_tq_tick && o_tdc_active && reg_tx_point_hist[w_tdc_hist_idx];

  // Compare the delayed Tx bit against synchronized Rx at the SSP.
  assign w_ssp_mismatch = w_ssp_event && (reg_tx_bit_hist[w_tdc_hist_idx] != i_rx_sync);
  assign o_tdcv = reg_tdcv;
  assign o_tdc_bit_err = reg_tdc_bit_err;
  assign o_tdc_timeout = reg_tdc_timeout;

  // Retain qualified Tx points and bits across the full legal SSP range.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_tdc_history
    if (!i_rst_n_can) begin
      reg_tx_point_hist <= '0;
      reg_tx_bit_hist <= '0;
    end else begin
      casez ({i_tdc_measure_start, i_min_tq_tick, i_tx_point})
        3'b1??: begin
          reg_tx_point_hist <= '0;
          reg_tx_bit_hist <= '0;
        end
        3'b01?: begin
          reg_tx_point_hist <= {reg_tx_point_hist[285:0], w_tx_point_qual};
          reg_tx_bit_hist <= {reg_tx_bit_hist[285:0], i_tx_bit};
        end
        3'b001: begin
          reg_tx_point_hist[0] <= w_tx_point_qual;
          reg_tx_bit_hist[0] <= i_tx_bit;
        end
        default: begin end
      endcase
    end
  end

  // Measure FDF-to-res loop delay; an echo on the 127th tq boundary takes priority over timeout.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_tdc_measure
    if (!i_rst_n_can) begin
      reg_tdc_measure_active <= 1'b0;
      reg_tdc_measure_done <= 1'b0;
      reg_tdc_rx_armed <= 1'b0;
      reg_tdc_measure_count <= 7'd0;
      reg_tdcv <= 7'd0;
      reg_tdc_timeout <= 1'b0;
    end else begin
      reg_tdc_timeout <= 1'b0;
      if (i_tdc_measure_start) begin
        reg_tdc_measure_active <= 1'b1;
        reg_tdc_measure_done <= 1'b0;
        reg_tdc_rx_armed <= i_rx_sync;
        reg_tdc_measure_count <= 7'd0;
      end else if (reg_tdc_measure_active && i_min_tq_tick) begin
        if (i_rx_sync)
          reg_tdc_rx_armed <= 1'b1;
        if (w_tdc_echo_qual) begin
          reg_tdc_measure_active <= 1'b0;
          reg_tdc_measure_done <= 1'b1;
          reg_tdc_measure_count <= $bits(reg_tdc_measure_count)'(w_measure_count_at_tick);
          reg_tdcv <= $bits(reg_tdcv)'(w_measure_count_at_tick);
        end else if (reg_tdc_measure_count == LPARA_TDC_TIMEOUT_PREV[6:0]) begin
          reg_tdc_measure_active <= 1'b0;
          reg_tdc_measure_done <= 1'b0;
          reg_tdc_measure_count <= LPARA_TDC_TIMEOUT_MAX[6:0];
          reg_tdc_timeout <= 1'b1;
        end else begin
          reg_tdc_measure_count <= $bits(reg_tdc_measure_count)'(w_measure_count_at_tick);
        end
      end
    end
  end

  // Functional role: report SSP mismatches at the next primary sample point.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_tdc_err
    if (!i_rst_n_can) begin
      reg_tdc_err_pending <= 1'b0;
      reg_tdc_bit_err <= 1'b0;
    end else begin
      reg_tdc_bit_err <= 1'b0;
      if (i_tdc_measure_start) begin
        reg_tdc_err_pending <= 1'b0;
      end else begin
        if (i_sample) begin
          if (reg_tdc_err_pending)
            reg_tdc_bit_err <= 1'b1;
          reg_tdc_err_pending <= 1'b0;
        end
        if (w_ssp_mismatch)
          reg_tdc_err_pending <= 1'b1;
      end
    end
  end

endmodule
