/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-08
 * Description  : CAN receive synchronizer, nominal/data bit-time generator, primary sample point,
 *                minimum-tq event, hard/soft synchronization, edge filter and timing checks.
 *                Implements REQ-BTL-001 through REQ-BTL-008 and decisions DEC-061/074/075.
 */
`timescale 1ns/1ps

module m_canfd_btl #(
  // Parameter Description: include ISO CAN-FD bit-timing validation and data-phase switching.
  // Parameter values: 0 = Classic CAN only, 1 = Classic CAN and CAN FD; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_FD_EN = 32'd1,
  // Parameter Description: synchronizer structure for the asynchronous CAN RX input.
  // Parameter values: 0 = two DFF stages, 1 = VLSIT 2-FF cell; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_CELL_TYPE = 32'd0,
  localparam logic [31:0] LPARA_IPT_MAX = 32'd2,
  localparam logic [31:0] LPARA_NOM_TQ_MIN = 32'd8,
  localparam logic [31:0] LPARA_NOM_TQ_MAX = 32'd80,
  localparam logic [31:0] LPARA_DATA_TQ_MIN = 32'd5,
  localparam logic [31:0] LPARA_DATA_TQ_MAX = 32'd25,
  localparam logic [31:0] LPARA_DOM_RUN_MAX = 32'd2,
  localparam logic [31:0] LPARA_TQ_TWO = 32'd2,
  localparam logic [31:0] LPARA_NOM_TOTAL_RST = 32'd5,
  localparam logic [31:0] LPARA_DATA_TOTAL_RST = 32'd4,
  localparam logic [31:0] LPARA_NBRP_CODE_MAX = 32'd31,
  localparam logic [31:0] LPARA_NPROP_CODE_MAX = 32'd383,
  localparam logic [31:0] LPARA_NPROP_MAX = 32'd384,
  localparam logic [31:0] LPARA_DPROP_MAX = 32'd128
) (
  // CAN clock and reset
  input  wire        i_clk_can,
  input  wire        i_rst_n_can,

  // Asynchronous CAN receive pin
  input  wire        i_can_rx,

  // Timing configuration fields from the CAN-domain configuration snapshot
  input  wire  [8:0] i_cfd_nbt_nbrp,
  input  wire  [8:0] i_cfd_nbt_nprop,
  input  wire  [6:0] i_cfd_nbt_nphs1,
  input  wire  [6:0] i_cfd_nbt_nphs2,
  input  wire  [6:0] i_cfd_nbt2_nsjw,
  input  wire  [6:0] i_cfd_nbt2_dsjw,
  input  wire  [4:0] i_cfd_dbt_dbrp,
  input  wire  [7:0] i_cfd_dbt_dprop,
  input  wire  [6:0] i_cfd_dbt_dphs1,
  input  wire  [6:0] i_cfd_dbt_dphs2,
  input  wire        i_cfd_ctrl_efbi,
  input  wire        i_cfg_check,

  // Frame-state controls for synchronization and rate switching
  input  wire        i_bus_integrating,
  input  wire        i_hard_sync_en,
  input  wire        i_hs_edl,
  input  wire        i_tx_dom,
  input  wire        i_no_resync,
  input  wire        i_rate_data_candidate,
  input  wire        i_rate_nom_candidate,

  // Timing events and state to the frame engine and TDC
  output logic       o_sample,
  output logic       o_sample_val,
  output logic       o_tx_point,
  output logic       o_min_tq_tick,
  output logic       o_rx_sync,
  output logic       o_data_phase,

  // Timing-configuration result to the power controller and status logic
  output logic       o_timing_cfg_valid,
  output logic       o_cfg_fix_event
);

  // Segment encodings identify the current position inside one CAN bit time.
  typedef enum logic [1:0] {
    ENUM_SEG_SYNC = 2'b00,
    ENUM_SEG_1    = 2'b01,
    ENUM_SEG_2    = 2'b10
  } btl_segment_type_def;

  logic w_rx_sync;
  logic reg_rx_prev;
  logic reg_sample_q;
  logic reg_synced;
  logic [8:0] reg_div;
  logic [9:0] reg_t;
  logic [9:0] reg_len1;
  logic [7:0] reg_len2;
  logic reg_phase_data;
  logic [1:0] reg_dom_run;

  logic [4:0] w_nbrp_code;
  logic [5:0] w_nbrp_eff;
  logic [5:0] w_dbrp_eff;
  logic [9:0] w_nprop_eff;
  logic [7:0] w_nphs1_eff;
  logic [7:0] w_nphs2_eff;
  logic [7:0] w_nsjw_eff;
  logic [7:0] w_dprop_eff;
  logic [7:0] w_dphs1_eff;
  logic [7:0] w_dphs2_eff;
  logic [7:0] w_dsjw_eff;
  logic [9:0] w_nseg1;
  logic [9:0] w_dseg1;
  logic [9:0] w_nom_total;
  logic [9:0] w_data_total;
  logic w_scalar_fix;
  logic w_nom_valid;
  logic w_data_valid;
  logic w_cfg_tuple_valid;
  logic [5:0] w_brp_active;
  logic [9:0] w_seg1_active;
  logic [7:0] w_seg2_active;
  logic [7:0] w_sjw_active;
  logic [8:0] w_div_limit;
  logic w_tick;
  logic w_nom_tick;
  logic w_raw_edge;
  logic w_filtered_edge;
  logic w_sync_edge;
  logic w_edge_accept;
  btl_segment_type_def w_seg;
  logic [9:0] w_sync_t;
  logic [8:0] w_sync_div;
  logic [10:0] w_seg2_err;
  logic [9:0] w_cell_end;
  logic [10:0] w_sjw_plus1;
  logic reg_sample;
  logic reg_sample_val;
  logic reg_tx_point;
  logic reg_timing_cfg_valid;
  logic reg_cfg_fix_event;

  // Expose registered timing state and the shared synchronized bus level to the frame engine.
  // The output aliases keep the sequential state naming separate from the module interface.
  assign o_rx_sync = w_rx_sync;
  assign o_data_phase = reg_phase_data;
  assign o_sample = reg_sample;
  assign o_sample_val = reg_sample_val;
  assign o_tx_point = reg_tx_point;
  assign o_timing_cfg_valid = reg_timing_cfg_valid;
  assign o_cfg_fix_event = reg_cfg_fix_event;

  // The TDC timebase follows an actual BTL quantum update, not a second divider.
  assign o_min_tq_tick = w_tick && !i_cfg_check && !w_edge_accept;

  // Clamp scalar fields to the documented limits, then validate complete timing tuples.
  always_comb begin : p_com_btl_config
    w_nbrp_code = '0;
    w_nbrp_eff = 6'd1;
    w_dbrp_eff = 6'd1;
    w_nprop_eff = 10'd1;
    w_nphs1_eff = 8'd1;
    w_nphs2_eff = 8'(LPARA_TQ_TWO);
    w_nsjw_eff = 8'd1;
    w_dprop_eff = 8'd0;
    w_dphs1_eff = 8'd1;
    w_dphs2_eff = 8'(LPARA_TQ_TWO);
    w_dsjw_eff = 8'd1;
    w_nseg1 = 10'(LPARA_TQ_TWO);
    w_dseg1 = 10'd1;
    w_nom_total = 10'(LPARA_NOM_TOTAL_RST);
    w_data_total = 10'(LPARA_DATA_TOTAL_RST);
    w_scalar_fix = 1'b0;
    w_nom_valid = 1'b0;
    w_data_valid = 1'b0;
    w_cfg_tuple_valid = 1'b0;

    if (i_cfd_nbt_nbrp > 9'(LPARA_NBRP_CODE_MAX)) begin
      w_nbrp_code = 5'(LPARA_NBRP_CODE_MAX);
      w_scalar_fix = 1'b1;
    end else begin
      w_nbrp_code = i_cfd_nbt_nbrp[4:0];
    end
    w_nbrp_eff = $bits(w_nbrp_eff)'({1'b0, w_nbrp_code} + 6'd1);
    w_dbrp_eff = $bits(w_dbrp_eff)'({1'b0, i_cfd_dbt_dbrp} + 6'd1);

    if (i_cfd_nbt_nprop > 9'(LPARA_NPROP_CODE_MAX)) begin
      w_nprop_eff = 10'(LPARA_NPROP_MAX);
      w_scalar_fix = 1'b1;
    end else begin
      w_nprop_eff = $bits(w_nprop_eff)'({1'b0, i_cfd_nbt_nprop} + 10'd1);
    end
    w_nphs1_eff = $bits(w_nphs1_eff)'({1'b0, i_cfd_nbt_nphs1} + 8'd1);
    if (i_cfd_nbt_nphs2 == 7'd0) begin
      w_nphs2_eff = 8'(LPARA_TQ_TWO);
      w_scalar_fix = 1'b1;
    end else begin
      w_nphs2_eff = $bits(w_nphs2_eff)'({1'b0, i_cfd_nbt_nphs2} + 8'd1);
    end
    w_nsjw_eff = $bits(w_nsjw_eff)'({1'b0, i_cfd_nbt2_nsjw} + 8'd1);

    if (i_cfd_dbt_dprop > 8'(LPARA_DPROP_MAX)) begin
      w_dprop_eff = 8'(LPARA_DPROP_MAX);
      if (PARA_CANFD_FD_EN == 32'd1)
        w_scalar_fix = 1'b1;
    end else begin
      w_dprop_eff = i_cfd_dbt_dprop;
    end
    w_dphs1_eff = $bits(w_dphs1_eff)'({1'b0, i_cfd_dbt_dphs1} + 8'd1);
    if (i_cfd_dbt_dphs2 == 7'd0) begin
      w_dphs2_eff = 8'(LPARA_TQ_TWO);
      if (PARA_CANFD_FD_EN == 32'd1)
        w_scalar_fix = 1'b1;
    end else begin
      w_dphs2_eff = $bits(w_dphs2_eff)'({1'b0, i_cfd_dbt_dphs2} + 8'd1);
    end
    w_dsjw_eff = $bits(w_dsjw_eff)'({1'b0, i_cfd_nbt2_dsjw} + 8'd1);

    w_nseg1 = $bits(w_nseg1)'({2'b00, w_nphs1_eff} + w_nprop_eff);
    w_dseg1 = $bits(w_dseg1)'({2'b00, w_dphs1_eff} + {2'b00, w_dprop_eff});
    w_nom_total = $bits(w_nom_total)'(10'd1 + w_nprop_eff + {2'b00, w_nphs1_eff} +
                                      {2'b00, w_nphs2_eff});
    w_data_total = $bits(w_data_total)'(10'd1 + {2'b00, w_dprop_eff} +
                                        {2'b00, w_dphs1_eff} + {2'b00, w_dphs2_eff});

    w_nom_valid = (w_nom_total >= 10'(LPARA_NOM_TQ_MIN)) &&
                  (w_nom_total <= 10'(LPARA_NOM_TQ_MAX)) &&
                  ({2'b00, w_nphs2_eff} >= 10'(LPARA_IPT_MAX)) &&
                  ({2'b00, w_nphs2_eff} >= {2'b00, w_nsjw_eff}) &&
                  ({2'b00, w_nsjw_eff} <= {2'b00, w_nphs1_eff});
    w_data_valid = (w_data_total >= 10'(LPARA_DATA_TQ_MIN)) &&
                   (w_data_total <= 10'(LPARA_DATA_TQ_MAX)) &&
                   (w_dbrp_eff == w_nbrp_eff) &&
                   ({2'b00, w_dphs2_eff} >= 10'(LPARA_IPT_MAX)) &&
                   ({2'b00, w_dphs2_eff} >= {2'b00, w_dsjw_eff}) &&
                   ({2'b00, w_dsjw_eff} <= {2'b00, w_dphs1_eff}) &&
                   (w_data_total <= w_nom_total);
    w_cfg_tuple_valid = w_nom_valid &&
                        ((PARA_CANFD_FD_EN == 32'd0) || w_data_valid);
  end

  // Select one active phase and decode the time segment containing the current quantum.
  always_comb begin : p_com_btl_active
    w_brp_active = w_nbrp_eff;
    w_seg1_active = w_nseg1;
    w_seg2_active = w_nphs2_eff;
    w_sjw_active = w_nsjw_eff;
    if ((PARA_CANFD_FD_EN == 32'd1) && reg_phase_data) begin
      w_brp_active = w_dbrp_eff;
      w_seg1_active = w_dseg1;
      w_seg2_active = w_dphs2_eff;
      w_sjw_active = w_dsjw_eff;
    end
    w_div_limit = $bits(w_div_limit)'({3'b000, w_brp_active} - 9'd1);
    w_tick = (reg_div == w_div_limit);
    w_nom_tick = (reg_div == $bits(w_div_limit)'({3'b000, w_nbrp_eff} - 9'd1));

    w_seg = ENUM_SEG_SYNC;
    if (reg_t == 10'd0)
      w_seg = ENUM_SEG_SYNC;
    else if (reg_t <= reg_len1)
      w_seg = ENUM_SEG_1;
    else
      w_seg = ENUM_SEG_2;

    w_seg2_err = $bits(w_seg2_err)'(11'd1 + {1'b0, reg_len1} + {3'b000, reg_len2} -
                                    {1'b0, reg_t});
    w_cell_end = $bits(w_cell_end)'(reg_len1 + {2'b00, reg_len2});
    w_raw_edge = (w_rx_sync == 1'b0) && (reg_rx_prev == 1'b1) &&
                 (reg_sample_q == 1'b1) && (reg_synced == 1'b0);
    w_filtered_edge = i_bus_integrating && i_hard_sync_en && i_cfd_ctrl_efbi &&
                      w_nom_tick && (reg_dom_run >= 2'd1) && (w_rx_sync == 1'b0) &&
                      (reg_sample_q == 1'b1) && (reg_synced == 1'b0);
    w_sync_edge = 1'b0;
    if (i_bus_integrating && i_cfd_ctrl_efbi)
      w_sync_edge = w_filtered_edge;
    else
      w_sync_edge = w_raw_edge;
    w_edge_accept = w_sync_edge && !i_no_resync;

    w_sync_t = '0;
    if (w_brp_active > 6'd1)
      w_sync_t = 10'd0;
    else
      w_sync_t = 10'd1;
    w_sync_div = '0;
    if (w_brp_active > 6'd1)
      w_sync_div = 9'd1;
    w_sjw_plus1 = $bits(w_sjw_plus1)'({3'b000, w_sjw_active} + 11'd1);
  end

  // Track the synchronized bus history used for edge eligibility.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_btl_rxhist
    if (!i_rst_n_can)
      reg_rx_prev <= 1'b1;
    else
      reg_rx_prev <= w_rx_sync;
  end

  // Advance the prescaler, bit cell, synchronization state and registered timing outputs.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_btl_state
    if (!i_rst_n_can) begin
      reg_sample_q <= 1'b1;
      reg_synced <= 1'b0;
      reg_div <= 9'd0;
      reg_t <= 10'd0;
      reg_len1 <= 10'd1;
      reg_len2 <= 8'(LPARA_TQ_TWO);
      reg_phase_data <= 1'b0;
      reg_dom_run <= 2'd0;
      reg_sample <= 1'b0;
      reg_sample_val <= 1'b1;
      reg_tx_point <= 1'b0;
      reg_timing_cfg_valid <= 1'b0;
      reg_cfg_fix_event <= 1'b0;
    end else begin
      reg_sample <= 1'b0;
      reg_tx_point <= 1'b0;
      reg_cfg_fix_event <= 1'b0;

      if (i_cfg_check) begin
        reg_timing_cfg_valid <= w_cfg_tuple_valid;
        reg_cfg_fix_event <= w_scalar_fix || !w_cfg_tuple_valid;
        // Rebase the bit cell to the clamped nominal tuple while the core stays in INIT.
        reg_sample_q <= 1'b1;
        reg_synced <= 1'b0;
        reg_div <= '0;
        reg_t <= '0;
        reg_len1 <= w_nseg1;
        reg_len2 <= w_nphs2_eff;
        reg_phase_data <= 1'b0;
        reg_dom_run <= '0;
        reg_sample_val <= 1'b1;
      end else begin
        // Count consecutive dominant nominal quanta only during bus integration/recovery.
        if (!i_bus_integrating || !i_cfd_ctrl_efbi) begin
          reg_dom_run <= '0;
        end else if (w_nom_tick) begin
          if (w_rx_sync == 1'b0) begin
            if (reg_dom_run < 2'(LPARA_DOM_RUN_MAX))
              reg_dom_run <= $bits(reg_dom_run)'(reg_dom_run + 2'd1);
          end else begin
            reg_dom_run <= '0;
          end
        end else begin
          // Hold the count between nominal time-quantum boundaries.
        end

        // Apply at most one synchronization between successive sample points.
        if (w_edge_accept) begin
          if (i_hard_sync_en || i_hs_edl) begin
            reg_t <= w_sync_t;
            reg_div <= w_sync_div;
            reg_len1 <= w_seg1_active;
            reg_len2 <= w_seg2_active;
            reg_synced <= 1'b1;
          end else begin
            case (w_seg)
              ENUM_SEG_SYNC: begin
                reg_synced <= 1'b1;
              end
              ENUM_SEG_1: begin
                if (!i_tx_dom) begin
                  if (reg_t <= {2'b00, w_sjw_active}) begin
                    reg_t <= w_sync_t;
                    reg_div <= w_sync_div;
                    reg_len1 <= w_seg1_active;
                    reg_len2 <= w_seg2_active;
                    reg_synced <= 1'b1;
                  end else begin
                    reg_len1 <= $bits(reg_len1)'(reg_len1 + {2'b00, w_sjw_active});
                    reg_synced <= 1'b1;
                  end
                end
              end
              ENUM_SEG_2: begin
                if (w_seg2_err < w_sjw_plus1) begin
                  reg_t <= w_sync_t;
                  reg_div <= w_sync_div;
                  reg_len1 <= w_seg1_active;
                  reg_len2 <= w_seg2_active;
                  reg_synced <= 1'b1;
                end else begin
                  reg_len2 <= $bits(reg_len2)'(reg_len2 - w_sjw_active[7:0]);
                  reg_synced <= 1'b1;
                end
              end
              default: begin
                reg_synced <= 1'b1;
              end
            endcase
          end
        end else if (w_tick) begin
          // Sample once at the end of SEG1, then advance or wrap the current bit cell.
          reg_div <= '0;
          if (reg_t == reg_len1) begin
            reg_sample <= 1'b1;
            reg_sample_val <= w_rx_sync;
            reg_sample_q <= w_rx_sync;
            reg_synced <= 1'b0;
            if (i_rate_nom_candidate) begin
              reg_phase_data <= 1'b0;
              reg_len2 <= w_nphs2_eff;
            end else if ((PARA_CANFD_FD_EN == 32'd1) && i_rate_data_candidate &&
                         (w_rx_sync == 1'b1)) begin
              reg_phase_data <= 1'b1;
              reg_len2 <= w_dphs2_eff;
            end
          end

          if (reg_t == w_cell_end) begin
            reg_t <= '0;
            reg_len1 <= w_seg1_active;
            reg_len2 <= w_seg2_active;
            reg_tx_point <= 1'b1;
          end else begin
            reg_t <= $bits(reg_t)'(reg_t + 10'd1);
          end
        end else begin
          reg_div <= $bits(reg_div)'(reg_div + 9'd1);
        end
      end
    end
  end

  // The receive pin is asynchronous and idles recessive, so the synchronizer resets to logic 1.
  m_canfd_sync_bit #(
    .PARA_CANFD_CELL_TYPE    (PARA_CANFD_CELL_TYPE),
    .PARA_CANFD_SYNC_RST_VAL (32'd1)
  ) u_canfd_sync_bit_0 (
    .i_clk_dst   (i_clk_can),
    .i_rst_n_dst (i_rst_n_can),
    .i_data      (i_can_rx),
    .o_data      (w_rx_sync)
  );

endmodule
