/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-09
 * Description  : Arbitrates Rx, Tx and optional TTCAN word requests onto the external
 *                single-port Message RAM interface and returns registered responses.
 * DEC IDs      : DEC-060, DEC-063, DEC-090, DEC-089
 */
`timescale 1ns/1ps

module m_canfd_mram #(
  // Parameter Description: width of the external Message-RAM word address.
  // Parameter values: 8 through 14; default is 14.
  // Parameter unit: bit
  parameter logic [31:0] PARA_CANFD_MRAM_AW = 32'd14,
  // Parameter Description: include the TTCAN trigger-list RAM client.
  // Parameter values: 0 = disabled, 1 = enabled; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_TT_EN = 32'd0,
  // Parameter Description: include the Message-RAM access watchdog.
  // Parameter values: 0 = disabled, 1 = enabled; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_SAF_WDT_EN = 32'd0,
  // Parameter Description: pass and report external Message-RAM ECC status.
  // Parameter values: 0 = disabled, 1 = enabled; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_SAF_RAM_EN = 32'd0,
  localparam logic [31:0] LPARA_CLIENT_RX = 32'd0,
  localparam logic [31:0] LPARA_CLIENT_TX = 32'd1,
  localparam logic [31:0] LPARA_CLIENT_TT = 32'd2,
  localparam logic [31:0] LPARA_STATE_IDLE = 32'd0,
  localparam logic [31:0] LPARA_STATE_WAIT_ACK = 32'd1,
  localparam logic [31:0] LPARA_STATE_BUBBLE = 32'd2
) (
  // Clock and reset
  input  wire                           i_clk_bus,
  input  wire                           i_rst_n_bus,

  // Rx Message-RAM client
  input  wire                           i_rx_req,
  input  wire                           i_rx_we,
  input  wire  [31:0]                   i_rx_addr,
  input  wire  [31:0]                   i_rx_wdata,
  output logic                          o_rx_ack,
  output logic [31:0]                   o_rx_rdata,
  output logic                          o_rx_err,
  output logic                          o_rx_err_cor,
  output logic                          o_rx_err_unc,

  // Tx Message-RAM client
  input  wire                           i_tx_req,
  input  wire                           i_tx_we,
  input  wire  [31:0]                   i_tx_addr,
  input  wire  [31:0]                   i_tx_wdata,
  output logic                          o_tx_ack,
  output logic [31:0]                   o_tx_rdata,
  output logic                          o_tx_err,
  output logic                          o_tx_err_cor,
  output logic                          o_tx_err_unc,

  // Optional TTCAN trigger-list Message-RAM client
  input  wire                           i_tt_req,
  input  wire                           i_tt_we,
  input  wire  [31:0]                   i_tt_addr,
  input  wire  [31:0]                   i_tt_wdata,
  output logic                          o_tt_ack,
  output logic [31:0]                   o_tt_rdata,
  output logic                          o_tt_err,
  output logic                          o_tt_err_cor,
  output logic                          o_tt_err_unc,

  // External Message-RAM master interface
  output logic                          o_mram_req,
  output logic                          o_mram_we,
  output logic [PARA_CANFD_MRAM_AW-1:0] o_mram_addr,
  output logic [31:0]                   o_mram_wdata,
  output logic [3:0]                    o_mram_be,
  input  wire                           i_mram_ack,
  input  wire  [31:0]                   i_mram_rdata,
  input  wire                           i_mram_err_cor,
  input  wire                           i_mram_err_unc,

  // Access watchdog controls from cfd_mram_wdt
  input  wire                           i_wdt_en,
  input  wire  [15:0]                   i_wdt_limit,

  // Fault and ECC event pulses for the IRQ and safety logic
  output logic                          o_ram_flt_event,
  output logic                          o_ram_wdt_event,
  output logic                          o_ecc_cor_event,
  output logic                          o_ecc_unc_event,
  output logic                          o_tx_fetch_timeout,
  output logic [31:0]                   o_fault_addr
);

  typedef enum logic [1:0] {
    ENUM_CLIENT_RX = LPARA_CLIENT_RX[1:0],
    ENUM_CLIENT_TX = LPARA_CLIENT_TX[1:0],
    ENUM_CLIENT_TT = LPARA_CLIENT_TT[1:0]
  } mram_client_type_def;

  typedef enum logic [1:0] {
    ENUM_STATE_IDLE = LPARA_STATE_IDLE[1:0],
    ENUM_STATE_WAIT_ACK = LPARA_STATE_WAIT_ACK[1:0],
    ENUM_STATE_BUBBLE = LPARA_STATE_BUBBLE[1:0]
  } mram_state_type_def;

  logic w_gnt_valid;
  mram_client_type_def w_gnt_client;
  logic [31:0] w_gnt_addr;
  logic w_gnt_we;
  logic [31:0] w_gnt_wdata;
  logic w_gnt_addr_valid;
  logic [2:0] w_req_vector;
  logic [2:0] w_rot_req_vector;
  logic w_wdt_active;
  logic w_wdt_timeout;
  logic [15:0] w_wdt_limit_eff;

  mram_state_type_def reg_mram_state;
  mram_client_type_def reg_active_client;
  logic [1:0] reg_rr_ptr;
  logic reg_active_we;
  logic [31:0] reg_active_addr;
  logic [31:0] reg_active_wdata;
  logic [15:0] reg_wdt_count;

  logic reg_rx_ack;
  logic [31:0] reg_rx_rdata;
  logic reg_rx_err;
  logic reg_rx_err_cor;
  logic reg_rx_err_unc;
  logic reg_tx_ack;
  logic [31:0] reg_tx_rdata;
  logic reg_tx_err;
  logic reg_tx_err_cor;
  logic reg_tx_err_unc;
  logic reg_tt_ack;
  logic [31:0] reg_tt_rdata;
  logic reg_tt_err;
  logic reg_tt_err_cor;
  logic reg_tt_err_unc;
  logic reg_ram_flt_event;
  logic reg_ram_wdt_event;
  logic reg_ecc_cor_event;
  logic reg_ecc_unc_event;
  logic reg_tx_fetch_timeout;
  logic [31:0] reg_fault_addr;

  // Drive each client response from registered status and data.
  assign o_rx_ack = reg_rx_ack;
  assign o_rx_rdata = reg_rx_rdata;
  assign o_rx_err = reg_rx_err;
  assign o_rx_err_cor = reg_rx_err_cor;
  assign o_rx_err_unc = reg_rx_err_unc;
  assign o_tx_ack = reg_tx_ack;
  assign o_tx_rdata = reg_tx_rdata;
  assign o_tx_err = reg_tx_err;
  assign o_tx_err_cor = reg_tx_err_cor;
  assign o_tx_err_unc = reg_tx_err_unc;
  assign o_tt_ack = reg_tt_ack;
  assign o_tt_rdata = reg_tt_rdata;
  assign o_tt_err = reg_tt_err;
  assign o_tt_err_cor = reg_tt_err_cor;
  assign o_tt_err_unc = reg_tt_err_unc;
  assign o_ram_flt_event = reg_ram_flt_event;
  assign o_ram_wdt_event = reg_ram_wdt_event;
  assign o_ecc_cor_event = reg_ecc_cor_event;
  assign o_ecc_unc_event = reg_ecc_unc_event;
  assign o_tx_fetch_timeout = reg_tx_fetch_timeout;
  assign o_fault_addr = reg_fault_addr;

  // Exclude the TTCAN client at elaboration when TTCAN support is not built.
  assign w_req_vector = {i_tt_req && (PARA_CANFD_TT_EN == 32'd1), i_tx_req, i_rx_req};

  // Keep the external request registered and independent of acknowledge input paths.
  assign o_mram_req = (reg_mram_state == ENUM_STATE_WAIT_ACK);
  assign o_mram_we = reg_active_we;
  assign o_mram_addr = reg_active_addr[PARA_CANFD_MRAM_AW-1:0];
  assign o_mram_wdata = reg_active_wdata;
  assign o_mram_be = (reg_mram_state == ENUM_STATE_WAIT_ACK) ? 4'b1111 : 4'b0000;

  // Treat a programmed watchdog limit of zero as a one-clock limit.
  assign w_wdt_limit_eff = (i_wdt_limit == 16'd0) ? 16'd1 : i_wdt_limit;
  assign w_wdt_active = (PARA_CANFD_SAF_WDT_EN == 32'd1) && i_wdt_en;
  assign w_wdt_timeout = w_wdt_active &&
                         (reg_wdt_count >= (w_wdt_limit_eff - 16'd1));
  // Reject upper word-address bits before the external address is truncated.
  assign w_gnt_addr_valid = !(|w_gnt_addr[31:PARA_CANFD_MRAM_AW]);

  // Select the first pending client from the round-robin start pointer.
  always_comb begin : p_com_mram_arb_sel
    w_rot_req_vector = w_req_vector;
    casez (reg_rr_ptr)
      ENUM_CLIENT_RX: w_rot_req_vector = w_req_vector;
      ENUM_CLIENT_TX: w_rot_req_vector = {w_req_vector[0], w_req_vector[2:1]};
      ENUM_CLIENT_TT: w_rot_req_vector = {w_req_vector[1:0], w_req_vector[2]};
      default:        w_rot_req_vector = w_req_vector;
    endcase

    w_gnt_valid = 1'b0;
    w_gnt_client = ENUM_CLIENT_RX;
    w_gnt_addr = '0;
    w_gnt_we = 1'b0;
    w_gnt_wdata = '0;
    casez (w_rot_req_vector)
      3'b??1: begin
        w_gnt_valid = 1'b1;
        casez (reg_rr_ptr)
          ENUM_CLIENT_RX: w_gnt_client = ENUM_CLIENT_RX;
          ENUM_CLIENT_TX: w_gnt_client = ENUM_CLIENT_TX;
          ENUM_CLIENT_TT: w_gnt_client = ENUM_CLIENT_TT;
          default:        w_gnt_client = ENUM_CLIENT_RX;
        endcase
      end
      3'b?10: begin
        w_gnt_valid = 1'b1;
        casez (reg_rr_ptr)
          ENUM_CLIENT_RX: w_gnt_client = ENUM_CLIENT_TX;
          ENUM_CLIENT_TX: w_gnt_client = ENUM_CLIENT_TT;
          ENUM_CLIENT_TT: w_gnt_client = ENUM_CLIENT_RX;
          default:        w_gnt_client = ENUM_CLIENT_TX;
        endcase
      end
      3'b100: begin
        w_gnt_valid = 1'b1;
        casez (reg_rr_ptr)
          ENUM_CLIENT_RX: w_gnt_client = ENUM_CLIENT_TT;
          ENUM_CLIENT_TX: w_gnt_client = ENUM_CLIENT_RX;
          ENUM_CLIENT_TT: w_gnt_client = ENUM_CLIENT_TX;
          default:        w_gnt_client = ENUM_CLIENT_TT;
        endcase
      end
      default: begin
        w_gnt_valid = 1'b0;
        w_gnt_client = ENUM_CLIENT_RX;
      end
    endcase

    casez (w_gnt_client)
      ENUM_CLIENT_RX: begin
        w_gnt_addr = i_rx_addr;
        w_gnt_we = i_rx_we;
        w_gnt_wdata = i_rx_wdata;
      end
      ENUM_CLIENT_TX: begin
        w_gnt_addr = i_tx_addr;
        w_gnt_we = i_tx_we;
        w_gnt_wdata = i_tx_wdata;
      end
      default: begin
        w_gnt_addr = i_tt_addr;
        w_gnt_we = i_tt_we;
        w_gnt_wdata = i_tt_wdata;
      end
    endcase
  end

  // Complete the selected client's word and advance the round-robin pointer.
  always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_mram_ctrl
    if (!i_rst_n_bus) begin
      reg_mram_state <= ENUM_STATE_IDLE;
      reg_active_client <= ENUM_CLIENT_RX;
      reg_rr_ptr <= LPARA_CLIENT_RX[1:0];
      reg_active_we <= 1'b0;
      reg_active_addr <= '0;
      reg_active_wdata <= '0;
      reg_wdt_count <= '0;
      reg_rx_ack <= 1'b0;
      reg_rx_rdata <= '0;
      reg_rx_err <= 1'b0;
      reg_rx_err_cor <= 1'b0;
      reg_rx_err_unc <= 1'b0;
      reg_tx_ack <= 1'b0;
      reg_tx_rdata <= '0;
      reg_tx_err <= 1'b0;
      reg_tx_err_cor <= 1'b0;
      reg_tx_err_unc <= 1'b0;
      reg_tt_ack <= 1'b0;
      reg_tt_rdata <= '0;
      reg_tt_err <= 1'b0;
      reg_tt_err_cor <= 1'b0;
      reg_tt_err_unc <= 1'b0;
      reg_ram_flt_event <= 1'b0;
      reg_ram_wdt_event <= 1'b0;
      reg_ecc_cor_event <= 1'b0;
      reg_ecc_unc_event <= 1'b0;
      reg_tx_fetch_timeout <= 1'b0;
      reg_fault_addr <= '0;
    end else begin
      reg_rx_ack <= 1'b0;
      reg_rx_err <= 1'b0;
      reg_rx_err_cor <= 1'b0;
      reg_rx_err_unc <= 1'b0;
      reg_tx_ack <= 1'b0;
      reg_tx_err <= 1'b0;
      reg_tx_err_cor <= 1'b0;
      reg_tx_err_unc <= 1'b0;
      reg_tt_ack <= 1'b0;
      reg_tt_err <= 1'b0;
      reg_tt_err_cor <= 1'b0;
      reg_tt_err_unc <= 1'b0;
      reg_ram_flt_event <= 1'b0;
      reg_ram_wdt_event <= 1'b0;
      reg_ecc_cor_event <= 1'b0;
      reg_ecc_unc_event <= 1'b0;
      reg_tx_fetch_timeout <= 1'b0;

      casez (reg_mram_state)
        ENUM_STATE_IDLE: begin
          reg_wdt_count <= '0;
          if (w_gnt_valid && !w_gnt_addr_valid) begin
            // Reject an address before truncation and return an error without a RAM request.
            reg_ram_flt_event <= 1'b1;
            reg_fault_addr <= w_gnt_addr;
            casez (w_gnt_client)
              ENUM_CLIENT_RX: begin
                reg_rx_ack <= 1'b1;
                reg_rx_rdata <= '0;
                reg_rx_err <= 1'b1;
              end
              ENUM_CLIENT_TX: begin
                reg_tx_ack <= 1'b1;
                reg_tx_rdata <= '0;
                reg_tx_err <= 1'b1;
              end
              default: begin
                reg_tt_ack <= 1'b1;
                reg_tt_rdata <= '0;
                reg_tt_err <= 1'b1;
              end
            endcase
            if (w_gnt_client == ENUM_CLIENT_TT)
              reg_rr_ptr <= LPARA_CLIENT_RX[1:0];
            else
              reg_rr_ptr <= w_gnt_client + 2'd1;
          end else if (w_gnt_valid) begin
            reg_active_client <= w_gnt_client;
            reg_active_we <= w_gnt_we;
            reg_active_addr <= w_gnt_addr;
            reg_active_wdata <= w_gnt_wdata;
            reg_wdt_count <= '0;
            reg_mram_state <= ENUM_STATE_WAIT_ACK;
          end
        end
        ENUM_STATE_WAIT_ACK: begin
          casez ({i_mram_ack, w_wdt_timeout, w_wdt_active})
            3'b1??: begin
            // The RAM data and ECC flags are captured on the acknowledge edge.
            if ((PARA_CANFD_SAF_RAM_EN == 32'd1) && i_mram_err_cor)
              reg_ecc_cor_event <= 1'b1;
            if ((PARA_CANFD_SAF_RAM_EN == 32'd1) && i_mram_err_unc)
              reg_ecc_unc_event <= 1'b1;
            casez (reg_active_client)
              ENUM_CLIENT_RX: begin
                reg_rx_ack <= 1'b1;
                reg_rx_rdata <= i_mram_rdata;
                reg_rx_err_cor <= (PARA_CANFD_SAF_RAM_EN == 32'd1) && i_mram_err_cor;
                reg_rx_err_unc <= (PARA_CANFD_SAF_RAM_EN == 32'd1) && i_mram_err_unc;
                reg_rx_err <= (PARA_CANFD_SAF_RAM_EN == 32'd1) && i_mram_err_unc;
              end
              ENUM_CLIENT_TX: begin
                reg_tx_ack <= 1'b1;
                reg_tx_rdata <= i_mram_rdata;
                reg_tx_err_cor <= (PARA_CANFD_SAF_RAM_EN == 32'd1) && i_mram_err_cor;
                reg_tx_err_unc <= (PARA_CANFD_SAF_RAM_EN == 32'd1) && i_mram_err_unc;
                reg_tx_err <= (PARA_CANFD_SAF_RAM_EN == 32'd1) && i_mram_err_unc;
              end
              ENUM_CLIENT_TT: begin
                reg_tt_ack <= 1'b1;
                reg_tt_rdata <= i_mram_rdata;
                reg_tt_err_cor <= (PARA_CANFD_SAF_RAM_EN == 32'd1) && i_mram_err_cor;
                reg_tt_err_unc <= (PARA_CANFD_SAF_RAM_EN == 32'd1) && i_mram_err_unc;
                reg_tt_err <= (PARA_CANFD_SAF_RAM_EN == 32'd1) && i_mram_err_unc;
              end
              default: begin
                reg_rx_ack <= 1'b0;
                reg_tx_ack <= 1'b0;
                reg_tt_ack <= 1'b0;
              end
            endcase
            if (reg_active_client == ENUM_CLIENT_TT)
              reg_rr_ptr <= LPARA_CLIENT_RX[1:0];
            else
              reg_rr_ptr <= reg_active_client + 2'd1;
            reg_wdt_count <= '0;
              reg_mram_state <= ENUM_STATE_BUBBLE;
            end
            3'b01?: begin
            // A timed-out external request completes to its owner as an error.
            reg_ram_flt_event <= 1'b1;
            reg_ram_wdt_event <= 1'b1;
            reg_fault_addr <= reg_active_addr;
            casez (reg_active_client)
              ENUM_CLIENT_RX: begin
                reg_rx_ack <= 1'b1;
                reg_rx_rdata <= '0;
                reg_rx_err <= 1'b1;
              end
              ENUM_CLIENT_TX: begin
                reg_tx_ack <= 1'b1;
                reg_tx_rdata <= '0;
                reg_tx_err <= 1'b1;
                if (!reg_active_we)
                  reg_tx_fetch_timeout <= 1'b1;
              end
              default: begin
                reg_tt_ack <= 1'b1;
                reg_tt_rdata <= '0;
                reg_tt_err <= 1'b1;
              end
            endcase
            if (reg_active_client == ENUM_CLIENT_TT)
              reg_rr_ptr <= LPARA_CLIENT_RX[1:0];
            else
              reg_rr_ptr <= reg_active_client + 2'd1;
            reg_wdt_count <= '0;
              reg_mram_state <= ENUM_STATE_BUBBLE;
            end
            3'b001: begin
              reg_wdt_count <= reg_wdt_count + 16'd1;
            end
            default: begin
              reg_wdt_count <= reg_wdt_count;
            end
          endcase
        end
        ENUM_STATE_BUBBLE: begin
          // Keep the external port idle for a complete BUS cycle after completion.
          reg_mram_state <= ENUM_STATE_IDLE;
          reg_wdt_count <= '0;
        end
        default: begin
          reg_mram_state <= ENUM_STATE_IDLE;
          reg_wdt_count <= '0;
          reg_rr_ptr <= LPARA_CLIENT_RX[1:0];
        end
      endcase
    end
  end

endmodule
