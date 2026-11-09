/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-08
 * Description  : Transfers one stable source-domain data bundle through a four-phase request and
 *                acknowledge handshake. The source holds data until the full return-to-zero cycle
 *                completes; the destination holds valid and data until accepted.
 */
`timescale 1ns/1ps

module m_canfd_sync_hsk #(
  // Parameter Description: width of the atomically transferred data bundle.
  // Parameter values: 1 or more; default is 1.
  // Parameter unit: bit
  parameter logic [31:0] PARA_CANFD_DATA_W = 32'd1,
  // Parameter Description: synchronizer structure selection for the request and acknowledge.
  // Parameter values: 0 = two discrete DFF stages; 1 = VLSIT 2-FF synchronizer cell; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_CELL_TYPE = 32'd0
) (
  // Source clock, reset, readiness and input bundle
  input  wire                          i_clk_src,
  input  wire                          i_rst_n_src,
  input  wire                          i_cdc_ready_src,
  input  wire                          i_valid_src,
  output logic                         o_ready_src,
  input  wire  [PARA_CANFD_DATA_W-1:0] i_data_src,

  // Destination clock, reset, readiness and output bundle
  input  wire                          i_clk_dst,
  input  wire                          i_rst_n_dst,
  input  wire                          i_cdc_ready_dst,
  output logic                         o_valid_dst,
  input  wire                          i_ready_dst,
  output logic [PARA_CANFD_DATA_W-1:0] o_data_dst
);

  logic reg_req_tgl;
  logic reg_ack_tgl;
  logic reg_valid_dst;
  logic [PARA_CANFD_DATA_W-1:0] reg_data_src;
  logic [PARA_CANFD_DATA_W-1:0] reg_data_dst;
  logic w_ack_sync;
  logic w_req_sync;

  // Synchronize request and acknowledgement control levels without logic between stages.
  m_canfd_sync_bit #(
    .PARA_CANFD_CELL_TYPE (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_bit_0 (
    .i_clk_dst   (i_clk_dst),
    .i_rst_n_dst (i_rst_n_dst),
    .i_data      (reg_req_tgl),
    .o_data      (w_req_sync)
  );

  m_canfd_sync_bit #(
    .PARA_CANFD_CELL_TYPE (PARA_CANFD_CELL_TYPE)
  ) u_canfd_sync_bit_1 (
    .i_clk_dst   (i_clk_src),
    .i_rst_n_dst (i_rst_n_src),
    .i_data      (reg_ack_tgl),
    .o_data      (w_ack_sync)
  );

  // Keep the source bundle stable until request and acknowledgement both return low.
  always_ff @(posedge i_clk_src, negedge i_rst_n_src) begin : p_ff_hsk_src
    if (!i_rst_n_src) begin
      reg_req_tgl  <= 1'b0;
      reg_data_src <= '0;
    end else begin
      if (i_cdc_ready_src && !reg_req_tgl && !w_ack_sync) begin
        if (i_valid_src) begin
          reg_data_src <= i_data_src;
          reg_req_tgl  <= 1'b1;
        end
      end else if (reg_req_tgl && w_ack_sync) begin
        reg_req_tgl <= 1'b0;
      end
    end
  end

  // Hold the captured bundle until accepted, then acknowledge it to release the source register.
  always_ff @(posedge i_clk_dst, negedge i_rst_n_dst) begin : p_ff_hsk_dst
    if (!i_rst_n_dst) begin
      reg_ack_tgl   <= 1'b0;
      reg_valid_dst <= 1'b0;
      reg_data_dst  <= '0;
    end else if (!i_cdc_ready_dst) begin
      reg_ack_tgl   <= 1'b0;
      reg_valid_dst <= 1'b0;
    end else begin
      if (w_req_sync && !reg_ack_tgl && !reg_valid_dst) begin
        reg_data_dst  <= reg_data_src;
        reg_valid_dst <= 1'b1;
      end else if (reg_valid_dst && i_ready_dst) begin
        reg_valid_dst <= 1'b0;
        reg_ack_tgl   <= 1'b1;
      end
      if (!w_req_sync)
        reg_ack_tgl <= 1'b0;
    end
  end

  // Expose registered handshake state and destination data.
  assign o_ready_src = i_rst_n_src && i_cdc_ready_src && !reg_req_tgl && !w_ack_sync;
  assign o_valid_dst = reg_valid_dst;
  assign o_data_dst = reg_data_dst;

endmodule

