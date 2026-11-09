/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-08
 * Description  : Parallel Classical CAN CRC-15 and ISO CAN-FD CRC-17/CRC-21 shift registers.
 *                The caller supplies the protocol-qualified CRC streams; fixed CRC-field stuff
 *                bits are excluded, while ISO FD dynamic stuff bits are included.
 */
`timescale 1ns/1ps

module m_canfd_crc #(
  localparam logic [31:0] LPARA_CRC15_POLY = 32'h0000_C599,
  localparam logic [31:0] LPARA_CRC17_POLY = 32'h0003_685B,
  localparam logic [31:0] LPARA_CRC21_POLY = 32'h0030_2899,
  localparam logic [31:0] LPARA_CRC15_INIT = 32'h0000_0000,
  localparam logic [31:0] LPARA_CRC17_INIT = 32'h0001_0000,
  localparam logic [31:0] LPARA_CRC21_INIT = 32'h0010_0000
) (
  // Clock and reset
  input  wire         i_clk_can,
  input  wire         i_rst_n_can,

  // Start a new frame CRC sequence and provide its protocol-qualified serial bit stream
  input  wire         i_crc_init,
  input  wire         i_crc_cc_valid,
  input  wire         i_crc_fd_valid,
  input  wire         i_crc_bit,

  // Current CRC states, transmitted most-significant bit first by the frame engine
  output logic [14:0] o_crc15,
  output logic [16:0] o_crc17,
  output logic [20:0] o_crc21
);

  logic w_crc15_mix;
  logic w_crc17_mix;
  logic w_crc21_mix;
  logic [14:0] reg_crc15;
  logic [16:0] reg_crc17;
  logic [20:0] reg_crc21;
  logic [14:0] w_crc15_nxt;
  logic [16:0] w_crc17_nxt;
  logic [20:0] w_crc21_nxt;

  // Compute the next state using the CRC register's outgoing MSB and the serial input bit.
  assign w_crc15_mix = reg_crc15[14] ^ i_crc_bit;
  assign w_crc17_mix = reg_crc17[16] ^ i_crc_bit;
  assign w_crc21_mix = reg_crc21[20] ^ i_crc_bit;
  assign w_crc15_nxt = {reg_crc15[13:0], 1'b0} ^ (w_crc15_mix ? 15'(LPARA_CRC15_POLY) : 15'd0);
  assign w_crc17_nxt = {reg_crc17[15:0], 1'b0} ^ (w_crc17_mix ? 17'(LPARA_CRC17_POLY) : 17'd0);
  assign w_crc21_nxt = {reg_crc21[19:0], 1'b0} ^ (w_crc21_mix ? 21'(LPARA_CRC21_POLY) : 21'd0);
  assign o_crc15 = reg_crc15;
  assign o_crc17 = reg_crc17;
  assign o_crc21 = reg_crc21;

  // Initialize the three independent CRC engines at SOF and update only for qualified input bits.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_crc_state
    if (!i_rst_n_can) begin
      reg_crc15 <= 15'(LPARA_CRC15_INIT);
      reg_crc17 <= 17'(LPARA_CRC17_INIT);
      reg_crc21 <= 21'(LPARA_CRC21_INIT);
    end else if (i_crc_init) begin
      reg_crc15 <= 15'(LPARA_CRC15_INIT);
      reg_crc17 <= 17'(LPARA_CRC17_INIT);
      reg_crc21 <= 21'(LPARA_CRC21_INIT);
    end else begin
      if (i_crc_cc_valid)
        reg_crc15 <= w_crc15_nxt;
      if (i_crc_fd_valid) begin
        reg_crc17 <= w_crc17_nxt;
        reg_crc21 <= w_crc21_nxt;
      end
    end
  end

endmodule
