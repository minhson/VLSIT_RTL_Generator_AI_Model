/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-08
 * Description  : Inserts and removes dynamic and fixed CAN stuff bits and checks ISO FD SBC.
 *                BSP supplies the frame-region and fixed-slot strobes; CRC handling stays separate.
 * DEC IDs      : REQ-FUNC-005, REQ-FUNC-007, REQ-FUNC-008
 */
`timescale 1ns/1ps

module m_canfd_stuf #(
  localparam logic [31:0] LPARA_STUF_RUN_LIMIT = 32'd5,
  localparam logic [31:0] LPARA_STUF_RUN_ONE   = 32'd1
) (
  // Clock and reset
  input  wire        i_clk_can,
  input  wire        i_rst_n_can,

  // Frame-region controls from the single frame sequencer
  input  wire        i_stuf_clear,
  input  wire        i_dyn_stuf_en,
  input  wire        i_iso_fd,
  input  wire        i_tx_fixed_slot,
  input  wire        i_rx_fixed_slot,

  // Transmit bit step and stuffed wire-bit result
  input  wire        i_tx_point,
  input  wire        i_tx_logical_bit,
  output logic       o_tx_bit,
  output logic       o_tx_logical_adv,
  output logic       o_tx_dyn_stuff,
  output logic       o_tx_fixed_stuff,
  output logic [3:0] o_tx_sbc_code,

  // Receive sample and destuffed bit result
  input  wire        i_rx_sample,
  input  wire        i_rx_wire_bit,
  output logic       o_rx_bit,
  output logic       o_rx_bit_valid,
  output logic       o_rx_dyn_stuff,
  output logic       o_rx_stuff_err,

  // Received ISO FD stuff-count field, accumulated MSB first by BSP
  input  wire        i_rx_sbc_valid,
  input  wire  [3:0] i_rx_sbc_code,
  output logic       o_rx_sbc_err
);

  // Internal signal declarations
  logic [2:0] reg_tx_run_count;
  logic [2:0] reg_rx_run_count;
  logic [2:0] reg_tx_sbc_count;
  logic [2:0] reg_rx_sbc_count;
  logic       reg_tx_last_bit;
  logic       reg_rx_last_bit;
  logic       reg_tx_last_valid;
  logic       reg_rx_last_valid;
  logic [2:0] w_tx_sbc_gray;
  logic [2:0] w_rx_sbc_gray;

  // Converts the modulo-eight count to the reflected Gray code used by ISO FD.
  function automatic logic [2:0] stuf_gray_encode(input logic [2:0] w_binary_count);
    stuf_gray_encode = w_binary_count ^ (w_binary_count >> 1);
  endfunction

  // Combinational bit selection emits stuff bits without advancing the BSP field.
  always_comb begin : p_com_stuf_bits
    o_tx_bit = i_tx_logical_bit;
    o_tx_logical_adv = 1'b0;
    o_tx_dyn_stuff = 1'b0;
    o_tx_fixed_stuff = 1'b0;
    o_tx_sbc_code = 4'b0000;
    o_rx_bit = i_rx_wire_bit;
    o_rx_bit_valid = 1'b0;
    o_rx_dyn_stuff = 1'b0;
    o_rx_stuff_err = 1'b0;
    o_rx_sbc_err = 1'b0;
    w_tx_sbc_gray = stuf_gray_encode(reg_tx_sbc_count);
    w_rx_sbc_gray = stuf_gray_encode(reg_rx_sbc_count);
    o_tx_sbc_code = {w_tx_sbc_gray, ^w_tx_sbc_gray};

    if (i_tx_point) begin
      if (i_tx_fixed_slot) begin
        o_tx_bit = reg_tx_last_valid ? ~reg_tx_last_bit : 1'b1;
        o_tx_fixed_stuff = 1'b1;
      end else if (i_dyn_stuf_en &&
                   (reg_tx_run_count ==
                    $bits(reg_tx_run_count)'(LPARA_STUF_RUN_LIMIT)) &&
                   reg_tx_last_valid) begin
        o_tx_bit = ~reg_tx_last_bit;
        o_tx_dyn_stuff = 1'b1;
      end else begin
        o_tx_logical_adv = 1'b1;
      end
    end

    if (i_rx_sample) begin
      if (i_rx_fixed_slot) begin
        if (!reg_rx_last_valid || (i_rx_wire_bit == reg_rx_last_bit))
          o_rx_stuff_err = 1'b1;
      end else if (i_dyn_stuf_en &&
                   (reg_rx_run_count ==
                    $bits(reg_rx_run_count)'(LPARA_STUF_RUN_LIMIT))) begin
        if (!reg_rx_last_valid || (i_rx_wire_bit == reg_rx_last_bit))
          o_rx_stuff_err = 1'b1;
        else
          o_rx_dyn_stuff = 1'b1;
      end else begin
        o_rx_bit_valid = 1'b1;
      end
    end

    if (i_rx_sbc_valid && i_iso_fd &&
        (i_rx_sbc_code != {w_rx_sbc_gray, ^w_rx_sbc_gray}))
      o_rx_sbc_err = 1'b1;
  end

  // TX state tracks the wire run and counts only dynamic stuff bits before ISO FD SBC.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_stuf_tx
    if (!i_rst_n_can) begin
      reg_tx_run_count <= 3'b000;
      reg_tx_sbc_count <= 3'b000;
      reg_tx_last_bit <= 1'b1;
      reg_tx_last_valid <= 1'b0;
    end else if (i_stuf_clear) begin
      reg_tx_run_count <= 3'b000;
      reg_tx_sbc_count <= 3'b000;
      reg_tx_last_bit <= 1'b1;
      reg_tx_last_valid <= 1'b0;
    end else if (i_tx_point) begin
      reg_tx_last_bit <= o_tx_bit;
      reg_tx_last_valid <= 1'b1;

      if (i_tx_fixed_slot) begin
        reg_tx_run_count <= 3'b000;
      end else if (i_dyn_stuf_en) begin
        if (o_tx_dyn_stuff) begin
          reg_tx_run_count <= $bits(reg_tx_run_count)'(LPARA_STUF_RUN_ONE);
          if (i_iso_fd)
            reg_tx_sbc_count <= $bits(reg_tx_sbc_count)'(
              reg_tx_sbc_count + $bits(reg_tx_sbc_count)'(LPARA_STUF_RUN_ONE)
            );
        end else begin
          if (!reg_tx_last_valid || (i_tx_logical_bit != reg_tx_last_bit))
            reg_tx_run_count <= $bits(reg_tx_run_count)'(LPARA_STUF_RUN_ONE);
          else if (reg_tx_run_count <
                   $bits(reg_tx_run_count)'(LPARA_STUF_RUN_LIMIT))
            reg_tx_run_count <= $bits(reg_tx_run_count)'(
              reg_tx_run_count + $bits(reg_tx_run_count)'(LPARA_STUF_RUN_ONE)
            );
        end
      end else begin
        reg_tx_run_count <= 3'b000;
      end
    end
  end

  // RX state removes stuff bits, checks fixed slots and independently counts ISO FD SBC.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_stuf_rx
    if (!i_rst_n_can) begin
      reg_rx_run_count <= 3'b000;
      reg_rx_sbc_count <= 3'b000;
      reg_rx_last_bit <= 1'b1;
      reg_rx_last_valid <= 1'b0;
    end else if (i_stuf_clear) begin
      reg_rx_run_count <= 3'b000;
      reg_rx_sbc_count <= 3'b000;
      reg_rx_last_bit <= 1'b1;
      reg_rx_last_valid <= 1'b0;
    end else if (i_rx_sample) begin
      reg_rx_last_bit <= i_rx_wire_bit;
      reg_rx_last_valid <= 1'b1;

      if (i_rx_fixed_slot) begin
        reg_rx_run_count <= 3'b000;
      end else if (i_dyn_stuf_en) begin
        if (reg_rx_run_count ==
            $bits(reg_rx_run_count)'(LPARA_STUF_RUN_LIMIT)) begin
          if (o_rx_dyn_stuff) begin
            reg_rx_run_count <= $bits(reg_rx_run_count)'(LPARA_STUF_RUN_ONE);
            if (i_iso_fd)
              reg_rx_sbc_count <= $bits(reg_rx_sbc_count)'(
                reg_rx_sbc_count + $bits(reg_rx_sbc_count)'(LPARA_STUF_RUN_ONE)
              );
          end else begin
            reg_rx_run_count <= 3'b000;
          end
        end else begin
          if (!reg_rx_last_valid || (i_rx_wire_bit != reg_rx_last_bit))
            reg_rx_run_count <= $bits(reg_rx_run_count)'(LPARA_STUF_RUN_ONE);
          else if (reg_rx_run_count <
                   $bits(reg_rx_run_count)'(LPARA_STUF_RUN_LIMIT))
            reg_rx_run_count <= $bits(reg_rx_run_count)'(
              reg_rx_run_count + $bits(reg_rx_run_count)'(LPARA_STUF_RUN_ONE)
            );
        end
      end else begin
        reg_rx_run_count <= 3'b000;
      end
    end
  end

endmodule

