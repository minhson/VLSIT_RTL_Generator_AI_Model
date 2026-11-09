/*
 * Project      : CAN FD Controller
 * Author       : Nguyen Hung Quan (user)
 * AI Flow      : VLSIT RTL Generator AI Automation Flow
 * AI Flow Page : https://github.com/nguyenquanicd/VLSIT_RTL_Generator_AI_Model
 * Date         : 2026-11-09
 * Description  : Generates four held DMA service requests for Rx FIFO 0, Rx FIFO 1, Tx
 *                FIFO space and the Tx-event FIFO, with optional burst flush timers.
 * DEC IDs      : DEC-041, DEC-042, DEC-043, DEC-044, DEC-089
 */
`timescale 1ns/1ps

module m_canfd_dma #(
  // Parameter Description: select pulse or four-phase level acknowledge.
  // Parameter values: 0 = one-cycle pulse, 1 = four-phase level; default is 0.
  // Parameter unit: none
  parameter logic [31:0] PARA_CANFD_DMA_HS = 32'd0,
  localparam logic [31:0] LPARA_DMA_CH_NUM = 32'd4,
  localparam logic [31:0] LPARA_DMA_TOUT_DIV = 32'd64
) (
  // Clock and reset
  input  wire                         i_clk_bus,
  input  wire                         i_rst_n_bus,
  input  wire                         i_soft_reset,

  // Channel service conditions: Rx0, Rx1, Tx free space, Tx-event FIFO
  input  wire  [LPARA_DMA_CH_NUM-1:0] i_enable,
  input  wire  [LPARA_DMA_CH_NUM-1:0] i_level,
  input  wire  [LPARA_DMA_CH_NUM-1:0] i_burst,
  input  wire  [6:0]                  i_rx0_fill,
  input  wire  [6:0]                  i_rx1_fill,
  input  wire  [5:0]                  i_txe_fill,
  input  wire  [6:0]                  i_rx0_watermark,
  input  wire  [6:0]                  i_rx1_watermark,
  input  wire  [5:0]                  i_txe_watermark,
  input  wire  [15:0]                 i_flush_timeout,

  // Request acknowledge and post-service re-arm conditions
  input  wire  [LPARA_DMA_CH_NUM-1:0] i_ack,
  input  wire  [LPARA_DMA_CH_NUM-1:0] i_service_done,

  // DMA requests and flush status
  output logic [LPARA_DMA_CH_NUM-1:0] o_req,
  output logic [LPARA_DMA_CH_NUM-1:0] o_flush,
  output logic [LPARA_DMA_CH_NUM-1:0] o_req_status
);

  logic [LPARA_DMA_CH_NUM-1:0] w_threshold_met;
  logic [LPARA_DMA_CH_NUM-1:0] w_flush_active;
  logic [LPARA_DMA_CH_NUM-1:0] w_req_condition;

  // Evaluate the watermark for the three FIFO channels; the Tx channel requests free space.
  assign w_threshold_met[0] = (i_rx0_watermark != 7'd0) &&
                               (i_rx0_fill >= i_rx0_watermark);
  assign w_threshold_met[1] = (i_rx1_watermark != 7'd0) &&
                               (i_rx1_fill >= i_rx1_watermark);
  assign w_threshold_met[2] = i_level[2];
  assign w_threshold_met[3] = (i_txe_watermark != 6'd0) &&
                               (i_txe_fill >= i_txe_watermark);

  assign w_flush_active = {o_flush[3], 1'b0, o_flush[1], o_flush[0]};
  assign w_req_condition[0] = i_enable[0] && i_level[0] &&
                              (!i_burst[0] || w_threshold_met[0] || w_flush_active[0]);
  assign w_req_condition[1] = i_enable[1] && i_level[1] &&
                              (!i_burst[1] || w_threshold_met[1] || w_flush_active[1]);
  assign w_req_condition[2] = i_enable[2] && i_level[2];
  assign w_req_condition[3] = i_enable[3] && i_level[3] &&
                              (!i_burst[3] || w_threshold_met[3] || w_flush_active[3]);
  assign o_req_status = o_req;

  // Each channel has independent request, acknowledge and burst-flush state.
  generate
    for (genvar g_dma = 0; g_dma < LPARA_DMA_CH_NUM; g_dma = g_dma + 1) begin : gen_dma_ch
      logic reg_dma_req;
      logic reg_wait_ack_low;
      logic reg_wait_service;
      logic reg_flush;
      logic [5:0] reg_div_count;
      logic [15:0] reg_flush_count;
      logic [15:0] w_timeout_limit;
      logic w_fill_present;
      logic w_flush_mode;

      assign o_req[g_dma] = reg_dma_req;
      assign o_flush[g_dma] = reg_flush;
      assign w_timeout_limit = i_flush_timeout;

      case (g_dma)
        0: begin : gen_rx0_timer
          assign w_fill_present = (i_rx0_fill != 7'd0);
          assign w_flush_mode = i_burst[0] && (i_rx0_watermark != 7'd0) &&
                                (i_rx0_fill < i_rx0_watermark);
        end
        1: begin : gen_rx1_timer
          assign w_fill_present = (i_rx1_fill != 7'd0);
          assign w_flush_mode = i_burst[1] && (i_rx1_watermark != 7'd0) &&
                                (i_rx1_fill < i_rx1_watermark);
        end
        3: begin : gen_txe_timer
          assign w_fill_present = (i_txe_fill != 6'd0);
          assign w_flush_mode = i_burst[3] && (i_txe_watermark != 6'd0) &&
                                (i_txe_fill < i_txe_watermark);
        end
        default: begin : gen_tx_no_timer
          assign w_fill_present = 1'b0;
          assign w_flush_mode = 1'b0;
        end
      endcase

      // Count one timeout unit per 64 BUS clocks while a partial burst waits for its watermark.
      always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_flush_timer
        if (!i_rst_n_bus) begin
          reg_div_count <= '0;
          reg_flush_count <= '0;
          reg_flush <= 1'b0;
        end else if (i_soft_reset || i_service_done[g_dma] || !w_fill_present ||
                     !w_flush_mode || (w_timeout_limit == 16'd0) ||
                     w_threshold_met[g_dma]) begin
          reg_div_count <= '0;
          reg_flush_count <= '0;
          reg_flush <= 1'b0;
        end else if (!reg_flush) begin
          if (reg_div_count == 6'(LPARA_DMA_TOUT_DIV - 32'd1)) begin
            reg_div_count <= '0;
            if (reg_flush_count == (w_timeout_limit - 16'd1)) begin
              reg_flush_count <= w_timeout_limit;
              reg_flush <= 1'b1;
            end else begin
              reg_flush_count <= reg_flush_count + 16'd1;
            end
          end else begin
            reg_div_count <= reg_div_count + 6'd1;
          end
        end
      end

      // Hold each request through the configured acknowledge phases and service re-arm window.
      always_ff @(posedge i_clk_bus, negedge i_rst_n_bus) begin : p_ff_dma_req
        if (!i_rst_n_bus) begin
          reg_dma_req <= 1'b0;
          reg_wait_ack_low <= 1'b0;
          reg_wait_service <= 1'b0;
        end else if (i_soft_reset) begin
          reg_dma_req <= 1'b0;
          reg_wait_ack_low <= 1'b0;
          reg_wait_service <= 1'b0;
        end else begin
          casez (1'b1)
            (reg_dma_req && i_ack[g_dma]): begin
              reg_dma_req <= 1'b0;
              reg_wait_service <= 1'b1;
              if (PARA_CANFD_DMA_HS == 32'd1)
                reg_wait_ack_low <= 1'b1;
            end
            (reg_wait_ack_low && !i_ack[g_dma]): begin
              reg_wait_ack_low <= 1'b0;
            end
            (reg_wait_service && i_service_done[g_dma] && !reg_wait_ack_low): begin
              reg_wait_service <= 1'b0;
            end
            (!reg_dma_req && !reg_wait_service && !reg_wait_ack_low &&
             w_req_condition[g_dma]): begin
              reg_dma_req <= 1'b1;
            end
            default: begin
              reg_dma_req <= reg_dma_req;
            end
          endcase
        end
      end
    end
  endgenerate

endmodule
