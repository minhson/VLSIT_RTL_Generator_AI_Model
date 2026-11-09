/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-09
 * Description  : Converts event pulses and software-injection edges into CSR hardware-set
 *                strobes and routes enabled sticky interrupt status to the two IRQ lines.
 * DEC IDs      : DEC-071, DEC-089
 */
`timescale 1ns/1ps

module m_canfd_irq #(
  // Parameter Description: number of interrupt causes in the workbook event map.
  // Parameter values: 1 through 32; default is 32.
  // Parameter unit: cause
  parameter logic [31:0] PARA_CANFD_EVENT_W = 32'd32,
  localparam logic [31:0] LPARA_CANFD_EVENT_W = PARA_CANFD_EVENT_W
) (
  // Clock and reset
  input  wire                           i_clk_bus,
  input  wire                           i_rst_n_bus,
  input  wire                           i_srst_req_bus,

  // Synchronized event and software-injection vectors
  input  wire  [PARA_CANFD_EVENT_W-1:0] i_event_bus,
  input  wire  [PARA_CANFD_EVENT_W-1:0] i_irq_inj,

  // CSR raw and enable fields
  input  wire  [PARA_CANFD_EVENT_W-1:0] i_irq_raw,
  input  wire  [PARA_CANFD_EVENT_W-1:0] i_irq_en,
  input  wire  [PARA_CANFD_EVENT_W-1:0] i_irq_line_sel,
  input  wire                           i_irq_line0_en,
  input  wire                           i_irq_line1_en,

  // Hardware-set interface to the generated CSR block
  output logic [PARA_CANFD_EVENT_W-1:0] o_irq_raw_hw_data,
  output logic [PARA_CANFD_EVENT_W-1:0] o_irq_raw_hw_we,
  output logic [PARA_CANFD_EVENT_W-1:0] o_irq_sts,

  // Interrupt outputs
  output logic                          o_irq_0,
  output logic                          o_irq_1
);

  logic [PARA_CANFD_EVENT_W-1:0] reg_irq_inj_d;
  logic [PARA_CANFD_EVENT_W-1:0] w_irq_inj_edge;
  logic [PARA_CANFD_EVENT_W-1:0] w_irq0_causes;
  logic [PARA_CANFD_EVENT_W-1:0] w_irq1_causes;

  // A rising injection bit has the same sticky-raw effect as its hardware event.
  assign w_irq_inj_edge = i_irq_inj & ~reg_irq_inj_d;
  assign o_irq_raw_hw_data = {LPARA_CANFD_EVENT_W{1'b1}};
  assign o_irq_raw_hw_we = i_event_bus | w_irq_inj_edge;
  assign o_irq_sts = i_irq_raw & i_irq_en;
  assign w_irq0_causes = o_irq_sts & ~i_irq_line_sel;
  assign w_irq1_causes = o_irq_sts & i_irq_line_sel;
  assign o_irq_0 = i_irq_line0_en && (|w_irq0_causes);
  assign o_irq_1 = i_irq_line1_en && (|w_irq1_causes);

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

endmodule
