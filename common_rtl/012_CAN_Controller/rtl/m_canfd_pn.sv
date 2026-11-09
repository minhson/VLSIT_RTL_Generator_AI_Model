/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-09
 * Description  : Compares Classical CAN receive fields against the programmable wake filters.
 *                The block processes destuffed bits and reports a match at the CRC delimiter.
 * DEC IDs      : DEC-046, DEC-048, DEC-089
 */
`timescale 1ns/1ps

module m_canfd_pn #(
  // Parameter Description: enables the partial-networking wake-frame filter.
  // Parameter values: 0 = removed, 1 = included; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_PN_EN = 32'd1,
  // Parameter Description: number of programmable Classical CAN wake filters.
  // Parameter values: legal values are 1 to 8; default is 4.
  // Parameter unit: count
  parameter logic [31:0] PARA_CANFD_PN_NUM = 32'd4,
  localparam logic [31:0] LPARA_PN_DATA_W = 32'd64,
  localparam logic [31:0] LPARA_PN_ID_MSB = 32'd28,
  localparam logic [31:0] LPARA_PN_ID_NUM = 32'd29,
  localparam logic [31:0] LPARA_PN_BITS_PER_BYTE = 32'd8,
  localparam logic [31:0] LPARA_PN_DLC_MAX_BYTES = 32'd8,
  localparam logic [31:0] LPARA_PN_DLC_LAST_IDX = 32'd3,
  localparam logic [31:0] LPARA_PN_BYTE_MSB = 32'd7,
  localparam logic [31:0] LPARA_PN_IDX_W =
    (PARA_CANFD_PN_NUM <= 32'd1) ? 32'd1 : $clog2(PARA_CANFD_PN_NUM)
) (
  // Clock and reset
  input  wire                                i_clk_can,
  input  wire                                i_rst_n_can,

  // Sleep and partial-networking controls
  input  wire                                i_sleep_active,
  input  wire                                i_pn_on,
  input  wire                                i_bus_idle,
  output logic                               o_pn_active,

  // Synchronized filter configuration snapshot
  input  wire                                i_pnf_cfg_valid,
  output logic                               o_pnf_cfg_ready,
  input  wire  [PARA_CANFD_PN_NUM-1:0]       i_pnf_cfg_on,
  input  wire  [PARA_CANFD_PN_NUM-1:0]       i_pnf_cfg_xtd,
  input  wire  [PARA_CANFD_PN_NUM-1:0][28:0] i_pnf_cfg_id,
  input  wire  [PARA_CANFD_PN_NUM-1:0][28:0] i_pnf_cfg_idm,
  input  wire  [PARA_CANFD_PN_NUM-1:0]       i_pnf_cfg_dlc_en,
  input  wire  [PARA_CANFD_PN_NUM-1:0][3:0]  i_pnf_cfg_dlc,
  input  wire  [PARA_CANFD_PN_NUM-1:0][31:0] i_pnf_cfg_d0,
  input  wire  [PARA_CANFD_PN_NUM-1:0][31:0] i_pnf_cfg_d1,
  input  wire  [PARA_CANFD_PN_NUM-1:0][31:0] i_pnf_cfg_dm0,
  input  wire  [PARA_CANFD_PN_NUM-1:0][31:0] i_pnf_cfg_dm1,

  // Destuffed Classical CAN receive fields, sampled at the CAN sample point
  input  wire                                i_rx_frame_start,
  input  wire                                i_rx_abort,
  input  wire                                i_rx_id_bit_valid,
  input  wire                                i_rx_id_bit,
  input  wire  [4:0]                         i_rx_id_bit_idx,
  input  wire                                i_rx_ide_valid,
  input  wire                                i_rx_ide,
  input  wire                                i_rx_rtr_valid,
  input  wire                                i_rx_rtr,
  input  wire                                i_rx_fdf_valid,
  input  wire                                i_rx_fdf,
  input  wire                                i_rx_dlc_bit_valid,
  input  wire                                i_rx_dlc_bit,
  input  wire  [1:0]                         i_rx_dlc_bit_idx,
  input  wire                                i_rx_data_bit_valid,
  input  wire                                i_rx_data_bit,
  input  wire  [5:0]                         i_rx_data_bit_idx,

  // Frame integrity at the CRC delimiter
  input  wire                                i_rx_crc_delim,
  input  wire                                i_rx_crc_ok,
  input  wire                                i_rx_stuff_ok,

  // Wake event and first matching filter index
  output logic                               o_pn_wake_frame,
  output logic [3:0]                         o_pn_wake_idx
);

  // Module-local types

  // Internal signal declarations
  logic [PARA_CANFD_PN_NUM-1:0] reg_pnf_on;
  logic [PARA_CANFD_PN_NUM-1:0] reg_pnf_xtd;
  logic [PARA_CANFD_PN_NUM-1:0][28:0] reg_pnf_id;
  logic [PARA_CANFD_PN_NUM-1:0][28:0] reg_pnf_idm;
  logic [PARA_CANFD_PN_NUM-1:0] reg_pnf_dlc_en;
  logic [PARA_CANFD_PN_NUM-1:0][3:0] reg_pnf_dlc;
  logic [PARA_CANFD_PN_NUM-1:0][LPARA_PN_DATA_W-1:0] reg_pnf_data;
  logic [PARA_CANFD_PN_NUM-1:0][LPARA_PN_DATA_W-1:0] reg_pnf_data_mask;
  logic [PARA_CANFD_PN_NUM-1:0] reg_pnf_match;
  logic reg_frame_active;
  logic reg_frame_fd;
  logic reg_frame_rtr;
  logic [2:0] reg_rx_dlc;
  logic [3:0] w_rx_dlc_nxt;
  logic [3:0] w_rx_data_bytes;
  logic [6:0] w_payload_shift;
  logic [LPARA_PN_DATA_W-1:0] w_payload_mask;
  logic [4:0] w_id_bit_pos;
  logic [5:0] w_data_bit_pos;
  logic w_pnf_first_match;
  logic [LPARA_PN_IDX_W-1:0] w_pnf_first_idx;
  logic [PARA_CANFD_PN_NUM:0] w_pnf_match_chain;
  logic [PARA_CANFD_PN_NUM:0][LPARA_PN_IDX_W-1:0] w_pnf_idx_chain;
  logic w_pn_filter_en;
  logic w_pnf_cfg_accept;
  logic reg_pn_wake_frame;
  logic [3:0] reg_pn_wake_idx;

  // Qualify filtering and the complete-bank update handshake in the CAN domain.
  assign o_pn_active = (PARA_CANFD_PN_EN == 32'd1) && i_sleep_active && i_pn_on;
  assign w_pn_filter_en = o_pn_active;
  assign w_pnf_cfg_accept = i_pnf_cfg_valid && o_pnf_cfg_ready;
  assign w_rx_dlc_nxt = {reg_rx_dlc[2:0], i_rx_dlc_bit};
  assign w_id_bit_pos = 5'(LPARA_PN_ID_MSB) - i_rx_id_bit_idx;
  assign w_data_bit_pos = $bits(w_data_bit_pos)'(
    (i_rx_data_bit_idx / 6'(LPARA_PN_BITS_PER_BYTE)) *
    6'(LPARA_PN_BITS_PER_BYTE) +
    (6'(LPARA_PN_BYTE_MSB) - (i_rx_data_bit_idx % 6'(LPARA_PN_BITS_PER_BYTE)))
  );

  // Convert the Classical CAN DLC to available payload bytes and a low-byte-first bit mask.
  always_comb begin : p_com_pn_payload_mask
    w_rx_data_bytes = 4'd0;
    casez ({reg_frame_rtr, w_rx_dlc_nxt[3]})
      2'b1?:   w_rx_data_bytes = 4'd0;
      2'b01:   w_rx_data_bytes = 4'(LPARA_PN_DLC_MAX_BYTES);
      2'b00:   w_rx_data_bytes = {1'b0, w_rx_dlc_nxt[2:0]};
      default: w_rx_data_bytes = 4'd0;
    endcase
    w_payload_shift = $bits(w_payload_shift)'(
      LPARA_PN_DATA_W -
      (7'(w_rx_data_bytes) * 7'(LPARA_PN_BITS_PER_BYTE))
    );
    w_payload_mask = {LPARA_PN_DATA_W{1'b1}} >> w_payload_shift;
  end

  // Snapshot all synchronized filter fields atomically at an idle frame boundary.
  generate
    if (PARA_CANFD_PN_EN == 32'd1) begin : gen_pn_enabled
      // Forward the registered wake event and selected filter index to the module boundary.
      assign o_pn_wake_frame = reg_pn_wake_frame;
      assign o_pn_wake_idx = reg_pn_wake_idx;

      // Accept the complete synchronized filter bank only at an idle frame boundary.
      assign o_pnf_cfg_ready = i_bus_idle && !reg_frame_active && !i_rx_frame_start;

      // Select the first enabled matching filter with a generated fixed-priority chain.
      assign w_pnf_match_chain[0] = 1'b0;
      assign w_pnf_idx_chain[0] = '0;
      for (genvar gen_pnf_idx = 0; gen_pnf_idx < PARA_CANFD_PN_NUM; gen_pnf_idx++) begin : gen_pn_prio
        // Accumulate a match indication from the preceding filter positions.
        assign w_pnf_match_chain[gen_pnf_idx + 1] =
          w_pnf_match_chain[gen_pnf_idx] | reg_pnf_match[gen_pnf_idx];
        // Preserve the earliest matching filter index.
        assign w_pnf_idx_chain[gen_pnf_idx + 1] =
          (!w_pnf_match_chain[gen_pnf_idx] && reg_pnf_match[gen_pnf_idx]) ?
          LPARA_PN_IDX_W'(gen_pnf_idx) : w_pnf_idx_chain[gen_pnf_idx];
      end
      // Forward the last stage of the fixed-priority result.
      assign w_pnf_first_match = w_pnf_match_chain[PARA_CANFD_PN_NUM];
      assign w_pnf_first_idx = w_pnf_idx_chain[PARA_CANFD_PN_NUM];

      // Capture all filter fields atomically when the CDC configuration handshake completes.
      always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_pn_cfg
        if (!i_rst_n_can) begin
          reg_pnf_on <= '0;
          reg_pnf_xtd <= '0;
          reg_pnf_id <= '0;
          reg_pnf_idm <= '0;
          reg_pnf_dlc_en <= '0;
          reg_pnf_dlc <= '0;
          reg_pnf_data <= '0;
          reg_pnf_data_mask <= '0;
        end else if (w_pnf_cfg_accept) begin
          reg_pnf_on <= i_pnf_cfg_on;
          reg_pnf_xtd <= i_pnf_cfg_xtd;
          reg_pnf_id <= i_pnf_cfg_id;
          reg_pnf_idm <= i_pnf_cfg_idm;
          reg_pnf_dlc_en <= i_pnf_cfg_dlc_en;
          reg_pnf_dlc <= i_pnf_cfg_dlc;
          for (int unsigned w_pnf_idx = 0; w_pnf_idx < PARA_CANFD_PN_NUM; w_pnf_idx++) begin
            reg_pnf_data[w_pnf_idx] <= {i_pnf_cfg_d1[w_pnf_idx], i_pnf_cfg_d0[w_pnf_idx]};
            reg_pnf_data_mask[w_pnf_idx] <=
              {i_pnf_cfg_dm1[w_pnf_idx], i_pnf_cfg_dm0[w_pnf_idx]};
          end
        end
      end

      // Compare received fields serially and retain only match flags and current field context.
      always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_pn_filter
        if (!i_rst_n_can) begin
          reg_pnf_match <= '0;
          reg_frame_active <= 1'b0;
          reg_frame_fd <= 1'b0;
          reg_frame_rtr <= 1'b0;
          reg_rx_dlc <= '0;
          reg_pn_wake_frame <= 1'b0;
          reg_pn_wake_idx <= '0;
        end else begin
          reg_pn_wake_frame <= 1'b0;
          if (!w_pn_filter_en) begin
            reg_pnf_match <= '0;
            reg_frame_active <= 1'b0;
            reg_frame_fd <= 1'b0;
            reg_frame_rtr <= 1'b0;
            reg_rx_dlc <= '0;
          end else begin
            if (i_rx_frame_start) begin
              reg_pnf_match <= reg_pnf_on;
              reg_frame_active <= 1'b1;
              reg_frame_fd <= 1'b0;
              reg_frame_rtr <= 1'b0;
              reg_rx_dlc <= '0;
            end else if (reg_frame_active) begin
              if (i_rx_abort) begin
                reg_pnf_match <= '0;
                reg_frame_active <= 1'b0;
                reg_frame_fd <= 1'b0;
              end else if (reg_frame_fd && i_bus_idle) begin
                reg_pnf_match <= '0;
                reg_frame_active <= 1'b0;
                reg_frame_fd <= 1'b0;
              end else begin
                if (i_rx_id_bit_valid && (i_rx_id_bit_idx < 5'(LPARA_PN_ID_NUM))) begin
                  for (int unsigned w_pnf_idx = 0; w_pnf_idx < PARA_CANFD_PN_NUM; w_pnf_idx++) begin
                    if (reg_pnf_match[w_pnf_idx] && reg_pnf_idm[w_pnf_idx][w_id_bit_pos] &&
                        (reg_pnf_id[w_pnf_idx][w_id_bit_pos] != i_rx_id_bit))
                      reg_pnf_match[w_pnf_idx] <= 1'b0;
                  end
                end
                if (i_rx_ide_valid) begin
                  for (int unsigned w_pnf_idx = 0; w_pnf_idx < PARA_CANFD_PN_NUM; w_pnf_idx++) begin
                    if (reg_pnf_match[w_pnf_idx] && (reg_pnf_xtd[w_pnf_idx] != i_rx_ide))
                      reg_pnf_match[w_pnf_idx] <= 1'b0;
                  end
                end
                if (i_rx_rtr_valid)
                  reg_frame_rtr <= i_rx_rtr;
                if (i_rx_fdf_valid && i_rx_fdf) begin
                  reg_frame_fd <= 1'b1;
                  reg_pnf_match <= '0;
                end
                if (i_rx_dlc_bit_valid) begin
                  reg_rx_dlc <= w_rx_dlc_nxt[2:0];
                  if (i_rx_dlc_bit_idx == 2'(LPARA_PN_DLC_LAST_IDX)) begin
                    for (int unsigned w_pnf_idx = 0; w_pnf_idx < PARA_CANFD_PN_NUM; w_pnf_idx++) begin
                      if (reg_pnf_match[w_pnf_idx] &&
                          ((reg_pnf_dlc_en[w_pnf_idx] &&
                            (reg_pnf_dlc[w_pnf_idx] != w_rx_dlc_nxt)) ||
                           (|(reg_pnf_data_mask[w_pnf_idx] & ~w_payload_mask))))
                        reg_pnf_match[w_pnf_idx] <= 1'b0;
                    end
                  end
                end
                if (i_rx_data_bit_valid) begin
                  for (int unsigned w_pnf_idx = 0; w_pnf_idx < PARA_CANFD_PN_NUM; w_pnf_idx++) begin
                    if (reg_pnf_match[w_pnf_idx] && reg_pnf_data_mask[w_pnf_idx][w_data_bit_pos] &&
                        (reg_pnf_data[w_pnf_idx][w_data_bit_pos] != i_rx_data_bit))
                      reg_pnf_match[w_pnf_idx] <= 1'b0;
                  end
                end
                if (i_rx_crc_delim) begin
                  if (!reg_frame_fd && i_rx_crc_ok && i_rx_stuff_ok && w_pnf_first_match) begin
                    reg_pn_wake_frame <= 1'b1;
                    reg_pn_wake_idx <= 4'(w_pnf_first_idx);
                  end
                  reg_frame_active <= 1'b0;
                  reg_pnf_match <= '0;
                end
              end
            end
          end
        end
      end
    end else begin : gen_pn_disabled
      // Disabled builds acknowledge configuration without activating the optional filter.
      assign o_pnf_cfg_ready = 1'b1;
      assign o_pn_wake_frame = 1'b0;
      assign o_pn_wake_idx = 4'd0;
    end
  endgenerate

endmodule
