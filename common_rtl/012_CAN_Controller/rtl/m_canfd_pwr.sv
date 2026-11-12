/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-11
 * Description  : Controls normal, sleep-pending, sleep, wake-pending and restart states;
 *                gates transmission, selects one CAN pin pair, and keeps the inactive
 *                transmit output recessive.
 * DEC IDs      : DEC-013, DEC-015, DEC-045, DEC-046, DEC-047, DEC-089, DEC-112
 */
`timescale 1ns/1ps

module m_canfd_pwr #(
  // Parameter Description: enable the selectable secondary CAN pin pair.
  // Parameter values: 0 = primary pair only, 1 = primary or secondary pair; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_RED_EN = 32'd1,
  localparam logic [31:0] LPARA_PWR_NORMAL = 32'd0,
  localparam logic [31:0] LPARA_PWR_SLEEP_PEND = 32'd1,
  localparam logic [31:0] LPARA_PWR_SLEEP = 32'd2,
  localparam logic [31:0] LPARA_PWR_WAKE_PEND = 32'd3,
  localparam logic [31:0] LPARA_PWR_RESTART = 32'd4,
  localparam logic [31:0] LPARA_TRCV_DIV = 32'd63
) (
  // Clock and reset
  input  wire         i_clk_can,
  input  wire         i_rst_n_can,

  // Controller and bus activity
  input  wire         i_init,
  input  wire         i_bus_idle,
  input  wire         i_frame_active,
  input  wire         i_tx_pending,
  input  wire         i_tt_active,
  input  wire         i_bus_sel_cfg,
  input  wire         i_can_rx,
  input  wire         i_can_rx_b,
  input  wire         i_can_tx,

  // Sleep, wake-up and transceiver controls
  input  wire         i_sleep_req,
  input  wire         i_wake_bus_en,
  input  wire         i_pn_active,
  input  wire         i_wake_bus_event,
  input  wire         i_wake_trcv_event,
  input  wire         i_wake_frame_event,
  input  wire         i_wake_ack,
  input  wire         i_trcv_on,
  input  wire         i_trcv_auto,
  input  wire  [15:0] i_trcv_delay,

  // Clock-stop request already synchronized to CLK-CAN
  input  wire         i_clk_stop_req,

  // CAN start permission and power status
  output logic        o_tx_permit,
  output logic        o_sleep,
  output logic        o_wake_req,
  output logic        o_wake_pend,
  output logic        o_wake_src_bus,
  output logic        o_wake_src_trcv,
  output logic        o_wake_src_wuf,
  output logic        o_sleep_blocked,
  output logic        o_trcv_en,
  output logic        o_bus_sel,
  output logic        o_can_rx,
  output logic        o_can_tx,
  output logic        o_can_tx_b,
  output logic        o_clk_stop_ack,
  output logic        o_clkc_stop_ack,

  // One-clock pulses: INIT request of the clock stop, and the wake acknowledge that ends sleep_req
  output logic        o_init_set_clk,
  output logic        o_wake_ack_done
);

  typedef enum logic [2:0] {
    ENUM_ST_NORMAL     = LPARA_PWR_NORMAL[2:0],
    ENUM_ST_SLEEP_PEND = LPARA_PWR_SLEEP_PEND[2:0],
    ENUM_ST_SLEEP      = LPARA_PWR_SLEEP[2:0],
    ENUM_ST_WAKE_PEND  = LPARA_PWR_WAKE_PEND[2:0],
    ENUM_ST_RESTART    = LPARA_PWR_RESTART[2:0]
  } pwr_state_type_def;

  pwr_state_type_def reg_fsm_pwr_current_state;
  pwr_state_type_def w_fsm_pwr_nxt_state;
  logic [5:0] reg_trcv_div;
  logic [15:0] reg_trcv_count;
  logic reg_trcv_delay_done;
  logic reg_bus_sel;
  logic reg_wake_req;
  logic reg_wake_src_bus;
  logic reg_wake_src_trcv;
  logic reg_wake_src_wuf;
  logic reg_sleep_blocked;
  logic reg_clk_stop_ack;
  logic reg_clkc_stop_ack;
  logic reg_stop_cond_d;
  logic reg_wake_ack_done;
  logic w_stop_cond;
  logic w_bus_sel_eff;
  logic w_restart_active;
  logic w_trcv_delay_complete;
  logic w_trcv_div_terminal;

  // Decode the registered power state and expose retained wake/control status.
  assign o_sleep = (reg_fsm_pwr_current_state == ENUM_ST_SLEEP);
  assign o_wake_pend = (reg_fsm_pwr_current_state == ENUM_ST_WAKE_PEND);
  assign o_wake_req = reg_wake_req;
  assign o_wake_src_bus = reg_wake_src_bus;
  assign o_wake_src_trcv = reg_wake_src_trcv;
  assign o_wake_src_wuf = reg_wake_src_wuf;
  assign o_sleep_blocked = reg_sleep_blocked;
  assign w_bus_sel_eff = (PARA_CANFD_RED_EN != 32'd0) ? reg_bus_sel : 1'b0;
  // Route the protocol bit and receive pin only through the selected bus pair.
  assign o_bus_sel = w_bus_sel_eff;
  assign o_can_rx = w_bus_sel_eff ? i_can_rx_b : i_can_rx;
  assign o_can_tx = w_bus_sel_eff ? 1'b1 : i_can_tx;
  assign o_can_tx_b = w_bus_sel_eff ? i_can_tx : 1'b1;
  assign o_trcv_en = ((reg_fsm_pwr_current_state == ENUM_ST_NORMAL) ||
                      (reg_fsm_pwr_current_state == ENUM_ST_SLEEP_PEND) ||
                      (reg_fsm_pwr_current_state == ENUM_ST_RESTART)) &&
                     (i_trcv_on || i_trcv_auto);
  // Power logic permits transmission in normal mode; TTCAN applies its separate window gate.
  assign o_tx_permit = (reg_fsm_pwr_current_state == ENUM_ST_NORMAL) && !i_init;
  assign o_clk_stop_ack = reg_clk_stop_ack;
  assign o_clkc_stop_ack = reg_clkc_stop_ack;
  // A clock stop request needs INIT: ask for it once, when idle with nothing pending.
  assign w_stop_cond = i_clk_stop_req && i_bus_idle && !i_frame_active && !i_tx_pending && !i_init;
  assign o_init_set_clk = w_stop_cond && !reg_stop_cond_d;
  assign o_wake_ack_done = reg_wake_ack_done;

  // Select power-state transitions while preserving the wake source for software.
  always_comb begin : p_com_pwr_nxt_state
    w_fsm_pwr_nxt_state = reg_fsm_pwr_current_state;
    casez (reg_fsm_pwr_current_state)
      ENUM_ST_NORMAL: begin
        casez ({i_sleep_req, i_tt_active, i_tx_pending})
          3'b100: w_fsm_pwr_nxt_state = ENUM_ST_SLEEP_PEND;
          default: w_fsm_pwr_nxt_state = ENUM_ST_NORMAL;
        endcase
      end
      ENUM_ST_SLEEP_PEND: begin
        if (i_wake_bus_event || i_wake_trcv_event || i_wake_frame_event)
          w_fsm_pwr_nxt_state = ENUM_ST_WAKE_PEND;
        else if (!i_frame_active && i_bus_idle)
          w_fsm_pwr_nxt_state = ENUM_ST_SLEEP;
      end
      ENUM_ST_SLEEP: begin
        if (i_wake_bus_event || i_wake_trcv_event || i_wake_frame_event)
          w_fsm_pwr_nxt_state = ENUM_ST_WAKE_PEND;
      end
      ENUM_ST_WAKE_PEND: begin
        if (i_wake_ack)
          w_fsm_pwr_nxt_state = ENUM_ST_RESTART;
      end
      ENUM_ST_RESTART: begin
        if (!i_init && reg_trcv_delay_done && i_bus_idle && !i_sleep_req)
          w_fsm_pwr_nxt_state = ENUM_ST_NORMAL;
      end
      default: begin
        w_fsm_pwr_nxt_state = ENUM_ST_NORMAL;
      end
    endcase
  end

  // Keep the FSM state in its own sequential process for synthesis extraction.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_pwr_state
    if (!i_rst_n_can)
      reg_fsm_pwr_current_state <= ENUM_ST_NORMAL;
    else
      reg_fsm_pwr_current_state <= w_fsm_pwr_nxt_state;
  end

  // Retain wake causes until software acknowledges the wake request.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_wake_sts
    if (!i_rst_n_can) begin
      reg_wake_req <= 1'b0;
      reg_wake_src_bus <= 1'b0;
      reg_wake_src_trcv <= 1'b0;
      reg_wake_src_wuf <= 1'b0;
      reg_sleep_blocked <= 1'b0;
    end else begin
      if (i_sleep_req && i_tt_active)
        reg_sleep_blocked <= 1'b1;
      else if (i_sleep_req && i_tx_pending)
        reg_sleep_blocked <= 1'b1;
      if (i_wake_bus_event) begin
        reg_wake_req <= 1'b1;
        reg_wake_src_bus <= 1'b1;
      end
      if (i_wake_trcv_event) begin
        reg_wake_req <= 1'b1;
        reg_wake_src_trcv <= 1'b1;
      end
      if (i_wake_frame_event) begin
        reg_wake_req <= 1'b1;
        reg_wake_src_wuf <= 1'b1;
      end
      if (i_wake_ack) begin
        reg_wake_req <= 1'b0;
        reg_wake_src_bus <= 1'b0;
        reg_wake_src_trcv <= 1'b0;
        reg_wake_src_wuf <= 1'b0;
        reg_sleep_blocked <= 1'b0;
      end
    end
  end

  // Qualify the transceiver delay counter and its terminal conditions.
  assign w_restart_active = (reg_fsm_pwr_current_state == ENUM_ST_RESTART) &&
                            (i_trcv_on || i_trcv_auto);
  // Compare the counter with the configured delay and identify its prescale boundary.
  assign w_trcv_delay_complete = (reg_trcv_count >= i_trcv_delay);
  assign w_trcv_div_terminal = (reg_trcv_div == LPARA_TRCV_DIV[5:0]);

  // Wait the programmed transceiver startup delay in units of 64 CAN clocks.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_trcv_delay
    if (!i_rst_n_can) begin
      reg_trcv_div <= '0;
      reg_trcv_count <= '0;
      reg_trcv_delay_done <= 1'b0;
    end else begin
      casez ({w_restart_active, w_trcv_delay_complete, w_trcv_div_terminal})
        3'b0??: begin
          reg_trcv_div <= '0;
          reg_trcv_count <= '0;
          reg_trcv_delay_done <= 1'b0;
        end
        3'b11?: begin
          reg_trcv_delay_done <= 1'b1;
        end
        3'b101: begin
          reg_trcv_div <= '0;
          reg_trcv_count <= reg_trcv_count + 16'd1;
        end
        3'b100: begin
          reg_trcv_div <= reg_trcv_div + 6'd1;
        end
        default: begin
          reg_trcv_div <= reg_trcv_div;
          reg_trcv_count <= reg_trcv_count;
          reg_trcv_delay_done <= reg_trcv_delay_done;
        end
      endcase
    end
  end

  // Change the active bus pair only while the bus is idle or INIT is asserted.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_bus_sel
    if (!i_rst_n_can)
      reg_bus_sel <= 1'b0;
    else if (i_init || (i_bus_idle && !i_frame_active))
      reg_bus_sel <= i_bus_sel_cfg;
  end

  // Hold acknowledgements; CAN stop is disallowed when a clocked wake source is active.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_clk_stop
    if (!i_rst_n_can) begin
      reg_clk_stop_ack <= 1'b0;
      reg_clkc_stop_ack <= 1'b0;
    end else begin
      reg_clk_stop_ack <= i_clk_stop_req && i_init && i_bus_idle && !i_frame_active;
      reg_clkc_stop_ack <= i_clk_stop_req && i_init && i_bus_idle && !i_frame_active &&
                           !i_wake_bus_en && !i_pn_active;
    end
  end

  // Remember the stop condition; the wake acknowledge is the done pulse of sleep_req and wake_ack.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_pwr_done
    if (!i_rst_n_can) begin
      reg_stop_cond_d <= 1'b0;
      reg_wake_ack_done <= 1'b0;
    end else begin
      reg_stop_cond_d <= w_stop_cond;
      reg_wake_ack_done <= i_wake_ack;
    end
  end

endmodule
