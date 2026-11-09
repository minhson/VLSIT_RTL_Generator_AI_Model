/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-08
 * Description  : Two-stage level synchronizer wrapper used by the CAN controller CDC and input
 *                conditioning paths. Uses the shared AFIFO synchronizer wrapper and never selects
 *                bypass; parameters select the cell structure and reset level.
 */
`timescale 1ns/1ps

module m_canfd_sync_bit #(
  // Parameter Description: synchronizer structure selection.
  // Parameter values: 0 = two discrete DFF stages; 1 = VLSIT 2-FF synchronizer cell; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_CELL_TYPE = 32'd0,
  // Parameter Description: reset value of the synchronized level.
  // Parameter values: 0 or 1; default is 0 for inactive control levels.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_SYNC_RST_VAL = 32'd0,
  localparam logic [31:0] LPARA_AFIFO_CELL_TYPE_DFF2 = 32'd1,
  localparam logic [31:0] LPARA_AFIFO_CELL_TYPE_2FF = 32'd2,
  localparam logic [31:0] LPARA_AFIFO_SYNC_W = 32'd1,
  localparam logic [31:0] LPARA_SYNC_RST_VAL = PARA_CANFD_SYNC_RST_VAL,
  localparam logic [31:0] LPARA_CELL_TYPE = (PARA_CANFD_CELL_TYPE == 32'd1) ?
                                                  LPARA_AFIFO_CELL_TYPE_2FF : LPARA_AFIFO_CELL_TYPE_DFF2
) (
  // Destination clock and reset
  input  wire  i_clk_dst,
  input  wire  i_rst_n_dst,

  // Asynchronous source level and synchronized level
  input  wire  i_data,
  output logic o_data
);

  // Map the CAN configuration to a non-bypass shared two-stage synchronizer.
  m_vlsit_afifo_sync #(
    .PARA_AFIFO_SYNC_W       (LPARA_AFIFO_SYNC_W),
    .PARA_AFIFO_SYNC_RST_VAL (LPARA_SYNC_RST_VAL),
    .PARA_AFIFO_CELL_TYPE    (LPARA_CELL_TYPE)
  ) u_vlsit_afifo_sync (
    .i_clk_dst   (i_clk_dst),
    .i_rst_n_dst (i_rst_n_dst),
    .i_data      (i_data),
    .o_data      (o_data)
  );

endmodule
