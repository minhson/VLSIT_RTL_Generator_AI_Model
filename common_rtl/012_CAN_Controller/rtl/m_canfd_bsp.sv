/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-11
 * Description  : Sequences CAN frame fields, performs arbitration and frame checks, and connects
 *                the BTL, stuffing, CRC and TDC functions.
 *                This functional block is not the design top; its CRC and stuffing instances are
 *                implementation leaves beneath the structural top module.
 * DEC IDs      : DEC-033, DEC-034, DEC-035, DEC-069, DEC-072, DEC-086, DEC-087,
 *                DEC-091, DEC-096, DEC-102, DEC-103, DEC-113, DEC-118, DEC-119, DEC-120
 */
`timescale 1ns/1ps

module m_canfd_bsp #(
  // Parameter Description: enable Classical CAN and ISO FD frame sequencing.
  // Parameter values: 0 = Classic only, 1 = Classic and FD; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_FD_EN = 32'd1,
  // Parameter Description: enable the source-limited Bosch non-ISO FD profile.
  // Parameter values: 0 = disabled, 1 = enabled; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_NISO_EN = 32'd1,
  // Parameter Description: enable Classical CAN remote frames.
  // Parameter values: 0 = disabled, 1 = enabled; default is 1.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_RTR_EN = 32'd1,
  // Parameter Description: maximum payload bytes in the internal frame bundle.
  // Parameter values: 8, 12, 16, 20, 24, 32, 48 or 64; default is 64.
  // Parameter unit: byte
  parameter logic [31:0] PARA_CANFD_DATA_MAX = 32'd64,
  localparam logic [31:0] LPARA_CANFD_FRAME_W =
    32'd32 * (32'd4 + PARA_CANFD_DATA_MAX / 32'd4),
  localparam logic [31:0] LPARA_PAYLOAD_W = PARA_CANFD_DATA_MAX * 32'd8,
  localparam logic [31:0] LPARA_IDLE_BITS = 32'd11,
  localparam logic [31:0] LPARA_INTERM_BITS = 32'd3,
  localparam logic [31:0] LPARA_DLC_FD_9 = 32'd12,
  localparam logic [31:0] LPARA_DLC_FD_10 = 32'd16,
  localparam logic [31:0] LPARA_DLC_FD_11 = 32'd20,
  localparam logic [31:0] LPARA_DLC_FD_12 = 32'd24,
  localparam logic [31:0] LPARA_DLC_FD_13 = 32'd32,
  localparam logic [31:0] LPARA_DLC_FD_14 = 32'd48,
  localparam logic [31:0] LPARA_DLC_FD_15 = 32'd64
) (
  // Clock and reset
  input  wire                            i_clk_can,
  input  wire                            i_rst_n_can,

  // Clock-domain readiness
  input  wire                            i_cdc_ready_can,

  // Controller mode and frame-format controls
  input  wire                            i_cfd_ctrl_init,
  input  wire                            i_cfd_ctrl_fdoe,
  input  wire                            i_cfd_ctrl_brse,
  input  wire                            i_cfd_ctrl_niso,
  input  wire                            i_cfd_ctrl_pxd,
  input  wire                            i_cfd_ctrl_mon,
  input  wire                            i_cfd_ctrl_rest,
  input  wire                            i_cfd_ctrl_lbk_int,
  input  wire                            i_cfd_ctrl_lbk_ext,
  input  wire                            i_cfd_ctrl_dar,
  input  wire                            i_cfd_ctrl_tdc_ena,
  input  wire                            i_cfd_ctrl_ovl_en,
  input  wire  [7:0]                     i_cfd_dom_cfg_dom_lim,
  input  wire                            i_tx_permit,
  input  wire                            i_rx_frame_full_can,
  input  wire  [31:0]                    i_tx_timestamp_can,
  input  wire  [31:0]                    i_rx_timestamp_can,
  input  wire                            i_tx_result_ready_can,
  input  wire                            i_tt_ref_result_ready_can,

  // Error-management state
  input  wire                            i_err_passive,
  input  wire                            i_bus_off,

  // BTL sample and transmit timing
  input  wire                            i_sample,
  input  wire                            i_sample_val,
  input  wire                            i_rx_sync,
  input  wire                            i_tx_point,
  input  wire                            i_data_phase,
  input  wire                            i_timing_cfg_valid,
  input  wire                            i_btl_cfg_fix_event,

  // TDC feedback
  input  wire                            i_tdc_active,
  input  wire                            i_tdc_bit_err,

  // Tx frame bundle
  // Per REQ-MSG-021, BSP ignores reserved metadata words 2/3 and header bits.
  input  wire                            i_tx_frame_valid_can,
  input  wire  [LPARA_CANFD_FRAME_W-1:0] i_tx_frame_can,
  input  wire                            i_tx_trigger_tag_valid_can,
  input  wire  [5:0]                     i_tx_trigger_buf_can,
  input  wire  [31:0]                    i_tx_trigger_window_seq_can,
  input  wire  [31:0]                    i_tt_window_seq_can,
  output logic                           o_tx_frame_ready_can,
  input  wire                            i_tt_ref_frame_valid_can,
  input  wire  [LPARA_CANFD_FRAME_W-1:0] i_tt_ref_frame_can,
  output logic                           o_tt_ref_frame_ready_can,

  // Rx frame bundle
  output logic                           o_rx_frame_valid_can,
  output logic [LPARA_CANFD_FRAME_W-1:0] o_rx_frame_can,

  // Partial-networking receive observations at the sampled, destuffed field stream
  output logic                           o_rx_sof_sample,
  output logic                           o_rx_frame_start,
  output logic                           o_rx_frame_abort,
  output logic                           o_rx_id_bit_valid,
  output logic                           o_rx_id_bit,
  output logic [4:0]                     o_rx_id_bit_idx,
  output logic                           o_rx_ide_valid,
  output logic                           o_rx_ide,
  output logic                           o_rx_rtr_valid,
  output logic                           o_rx_rtr,
  output logic                           o_rx_fdf_valid,
  output logic                           o_rx_fdf,
  output logic                           o_rx_dlc_bit_valid,
  output logic                           o_rx_dlc_bit,
  output logic [1:0]                     o_rx_dlc_bit_idx,
  output logic                           o_rx_data_bit_valid,
  output logic                           o_rx_data_bit,
  output logic [5:0]                     o_rx_data_bit_idx,
  output logic                           o_rx_crc_delim,
  output logic                           o_rx_crc_ok,
  output logic                           o_rx_stuff_ok,

  // CAN transmit pin value
  output logic                           o_can_tx,
  output logic                           o_can_tx_nxt,
  output logic                           o_frame_active,
  output logic                           o_bus_idle,

  // Tx SOF capture pulse and atomic terminal result
  output logic                           o_tx_sof_sample,
  output logic                           o_sof_sample_can,

  // Tx terminal result
  output logic                           o_tx_result_valid,
  output logic                           o_tx_result_success,
  output logic                           o_tx_result_cancel,
  output logic                           o_tx_result_err,
  output logic                           o_tx_result_arb_lost,
  output logic [31:0]                    o_tx_result_timestamp,
  output logic                           o_tx_result_trigger_valid,
  output logic [5:0]                     o_tx_result_trigger_buf,
  output logic                           o_tx_result_trigger_started,
  output logic                           o_tx_result_trigger_expired,
  output logic                           o_tt_ref_result_valid,
  output logic                           o_tt_ref_result_success,
  output logic                           o_tt_ref_result_cancel,
  output logic                           o_tt_ref_result_err,
  output logic                           o_tt_ref_result_arb_lost,
  output logic [31:0]                    o_tt_ref_result_timestamp,

  // Fault-confinement events
  output logic                           o_evt_rx_err,
  output logic                           o_evt_rx_dom_after_flag,
  output logic                           o_evt_tx_err_count,
  output logic                           o_evt_tx_bit_err_flag,
  output logic                           o_evt_rx_bit_err_flag,
  output logic                           o_evt_tx_dom_seq8,
  output logic                           o_evt_rx_dom_seq8,
  output logic                           o_evt_tx_success,
  output logic                           o_evt_rx_success,
  output logic                           o_evt_idle11,

  // First-error capture
  output logic                           o_err_start,
  output logic                           o_err_phase_data,
  output logic [2:0]                     o_err_code,

  // Frame-engine status
  output logic [1:0]                     o_sts_act,
  output logic                           o_evt_err_arb,
  output logic                           o_evt_err_dat,
  output logic                           o_sts_init_ack,
  output logic                           o_sts_rfdf,
  output logic                           o_sts_rbrs,
  output logic                           o_sts_resi,
  output logic                           o_sts_pxe,
  output logic                           o_sts_dom_stk,

  // Protocol and stuck-dominant events
  output logic                           o_evt_crc_err,
  output logic                           o_evt_stuff_err,
  output logic                           o_evt_form_err,
  output logic                           o_evt_ack_err,
  output logic                           o_evt_pxe,
  output logic                           o_evt_dom_to,

  // BTL control outputs
  output logic                           o_cfg_check,
  output logic                           o_bus_integrating,
  output logic                           o_hard_sync_en,
  output logic                           o_hs_edl,
  output logic                           o_tx_dom,
  output logic                           o_no_resync,
  output logic                           o_rate_data_candidate,
  output logic                           o_rate_nom_candidate,
  output logic                           o_prev_sample_rec,

  // TDC qualification outputs
  output logic                           o_tdc_frame_active,
  output logic                           o_tdc_measure_start
);

  // State encodings follow the frame-field order in HDS section 10.7.
  typedef enum logic [4:0] {
    ENUM_ST_INTEG    = 5'd0,
    ENUM_ST_IDLE     = 5'd1,
    ENUM_ST_SOF      = 5'd2,
    ENUM_ST_ID_A     = 5'd3,
    ENUM_ST_RTR1     = 5'd4,
    ENUM_ST_IDE      = 5'd5,
    ENUM_ST_ID_B     = 5'd6,
    ENUM_ST_RTR2     = 5'd7,
    ENUM_ST_FDF      = 5'd8,
    ENUM_ST_R0       = 5'd9,
    ENUM_ST_RES      = 5'd10,
    ENUM_ST_BRS      = 5'd11,
    ENUM_ST_ESI      = 5'd12,
    ENUM_ST_DLC      = 5'd13,
    ENUM_ST_DATA     = 5'd14,
    ENUM_ST_FIX_PRE  = 5'd15,
    ENUM_ST_SBC      = 5'd16,
    ENUM_ST_FIX      = 5'd17,
    ENUM_ST_CRC      = 5'd18,
    ENUM_ST_CRC_DEL  = 5'd19,
    ENUM_ST_CRC_WAIT = 5'd20,
    ENUM_ST_ACK      = 5'd21,
    ENUM_ST_ACK_DEL  = 5'd22,
    ENUM_ST_EOF      = 5'd23,
    ENUM_ST_INTERM   = 5'd24,
    ENUM_ST_SUSP     = 5'd25,
    ENUM_ST_ERR_FLAG = 5'd26,
    ENUM_ST_ERR_DEL  = 5'd27,
    ENUM_ST_OVL      = 5'd28,
    ENUM_ST_BUS_OFF  = 5'd29
  } bsp_state_type_def;

  // Internal signal declarations
  bsp_state_type_def reg_fsm_bsp_current_state;
  bsp_state_type_def w_fsm_bsp_nxt_state;
  logic [3:0] reg_idle_count;
  logic [3:0] reg_interm_count;
  logic [3:0] reg_err_count;
  logic [3:0] reg_err_del_count;
  logic       reg_err_del_first_seen;
  logic [3:0] reg_crc_wait_count;
  logic [3:0] reg_suspend_count;
  logic [3:0] reg_ovl_req_count;
  logic [2:0] reg_del_dom_count;
  logic [9:0] reg_field_idx;
  logic [5:0] reg_fd_seq_count;
  logic [5:0] reg_fd_seq_total;
  logic [6:0] reg_data_len;
  logic [3:0] reg_tx_dlc;
  logic [3:0] reg_rx_dlc;
  logic [28:0] reg_tx_id;
  logic [28:0] reg_rx_id;
  logic reg_tx_xtd;
  logic reg_rx_xtd;
  logic reg_tx_rtr;
  logic w_frame_xtd;
  logic reg_rx_rtr;
  logic reg_frame_fd;
  logic reg_frame_brs;
  logic reg_frame_niso;
  logic reg_rx_esi;
  logic reg_rx_res;
  logic reg_tx_buf_valid;
  logic reg_tx_owner_tt;
  logic reg_tx_trigger_valid;
  logic [5:0] reg_tx_trigger_buf;
  logic [31:0] reg_tx_trigger_window_seq;
  logic reg_tx_trigger_started;
  logic reg_tx_trigger_expired;
  logic reg_tx_fd;
  logic reg_tx_brs;
  logic reg_tx_niso;
  logic [6:0] reg_tx_data_len;
  logic [2:0] reg_err_code;
  logic reg_err_phase_data;
  logic reg_err_start;
  logic reg_evt_ack_err;
  logic reg_evt_crc_err;
  logic reg_evt_dom_to;
  logic reg_evt_form_err;
  logic reg_evt_idle11;
  logic reg_evt_pxe;
  logic reg_evt_rx_bit_err_flag;
  logic reg_evt_rx_dom_after_flag;
  logic reg_evt_rx_dom_seq8;
  logic reg_evt_rx_err;
  logic reg_evt_rx_success;
  logic reg_evt_stuff_err;
  logic reg_evt_tx_bit_err_flag;
  logic reg_evt_tx_dom_seq8;
  logic reg_evt_tx_err_count;
  logic reg_evt_tx_success;
  logic reg_rx_frame_valid_can;
  logic reg_tx_result_cancel;
  logic reg_tx_result_err;
  logic reg_tx_result_arb_lost;
  logic reg_tx_result_success;
  logic reg_tx_result_valid;
  logic [31:0] reg_tx_result_timestamp;
  logic reg_tx_result_trigger_valid;
  logic [5:0] reg_tx_result_trigger_buf;
  logic reg_tx_result_trigger_started;
  logic reg_tx_result_trigger_expired;
  logic reg_tx_role;
  logic w_act_run;
  logic reg_rx_store_en;
  logic reg_frame_good;
  logic reg_crc_bad;
  logic reg_ack_seen;
  logic reg_crc_del2_seen;
  logic reg_ack_dom_seen;
  logic w_ack_tol_en;
  logic w_crc_del2;
  logic reg_err_seen;
  logic reg_err_passive;
  logic reg_rx_start_seen;
  logic reg_rx_frame_fd;
  logic reg_rx_frame_brs;
  logic reg_rx_frame_xtd;
  logic reg_rx_frame_rtr;
  logic reg_rx_frame_esi;
  logic [31:0] reg_rx_timestamp;
  logic reg_dom_stk;
  logic reg_dom_event_sent;
  logic [7:0] reg_dom_count;
  logic reg_tx_passive_ack_pending;
  logic reg_tx_passive_ack_dom_seen;
  logic reg_tx_adv;
  logic reg_tx_fixed;
  logic reg_tx_bit_sent;
  logic w_tx_bit_nxt;
  logic w_tx_own_bit;
  logic reg_tx_cmp_en;
  logic [LPARA_PAYLOAD_W-1:0] reg_tx_payload;
  logic [LPARA_PAYLOAD_W-1:0] reg_rx_payload;
  logic [19:0] reg_rx_crc_shift;
  logic [2:0] reg_rx_sbc;
  logic [30:0] w_tx_header0;
  logic [5:0] w_tx_header1;
  logic [LPARA_PAYLOAD_W-1:0] w_tx_payload;
  logic [6:0] w_tx_len_raw;
  logic [6:0] w_tx_len_cfg;
  logic [3:0] w_tx_dlc_cfg;
  logic [6:0] w_rx_len_calc;
  logic [6:0] w_crc_len;
  logic [8:0] w_data_bit_pos;
  logic       w_tx_dyn_stuff;
  logic       w_tx_fixed_stuff;
  logic [7:0] w_dom_limit;
  logic w_rx_wire_bit;
  logic w_rx_sof_start;
  logic w_rx_sof_pre;
  logic w_tx_accept;
  logic w_tx_frame_ready_common;
  logic w_tx_result_ready;
  logic w_tx_start;
  logic w_tx_trigger_expire_pending;
  logic w_tx_sof_sample;
  logic w_tx_field_step;
  logic w_rx_field_step;
  logic w_frame_step;
  logic w_fixed_slot;
  logic w_dyn_stuf_en;
  logic w_crc_init;
  logic w_crc_rx_mismatch;
  logic w_sbc_last;
  logic w_arb_field;
  logic w_arb_loss;
  logic w_tx_bit_err;
  logic w_flag_bit_err;
  logic w_tx_exception2;
  logic w_form_err;
  logic w_stuff_err;
  logic w_ack_err;
  logic w_err_detect;
  logic w_err_del_done;
  logic w_pxe_event;
  logic w_err_first;
  logic w_tx_logic_bit;
  logic w_tx_wire_bit;
  logic w_tx_logical_adv;
  logic w_rx_bit;
  logic w_rx_bit_valid;
  logic w_rx_dyn_stuff;
  logic w_rx_stuff_err;
  logic w_rx_fixed_err;
  logic w_rx_sbc_err;
  logic [3:0] w_tx_sbc_code;
  logic [14:0] w_crc15;
  logic [16:0] w_crc17;
  logic [20:0] w_crc21;
  logic [20:0] w_crc_rx_shift_nxt;
  logic [3:0] w_rx_dlc_nxt;
  logic w_frame_active;
  logic w_rx_protected;
  logic w_tx_end_good;
  logic w_rx_end_good;
  logic w_rx_store_end;
  logic w_dom_reached;
  
  // Convert a DLC to the payload length in bytes for Classic and FD frames.
  function automatic logic [6:0] f_dlc_len(
    input logic [3:0] i_dlc,
    input logic i_fd
  );
    f_dlc_len = 7'd0;
    casez ({i_fd, i_dlc})
      5'b0_0000: f_dlc_len = 7'd0;
      5'b0_0001: f_dlc_len = 7'd1;
      5'b0_0010: f_dlc_len = 7'd2;
      5'b0_0011: f_dlc_len = 7'd3;
      5'b0_0100: f_dlc_len = 7'd4;
      5'b0_0101: f_dlc_len = 7'd5;
      5'b0_0110: f_dlc_len = 7'd6;
      5'b0_0111: f_dlc_len = 7'd7;
      5'b0_1???: f_dlc_len = 7'd8;
      5'b1_0000: f_dlc_len = 7'd0;
      5'b1_0001: f_dlc_len = 7'd1;
      5'b1_0010: f_dlc_len = 7'd2;
      5'b1_0011: f_dlc_len = 7'd3;
      5'b1_0100: f_dlc_len = 7'd4;
      5'b1_0101: f_dlc_len = 7'd5;
      5'b1_0110: f_dlc_len = 7'd6;
      5'b1_0111: f_dlc_len = 7'd7;
      5'b1_1000: f_dlc_len = 7'd8;
      5'b1_1001: f_dlc_len = 7'(LPARA_DLC_FD_9);
      5'b1_1010: f_dlc_len = 7'(LPARA_DLC_FD_10);
      5'b1_1011: f_dlc_len = 7'(LPARA_DLC_FD_11);
      5'b1_1100: f_dlc_len = 7'(LPARA_DLC_FD_12);
      5'b1_1101: f_dlc_len = 7'(LPARA_DLC_FD_13);
      5'b1_1110: f_dlc_len = 7'(LPARA_DLC_FD_14);
      5'b1_1111: f_dlc_len = 7'(LPARA_DLC_FD_15);
      default:   f_dlc_len = 7'd0;
    endcase
  endfunction

  // Select the highest DLC code that fits the configured payload size.
  function automatic logic [3:0] f_max_dlc;
    f_max_dlc = 4'd8;
    case (PARA_CANFD_DATA_MAX)
      32'd8:  f_max_dlc = 4'd8;
      32'd12: f_max_dlc = 4'd9;
      32'd16: f_max_dlc = 4'd10;
      32'd20: f_max_dlc = 4'd11;
      32'd24: f_max_dlc = 4'd12;
      32'd32: f_max_dlc = 4'd13;
      32'd48: f_max_dlc = 4'd14;
      32'd64: f_max_dlc = 4'd15;
      default: f_max_dlc = 4'd8;
    endcase
  endfunction

  // Map the bundle's fixed word positions to the Tx element headers and payload.
  assign w_tx_header0 = i_tt_ref_frame_valid_can ? i_tt_ref_frame_can[30:0] :
                                                     i_tx_frame_can[30:0];
  // Select the common flags/DLC word; reserved bits in this word are not consumed by BSP.
  assign w_tx_header1 = i_tt_ref_frame_valid_can ? i_tt_ref_frame_can[53:48] :
                                                     i_tx_frame_can[53:48];
  // The fixed word-4 payload offset leaves metadata words 2/3 unused in this frame engine.
  assign w_tx_payload = i_tt_ref_frame_valid_can ?
                        i_tt_ref_frame_can[LPARA_CANFD_FRAME_W-1:128] :
                        i_tx_frame_can[LPARA_CANFD_FRAME_W-1:128];

  // Clamp Tx DLC and length to this build's payload capacity.
  always_comb begin : p_com_tx_len
    w_tx_dlc_cfg = w_tx_header1[3:0];
    w_tx_len_raw = f_dlc_len(w_tx_dlc_cfg, w_tx_header1[5]);
    if (w_tx_header1[5] && (w_tx_len_raw > 7'(PARA_CANFD_DATA_MAX))) begin
      w_tx_dlc_cfg = f_max_dlc();
      w_tx_len_raw = f_dlc_len(w_tx_dlc_cfg, 1'b1);
    end
    if (!w_tx_header1[5] && (w_tx_len_raw > 7'd8)) begin
      w_tx_dlc_cfg = 4'd8;
      w_tx_len_raw = 7'd8;
    end
    w_tx_len_cfg = w_tx_header0[29] ? 7'd0 : w_tx_len_raw;
    if (w_tx_header0[29] && w_tx_header1[5]) begin
      w_tx_dlc_cfg = 4'd0;
      w_tx_len_cfg = 7'd0;
    end
  end

  // Decode received DLC size and derive the active CRC sequence length.
  assign w_rx_dlc_nxt = {reg_rx_dlc[2:0], w_rx_bit};
  assign w_rx_len_calc = reg_rx_rtr ? 7'd0 : f_dlc_len(w_rx_dlc_nxt, reg_frame_fd);
  assign w_crc_len = reg_frame_fd ?
                     ((reg_data_len > 7'd16) ? 7'd21 : 7'd17) : 7'd15;
  assign w_crc_rx_shift_nxt = {reg_rx_crc_shift[19:0], w_rx_bit};
  assign w_frame_xtd = reg_tx_role ? reg_tx_xtd : w_rx_bit;

  // Qualify handshakes, frame starts and the bus sample source.
  // While the TDC checks the echo at the secondary sample point (ESI to CRC of a sent FD frame),
  // the transmitter destuffs and checks the CRC on its own bit; a different level is a TDC error.
  assign w_tx_own_bit = reg_tx_role && i_tdc_active;
  assign w_rx_wire_bit = ((i_cfd_ctrl_lbk_int || i_cfd_ctrl_lbk_ext) && reg_tx_role &&
                          (reg_fsm_bsp_current_state == ENUM_ST_ACK)) ? 1'b0 :
                         ((i_cfd_ctrl_lbk_int || w_tx_own_bit) ? reg_tx_bit_sent : i_sample_val);

  // Accept new Tx frames only when the frame engine and downstream CDC can hold one.
  assign w_tx_frame_ready_common = !reg_tx_buf_valid && !reg_tx_result_valid &&
                                   ((reg_fsm_bsp_current_state == ENUM_ST_IDLE) ||
                                    (reg_fsm_bsp_current_state == ENUM_ST_INTEG)) &&
                                   i_cdc_ready_can && !i_cfd_ctrl_init && !i_bus_off;
  // TT can see this shared-slot readiness only while the common Tx-permission gate is active.
  assign o_tt_ref_frame_ready_can = w_tx_frame_ready_common && i_tx_permit;
  // Give an accepted-at-trigger TT reference frame priority over a simultaneous ordinary CDC frame.
  assign o_tx_frame_ready_can = w_tx_frame_ready_common && !i_tt_ref_frame_valid_can;
  assign w_tx_accept = (i_tt_ref_frame_valid_can && o_tt_ref_frame_ready_can) ||
                       (!i_tt_ref_frame_valid_can && i_tx_frame_valid_can &&
                        o_tx_frame_ready_can);
  // Route the single held result to the owner recorded at frame acceptance.
  assign w_tx_result_ready = reg_tx_owner_tt ? i_tt_ref_result_ready_can :
                                                i_tx_result_ready_can;
  // DEC-102: Tx permission gates only a new SOF; the active-frame FSM runs to its terminal result.
  // A stale tagged frame waiting in IDLE yields a no-SOF miss.
  // It cannot start in a later window.
  assign w_tx_trigger_expire_pending = reg_tx_buf_valid && reg_tx_trigger_valid &&
                                       !reg_tx_role &&
                                       (!i_tx_permit ||
                                        (i_tt_window_seq_can != reg_tx_trigger_window_seq));
  assign w_tx_start = (reg_fsm_bsp_current_state == ENUM_ST_IDLE) &&
                      i_tx_point && reg_tx_buf_valid && i_tx_permit &&
                      !w_tx_trigger_expire_pending &&
                      (reg_idle_count >= 4'(LPARA_INTERM_BITS)) &&
                      !i_cfd_ctrl_init && i_cdc_ready_can && !i_bus_off &&
                      !i_cfd_ctrl_mon && !i_cfd_ctrl_rest && i_timing_cfg_valid &&
                      !reg_tx_result_valid;
  assign w_tx_sof_sample = i_sample && reg_tx_role &&
                           (reg_fsm_bsp_current_state == ENUM_ST_SOF);
  assign w_rx_sof_start = i_sample && !w_rx_wire_bit &&
                          (((reg_fsm_bsp_current_state == ENUM_ST_IDLE) &&
                            (reg_idle_count >= 4'(LPARA_IDLE_BITS))) ||
                           ((reg_fsm_bsp_current_state == ENUM_ST_INTERM) &&
                            (reg_interm_count == 4'd2)));
  assign w_rx_sof_pre = (reg_fsm_bsp_current_state == ENUM_ST_IDLE) &&
                        !i_rx_sync && !reg_rx_start_seen &&
                        (reg_idle_count >= 4'(LPARA_IDLE_BITS));

  // Define stuffing regions, frame activity and CRC coverage from the current field.
  always_comb begin : p_com_field_ctrl
    w_fixed_slot = 1'b0;
    w_dyn_stuf_en = 1'b0;
    w_frame_active = 1'b0;
    w_rx_protected = 1'b0;
    case (reg_fsm_bsp_current_state)
      ENUM_ST_SOF, ENUM_ST_ID_A, ENUM_ST_RTR1, ENUM_ST_IDE, ENUM_ST_ID_B,
      ENUM_ST_RTR2, ENUM_ST_FDF, ENUM_ST_R0, ENUM_ST_RES, ENUM_ST_BRS,
      ENUM_ST_ESI, ENUM_ST_DLC, ENUM_ST_DATA, ENUM_ST_SBC, ENUM_ST_CRC,
      ENUM_ST_CRC_DEL, ENUM_ST_ACK, ENUM_ST_ACK_DEL, ENUM_ST_EOF:
        w_frame_active = 1'b1;
      default: w_frame_active = 1'b0;
    endcase

    if ((reg_fsm_bsp_current_state == ENUM_ST_FIX_PRE) ||
        (reg_fsm_bsp_current_state == ENUM_ST_FIX))
      w_fixed_slot = reg_frame_fd && !reg_frame_niso;

    if (reg_frame_fd && !reg_frame_niso) begin
      case (reg_fsm_bsp_current_state)
        ENUM_ST_SOF, ENUM_ST_ID_A, ENUM_ST_RTR1, ENUM_ST_IDE, ENUM_ST_ID_B,
        ENUM_ST_RTR2, ENUM_ST_FDF, ENUM_ST_RES, ENUM_ST_BRS, ENUM_ST_ESI,
        ENUM_ST_DLC, ENUM_ST_DATA: w_dyn_stuf_en = 1'b1;
        default: w_dyn_stuf_en = 1'b0;
      endcase
      case (reg_fsm_bsp_current_state)
        ENUM_ST_SOF, ENUM_ST_ID_A, ENUM_ST_RTR1, ENUM_ST_IDE, ENUM_ST_ID_B,
        ENUM_ST_RTR2, ENUM_ST_FDF, ENUM_ST_RES, ENUM_ST_BRS, ENUM_ST_ESI,
        ENUM_ST_DLC, ENUM_ST_DATA, ENUM_ST_SBC: w_rx_protected = 1'b1;
        default: w_rx_protected = 1'b0;
      endcase
    end else begin
      case (reg_fsm_bsp_current_state)
        ENUM_ST_SOF, ENUM_ST_ID_A, ENUM_ST_RTR1, ENUM_ST_IDE, ENUM_ST_ID_B,
        ENUM_ST_RTR2, ENUM_ST_FDF, ENUM_ST_R0, ENUM_ST_RES, ENUM_ST_BRS,
        ENUM_ST_ESI, ENUM_ST_DLC, ENUM_ST_DATA, ENUM_ST_CRC:
          w_dyn_stuf_en = 1'b1;
        default: w_dyn_stuf_en = 1'b0;
      endcase
      case (reg_fsm_bsp_current_state)
        ENUM_ST_SOF, ENUM_ST_ID_A, ENUM_ST_RTR1, ENUM_ST_IDE, ENUM_ST_ID_B,
        ENUM_ST_RTR2, ENUM_ST_FDF, ENUM_ST_R0, ENUM_ST_RES, ENUM_ST_BRS,
        ENUM_ST_ESI, ENUM_ST_DLC, ENUM_ST_DATA: w_rx_protected = 1'b1;
        default: w_rx_protected = 1'b0;
      endcase
    end
    if (reg_fsm_bsp_current_state == ENUM_ST_IDLE && w_rx_sof_start)
      w_rx_protected = 1'b1;
  end

  // Select the logical output bit for the current field.
  always_comb begin : p_com_tx_bit
    w_tx_logic_bit = 1'b1;
    w_data_bit_pos = 9'd0;
    case (reg_fsm_bsp_current_state)
      ENUM_ST_IDLE: begin
        if (w_tx_start)
          w_tx_logic_bit = 1'b0;
      end
      ENUM_ST_SOF: w_tx_logic_bit = 1'b0;
      ENUM_ST_ID_A: begin
        if (reg_field_idx < 10'd11)
          w_tx_logic_bit = reg_tx_id[28 - reg_field_idx];
      end
      ENUM_ST_RTR1: w_tx_logic_bit = reg_tx_xtd ? 1'b1 : reg_tx_rtr;
      ENUM_ST_IDE:  w_tx_logic_bit = reg_tx_xtd;
      ENUM_ST_ID_B: begin
        if (reg_field_idx < 10'd18)
          w_tx_logic_bit = reg_tx_id[17 - reg_field_idx];
      end
      ENUM_ST_RTR2: w_tx_logic_bit = reg_frame_fd ? 1'b0 : reg_tx_rtr;
      ENUM_ST_FDF:  w_tx_logic_bit = reg_frame_fd;
      ENUM_ST_R0:   w_tx_logic_bit = 1'b0;
      ENUM_ST_RES:  w_tx_logic_bit = 1'b0;
      ENUM_ST_BRS:  w_tx_logic_bit = reg_frame_brs;
      ENUM_ST_ESI:  w_tx_logic_bit = i_err_passive;
      ENUM_ST_DLC: begin
        if (reg_field_idx < 10'd4)
          w_tx_logic_bit = reg_tx_dlc[3 - reg_field_idx];
      end
      ENUM_ST_DATA: begin
        w_data_bit_pos = 9'((reg_field_idx / 10'd8) * 10'd8 +
                          (10'd7 - (reg_field_idx % 10'd8)));
        if (reg_field_idx < (10'(reg_data_len) * 10'd8))
          w_tx_logic_bit = reg_tx_payload[w_data_bit_pos];
      end
      ENUM_ST_SBC: begin
        if (reg_field_idx < 10'd4)
          w_tx_logic_bit = w_tx_sbc_code[3 - reg_field_idx];
      end
      ENUM_ST_CRC: begin
        case (reg_frame_fd)
          1'b0: begin
            if (reg_field_idx < 10'd15)
              w_tx_logic_bit = w_crc15[14 - reg_field_idx];
          end
          1'b1: begin
            if (reg_data_len > 7'd16) begin
              if (reg_field_idx < 10'd21)
                w_tx_logic_bit = w_crc21[20 - reg_field_idx];
            end else if (reg_field_idx < 10'd17) begin
              w_tx_logic_bit = w_crc17[16 - reg_field_idx];
            end
          end
          default: begin end
        endcase
      end
      ENUM_ST_ACK: begin
        if (!reg_tx_role && reg_frame_good && !reg_crc_bad &&
            !i_cfd_ctrl_mon && !i_cfd_ctrl_rest)
          w_tx_logic_bit = 1'b0;
      end
      ENUM_ST_ERR_FLAG: w_tx_logic_bit = reg_err_passive;
      ENUM_ST_OVL:      w_tx_logic_bit = 1'b0;
      default:          w_tx_logic_bit = 1'b1;
    endcase
    if (i_cfd_ctrl_init || !i_cdc_ready_can || i_bus_off ||
        i_cfd_ctrl_mon || i_cfd_ctrl_rest)
      w_tx_logic_bit = 1'b1;
  end

  // Apply stuffing and remove received stuff bits at their protocol-defined positions.

  // Calculate Classic and FD CRC states from the sampled bus stream.

  // Pack Rx metadata words and the fixed word-4 payload offset.
  always_comb begin : p_com_rx_frame
    o_rx_frame_can = '0;
    o_rx_frame_can[31:0] = {reg_rx_frame_esi, reg_rx_frame_xtd,
                            reg_rx_frame_rtr, reg_rx_id};
    o_rx_frame_can[63:32] = 32'd0;
    o_rx_frame_can[32+21] = reg_rx_frame_fd;
    o_rx_frame_can[32+20] = reg_rx_frame_brs;
    o_rx_frame_can[32+19:32+16] = reg_rx_dlc;
    o_rx_frame_can[95:64] = reg_rx_timestamp;
    o_rx_frame_can[127:96] = 32'd0;
    o_rx_frame_can[LPARA_CANFD_FRAME_W-1:128] = reg_rx_payload;
  end

  // Drive timing, status, CAN pin and TDC qualification outputs.
  always_comb begin : p_com_outputs
    o_sts_act = 2'd0;
    o_can_tx = reg_tx_bit_sent;
    o_can_tx_nxt = w_tx_bit_nxt;
    o_frame_active = (reg_fsm_bsp_current_state != ENUM_ST_INTEG) &&
                     (reg_fsm_bsp_current_state != ENUM_ST_IDLE);
    o_bus_idle = (reg_fsm_bsp_current_state == ENUM_ST_IDLE);
    o_cfg_check = i_cfd_ctrl_init;
    o_bus_integrating = (reg_fsm_bsp_current_state == ENUM_ST_INTEG);
    o_hard_sync_en = (reg_fsm_bsp_current_state == ENUM_ST_INTEG) ||
                     (reg_fsm_bsp_current_state == ENUM_ST_IDLE) ||
                     (reg_fsm_bsp_current_state == ENUM_ST_INTERM) ||
                     (reg_fsm_bsp_current_state == ENUM_ST_SUSP);
    o_hs_edl = reg_frame_fd && (reg_fsm_bsp_current_state == ENUM_ST_RES);
    o_tx_dom = !reg_tx_bit_sent;
    o_no_resync = reg_tx_role && i_data_phase;
    o_rate_data_candidate = (reg_fsm_bsp_current_state == ENUM_ST_BRS);
    o_rate_nom_candidate = (reg_fsm_bsp_current_state == ENUM_ST_CRC_DEL);
    // The CRC delimiter that a TDC transmitter sent is recessive whatever its late echo shows
    o_prev_sample_rec = reg_tx_role && reg_frame_fd && reg_frame_brs && !reg_frame_niso &&
                        i_cfd_ctrl_tdc_ena && (reg_fsm_bsp_current_state == ENUM_ST_CRC_DEL);
    // Activity code of cfd_sts.act: 0 synchronizing, 1 idle, 2 receiving, 3 transmitting.
    w_act_run = !i_cfd_ctrl_init && i_cdc_ready_can && !i_bus_off &&
                (reg_fsm_bsp_current_state != ENUM_ST_INTEG);
    if (!w_act_run)
      o_sts_act = 2'd0;
    else if (reg_fsm_bsp_current_state == ENUM_ST_IDLE)
      o_sts_act = 2'd1;
    else
      o_sts_act = reg_tx_role ? 2'd3 : 2'd2;
    o_sts_init_ack = i_cfd_ctrl_init || !i_cdc_ready_can ||
                     !i_timing_cfg_valid || i_btl_cfg_fix_event ||
                     (reg_fsm_bsp_current_state == ENUM_ST_INTEG);
    o_sts_rfdf = reg_rx_frame_fd;
    o_sts_rbrs = i_data_phase;
    o_sts_resi = reg_rx_res;
    o_sts_pxe = reg_rx_frame_fd && reg_rx_res && !i_cfd_ctrl_pxd;
    o_sts_dom_stk = reg_dom_stk;
    // TDC runs only in the transmitter: a receiver does not drive the bus, it has no echo to check
    o_tdc_frame_active = reg_tx_role && reg_frame_fd && reg_frame_brs && !reg_frame_niso &&
                         i_cfd_ctrl_tdc_ena &&
                         ((reg_fsm_bsp_current_state == ENUM_ST_ESI) ||
                          (reg_fsm_bsp_current_state == ENUM_ST_DLC) ||
                          (reg_fsm_bsp_current_state == ENUM_ST_DATA) ||
                          (reg_fsm_bsp_current_state == ENUM_ST_FIX_PRE) ||
                          (reg_fsm_bsp_current_state == ENUM_ST_SBC) ||
                          (reg_fsm_bsp_current_state == ENUM_ST_FIX) ||
                          (reg_fsm_bsp_current_state == ENUM_ST_CRC) ||
                          (reg_fsm_bsp_current_state == ENUM_ST_CRC_DEL));
    o_tdc_measure_start = i_tx_point &&
                         (reg_fsm_bsp_current_state == ENUM_ST_RES) &&
                         reg_tx_role && reg_frame_fd && reg_frame_brs && !reg_frame_niso &&
                         i_cfd_ctrl_tdc_ena;

    // Expose only received, destuffed Classical CAN fields to the wake filter.
    o_rx_sof_sample = w_rx_sof_start && !w_tx_start;
    o_rx_frame_start = o_rx_sof_sample;
    o_rx_frame_abort = !reg_tx_role && reg_rx_store_en && w_frame_active &&
                       w_err_detect;
    o_rx_id_bit_valid = i_sample && w_rx_bit_valid && !reg_tx_role &&
                        ((reg_fsm_bsp_current_state == ENUM_ST_ID_A) ||
                         (reg_fsm_bsp_current_state == ENUM_ST_ID_B));
    o_rx_id_bit = w_rx_bit;
    o_rx_id_bit_idx = (reg_fsm_bsp_current_state == ENUM_ST_ID_B) ?
                      5'(10'd11 + reg_field_idx) : 5'(reg_field_idx);
    o_rx_ide_valid = i_sample && w_rx_bit_valid && !reg_tx_role &&
                     (reg_fsm_bsp_current_state == ENUM_ST_IDE);
    o_rx_ide = w_rx_bit;
    // RTR1 is reported only after IDE proves a base frame; RTR2 is the extended-frame RTR.
    o_rx_rtr_valid = i_sample && w_rx_bit_valid && !reg_tx_role &&
                     (((reg_fsm_bsp_current_state == ENUM_ST_IDE) && !w_rx_bit) ||
                      (reg_fsm_bsp_current_state == ENUM_ST_RTR2));
    o_rx_rtr = (reg_fsm_bsp_current_state == ENUM_ST_IDE) ? reg_rx_rtr : w_rx_bit;
    o_rx_fdf_valid = i_sample && w_rx_bit_valid && !reg_tx_role &&
                     (reg_fsm_bsp_current_state == ENUM_ST_FDF);
    o_rx_fdf = w_rx_bit;
    o_rx_dlc_bit_valid = i_sample && w_rx_bit_valid && !reg_tx_role &&
                         (reg_fsm_bsp_current_state == ENUM_ST_DLC);
    o_rx_dlc_bit = w_rx_bit;
    o_rx_dlc_bit_idx = 2'(reg_field_idx);
    o_rx_data_bit_valid = i_sample && w_rx_bit_valid && !reg_tx_role &&
                          !reg_frame_fd &&
                          (reg_fsm_bsp_current_state == ENUM_ST_DATA);
    o_rx_data_bit = w_rx_bit;
    o_rx_data_bit_idx = 6'(reg_field_idx);
    o_rx_crc_delim = i_sample && !reg_tx_role &&
                     (reg_fsm_bsp_current_state == ENUM_ST_CRC_DEL);
    o_rx_crc_ok = reg_frame_good && !reg_crc_bad && !reg_err_seen &&
                  !w_err_detect;
    o_rx_stuff_ok = !reg_err_seen && !w_rx_stuff_err && !w_rx_sbc_err;
  end

  // Classify arbitration loss and errors using the current field and sampled bus bit.
  assign w_arb_field = (reg_fsm_bsp_current_state == ENUM_ST_ID_A) ||
                       (reg_fsm_bsp_current_state == ENUM_ST_RTR1) ||
                       (reg_fsm_bsp_current_state == ENUM_ST_IDE) ||
                       (reg_fsm_bsp_current_state == ENUM_ST_ID_B) ||
                       (reg_fsm_bsp_current_state == ENUM_ST_RTR2);
  assign w_arb_loss = i_sample && reg_tx_role && reg_tx_adv && w_arb_field &&
                      reg_tx_bit_sent && !w_rx_wire_bit;
  assign w_rx_field_step = i_sample &&
                           (w_rx_bit_valid || w_fixed_slot);
  // A fixed stuff slot (ISO FD CRC field) is a field step of its own, with no logical bit.
  assign w_tx_field_step = i_sample && (reg_tx_adv || reg_tx_fixed);
  assign w_frame_step = reg_tx_role && !w_arb_loss ?
                        w_tx_field_step : w_rx_field_step;
  assign w_sbc_last = i_sample && (reg_fsm_bsp_current_state == ENUM_ST_SBC) &&
                      (reg_field_idx == 10'd3) && w_rx_bit_valid;
  assign w_crc_rx_mismatch = i_sample &&
                             (reg_fsm_bsp_current_state == ENUM_ST_CRC) &&
                             w_frame_step &&
                             (reg_field_idx + 10'd1 == 10'(w_crc_len)) &&
                             !reg_tx_role &&
                             ((reg_frame_fd && (reg_data_len > 7'd16) &&
                               (w_crc_rx_shift_nxt != w_crc21)) ||
                              (reg_frame_fd && (reg_data_len <= 7'd16) &&
                               (w_crc_rx_shift_nxt[16:0] != w_crc17)) ||
                              (!reg_frame_fd &&
                               (w_crc_rx_shift_nxt[14:0] != w_crc15)));
  // A stuff-count mismatch is an FCRC error (ISO 6.6.21.2 c), handled by the CRC path.
  assign w_stuff_err = i_sample && w_rx_stuff_err;
  assign w_pxe_event = i_sample && (reg_fsm_bsp_current_state == ENUM_ST_RES) &&
                       w_rx_bit_valid && w_rx_bit && !i_cfd_ctrl_pxd;
  // ISO FD ACK tolerances (ISO 6.6.11.5, 6.6.11.6); not applied to Bosch non-ISO FD.
  assign w_ack_tol_en = reg_frame_fd && !reg_frame_niso;
  // A transmitter accepts one extra recessive bit (second CRC delimiter) before the ACK slot.
  assign w_crc_del2 = i_sample && reg_tx_role && w_ack_tol_en && !reg_crc_del2_seen &&
                      (reg_fsm_bsp_current_state == ENUM_ST_ACK) && w_rx_wire_bit;
  assign w_ack_err = i_sample && reg_tx_role &&
                       (reg_fsm_bsp_current_state == ENUM_ST_ACK) && w_rx_wire_bit &&
                       !w_crc_del2;
  assign w_tx_bit_err = i_sample && reg_tx_role && reg_tx_cmp_en &&
                          !w_arb_field &&
                          (reg_fsm_bsp_current_state != ENUM_ST_ACK) &&
                          !((reg_fsm_bsp_current_state == ENUM_ST_ACK_DEL) &&
                            w_ack_tol_en && reg_ack_dom_seen) &&
                          !i_tdc_active &&
                          (reg_tx_bit_sent != w_rx_wire_bit);

  // Detect recessive bus samples that contradict an active error/overload flag.
  assign w_flag_bit_err = i_sample && !reg_err_passive &&
                          ((reg_fsm_bsp_current_state == ENUM_ST_ERR_FLAG) ||
                           (reg_fsm_bsp_current_state == ENUM_ST_OVL)) &&
                          w_rx_wire_bit;

  // Apply the arbitration stuff-error exception only to its specified wire condition.
  assign w_tx_exception2 = reg_tx_role && w_stuff_err && w_arb_field &&
                           reg_tx_bit_sent && !w_rx_wire_bit;
  // A violated fixed stuff bit is a form error (ISO 6.6.13.3.1); it carries no valid destuffed bit.
  assign w_form_err = i_sample &&
                      ((w_rx_bit_valid &&
                        ((((reg_fsm_bsp_current_state == ENUM_ST_CRC_DEL) ||
                           ((reg_fsm_bsp_current_state == ENUM_ST_ACK_DEL) &&
                            !(w_ack_tol_en && reg_ack_dom_seen))) &&
                          !w_rx_bit) ||
                         ((reg_fsm_bsp_current_state == ENUM_ST_EOF) &&
                          (reg_field_idx < 10'd6) && !w_rx_bit) ||
                         ((reg_fsm_bsp_current_state == ENUM_ST_RES) &&
                          w_rx_bit && i_cfd_ctrl_pxd) ||
                         ((reg_fsm_bsp_current_state == ENUM_ST_FDF) &&
                          w_rx_bit && ((PARA_CANFD_FD_EN != 32'd1) ||
                                       !i_cfd_ctrl_fdoe)))) ||
                       w_rx_fixed_err);
  assign w_err_detect = !w_pxe_event &&
                          (w_stuff_err || w_form_err || w_ack_err ||
                           w_tx_bit_err || i_tdc_bit_err);
  assign w_err_first = w_err_detect && !reg_err_seen;

  // Finish the error delimiter after eight consecutive recessive bus samples.
  assign w_err_del_done = (reg_fsm_bsp_current_state == ENUM_ST_ERR_DEL) &&
                          i_sample &&
                          w_rx_wire_bit && (reg_err_del_count == 4'd7);

  // Accept or store a frame only after its final EOF bit and all checks pass.
  assign w_tx_end_good = (reg_fsm_bsp_current_state == ENUM_ST_EOF) &&
                         w_frame_step && (reg_field_idx == 10'd6) &&
                         reg_frame_good && !reg_crc_bad && !w_err_detect &&
                         (!reg_tx_role || reg_ack_seen);
  assign w_rx_end_good = w_tx_end_good && !reg_tx_role && reg_rx_store_en &&
                         !(reg_rx_rtr && (PARA_CANFD_RTR_EN != 32'd1));
  assign w_rx_store_end = w_tx_end_good &&
                          ((reg_tx_role && (i_cfd_ctrl_lbk_int || i_cfd_ctrl_lbk_ext)) ||
                           (!reg_tx_role && reg_rx_store_en));

  // Advance the frame engine through fields, intermission and error signaling.
  always_comb begin : p_com_fsm_bsp
    w_fsm_bsp_nxt_state = reg_fsm_bsp_current_state;
    case (reg_fsm_bsp_current_state)
      ENUM_ST_INTEG: begin
        casez ({(i_cfd_ctrl_init || !i_cdc_ready_can), i_bus_off,
                (i_sample && i_sample_val &&
                 (reg_idle_count >= 4'(LPARA_IDLE_BITS - 32'd1)))})
          3'b1??: w_fsm_bsp_nxt_state = ENUM_ST_INTEG;
          3'b01?: w_fsm_bsp_nxt_state = ENUM_ST_BUS_OFF;
          3'b001: w_fsm_bsp_nxt_state = ENUM_ST_IDLE;
          default: begin end
        endcase
      end
      ENUM_ST_IDLE: begin
        casez ({(i_cfd_ctrl_init || !i_cdc_ready_can), i_bus_off,
                w_tx_start, w_rx_sof_start})
          4'b1???: w_fsm_bsp_nxt_state = ENUM_ST_INTEG;
          4'b01??: w_fsm_bsp_nxt_state = ENUM_ST_BUS_OFF;
          4'b001?: w_fsm_bsp_nxt_state = ENUM_ST_SOF;
          4'b0001: w_fsm_bsp_nxt_state = ENUM_ST_ID_A;
          default: begin end
        endcase
      end
      ENUM_ST_SOF: begin
        if (w_err_detect)
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
        else if (w_frame_step)
          w_fsm_bsp_nxt_state = ENUM_ST_ID_A;
      end
      ENUM_ST_ID_A: begin
        if (w_err_detect)
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
        else if (w_frame_step && (reg_field_idx == 10'd10))
          w_fsm_bsp_nxt_state = ENUM_ST_RTR1;
      end
      ENUM_ST_RTR1: begin
        if (w_err_detect)
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
        else if (w_frame_step)
          w_fsm_bsp_nxt_state = ENUM_ST_IDE;
      end
      ENUM_ST_IDE: begin
        if (w_err_detect)
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
        else if (w_frame_step)
          w_fsm_bsp_nxt_state = w_frame_xtd ? ENUM_ST_ID_B : ENUM_ST_FDF;
      end
      ENUM_ST_ID_B: begin
        if (w_err_detect)
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
        else if (w_frame_step && (reg_field_idx == 10'd17))
          w_fsm_bsp_nxt_state = ENUM_ST_RTR2;
      end
      ENUM_ST_RTR2: begin
        if (w_err_detect)
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
        else if (w_frame_step)
          w_fsm_bsp_nxt_state = ENUM_ST_FDF;
      end
      ENUM_ST_FDF: begin
        if (w_err_detect)
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
        else if (w_frame_step) begin
          if (w_rx_bit)
            w_fsm_bsp_nxt_state = ENUM_ST_RES;
          else if (reg_tx_role ? reg_tx_xtd : reg_rx_xtd)
            w_fsm_bsp_nxt_state = ENUM_ST_R0;
          else
            w_fsm_bsp_nxt_state = ENUM_ST_DLC;
        end
      end
      ENUM_ST_R0: begin
        if (w_err_detect)
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
        else if (w_frame_step)
          w_fsm_bsp_nxt_state = ENUM_ST_DLC;
      end
      ENUM_ST_RES: begin
        casez ({w_pxe_event, w_err_detect, w_frame_step})
          3'b1??: w_fsm_bsp_nxt_state = ENUM_ST_INTERM;
          3'b01?: w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
          3'b001: w_fsm_bsp_nxt_state = ENUM_ST_BRS;
          default: begin end
        endcase
      end
      ENUM_ST_BRS: begin
        if (w_err_detect)
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
        else if (w_frame_step)
          w_fsm_bsp_nxt_state = ENUM_ST_ESI;
      end
      ENUM_ST_ESI: begin
        if (w_err_detect)
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
        else if (w_frame_step)
          w_fsm_bsp_nxt_state = ENUM_ST_DLC;
      end
      ENUM_ST_DLC: begin
        if (w_err_detect)
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
        else if (w_frame_step && (reg_field_idx == 10'd3)) begin
          // A receiver latches the length at this same step, so it must use the decoded value.
          if ((reg_tx_role ? reg_data_len : w_rx_len_calc) == 7'd0)
            w_fsm_bsp_nxt_state = (reg_frame_fd && !reg_frame_niso) ?
                                  ENUM_ST_FIX_PRE : ENUM_ST_CRC;
          else
            w_fsm_bsp_nxt_state = ENUM_ST_DATA;
        end
      end
      ENUM_ST_DATA: begin
        if (w_err_detect)
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
        else if (w_frame_step &&
                 (reg_field_idx + 10'd1 == (10'(reg_data_len) * 10'd8)))
          w_fsm_bsp_nxt_state = (reg_frame_fd && !reg_frame_niso) ?
                                ENUM_ST_FIX_PRE : ENUM_ST_CRC;
      end
      ENUM_ST_FIX_PRE: begin
        if (w_err_detect)
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
        else if (w_frame_step)
          w_fsm_bsp_nxt_state = ENUM_ST_SBC;
      end
      ENUM_ST_SBC: begin
        casez ({w_err_detect,
                (w_frame_step && (reg_fd_seq_count[1:0] == 2'b11) &&
                 (reg_fd_seq_count + 6'd1 < reg_fd_seq_total)),
                (w_frame_step && (reg_field_idx == 10'd3))})
          3'b1??: w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
          3'b01?: w_fsm_bsp_nxt_state = ENUM_ST_FIX;
          3'b001: w_fsm_bsp_nxt_state = ENUM_ST_CRC;
          default: begin end
        endcase
      end
      ENUM_ST_FIX: begin
        if (w_err_detect)
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
        else if (w_frame_step)
          w_fsm_bsp_nxt_state = (reg_fd_seq_count < 6'd4) ?
                                ENUM_ST_SBC : ENUM_ST_CRC;
      end
      ENUM_ST_CRC: begin
        casez ({w_err_detect,
                (w_frame_step &&
                 (reg_field_idx + 10'd1 == 10'(w_crc_len))),
                (w_frame_step && reg_frame_fd && !reg_frame_niso &&
                 (reg_fd_seq_count[1:0] == 2'b11) &&
                 (reg_fd_seq_count + 6'd1 < reg_fd_seq_total))})
          3'b1??: w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
          3'b01?: w_fsm_bsp_nxt_state = ENUM_ST_CRC_DEL;
          3'b001: w_fsm_bsp_nxt_state = ENUM_ST_FIX;
          default: begin end
        endcase
      end
      ENUM_ST_CRC_DEL: begin
        if (w_err_detect)
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
        else if (w_frame_step) begin
          if (reg_crc_bad && reg_frame_fd)
            w_fsm_bsp_nxt_state = ENUM_ST_CRC_WAIT;
          else
            w_fsm_bsp_nxt_state = ENUM_ST_ACK;
        end
      end
      ENUM_ST_CRC_WAIT: begin
        if (w_frame_step && (reg_crc_wait_count == 4'd2))
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
      end
      ENUM_ST_ACK: begin
        if (w_err_detect)
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
        else if (w_frame_step && !w_crc_del2)
          w_fsm_bsp_nxt_state = ENUM_ST_ACK_DEL;
      end
      ENUM_ST_ACK_DEL: begin
        if (w_err_detect)
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
        else if (w_frame_step)
          w_fsm_bsp_nxt_state = ENUM_ST_EOF;
      end
      ENUM_ST_EOF: begin
        casez ({w_err_detect,
                (w_frame_step && reg_crc_bad && !reg_frame_fd &&
                 (reg_field_idx == 10'd0)),
                (w_frame_step && (reg_field_idx == 10'd6))})
          3'b1??: w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
          3'b01?: w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
          3'b001: begin
          if (!w_rx_wire_bit)
            w_fsm_bsp_nxt_state = ENUM_ST_OVL;
          else if (i_err_passive && reg_tx_role)
            w_fsm_bsp_nxt_state = ENUM_ST_SUSP;
          else
            w_fsm_bsp_nxt_state = ENUM_ST_INTERM;
          end
          default: begin end
        endcase
      end
      ENUM_ST_INTERM: begin
        if (w_rx_sof_start) begin
          w_fsm_bsp_nxt_state = ENUM_ST_ID_A;
        end else begin
          casez ({(w_frame_step && !w_rx_wire_bit &&
                   (reg_interm_count < 4'd2)),
                  (w_frame_step && i_cfd_ctrl_ovl_en && i_rx_frame_full_can &&
                   (reg_interm_count == 4'd0) && (reg_ovl_req_count < 4'd2)),
                  (w_frame_step && (reg_interm_count == 4'd2))})
            3'b1??: w_fsm_bsp_nxt_state = ENUM_ST_OVL;
            3'b01?: w_fsm_bsp_nxt_state = ENUM_ST_OVL;
            3'b001: w_fsm_bsp_nxt_state = ENUM_ST_IDLE;
            default: begin end
          endcase
        end
      end
      ENUM_ST_SUSP: begin
        if (w_frame_step && (reg_suspend_count == 4'd7))
          w_fsm_bsp_nxt_state = ENUM_ST_IDLE;
      end
      ENUM_ST_ERR_FLAG, ENUM_ST_OVL: begin
        if (w_frame_step && (reg_err_count == 4'd5))
          w_fsm_bsp_nxt_state = ENUM_ST_ERR_DEL;
      end
      ENUM_ST_ERR_DEL: begin
        if (w_err_del_done)
          w_fsm_bsp_nxt_state = ENUM_ST_INTERM;
        else if (i_sample && (reg_err_del_count == 4'd7) && !w_rx_wire_bit)
          w_fsm_bsp_nxt_state = ENUM_ST_OVL;
      end
      ENUM_ST_BUS_OFF: begin
        if (!i_bus_off && !i_cfd_ctrl_init)
          w_fsm_bsp_nxt_state = ENUM_ST_INTEG;
      end
      default: w_fsm_bsp_nxt_state = ENUM_ST_INTEG;
    endcase
    if (w_err_detect)
      w_fsm_bsp_nxt_state = ENUM_ST_ERR_FLAG;
  end

  // Keep the FSM state register isolated for synthesis state extraction.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_fsm_bsp
    if (!i_rst_n_can)
      reg_fsm_bsp_current_state <= ENUM_ST_INTEG;
    else
      reg_fsm_bsp_current_state <= w_fsm_bsp_nxt_state;
  end

  // Capture frame context and parse sampled identifiers, flags, DLC and payload data.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_frame_context
    if (!i_rst_n_can) begin
      reg_tx_id <= 29'd0;
      reg_rx_id <= 29'd0;
      reg_tx_xtd <= 1'b0;
      reg_rx_xtd <= 1'b0;
      reg_tx_rtr <= 1'b0;
      reg_rx_rtr <= 1'b0;
      reg_frame_fd <= 1'b0;
      reg_frame_brs <= 1'b0;
      reg_frame_niso <= 1'b0;
      reg_rx_esi <= 1'b0;
      reg_rx_res <= 1'b0;
      reg_tx_dlc <= 4'd0;
      reg_rx_dlc <= 4'd0;
      reg_data_len <= 7'd0;
      reg_tx_payload <= '0;
      reg_rx_payload <= '0;
      reg_rx_crc_shift <= 20'd0;
      reg_rx_sbc <= 3'd0;
      reg_tx_buf_valid <= 1'b0;
      reg_tx_owner_tt <= 1'b0;
      reg_tx_trigger_valid <= 1'b0;
      reg_tx_trigger_buf <= '0;
      reg_tx_trigger_window_seq <= '0;
      reg_tx_trigger_started <= 1'b0;
      reg_tx_trigger_expired <= 1'b0;
      reg_tx_fd <= 1'b0;
      reg_tx_brs <= 1'b0;
      reg_tx_niso <= 1'b0;
      reg_tx_data_len <= 7'd0;
      reg_tx_role <= 1'b0;
      reg_rx_store_en <= 1'b0;
      reg_frame_good <= 1'b0;
      reg_crc_bad <= 1'b0;
      reg_ack_seen <= 1'b0;
      reg_crc_del2_seen <= 1'b0;
      reg_ack_dom_seen <= 1'b0;
      reg_err_seen <= 1'b0;
      reg_err_passive <= 1'b0;
      reg_rx_frame_fd <= 1'b0;
      reg_rx_frame_brs <= 1'b0;
      reg_rx_frame_xtd <= 1'b0;
      reg_rx_frame_rtr <= 1'b0;
      reg_rx_frame_esi <= 1'b0;
      reg_rx_timestamp <= 32'd0;
      reg_ovl_req_count <= 4'd0;
    end else begin
      if (reg_tx_result_valid && w_tx_result_ready) begin
        reg_tx_trigger_valid <= 1'b0;
        reg_tx_trigger_started <= 1'b0;
        reg_tx_trigger_expired <= 1'b0;
      end

      if (w_tx_accept) begin
        reg_tx_buf_valid <= 1'b1;
        reg_tx_owner_tt <= i_tt_ref_frame_valid_can;
        reg_tx_trigger_valid <= i_tx_trigger_tag_valid_can && !i_tt_ref_frame_valid_can;
        reg_tx_trigger_buf <= i_tx_trigger_tag_valid_can ? i_tx_trigger_buf_can : 6'd0;
        reg_tx_trigger_window_seq <= i_tx_trigger_tag_valid_can ?
                                     i_tx_trigger_window_seq_can : 32'd0;
        reg_tx_trigger_started <= 1'b0;
        reg_tx_trigger_expired <= 1'b0;
        reg_tx_id <= w_tx_header0[28:0];
        reg_tx_xtd <= w_tx_header0[30];
        reg_tx_rtr <= w_tx_header0[29];
        reg_tx_fd <= w_tx_header1[5] && (PARA_CANFD_FD_EN == 32'd1) &&
                     i_cfd_ctrl_fdoe && !w_tx_header0[29];
        reg_tx_brs <= w_tx_header1[4] && i_cfd_ctrl_brse;
        reg_tx_niso <= i_cfd_ctrl_niso && (PARA_CANFD_NISO_EN == 32'd1);
        reg_tx_dlc <= w_tx_dlc_cfg;
        reg_tx_data_len <= w_tx_len_cfg;
        reg_tx_payload <= w_tx_payload;
      end

      if (w_tx_start) begin
        reg_tx_role <= 1'b1;
        reg_tx_trigger_started <= reg_tx_trigger_valid;
        reg_tx_trigger_expired <= 1'b0;
        reg_frame_fd <= reg_tx_fd;
        reg_frame_brs <= reg_tx_brs;
        reg_frame_niso <= reg_tx_niso;
        reg_data_len <= reg_tx_data_len;
        reg_rx_store_en <= 1'b0;
        reg_frame_good <= 1'b0;
        reg_crc_bad <= 1'b0;
        reg_ack_seen <= 1'b0;
        reg_crc_del2_seen <= 1'b0;
        reg_ack_dom_seen <= 1'b0;
        reg_err_seen <= 1'b0;
        reg_rx_crc_shift <= 20'd0;
        reg_rx_sbc <= 3'd0;
      end

      if (w_rx_sof_start) begin
        reg_tx_role <= 1'b0;
        reg_rx_store_en <= 1'b1;
        reg_rx_id <= 29'd0;
        reg_rx_xtd <= 1'b0;
        reg_rx_rtr <= 1'b0;
        reg_frame_fd <= 1'b0;
        reg_frame_brs <= 1'b0;
        reg_frame_niso <= i_cfd_ctrl_niso && (PARA_CANFD_NISO_EN == 32'd1);
        reg_rx_dlc <= 4'd0;
        reg_data_len <= 7'd0;
        reg_rx_payload <= '0;
        reg_rx_esi <= 1'b0;
        reg_rx_res <= 1'b0;
        reg_rx_crc_shift <= 20'd0;
        reg_rx_sbc <= 3'd0;
        reg_frame_good <= 1'b0;
        reg_crc_bad <= 1'b0;
        reg_ack_seen <= 1'b0;
        reg_crc_del2_seen <= 1'b0;
        reg_ack_dom_seen <= 1'b0;
        reg_err_seen <= 1'b0;
        reg_rx_timestamp <= i_rx_timestamp_can;
      end

      if (w_frame_step) begin
        case (reg_fsm_bsp_current_state)
          ENUM_ST_ID_A: reg_rx_id[28:18] <= {reg_rx_id[27:18], w_rx_bit};
          ENUM_ST_RTR1: reg_rx_rtr <= w_rx_bit;
          ENUM_ST_IDE:  reg_rx_xtd <= w_rx_bit;
          ENUM_ST_ID_B: reg_rx_id[17:0] <= {reg_rx_id[16:0], w_rx_bit};
          ENUM_ST_RTR2: reg_rx_rtr <= w_rx_bit;
          ENUM_ST_FDF: begin
            reg_frame_fd <= w_rx_bit && (PARA_CANFD_FD_EN == 32'd1) &&
                            i_cfd_ctrl_fdoe;
            reg_frame_niso <= i_cfd_ctrl_niso && (PARA_CANFD_NISO_EN == 32'd1);
          end
          ENUM_ST_RES: reg_rx_res <= w_rx_bit;
          ENUM_ST_BRS: reg_frame_brs <= w_rx_bit && i_cfd_ctrl_brse;
          ENUM_ST_ESI: reg_rx_esi <= w_rx_bit;
          ENUM_ST_DLC: begin
            reg_rx_dlc <= w_rx_dlc_nxt;
            if (reg_field_idx == 10'd3)
              reg_data_len <= w_rx_len_calc;
          end
          ENUM_ST_DATA: begin
            if (reg_field_idx < (10'(PARA_CANFD_DATA_MAX) * 10'd8))
              reg_rx_payload[(reg_field_idx / 10'd8) * 8 +: 8] <=
                {reg_rx_payload[(reg_field_idx / 10'd8) * 8 +: 7], w_rx_bit};
          end
          ENUM_ST_SBC: reg_rx_sbc <= {reg_rx_sbc[1:0], w_rx_bit};
          ENUM_ST_CRC: reg_rx_crc_shift <= w_crc_rx_shift_nxt[19:0];
          default: begin end
        endcase
      end

      if (w_crc_rx_mismatch || w_rx_sbc_err) begin
        reg_crc_bad <= 1'b1;
        reg_frame_good <= 1'b0;
      end
      if (reg_fsm_bsp_current_state == ENUM_ST_CRC && w_frame_step &&
          (reg_field_idx + 10'd1 == 10'(w_crc_len)) &&
          !(w_crc_rx_mismatch || w_rx_sbc_err))
        reg_frame_good <= 1'b1;
      if (w_err_detect)
        reg_err_seen <= 1'b1;
      if (reg_fsm_bsp_current_state == ENUM_ST_ACK &&
          i_sample && reg_tx_role && !w_rx_wire_bit)
        reg_ack_seen <= 1'b1;
      if (reg_fsm_bsp_current_state == ENUM_ST_ACK && i_sample && !w_rx_wire_bit)
        reg_ack_dom_seen <= 1'b1;
      if (w_crc_del2)
        reg_crc_del2_seen <= 1'b1;

      if (w_arb_loss) begin
        reg_tx_role <= 1'b0;
        reg_rx_store_en <= 1'b1;
        // TXH owns retry arbitration and must explicitly reoffer the retained frame.
        reg_tx_buf_valid <= 1'b0;
      end
      if (w_err_detect) begin
        reg_err_passive <= i_err_passive;
        reg_frame_good <= 1'b0;
        if (reg_tx_role)
          reg_tx_buf_valid <= 1'b0;
      end
      if (w_tx_end_good && reg_tx_role)
        reg_tx_buf_valid <= 1'b0;

      if (w_tx_trigger_expire_pending) begin
        reg_tx_buf_valid <= 1'b0;
        reg_tx_role <= 1'b0;
      end
      if (reg_tx_trigger_valid && reg_tx_trigger_started &&
          (!i_tx_permit || (i_tt_window_seq_can != reg_tx_trigger_window_seq)))
        reg_tx_trigger_expired <= 1'b1;

      if (w_rx_store_end) begin
        reg_rx_frame_fd <= reg_frame_fd;
        reg_rx_frame_brs <= reg_frame_brs;
        reg_rx_frame_xtd <= reg_tx_role ? reg_tx_xtd : reg_rx_xtd;
        reg_rx_frame_rtr <= reg_tx_role ? reg_tx_rtr : reg_rx_rtr;
        reg_rx_frame_esi <= reg_tx_role ? i_err_passive : reg_rx_esi;
        if (reg_tx_role) begin
          reg_rx_id <= reg_tx_id;
          reg_rx_dlc <= reg_tx_dlc;
          reg_rx_payload <= reg_tx_payload;
          reg_rx_timestamp <= i_tx_timestamp_can;
        end
      end

      if (reg_fsm_bsp_current_state == ENUM_ST_INTERM && w_frame_step &&
          (reg_interm_count == 4'd0) && i_cfd_ctrl_ovl_en &&
          i_rx_frame_full_can && (reg_ovl_req_count < 4'd2))
        reg_ovl_req_count <= $bits(reg_ovl_req_count)'(reg_ovl_req_count + 4'd1);
      if (reg_fsm_bsp_current_state == ENUM_ST_IDLE && !i_rx_frame_full_can)
        reg_ovl_req_count <= 4'd0;
    end
  end

  // Count field bits, FD fixed-stuff positions, intermission and error sequence lengths.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_field_count
    if (!i_rst_n_can) begin
      reg_field_idx <= 10'd0;
      reg_fd_seq_count <= 6'd0;
      reg_fd_seq_total <= 6'd0;
      reg_interm_count <= 4'd0;
      reg_err_count <= 4'd0;
      reg_err_del_count <= 4'd0;
      reg_err_del_first_seen <= 1'b0;
      reg_crc_wait_count <= 4'd0;
      reg_suspend_count <= 4'd0;
    end else begin
      casez ({(w_tx_start || w_rx_sof_start), w_err_detect, w_frame_step})
        3'b1??: begin
          reg_field_idx <= 10'd0;
          reg_fd_seq_count <= 6'd0;
          reg_fd_seq_total <= reg_tx_fd ?
            6'(4 + ((reg_tx_data_len > 7'd16) ? 21 : 17)) : 6'd0;
          reg_interm_count <= 4'd0;
          reg_err_count <= 4'd0;
          reg_err_del_count <= 4'd0;
          reg_err_del_first_seen <= 1'b0;
          reg_crc_wait_count <= 4'd0;
          reg_suspend_count <= 4'd0;
        end
        3'b01?: begin
          reg_field_idx <= 10'd0;
          reg_err_count <= 4'd0;
          reg_err_del_count <= 4'd0;
          reg_err_del_first_seen <= 1'b0;
        end
        3'b001: begin
          case (reg_fsm_bsp_current_state)
        ENUM_ST_SOF, ENUM_ST_RTR1, ENUM_ST_IDE, ENUM_ST_RTR2, ENUM_ST_FDF,
        ENUM_ST_R0, ENUM_ST_RES, ENUM_ST_BRS, ENUM_ST_ESI, ENUM_ST_FIX_PRE,
        ENUM_ST_CRC_DEL, ENUM_ST_ACK, ENUM_ST_ACK_DEL:
          reg_field_idx <= 10'd0;
        ENUM_ST_FIX: begin
          // A fixed stuff bit inside the CRC field keeps the index of the next CRC bit.
        end
        ENUM_ST_ID_A: begin
          if (reg_field_idx == 10'd10)
            reg_field_idx <= 10'd0;
          else
            reg_field_idx <= $bits(reg_field_idx)'(reg_field_idx + 10'd1);
        end
        ENUM_ST_ID_B: begin
          if (reg_field_idx == 10'd17)
            reg_field_idx <= 10'd0;
          else
            reg_field_idx <= $bits(reg_field_idx)'(reg_field_idx + 10'd1);
        end
        ENUM_ST_DLC: begin
          if (reg_field_idx == 10'd3)
            reg_field_idx <= 10'd0;
          else
            reg_field_idx <= $bits(reg_field_idx)'(reg_field_idx + 10'd1);
          if (reg_field_idx == 10'd3 && reg_frame_fd && !reg_frame_niso)
            reg_fd_seq_total <=
              6'(4 + ((w_rx_len_calc > 7'd16) ? 21 : 17));
        end
        ENUM_ST_DATA: begin
          if (reg_field_idx + 10'd1 == (10'(reg_data_len) * 10'd8))
            reg_field_idx <= 10'd0;
          else
            reg_field_idx <= $bits(reg_field_idx)'(reg_field_idx + 10'd1);
        end
        ENUM_ST_SBC: begin
          if (reg_field_idx == 10'd3)
            reg_field_idx <= 10'd0;
          else
            reg_field_idx <= $bits(reg_field_idx)'(reg_field_idx + 10'd1);
          reg_fd_seq_count <= $bits(reg_fd_seq_count)'(reg_fd_seq_count + 6'd1);
        end
        ENUM_ST_CRC: begin
          if (reg_field_idx + 10'd1 == 10'(w_crc_len))
            reg_field_idx <= 10'd0;
          else
            reg_field_idx <= $bits(reg_field_idx)'(reg_field_idx + 10'd1);
          if (reg_frame_fd && !reg_frame_niso)
            reg_fd_seq_count <= $bits(reg_fd_seq_count)'(reg_fd_seq_count + 6'd1);
        end
        ENUM_ST_EOF: begin
          if (reg_field_idx == 10'd6)
            reg_field_idx <= 10'd0;
          else
            reg_field_idx <= $bits(reg_field_idx)'(reg_field_idx + 10'd1);
        end
        ENUM_ST_INTERM: begin
          if (reg_interm_count == 4'd2)
            reg_interm_count <= 4'd0;
          else
            reg_interm_count <= $bits(reg_interm_count)'(reg_interm_count + 4'd1);
        end
        ENUM_ST_SUSP: begin
          if (reg_suspend_count == 4'd7)
            reg_suspend_count <= 4'd0;
          else
            reg_suspend_count <= $bits(reg_suspend_count)'(reg_suspend_count + 4'd1);
        end
        ENUM_ST_ERR_FLAG, ENUM_ST_OVL: begin
          if (reg_err_count == 4'd5)
            reg_err_count <= 4'd0;
          else
            reg_err_count <= $bits(reg_err_count)'(reg_err_count + 4'd1);
        end
        ENUM_ST_CRC_WAIT:
          reg_crc_wait_count <= $bits(reg_crc_wait_count)'(reg_crc_wait_count + 4'd1);
            default: reg_field_idx <= 10'd0;
          endcase
        end
        default: begin end
      endcase

      // Count only consecutive recessive samples in the error delimiter.
      casez ({w_err_detect,
              (((reg_fsm_bsp_current_state == ENUM_ST_ERR_FLAG) ||
                (reg_fsm_bsp_current_state == ENUM_ST_OVL)) &&
               w_frame_step && (reg_err_count == 4'd5)),
              ((reg_fsm_bsp_current_state == ENUM_ST_ERR_DEL) && i_sample)})
        3'b1??: begin
          reg_err_del_count <= 4'd0;
          reg_err_del_first_seen <= 1'b0;
        end
        3'b01?: begin
          reg_err_del_first_seen <= 1'b0;
        end
        3'b001: begin
          reg_err_del_first_seen <= 1'b1;
          if (w_rx_wire_bit) begin
            if (reg_err_del_count < 4'd7)
              reg_err_del_count <= $bits(reg_err_del_count)'(
                reg_err_del_count + 4'd1
              );
          end else begin
            reg_err_del_count <= 4'd0;
          end
        end
        default: begin end
      endcase
    end
  end

  // Wire bit that the next transmit point puts on the pin; the TDC stores it with the point.
  // A node that is not the transmitter drives only its ACK bit and its error/overload flags.
  assign w_tx_bit_nxt = (reg_tx_role || w_tx_start ||
                          (reg_fsm_bsp_current_state == ENUM_ST_ACK) ||
                          (reg_fsm_bsp_current_state == ENUM_ST_ERR_FLAG) ||
                          (reg_fsm_bsp_current_state == ENUM_ST_OVL)) ? w_tx_wire_bit : 1'b1;

  // Register the wire bit and comparison context at every BTL transmit point.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_tx_pin
    if (!i_rst_n_can) begin
      reg_tx_bit_sent <= 1'b1;
      reg_tx_adv <= 1'b0;
      reg_tx_fixed <= 1'b0;
      reg_tx_cmp_en <= 1'b0;
    end else if (i_tx_point) begin
      reg_tx_bit_sent <= w_tx_bit_nxt;
      reg_tx_adv <= w_tx_logical_adv && !w_tx_dyn_stuff && !w_tx_fixed_stuff;
      reg_tx_fixed <= w_tx_fixed_stuff;
      reg_tx_cmp_en <= reg_tx_role && w_frame_active &&
                       (reg_fsm_bsp_current_state != ENUM_ST_ACK);
    end
  end

  // Track integration-idle history, pre-start synchronizer clear and stuck-dominant count.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_bus_observe
    if (!i_rst_n_can) begin
      reg_idle_count <= 4'd0;
      reg_rx_start_seen <= 1'b0;
      reg_dom_count <= 8'd0;
      reg_dom_event_sent <= 1'b0;
      reg_dom_stk <= 1'b0;
    end else begin
      if (i_sample) begin
        if (w_rx_wire_bit) begin
          if (reg_idle_count < 4'(LPARA_IDLE_BITS))
            reg_idle_count <= $bits(reg_idle_count)'(reg_idle_count + 4'd1);
          reg_dom_count <= 8'd0;
          reg_dom_event_sent <= 1'b0;
        end else begin
          reg_idle_count <= 4'd0;
          if (reg_dom_count != 8'hff)
            reg_dom_count <= $bits(reg_dom_count)'(reg_dom_count + 8'd1);
          if (w_dom_reached)
            reg_dom_stk <= 1'b1;
        end
      end
      if (reg_fsm_bsp_current_state == ENUM_ST_IDLE && !i_rx_sync)
        reg_rx_start_seen <= 1'b1;
      else if (i_rx_sync)
        reg_rx_start_seen <= 1'b0;
      if (w_dom_reached)
        reg_dom_event_sent <= 1'b1;
      if (i_cfd_dom_cfg_dom_lim == 8'd0) begin
        reg_dom_count <= 8'd0;
        reg_dom_event_sent <= 1'b0;
      end
    end
  end

  // Clamp the stuck-dominant alert threshold and identify its one-shot event condition.
  always_comb begin : p_com_dom_limit
    w_dom_limit = (i_cfd_dom_cfg_dom_lim < 8'd16) ?
                  8'd16 : i_cfd_dom_cfg_dom_lim;
  end
  assign w_dom_reached = i_sample && !w_rx_wire_bit &&
                         (i_cfd_dom_cfg_dom_lim != 8'd0) &&
                         !reg_dom_event_sent &&
                         (reg_dom_count + 8'd1 >= w_dom_limit);

  // Emit one-cycle EML/IRQ events and hold each terminal result until CDC source acceptance.
  always_ff @(posedge i_clk_can, negedge i_rst_n_can) begin : p_ff_events
    if (!i_rst_n_can) begin
      reg_tx_result_valid <= 1'b0;
      reg_tx_result_success <= 1'b0;
      reg_tx_result_cancel <= 1'b0;
      reg_tx_result_err <= 1'b0;
      reg_tx_result_arb_lost <= 1'b0;
      reg_tx_result_timestamp <= '0;
      reg_tx_result_trigger_valid <= 1'b0;
      reg_tx_result_trigger_buf <= '0;
      reg_tx_result_trigger_started <= 1'b0;
      reg_tx_result_trigger_expired <= 1'b0;
      reg_rx_frame_valid_can <= 1'b0;
      reg_evt_rx_err <= 1'b0;
      reg_evt_rx_dom_after_flag <= 1'b0;
      reg_evt_tx_err_count <= 1'b0;
      reg_evt_tx_bit_err_flag <= 1'b0;
      reg_evt_rx_bit_err_flag <= 1'b0;
      reg_evt_tx_dom_seq8 <= 1'b0;
      reg_evt_rx_dom_seq8 <= 1'b0;
      reg_evt_tx_success <= 1'b0;
      reg_evt_rx_success <= 1'b0;
      reg_evt_idle11 <= 1'b0;
      reg_err_start <= 1'b0;
      reg_err_phase_data <= 1'b0;
      reg_err_code <= 3'd0;
      reg_evt_crc_err <= 1'b0;
      reg_evt_stuff_err <= 1'b0;
      reg_evt_form_err <= 1'b0;
      reg_evt_ack_err <= 1'b0;
      reg_evt_pxe <= 1'b0;
      reg_evt_dom_to <= 1'b0;
      reg_del_dom_count <= 3'd0;
      reg_tx_passive_ack_pending <= 1'b0;
      reg_tx_passive_ack_dom_seen <= 1'b0;
    end else begin
      // Release the held result only after the CDC source endpoint captures it.
      if (reg_tx_result_valid && w_tx_result_ready) begin
        reg_tx_result_valid <= 1'b0;
        reg_tx_result_success <= 1'b0;
        reg_tx_result_cancel <= 1'b0;
        reg_tx_result_err <= 1'b0;
        reg_tx_result_arb_lost <= 1'b0;
        reg_tx_result_trigger_valid <= 1'b0;
        reg_tx_result_trigger_buf <= '0;
        reg_tx_result_trigger_started <= 1'b0;
        reg_tx_result_trigger_expired <= 1'b0;
      end
      reg_rx_frame_valid_can <= 1'b0;
      reg_evt_rx_err <= 1'b0;
      reg_evt_rx_dom_after_flag <= 1'b0;
      reg_evt_tx_err_count <= 1'b0;
      reg_evt_tx_bit_err_flag <= 1'b0;
      reg_evt_rx_bit_err_flag <= 1'b0;
      reg_evt_tx_dom_seq8 <= 1'b0;
      reg_evt_rx_dom_seq8 <= 1'b0;
      reg_evt_tx_success <= 1'b0;
      reg_evt_rx_success <= 1'b0;
      reg_evt_idle11 <= 1'b0;
      reg_err_start <= 1'b0;
      reg_evt_crc_err <= 1'b0;
      reg_evt_stuff_err <= 1'b0;
      reg_evt_form_err <= 1'b0;
      reg_evt_ack_err <= 1'b0;
      reg_evt_pxe <= 1'b0;
      reg_evt_dom_to <= 1'b0;

      // Return a no-start expiry as a trigger result so BUS can set the buffer miss bit.
      if (w_tx_trigger_expire_pending && (!reg_tx_result_valid || w_tx_result_ready)) begin
        reg_tx_result_valid <= 1'b1;
        reg_tx_result_success <= 1'b0;
        reg_tx_result_cancel <= 1'b0;
        reg_tx_result_err <= 1'b0;
        reg_tx_result_arb_lost <= 1'b0;
        reg_tx_result_timestamp <= '0;
        reg_tx_result_trigger_valid <= 1'b1;
        reg_tx_result_trigger_buf <= reg_tx_trigger_buf;
        reg_tx_result_trigger_started <= 1'b0;
        reg_tx_result_trigger_expired <= 1'b1;
      end
      if (w_arb_loss && (!reg_tx_result_valid || w_tx_result_ready)) begin
        reg_tx_result_valid <= 1'b1;
        reg_tx_result_success <= 1'b0;
        reg_tx_result_cancel <= i_cfd_ctrl_dar;
        reg_tx_result_err <= 1'b0;
        reg_tx_result_arb_lost <= !i_cfd_ctrl_dar;
        reg_tx_result_timestamp <= i_tx_timestamp_can;
        reg_tx_result_trigger_valid <= reg_tx_trigger_valid && !reg_tx_owner_tt;
        reg_tx_result_trigger_buf <= reg_tx_trigger_buf;
        reg_tx_result_trigger_started <= reg_tx_trigger_started;
        reg_tx_result_trigger_expired <= reg_tx_trigger_valid &&
                                         (reg_tx_trigger_expired || !i_tx_permit ||
                                          (i_tt_window_seq_can != reg_tx_trigger_window_seq));
      end
      if (w_err_first) begin
        reg_err_start <= 1'b1;
        reg_err_phase_data <= i_data_phase;
        casez ({w_stuff_err, w_form_err, w_ack_err,
                w_tx_bit_err || i_tdc_bit_err})
          4'b1???: reg_err_code <= 3'b001;
          4'b01??: reg_err_code <= 3'b010;
          4'b001?: reg_err_code <= 3'b011;
          4'b0001: reg_err_code <= w_rx_wire_bit ? 3'b100 : 3'b101;
          default: reg_err_code <= 3'b110;
        endcase
      end
      if (w_err_detect) begin
        if (w_stuff_err)
          reg_evt_stuff_err <= 1'b1;
        if (w_form_err)
          reg_evt_form_err <= 1'b1;
        if (w_ack_err)
          reg_evt_ack_err <= 1'b1;
        if (!reg_tx_role)
          reg_evt_rx_err <= 1'b1;
      end
      if (w_err_first && reg_tx_role) begin
        if (i_err_passive && w_ack_err) begin
          reg_tx_passive_ack_pending <= 1'b1;
          reg_tx_passive_ack_dom_seen <= 1'b0;
        end else if (!w_tx_exception2) begin
          reg_evt_tx_err_count <= 1'b1;
        end
      end
      if (reg_tx_passive_ack_pending && i_sample &&
          (reg_fsm_bsp_current_state == ENUM_ST_ERR_FLAG) &&
          (reg_err_count == 4'd5)) begin
        if (reg_tx_passive_ack_dom_seen || !w_rx_wire_bit)
          reg_evt_tx_err_count <= 1'b1;
        reg_tx_passive_ack_pending <= 1'b0;
        reg_tx_passive_ack_dom_seen <= 1'b0;
      end else if (reg_tx_passive_ack_pending && i_sample &&
                   (reg_fsm_bsp_current_state == ENUM_ST_ERR_FLAG) &&
                   !w_rx_wire_bit) begin
        reg_tx_passive_ack_dom_seen <= 1'b1;
      end
      if (w_flag_bit_err) begin
        if (reg_tx_role)
          reg_evt_tx_bit_err_flag <= 1'b1;
        else
          reg_evt_rx_bit_err_flag <= 1'b1;
      end
      if (w_crc_rx_mismatch || w_rx_sbc_err) begin
        reg_evt_crc_err <= 1'b1;
        if (!reg_tx_role)
          reg_evt_rx_err <= 1'b1;
      end
      if (w_pxe_event)
        reg_evt_pxe <= 1'b1;
      if (w_dom_reached)
        reg_evt_dom_to <= 1'b1;

      if (w_tx_end_good && reg_tx_role &&
          (!reg_tx_result_valid || w_tx_result_ready)) begin
        reg_tx_result_valid <= 1'b1;
        reg_tx_result_success <= 1'b1;
        reg_tx_result_cancel <= 1'b0;
        reg_tx_result_err <= 1'b0;
        reg_tx_result_arb_lost <= 1'b0;
        reg_tx_result_timestamp <= i_tx_timestamp_can;
        reg_tx_result_trigger_valid <= reg_tx_trigger_valid && !reg_tx_owner_tt;
        reg_tx_result_trigger_buf <= reg_tx_trigger_buf;
        reg_tx_result_trigger_started <= reg_tx_trigger_started;
        reg_tx_result_trigger_expired <= reg_tx_trigger_valid &&
                                         (reg_tx_trigger_expired || !i_tx_permit ||
                                          (i_tt_window_seq_can != reg_tx_trigger_window_seq));
        reg_evt_tx_success <= 1'b1;
      end
      if (w_rx_end_good) begin
        reg_rx_frame_valid_can <= 1'b1;
        reg_evt_rx_success <= 1'b1;
      end
      if (w_tx_end_good && reg_tx_role &&
          (i_cfd_ctrl_lbk_int || i_cfd_ctrl_lbk_ext)) begin
        reg_rx_frame_valid_can <= 1'b1;
        reg_evt_rx_success <= 1'b1;
      end
      if (w_err_del_done && reg_tx_role &&
          (!reg_tx_result_valid || w_tx_result_ready)) begin
        reg_tx_result_valid <= 1'b1;
        reg_tx_result_success <= 1'b0;
        reg_tx_result_cancel <= 1'b0;
        reg_tx_result_err <= 1'b1;
        reg_tx_result_arb_lost <= 1'b0;
        reg_tx_result_timestamp <= i_tx_timestamp_can;
        reg_tx_result_trigger_valid <= reg_tx_trigger_valid && !reg_tx_owner_tt;
        reg_tx_result_trigger_buf <= reg_tx_trigger_buf;
        reg_tx_result_trigger_started <= reg_tx_trigger_started;
        reg_tx_result_trigger_expired <= reg_tx_trigger_valid &&
                                         (reg_tx_trigger_expired || !i_tx_permit ||
                                          (i_tt_window_seq_can != reg_tx_trigger_window_seq));
      end
      if (reg_fsm_bsp_current_state == ENUM_ST_INTEG && i_sample &&
          i_sample_val &&
          (reg_idle_count == 4'(LPARA_IDLE_BITS - 32'd1)))
        reg_evt_idle11 <= 1'b1;

      if ((reg_fsm_bsp_current_state == ENUM_ST_ERR_DEL) && i_sample) begin
        if (!w_rx_wire_bit) begin
          if (!reg_err_del_first_seen && !reg_tx_role)
            reg_evt_rx_dom_after_flag <= 1'b1;
          if (reg_del_dom_count == 3'd7) begin
            reg_del_dom_count <= 3'd0;
            if (reg_tx_role)
              reg_evt_tx_dom_seq8 <= 1'b1;
            else
              reg_evt_rx_dom_seq8 <= 1'b1;
          end else begin
            reg_del_dom_count <= $bits(reg_del_dom_count)'(reg_del_dom_count + 3'd1);
          end
        end else begin
          reg_del_dom_count <= 3'd0;
        end
      end
    end
  end

  assign o_err_code = reg_err_code;
  assign o_err_phase_data = reg_err_phase_data;
  assign o_err_start = reg_err_start;
  // One interrupt pulse per error, in the phase where it started.
  assign o_evt_err_arb = reg_err_start && !reg_err_phase_data;
  assign o_evt_err_dat = reg_err_start && reg_err_phase_data;
  assign o_evt_ack_err = reg_evt_ack_err;
  assign o_evt_crc_err = reg_evt_crc_err;
  assign o_evt_dom_to = reg_evt_dom_to;
  assign o_evt_form_err = reg_evt_form_err;
  assign o_evt_idle11 = reg_evt_idle11;
  assign o_evt_pxe = reg_evt_pxe;
  assign o_evt_rx_bit_err_flag = reg_evt_rx_bit_err_flag;
  assign o_evt_rx_dom_after_flag = reg_evt_rx_dom_after_flag;
  assign o_evt_rx_dom_seq8 = reg_evt_rx_dom_seq8;
  assign o_evt_rx_err = reg_evt_rx_err;
  assign o_evt_rx_success = reg_evt_rx_success;
  assign o_evt_stuff_err = reg_evt_stuff_err;
  assign o_evt_tx_bit_err_flag = reg_evt_tx_bit_err_flag;
  assign o_evt_tx_dom_seq8 = reg_evt_tx_dom_seq8;
  assign o_evt_tx_err_count = reg_evt_tx_err_count;
  assign o_evt_tx_success = reg_evt_tx_success;
  assign o_rx_frame_valid_can = reg_rx_frame_valid_can;
  // Route each held result only to the owner that supplied the accepted frame.
  assign o_tx_result_cancel = reg_tx_result_cancel && !reg_tx_owner_tt;
  assign o_tx_result_err = reg_tx_result_err && !reg_tx_owner_tt;
  assign o_tx_result_arb_lost = reg_tx_result_arb_lost && !reg_tx_owner_tt;
  assign o_tx_result_success = reg_tx_result_success && !reg_tx_owner_tt;
  assign o_tx_result_valid = reg_tx_result_valid && !reg_tx_owner_tt;
  assign o_tx_result_timestamp = reg_tx_result_timestamp;
  assign o_tx_result_trigger_valid = reg_tx_result_trigger_valid && !reg_tx_owner_tt;
  assign o_tx_result_trigger_buf = reg_tx_result_trigger_buf;
  assign o_tx_result_trigger_started = reg_tx_result_trigger_started && !reg_tx_owner_tt;
  assign o_tx_result_trigger_expired = reg_tx_result_trigger_expired && !reg_tx_owner_tt;
  assign o_tt_ref_result_cancel = reg_tx_result_cancel && reg_tx_owner_tt;
  assign o_tt_ref_result_err = reg_tx_result_err && reg_tx_owner_tt;
  assign o_tt_ref_result_arb_lost = reg_tx_result_arb_lost && reg_tx_owner_tt;
  assign o_tt_ref_result_success = reg_tx_result_success && reg_tx_owner_tt;
  assign o_tt_ref_result_valid = reg_tx_result_valid && reg_tx_owner_tt;
  assign o_tt_ref_result_timestamp = reg_tx_result_timestamp;
  assign o_tx_sof_sample = w_tx_sof_sample;
  // TTCAN captures one common Sync_Mark for locally transmitted and received SOFs.
  assign o_sof_sample_can = w_tx_sof_sample || w_rx_sof_start;

  // Seed CRC and stuffer state before a new Tx frame or synchronized receive SOF.
  assign w_crc_init = w_tx_start || w_rx_sof_pre;

  // Submodule instances
  m_canfd_stuf u_canfd_stuf (
    .i_clk_can        (i_clk_can),
    .i_rst_n_can      (i_rst_n_can),
    .i_stuf_clear     (w_tx_start || (w_rx_sof_pre && !reg_rx_start_seen)),
    .i_dyn_stuf_en    (w_dyn_stuf_en || w_rx_sof_start),
    .i_iso_fd         ((reg_frame_fd && !reg_frame_niso) ||
                       (!reg_tx_role && reg_rx_store_en) || w_rx_sof_start),
    .i_tx_fixed_slot  (w_fixed_slot),
    .i_rx_fixed_slot  (w_fixed_slot),
    .i_tx_point       (i_tx_point),
    .i_tx_logical_bit (w_tx_logic_bit),
    .o_tx_bit         (w_tx_wire_bit),
    .o_tx_logical_adv (w_tx_logical_adv),
    .o_tx_dyn_stuff   (w_tx_dyn_stuff),
    .o_tx_fixed_stuff (w_tx_fixed_stuff),
    .o_tx_sbc_code    (w_tx_sbc_code),
    .i_rx_sample      (i_sample),
    .i_rx_wire_bit    (w_rx_wire_bit),
    .o_rx_bit         (w_rx_bit),
    .o_rx_bit_valid   (w_rx_bit_valid),
    .o_rx_dyn_stuff   (w_rx_dyn_stuff),
    .o_rx_stuff_err   (w_rx_stuff_err),
    .o_rx_fixed_err   (w_rx_fixed_err),
    .i_rx_sbc_valid   (w_sbc_last),
    .i_rx_sbc_code    ({reg_rx_sbc[2:0], w_rx_bit}),
    .o_rx_sbc_err     (w_rx_sbc_err)
  );
  m_canfd_crc u_canfd_crc (
    .i_clk_can      (i_clk_can),
    .i_rst_n_can    (i_rst_n_can),
    .i_crc_init     (w_crc_init),
    .i_crc_cc_valid (i_sample && w_rx_protected && w_rx_bit_valid),
    .i_crc_fd_valid (i_sample && w_rx_protected &&
                     (w_rx_bit_valid || w_rx_dyn_stuff)),
    .i_crc_bit      (w_rx_dyn_stuff ? w_rx_wire_bit : w_rx_bit),
    .o_crc15        (w_crc15),
    .o_crc17        (w_crc17),
    .o_crc21        (w_crc21)
  );

endmodule

