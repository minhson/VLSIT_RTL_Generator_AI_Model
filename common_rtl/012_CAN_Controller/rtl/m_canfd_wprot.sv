/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-09
 * Description  : Blocks writes to protected CAN configuration registers unless INIT and
 *                CCE are set and, when enabled, the safety write lock is open.
 * DEC IDs      : DEC-021, DEC-089
 */
`timescale 1ns/1ps

module m_canfd_wprot (
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

  // Write-protection controls
  input  wire         i_cfg_write_protected,
  input  wire         i_init,
  input  wire         i_cce,
  input  wire         i_lock_en,
  input  wire         i_key_valid,

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

  logic w_access;
  logic w_write_blocked;
  logic reg_lock_violation;

  // A protected write is suppressed without changing APB completion timing.
  assign w_access = i_apb_psel && i_apb_penable && i_apb_pwrite;
  assign w_write_blocked = w_access && i_cfg_write_protected &&
                           (!i_init || !i_cce || (i_lock_en && !i_key_valid));

  assign o_apb_psel    = i_apb_psel;
  assign o_apb_penable = i_apb_penable;
  assign o_apb_pwrite  = i_apb_pwrite && !w_write_blocked;
  assign o_apb_paddr   = i_apb_paddr;
  assign o_apb_pwdata  = i_apb_pwdata;
  assign o_apb_pstrb   = i_apb_pstrb;
  assign o_apb_pprot   = i_apb_pprot;
  assign o_lock_violation = reg_lock_violation;

  // Report a lock violation only when the INIT/CCE gate passed and the lock denied access.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_lock_violation
    if (!i_rst_n_bus) begin
      reg_lock_violation <= 1'b0;
    end else begin
      reg_lock_violation <= w_access && i_cfg_write_protected && i_init && i_cce &&
                            i_lock_en && !i_key_valid;
    end
  end

endmodule
