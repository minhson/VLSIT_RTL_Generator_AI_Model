/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-11
 * Description  : Applies INIT/CCE and safety-lock protection to configuration
 *                fields while preserving runtime control fields in mixed words.
 * Decision     : DEC-021, DEC-089, DEC-112
 */
`timescale 1ns/1ps

module m_canfd_wprot #(
  localparam logic [31:0] LPARA_ADDR_CFD_NBT2       = 32'h000C,
  localparam logic [31:0] LPARA_ADDR_CFD_CTRL       = 32'h0010,
  localparam logic [31:0] LPARA_ADDR_CFD_NBT        = 32'h0014,
  localparam logic [31:0] LPARA_ADDR_CFD_DBT        = 32'h0018,
  localparam logic [31:0] LPARA_ADDR_CFD_TDC        = 32'h001C,
  localparam logic [31:0] LPARA_ADDR_CFD_WAKE       = 32'h002C,
  localparam logic [31:0] LPARA_ADDR_CFD_GFC        = 32'h0048,
  localparam logic [31:0] LPARA_ADDR_CFD_XIDAM      = 32'h004C,
  localparam logic [31:0] LPARA_ADDR_CFD_SF_CFG     = 32'h0050,
  localparam logic [31:0] LPARA_ADDR_CFD_EF_CFG     = 32'h0054,
  localparam logic [31:0] LPARA_ADDR_CFD_RXF0_CFG   = 32'h0058,
  localparam logic [31:0] LPARA_ADDR_CFD_RXF1_CFG   = 32'h005C,
  localparam logic [31:0] LPARA_ADDR_CFD_RXB_CFG    = 32'h0060,
  localparam logic [31:0] LPARA_ADDR_CFD_ESZ        = 32'h0064,
  localparam logic [31:0] LPARA_ADDR_CFD_TXB_CFG    = 32'h0068,
  localparam logic [31:0] LPARA_ADDR_CFD_TXE_CFG    = 32'h006C,
  localparam logic [31:0] LPARA_ADDR_CFD_TRIG_CFG   = 32'h0070,
  localparam logic [31:0] LPARA_ADDR_CFD_MRAM_WDT   = 32'h0074,
  localparam logic [31:0] LPARA_ADDR_CFD_BO_CFG     = 32'h0078,
  localparam logic [31:0] LPARA_ADDR_CFD_TXR_CFG    = 32'h00CC,
  localparam logic [31:0] LPARA_ADDR_CFD_TS_CFG     = 32'h00D0,
  localparam logic [31:0] LPARA_ADDR_CFD_TOUT_CFG   = 32'h00D8,
  localparam logic [31:0] LPARA_ADDR_CFD_DMA_CFG    = 32'h00E0,
  localparam logic [31:0] LPARA_ADDR_CFD_TXP_CFG    = 32'h00EC,
  localparam logic [31:0] LPARA_ADDR_CFD_DOM_CFG    = 32'h00F4,
  localparam logic [31:0] LPARA_ADDR_CFD_TT_CFG     = 32'h0200,
  localparam logic [31:0] LPARA_ADDR_CFD_TT_REF     = 32'h0204,
  localparam logic [31:0] LPARA_ADDR_CFD_TT_TURN    = 32'h0208,
  localparam logic [31:0] LPARA_ADDR_CFD_TT_TURD    = 32'h020C,
  localparam logic [31:0] LPARA_ADDR_CFD_TT_MTX     = 32'h0210,
  localparam logic [31:0] LPARA_ADDR_CFD_TT_WD      = 32'h0214,
  localparam logic [31:0] LPARA_ADDR_CFD_TT_TMARK   = 32'h022C,
  localparam logic [31:0] LPARA_ADDR_CFD_TT_CLK     = 32'h0230,
  localparam logic [31:0] LPARA_ADDR_CFD_TT_GAP     = 32'h0238,
  localparam logic [31:0] LPARA_ADDR_CFD_TTB_PER    = 32'h023C,
  localparam logic [31:0] LPARA_ADDR_CFD_SAF_CTRL   = 32'h0300,
  localparam logic [31:0] LPARA_ADDR_CFD_SAF_CLK    = 32'h0304,
  localparam logic [31:0] LPARA_ADDR_CFD_SAF_CLK2   = 32'h0308,
  localparam logic [31:0] LPARA_ADDR_CFD_SAF_RCT    = 32'h0318,
  localparam logic [31:0] LPARA_MASK_CFD_CTRL       = 32'h0001_DFFC,
  localparam logic [31:0] LPARA_MASK_CFD_WAKE       = 32'h0FFF_FFFE,
  localparam logic [31:0] LPARA_MASK_CFD_TT_WD      = 32'h0000_00FF,
  localparam logic [31:0] LPARA_MASK_CFD_TT_CLK     = 32'h0000_0003,
  localparam logic [31:0] LPARA_MASK_CFD_TT_GAP     = 32'h0000_000C,
  localparam logic [31:0] LPARA_MASK_CFD_SAF_CTRL   = 32'h0000_1FFF
) (
  // Clock and reset
  input  wire         i_clk_bus,
  input  wire         i_rst_n_bus,

  // APB request from the external bus
  input  wire         i_apb_psel,
  input  wire         i_apb_penable,
  input  wire         i_apb_pwrite,
  input  wire  [15:0] i_apb_paddr,
  input  wire  [31:0] i_apb_pwdata,
  input  wire  [3:0]  i_apb_pstrb,
  input  wire  [2:0]  i_apb_pprot,

  // Current values of mixed control/configuration words
  input  wire  [31:0] i_cfg_word_ctrl_current,
  input  wire  [31:0] i_cfg_word_wake_current,
  input  wire  [31:0] i_cfg_word_tt_wd_current,
  input  wire  [31:0] i_cfg_word_ttclk_current,
  input  wire  [31:0] i_cfg_word_tt_gap_current,
  input  wire  [31:0] i_cfg_word_saf_ctrl_current,

  // Write-protection controls
  input  wire         i_init,
  input  wire         i_cce,
  input  wire         i_lock_en,
  input  wire         i_key_valid,
  input  wire         i_init_hold_bus,

  // Filtered APB request to the generated CSR block
  output logic        o_apb_psel,
  output logic        o_apb_penable,
  output logic        o_apb_pwrite,
  output logic [15:0] o_apb_paddr,
  output logic [31:0] o_apb_pwdata,
  output logic [3:0]  o_apb_pstrb,
  output logic [2:0]  o_apb_pprot,

  // Lock violation event
  output logic        o_lock_violation
);

  logic        w_apb_wr_access;
  logic        w_config_window_open;
  logic        w_lock_blocks;
  logic        w_cfg_addr_full;
  logic        w_cfg_addr_mixed;
  logic        w_filter_mixed;
  logic        w_wr_blocked;
  logic        w_mixed_lock_violation;
  logic [31:0] w_mixed_mask;
  logic [31:0] w_mixed_current;
  logic [31:0] w_filtered_pwdata;
  logic [31:0] w_pwdata_sel;
  logic        w_init_hold_wr;
  logic        reg_lock_violation;

  // Decode configuration registers and mixed words from the CSR workbook map.
  always_comb begin : p_com_decode
    w_cfg_addr_full  = 1'b0;
    w_cfg_addr_mixed = 1'b0;
    w_mixed_mask     = 32'd0;
    w_mixed_current  = 32'd0;

    casez ({16'd0, i_apb_paddr})
      LPARA_ADDR_CFD_NBT2,
      LPARA_ADDR_CFD_NBT,
      LPARA_ADDR_CFD_DBT,
      LPARA_ADDR_CFD_TDC,
      LPARA_ADDR_CFD_GFC,
      LPARA_ADDR_CFD_XIDAM,
      LPARA_ADDR_CFD_SF_CFG,
      LPARA_ADDR_CFD_EF_CFG,
      LPARA_ADDR_CFD_RXF0_CFG,
      LPARA_ADDR_CFD_RXF1_CFG,
      LPARA_ADDR_CFD_RXB_CFG,
      LPARA_ADDR_CFD_ESZ,
      LPARA_ADDR_CFD_TXB_CFG,
      LPARA_ADDR_CFD_TXE_CFG,
      LPARA_ADDR_CFD_TRIG_CFG,
      LPARA_ADDR_CFD_MRAM_WDT,
      LPARA_ADDR_CFD_BO_CFG,
      LPARA_ADDR_CFD_TXR_CFG,
      LPARA_ADDR_CFD_TS_CFG,
      LPARA_ADDR_CFD_TOUT_CFG,
      LPARA_ADDR_CFD_DMA_CFG,
      LPARA_ADDR_CFD_TXP_CFG,
      LPARA_ADDR_CFD_DOM_CFG,
      LPARA_ADDR_CFD_TT_CFG,
      LPARA_ADDR_CFD_TT_REF,
      LPARA_ADDR_CFD_TT_TURN,
      LPARA_ADDR_CFD_TT_TURD,
      LPARA_ADDR_CFD_TT_MTX,
      LPARA_ADDR_CFD_TT_TMARK,
      LPARA_ADDR_CFD_TTB_PER,
      LPARA_ADDR_CFD_SAF_CLK,
      LPARA_ADDR_CFD_SAF_CLK2,
      LPARA_ADDR_CFD_SAF_RCT: begin
        w_cfg_addr_full = 1'b1;
      end

      LPARA_ADDR_CFD_CTRL: begin
        w_cfg_addr_mixed = 1'b1;
        w_mixed_mask     = LPARA_MASK_CFD_CTRL;
        w_mixed_current  = i_cfg_word_ctrl_current;
      end
      LPARA_ADDR_CFD_WAKE: begin
        w_cfg_addr_mixed = 1'b1;
        w_mixed_mask     = LPARA_MASK_CFD_WAKE;
        w_mixed_current  = i_cfg_word_wake_current;
      end
      LPARA_ADDR_CFD_TT_WD: begin
        w_cfg_addr_mixed = 1'b1;
        w_mixed_mask     = LPARA_MASK_CFD_TT_WD;
        w_mixed_current  = i_cfg_word_tt_wd_current;
      end
      LPARA_ADDR_CFD_TT_CLK: begin
        w_cfg_addr_mixed = 1'b1;
        w_mixed_mask     = LPARA_MASK_CFD_TT_CLK;
        w_mixed_current  = i_cfg_word_ttclk_current;
      end
      LPARA_ADDR_CFD_TT_GAP: begin
        w_cfg_addr_mixed = 1'b1;
        w_mixed_mask     = LPARA_MASK_CFD_TT_GAP;
        w_mixed_current  = i_cfg_word_tt_gap_current;
      end
      LPARA_ADDR_CFD_SAF_CTRL: begin
        w_cfg_addr_mixed = 1'b1;
        w_mixed_mask     = LPARA_MASK_CFD_SAF_CTRL;
        w_mixed_current  = i_cfg_word_saf_ctrl_current;
      end
      default: begin
        w_cfg_addr_full  = 1'b0;
        w_cfg_addr_mixed = 1'b0;
        w_mixed_mask     = 32'd0;
        w_mixed_current  = 32'd0;
      end
    endcase
  end

  // Gate protected fields only; control and command fields remain writable.
  // Identify an APB write in its access phase.
  assign w_apb_wr_access = i_apb_psel && i_apb_penable && i_apb_pwrite;

  // Open the protected configuration window only when INIT and CCE are both high.
  assign w_config_window_open = i_init && i_cce;

  // The safety lock blocks protected writes until the valid key is presented.
  assign w_lock_blocks = i_lock_en && !i_key_valid;

  // Preserve protected fields in mixed registers whenever either protection gate is closed.
  assign w_filter_mixed = w_apb_wr_access && w_cfg_addr_mixed &&
                          (!w_config_window_open || w_lock_blocks);

  // Suppress full-register writes while the configuration gate is closed.
  assign w_wr_blocked = w_apb_wr_access && w_cfg_addr_full &&
                           (!w_config_window_open || w_lock_blocks);

  // Flag only attempted changes to protected fields denied by the safety lock.
  assign w_mixed_lock_violation = w_apb_wr_access && w_cfg_addr_mixed &&
                                  w_config_window_open && w_lock_blocks &&
                                  (|((i_apb_pwdata ^ w_mixed_current) & w_mixed_mask));

  // Merge current protected field values with writable runtime control data.
  assign w_filtered_pwdata = (i_apb_pwdata & ~w_mixed_mask) |
                             (w_mixed_current & w_mixed_mask);

  // Pass APB timing and address unchanged; only protected write data/control is filtered.
  assign o_apb_psel    = i_apb_psel;
  assign o_apb_penable = i_apb_penable;
  assign o_apb_pwrite  = i_apb_pwrite && !w_wr_blocked;
  assign o_apb_paddr   = i_apb_paddr;
  assign w_pwdata_sel  = w_filter_mixed ? w_filtered_pwdata : i_apb_pwdata;
  // While the clock stop request is held a write to cfd_ctrl cannot clear INIT (REQ-PWR-001).
  assign w_init_hold_wr = i_init_hold_bus && w_apb_wr_access &&
                          (i_apb_paddr == LPARA_ADDR_CFD_CTRL[15:0]);
  assign o_apb_pwdata  = {w_pwdata_sel[31:1], w_pwdata_sel[0] || w_init_hold_wr};
  assign o_apb_pstrb   = i_apb_pstrb;
  assign o_apb_pprot   = i_apb_pprot;
  assign o_lock_violation = reg_lock_violation;

  // Report refused configuration writes when the safety lock is active.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_lock_violation
    if (!i_rst_n_bus) begin
      reg_lock_violation <= 1'b0;
    end else begin
      reg_lock_violation <= w_mixed_lock_violation ||
                            (w_apb_wr_access && w_cfg_addr_full &&
                             w_config_window_open && w_lock_blocks);
    end
  end

endmodule
