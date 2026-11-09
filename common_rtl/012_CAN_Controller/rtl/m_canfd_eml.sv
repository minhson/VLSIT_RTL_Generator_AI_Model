/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-08
 * Description  : CAN fault-confinement counters, error-state flags, bus-off recovery counter,
 *                and last-error-code storage for the arbitration and data phases.
 */
`timescale 1ns/1ps

module m_canfd_eml #(
  // Parameter Description: enable a separate counter mirror for safety comparison.
  // Parameter values: 0 = disabled, 1 = enabled; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_SAF_CNT_EN = 32'd0,
  localparam logic [31:0] LPARA_TEC_WARN = 32'd96,
  localparam logic [31:0] LPARA_TEC_PASSIVE = 32'd128,
  localparam logic [31:0] LPARA_TEC_BUS_OFF = 32'd256,
  localparam logic [31:0] LPARA_REC_PASSIVE = 32'd128,
  localparam logic [31:0] LPARA_REC_MAX = 32'd255,
  localparam logic [31:0] LPARA_REC_MIN = 32'd128,
  localparam logic [31:0] LPARA_REC_MAX_BEFORE_PLUS8 = 32'd247,
  localparam logic [31:0] LPARA_TEC_PLUS8_THR = 32'd249,
  localparam logic [31:0] LPARA_CNT_STEP = 32'd8,
  localparam logic [31:0] LPARA_CNT_ONE = 32'd1
) (
  // CAN clock and reset
  input  wire        i_clk_can,
  input  wire        i_rst_n_can,

  // Error-counter events from the frame engine
  input  wire        i_evt_rx_err,
  input  wire        i_evt_rx_dom_after_flag,
  input  wire        i_evt_tx_err_count,
  input  wire        i_evt_tx_bit_err_flag,
  input  wire        i_evt_rx_bit_err_flag,
  input  wire        i_evt_tx_dom_seq8,
  input  wire        i_evt_rx_dom_seq8,
  input  wire        i_evt_tx_success,
  input  wire        i_evt_rx_success,

  // Bus-off restart request and eleven-recessive-bit recovery event
  input  wire  [7:0] i_bo_cnt,
  input  wire        i_restart_req,
  input  wire        i_evt_idle11,

  // First error code of a frame, split by protocol phase
  input  wire        i_err_start,
  input  wire        i_err_phase_data,
  input  wire  [2:0] i_err_code,

  // Counter, state, recovery and diagnostic outputs
  output logic [8:0] o_tec,
  output logic [7:0] o_rec,
  output logic       o_err_warning,
  output logic       o_err_passive,
  output logic       o_bus_off,
  output logic [7:0] o_recovery_count,
  output logic       o_recovery_done,
  output logic       o_cfg_fix_event,
  output logic [2:0] o_lec,
  output logic [2:0] o_dlec,
  output logic       o_saf_fault
);

  logic [8:0] reg_tec;
  logic [7:0] reg_rec;
  logic [8:0] w_tec_nxt;
  logic [7:0] w_rec_nxt;
  logic [7:0] reg_recovery_count;
  logic reg_recovery_active;
  logic reg_recovery_done;
  logic [2:0] reg_lec;
  logic [2:0] reg_dlec;
  logic [7:0] w_recovery_limit;
  logic w_tx_err_event;
  logic w_rx_err_event;
  logic w_recover_now;

  // Apply counter updates in the protocol-table order and saturate at their maxima.
  always_comb begin : p_com_cnt_nxt
    w_tec_nxt = reg_tec;
    w_rec_nxt = reg_rec;

    if (i_evt_rx_err && (w_rec_nxt < 8'(LPARA_REC_MAX)))
      w_rec_nxt = $bits(w_rec_nxt)'(w_rec_nxt + 8'd1);
    if (i_evt_rx_dom_after_flag) begin
      if (w_rec_nxt > 8'(LPARA_REC_MAX_BEFORE_PLUS8))
        w_rec_nxt = 8'(LPARA_REC_MAX);
      else
        w_rec_nxt = $bits(w_rec_nxt)'(w_rec_nxt + 8'(LPARA_CNT_STEP));
    end

    if (i_evt_tx_err_count) begin
      if (w_tec_nxt >= 9'(LPARA_TEC_PLUS8_THR))
        w_tec_nxt = 9'(LPARA_TEC_BUS_OFF);
      else
        w_tec_nxt = $bits(w_tec_nxt)'(w_tec_nxt + 9'(LPARA_CNT_STEP));
    end
    if (i_evt_tx_bit_err_flag) begin
      if (w_tec_nxt >= 9'(LPARA_TEC_PLUS8_THR))
        w_tec_nxt = 9'(LPARA_TEC_BUS_OFF);
      else
        w_tec_nxt = $bits(w_tec_nxt)'(w_tec_nxt + 9'(LPARA_CNT_STEP));
    end
    if (i_evt_rx_bit_err_flag) begin
      if (w_rec_nxt > 8'(LPARA_REC_MAX_BEFORE_PLUS8))
        w_rec_nxt = 8'(LPARA_REC_MAX);
      else
        w_rec_nxt = $bits(w_rec_nxt)'(w_rec_nxt + 8'(LPARA_CNT_STEP));
    end
    if (i_evt_tx_dom_seq8) begin
      if (w_tec_nxt >= 9'(LPARA_TEC_PLUS8_THR))
        w_tec_nxt = 9'(LPARA_TEC_BUS_OFF);
      else
        w_tec_nxt = $bits(w_tec_nxt)'(w_tec_nxt + 9'(LPARA_CNT_STEP));
    end
    if (i_evt_rx_dom_seq8) begin
      if (w_rec_nxt > 8'(LPARA_REC_MAX_BEFORE_PLUS8))
        w_rec_nxt = 8'(LPARA_REC_MAX);
      else
        w_rec_nxt = $bits(w_rec_nxt)'(w_rec_nxt + 8'(LPARA_CNT_STEP));
    end

    if (i_evt_tx_success && !w_tx_err_event && (w_tec_nxt != 9'd0))
      w_tec_nxt = $bits(w_tec_nxt)'(w_tec_nxt - 9'd1);
    if (i_evt_rx_success && !w_rx_err_event) begin
      if (w_rec_nxt > 8'(LPARA_REC_PASSIVE - 32'd1))
        w_rec_nxt = 8'(LPARA_REC_PASSIVE - 32'd1);
      else if (w_rec_nxt != 8'd0)
        w_rec_nxt = $bits(w_rec_nxt)'(w_rec_nxt - 8'd1);
    end
  end

  // Qualify success events so a failed frame cannot also decrement its error counter.
  assign w_tx_err_event = i_evt_tx_err_count || i_evt_tx_bit_err_flag || i_evt_tx_dom_seq8;
  assign w_rx_err_event = i_evt_rx_err || i_evt_rx_dom_after_flag ||
                          i_evt_rx_bit_err_flag || i_evt_rx_dom_seq8;

  // Clamp the software bus-off recovery setting and detect its required correction event.
  assign w_recovery_limit = (i_bo_cnt < 8'(LPARA_REC_MIN)) ? 8'(LPARA_REC_MIN) : i_bo_cnt;
  assign w_recover_now = reg_recovery_active && i_evt_idle11 &&
                         (reg_recovery_count == $bits(reg_recovery_count)'(w_recovery_limit - 8'(LPARA_CNT_ONE)));

  // Update live counters, including the successful recovery clear at the final idle occurrence.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_cnt
    if (!i_rst_n_can) begin
      reg_tec <= 9'd0;
      reg_rec <= 8'd0;
    end else if (w_recover_now) begin
      reg_tec <= 9'd0;
      reg_rec <= 8'd0;
    end else begin
      reg_tec <= w_tec_nxt;
      reg_rec <= w_rec_nxt;
    end
  end

  // Count bus-off recovery occurrences and retain the first error code of each phase.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_sts
    if (!i_rst_n_can) begin
      reg_recovery_count  <= 8'd0;
      reg_recovery_active <= 1'b0;
      reg_recovery_done   <= 1'b0;
      reg_lec             <= 3'd0;
      reg_dlec            <= 3'd0;
    end else begin
      reg_recovery_done <= 1'b0;
      casez ({(i_restart_req && o_bus_off), w_recover_now, (reg_recovery_active && i_evt_idle11)})
        3'b1??: begin
          reg_recovery_count  <= 8'd0;
          reg_recovery_active <= 1'b1;
        end
        3'b01?: begin
          reg_recovery_count  <= 8'd0;
          reg_recovery_active <= 1'b0;
          reg_recovery_done   <= 1'b1;
        end
        3'b001: begin
          reg_recovery_count <= $bits(reg_recovery_count)'(reg_recovery_count + 8'(LPARA_CNT_ONE));
        end
        default: begin
          reg_recovery_count  <= reg_recovery_count;
          reg_recovery_active <= reg_recovery_active;
        end
      endcase

      if (i_err_start) begin
        if (i_err_phase_data)
          reg_dlec <= i_err_code;
        else
          reg_lec <= i_err_code;
      end
    end
  end

  // Expose the current fault-confinement state and the effective recovery configuration.
  assign o_tec = reg_tec;
  assign o_rec = reg_rec;
  assign o_recovery_done = reg_recovery_done;
  assign o_lec = reg_lec;
  assign o_dlec = reg_dlec;

  // Derive the warning and passive states from their protocol thresholds.
  assign o_err_warning = (reg_tec >= 9'(LPARA_TEC_WARN)) ||
                         (reg_rec >= 8'(LPARA_TEC_WARN));

  // Raise the passive state at the configured counter limits.
  assign o_err_passive = (reg_tec >= 9'(LPARA_TEC_PASSIVE)) ||
                         (reg_rec >= 8'(LPARA_REC_PASSIVE));

  // Report bus-off and the recovery progress to the system register snapshot.
  assign o_bus_off = (reg_tec >= 9'(LPARA_TEC_BUS_OFF));
  assign o_recovery_count = reg_recovery_count;
  assign o_cfg_fix_event = i_restart_req && o_bus_off && (i_bo_cnt < 8'(LPARA_REC_MIN));

  // Duplicate the counter state when safety counter monitoring is enabled.
  if (PARA_CANFD_SAF_CNT_EN == 32'd1) begin : gen_safety_cnt
    logic [8:0] reg_tec_mirror;
    logic [7:0] reg_rec_mirror;

    // Keep a physically separate counter mirror for the optional comparison mechanism.
    always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_safety_mirror
      if (!i_rst_n_can) begin
        reg_tec_mirror <= 9'd0;
        reg_rec_mirror <= 8'd0;
      end else if (w_recover_now) begin
        reg_tec_mirror <= 9'd0;
        reg_rec_mirror <= 8'd0;
      end else begin
        reg_tec_mirror <= w_tec_nxt;
        reg_rec_mirror <= w_rec_nxt;
      end
    end

    // Report any divergence between the main counters and their safety mirrors.
    assign o_saf_fault = (reg_tec_mirror != reg_tec) || (reg_rec_mirror != reg_rec);
  end else begin : gen_safety_cnt_off
    // Disable the optional counter comparison output in the base configuration.
    assign o_saf_fault = 1'b0;
  end

endmodule
