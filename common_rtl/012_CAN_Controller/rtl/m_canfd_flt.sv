/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-09
 * Description  : Evaluates one standard or extended acceptance-filter element using the
 *                range, dual-identifier and classic-mask element types in HDS section 10.11.2.
 * DEC IDs      : DEC-026, DEC-089
 */
`timescale 1ns/1ps

module m_canfd_flt (
  // Candidate frame identifier and format
  input  wire  [28:0] i_id,
  input  wire         i_xtd,

  // Filter element under evaluation
  input  wire         i_elem_en,
  input  wire  [1:0]  i_elem_type,
  input  wire  [28:0] i_elem_id1,
  input  wire  [28:0] i_elem_id2,
  input  wire         i_elem_xtd,

  // Match result
  output logic        o_match
);

  logic [28:0] w_id;
  logic [28:0] w_id1;
  logic [28:0] w_id2;
  logic w_format_match;

  // Standard identifiers occupy the upper eleven bits of the 29-bit element representation.
  always_comb begin : p_com_filter_match
    w_id = i_id;
    w_id1 = i_elem_id1;
    w_id2 = i_elem_id2;
    w_format_match = (i_xtd == i_elem_xtd);
    o_match = 1'b0;

    if (w_format_match && i_elem_en) begin
      if (i_xtd) begin
        casez (i_elem_type)
          2'd0: o_match = (w_id >= w_id1) && (w_id <= w_id2);
          2'd1: o_match = (w_id == w_id1) || (w_id == w_id2);
          2'd2: o_match = ((w_id & w_id2) == (w_id1 & w_id2));
          2'd3: o_match = 1'b0;
          default: o_match = 1'bx;
        endcase
      end else begin
        casez (i_elem_type)
          2'd0: o_match = (w_id[28:18] >= w_id1[28:18]) &&
                          (w_id[28:18] <= w_id2[28:18]);
          2'd1: o_match = (w_id[28:18] == w_id1[28:18]) ||
                          (w_id[28:18] == w_id2[28:18]);
          2'd2: o_match = ((w_id[28:18] & w_id2[28:18]) ==
                           (w_id1[28:18] & w_id2[28:18]));
          2'd3: o_match = 1'b0;
          default: o_match = 1'bx;
        endcase
      end
    end
  end

endmodule
