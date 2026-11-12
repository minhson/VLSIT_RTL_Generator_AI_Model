/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-11
 * Description  : Converts event pulses and software-injection edges into CSR hardware-set
 *                strobes and routes enabled sticky interrupt status to the two IRQ lines.
 * DEC IDs      : DEC-071, DEC-089, DEC-110
 */
`timescale 1ns/1ps

module m_canfd_irq #(
  // Parameter Description: number of interrupt causes in the workbook event map.
  // Parameter values: 32 for the fixed CSR map; default is 32.
  // Parameter unit: cause
  parameter logic [31:0] PARA_CANFD_EVENT_W = 32'd32,
  // Parameter Description: number of detailed TTCAN interrupt causes in the workbook event map.
  // Parameter values: 16; default is 16.
  // Parameter unit: cause
  parameter logic [31:0] PARA_CANFD_TT_EVENT_W = 32'd16,
  localparam logic [31:0] LPARA_CANFD_EVENT_W = PARA_CANFD_EVENT_W,
  localparam logic [31:0] LPARA_TT_ERR_GROUP_W = 32'd10,
  localparam logic [31:0] LPARA_TT_ERR_SUMMARY_BIT = 32'd26,
  localparam logic [31:0] LPARA_TT_MARK_SUMMARY_BIT = 32'd25
) (
  // Clock and reset
  input  wire                              i_clk_bus,
  input  wire                              i_rst_n_bus,
  input  wire                              i_srst_req_bus,

  // Synchronized event and software-injection vectors
  input  wire  [PARA_CANFD_EVENT_W-1:0]    i_event_bus,
  input  wire  [PARA_CANFD_EVENT_W-1:0]    i_event_local_bus,
  input  wire  [PARA_CANFD_EVENT_W-1:0]    i_irq_inj,
  input  wire  [PARA_CANFD_TT_EVENT_W-1:0] i_tt_event_bus,
  input  wire  [PARA_CANFD_TT_EVENT_W-1:0] i_tt_irq_inj,
  input  wire  [PARA_CANFD_TT_EVENT_W-1:0] i_tt_irq_raw,
  input  wire  [PARA_CANFD_TT_EVENT_W-1:0] i_tt_irq_en,
  input  wire                              i_tdc_timeout_event_bus,
  input  wire                              i_tdc_irq_inj,
  input  wire                              i_tdc_irq_raw,
  input  wire                              i_tdc_irq_en,
  input  wire                              i_tdc_irq_line,

  // CSR raw and enable fields
  input  wire  [PARA_CANFD_EVENT_W-1:0]    i_irq_raw,
  input  wire  [PARA_CANFD_EVENT_W-1:0]    i_irq_en,
  input  wire  [PARA_CANFD_EVENT_W-1:0]    i_irq_line_sel,
  input  wire                              i_irq_line0_en,
  input  wire                              i_irq_line1_en,

  // Hardware-set interface to the generated CSR block
  output logic [PARA_CANFD_EVENT_W-1:0]    o_irq_raw_hw_data,
  output logic [PARA_CANFD_EVENT_W-1:0]    o_irq_raw_hw_we,
  output logic [PARA_CANFD_EVENT_W-1:0]    o_irq_sts,
  output logic [PARA_CANFD_TT_EVENT_W-1:0] o_tt_irq_raw_hw_data,
  output logic [PARA_CANFD_TT_EVENT_W-1:0] o_tt_irq_raw_hw_we,
  output logic [PARA_CANFD_TT_EVENT_W-1:0] o_tt_irq_sts,
  output logic                             o_tdc_irq_raw_hw_data,
  output logic                             o_tdc_irq_raw_hw_we,
  output logic                             o_tdc_irq_sts,

  // Interrupt outputs
  output logic                             o_irq_0,
  output logic                             o_irq_1
);

  logic [PARA_CANFD_EVENT_W-1:0] reg_irq_inj_d;
  logic [PARA_CANFD_EVENT_W-1:0] w_irq_inj_edge;
  logic [PARA_CANFD_EVENT_W-1:0] w_irq0_causes;
  logic [PARA_CANFD_EVENT_W-1:0] w_irq1_causes;
  logic [PARA_CANFD_TT_EVENT_W-1:0] reg_tt_irq_inj_d;
  logic reg_tdc_irq_inj_d;
  logic [PARA_CANFD_TT_EVENT_W-1:0] w_tt_irq_inj_edge;
  logic [PARA_CANFD_TT_EVENT_W-1:0] w_tt_event_effective;
  logic [PARA_CANFD_EVENT_W-1:0] w_irq_event_effective;
  logic [PARA_CANFD_EVENT_W-1:0] w_tt_summary_event;
  logic w_tt_err_summary;
  logic w_tt_mark_summary;
  logic w_tdc_irq_inj_edge;
  logic w_tdc_irq_event;

  // A rising injection bit has the same sticky-raw effect as its hardware event.
  assign w_irq_inj_edge = i_irq_inj & ~reg_irq_inj_d;
  assign o_irq_raw_hw_data = {LPARA_CANFD_EVENT_W{1'b1}};

  // Detect TTCAN injection edges and qualify the two enabled summary groups.
  assign w_tt_irq_inj_edge = i_tt_irq_inj & ~reg_tt_irq_inj_d;
  assign w_tt_event_effective = i_tt_event_bus | w_tt_irq_inj_edge;
  assign w_tt_err_summary = |(w_tt_event_effective[LPARA_TT_ERR_GROUP_W-1:0] &
                              i_tt_irq_en[LPARA_TT_ERR_GROUP_W-1:0]);
  // Qualify the six TTCAN schedule and time-mark causes independently.
  assign w_tt_mark_summary = |(w_tt_event_effective[PARA_CANFD_TT_EVENT_W-1:LPARA_TT_ERR_GROUP_W] &
                               i_tt_irq_en[PARA_CANFD_TT_EVENT_W-1:LPARA_TT_ERR_GROUP_W]);
  // Combine crossed CAN events, BUS events, injection edges and TTCAN summaries for the main bank.
  assign w_irq_event_effective = i_event_bus | i_event_local_bus | w_irq_inj_edge |
                                 w_tt_summary_event;
  assign o_irq_raw_hw_we = w_irq_event_effective;
  assign o_irq_sts = i_irq_raw & i_irq_en;
  // Keep all detailed TTCAN causes in their independent CSR bank.
  assign o_tt_irq_raw_hw_data = {PARA_CANFD_TT_EVENT_W{1'b1}};
  assign o_tt_irq_raw_hw_we = w_tt_event_effective;
  assign o_tt_irq_sts = i_tt_irq_en & i_tt_irq_raw;
  // Route the dedicated TDC timeout cause through its own enable and line-select fields.
  assign w_tdc_irq_inj_edge = i_tdc_irq_inj & ~reg_tdc_irq_inj_d;
  assign w_tdc_irq_event = i_tdc_timeout_event_bus | w_tdc_irq_inj_edge;
  assign o_tdc_irq_raw_hw_data = 1'b1;
  assign o_tdc_irq_raw_hw_we = w_tdc_irq_event;
  assign o_tdc_irq_sts = i_tdc_irq_raw & i_tdc_irq_en;
  // Route the enabled main causes and the TDC cause to their selected IRQ outputs.
  assign w_irq0_causes = o_irq_sts & ~i_irq_line_sel;
  assign w_irq1_causes = o_irq_sts & i_irq_line_sel;
  assign o_irq_0 = i_irq_line0_en && ((|w_irq0_causes) || (o_tdc_irq_sts && !i_tdc_irq_line));
  assign o_irq_1 = i_irq_line1_en && ((|w_irq1_causes) || (o_tdc_irq_sts && i_tdc_irq_line));

  // Summarize enabled TTCAN error and schedule groups into the main IRQ causes.
  always_comb begin : p_com_tt_summary
    w_tt_summary_event = '0;
    w_tt_summary_event[LPARA_TT_ERR_SUMMARY_BIT] = w_tt_err_summary;
    w_tt_summary_event[LPARA_TT_MARK_SUMMARY_BIT] = w_tt_mark_summary;
  end

  // Retain the injection level to avoid repeatedly injecting a held software bit.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_irq_inj_edge
    if (!i_rst_n_bus) begin
      reg_irq_inj_d <= '0;
    end else if (i_srst_req_bus) begin
      reg_irq_inj_d <= '0;
    end else begin
      reg_irq_inj_d <= i_irq_inj;
    end
  end

  // Retain TTCAN injection levels so each rising software request creates one event.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_tt_irq_inj_edge
    if (!i_rst_n_bus) begin
      reg_tt_irq_inj_d <= '0;
    end else if (i_srst_req_bus) begin
      reg_tt_irq_inj_d <= '0;
    end else begin
      reg_tt_irq_inj_d <= i_tt_irq_inj;
    end
  end

  // Retain the TDC injection level so each rising software request creates one event.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_tdc_irq_inj_edge
    if (!i_rst_n_bus) begin
      reg_tdc_irq_inj_d <= 1'b0;
    end else if (i_srst_req_bus) begin
      reg_tdc_irq_inj_d <= 1'b0;
    end else begin
      reg_tdc_irq_inj_d <= i_tdc_irq_inj;
    end
  end

endmodule
