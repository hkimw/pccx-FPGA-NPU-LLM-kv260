// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 pccxai
// =====================================================================
// npu_core_outer.v — Verilog-2001 passthrough wrapper.
//
// Reason for existence: Vivado IP Integrator's `create_bd_cell -type
// module -reference` rejects SystemVerilog as the top file type
// (filemgmt 56-195). The real wrapper, npu_core_wrapper.sv, uses SV
// `axil_if` / `axis_if` interface *instances* internally and is therefore
// .sv. BD will accept this thin .v outer module as the reference and
// elaborate the SV body during synthesis.
//
// This file is a pure pass-through. No additional logic, no register, no
// width conversion. Updates to this file should always mirror the port
// list of npu_core_wrapper.sv exactly.
// =====================================================================

`timescale 1ns / 1ps

module npu_core_outer #(
    parameter integer AXIL_ADDR_W = 12,
    parameter integer AXIL_DATA_W = 64,
    parameter integer HP_DATA_W   = 128,
    parameter integer ACP_DATA_W  = 128
) (
    input  wire clk_core,
    input  wire rst_n_core,
    input  wire clk_axi,
    input  wire rst_axi_n,
    input  wire i_clear,

    // S_AXIL_CTRL
    input  wire [AXIL_ADDR_W-1:0]   s_axil_awaddr,
    input  wire                     s_axil_awvalid,
    output wire                     s_axil_awready,
    input  wire [AXIL_DATA_W-1:0]   s_axil_wdata,
    input  wire [AXIL_DATA_W/8-1:0] s_axil_wstrb,
    input  wire                     s_axil_wvalid,
    output wire                     s_axil_wready,
    output wire [1:0]               s_axil_bresp,
    output wire                     s_axil_bvalid,
    input  wire                     s_axil_bready,
    input  wire [AXIL_ADDR_W-1:0]   s_axil_araddr,
    input  wire                     s_axil_arvalid,
    output wire                     s_axil_arready,
    output wire [AXIL_DATA_W-1:0]   s_axil_rdata,
    output wire [1:0]               s_axil_rresp,
    output wire                     s_axil_rvalid,
    input  wire                     s_axil_rready,

    // 4 x AXIS HP weight slaves
    input  wire [HP_DATA_W-1:0] s_axis_hp0_tdata,
    input  wire                 s_axis_hp0_tvalid,
    output wire                 s_axis_hp0_tready,
    input  wire [HP_DATA_W-1:0] s_axis_hp1_tdata,
    input  wire                 s_axis_hp1_tvalid,
    output wire                 s_axis_hp1_tready,
    input  wire [HP_DATA_W-1:0] s_axis_hp2_tdata,
    input  wire                 s_axis_hp2_tvalid,
    output wire                 s_axis_hp2_tready,
    input  wire [HP_DATA_W-1:0] s_axis_hp3_tdata,
    input  wire                 s_axis_hp3_tvalid,
    output wire                 s_axis_hp3_tready,

    // ACP fmap (slave) + result (master)
    input  wire [ACP_DATA_W-1:0]  s_axis_acp_fmap_tdata,
    input  wire                   s_axis_acp_fmap_tvalid,
    output wire                   s_axis_acp_fmap_tready,
    output wire [ACP_DATA_W-1:0]  m_axis_acp_result_tdata,
    output wire                   m_axis_acp_result_tvalid,
    input  wire                   m_axis_acp_result_tready
);

    npu_core_wrapper #(
        .AXIL_ADDR_W (AXIL_ADDR_W),
        .AXIL_DATA_W (AXIL_DATA_W),
        .HP_DATA_W   (HP_DATA_W),
        .ACP_DATA_W  (ACP_DATA_W)
    ) u_wrap (
        .clk_core               (clk_core),
        .rst_n_core             (rst_n_core),
        .clk_axi                (clk_axi),
        .rst_axi_n              (rst_axi_n),
        .i_clear                (i_clear),
        .s_axil_awaddr          (s_axil_awaddr),
        .s_axil_awvalid         (s_axil_awvalid),
        .s_axil_awready         (s_axil_awready),
        .s_axil_wdata           (s_axil_wdata),
        .s_axil_wstrb           (s_axil_wstrb),
        .s_axil_wvalid          (s_axil_wvalid),
        .s_axil_wready          (s_axil_wready),
        .s_axil_bresp           (s_axil_bresp),
        .s_axil_bvalid          (s_axil_bvalid),
        .s_axil_bready          (s_axil_bready),
        .s_axil_araddr          (s_axil_araddr),
        .s_axil_arvalid         (s_axil_arvalid),
        .s_axil_arready         (s_axil_arready),
        .s_axil_rdata           (s_axil_rdata),
        .s_axil_rresp           (s_axil_rresp),
        .s_axil_rvalid          (s_axil_rvalid),
        .s_axil_rready          (s_axil_rready),
        .s_axis_hp0_tdata       (s_axis_hp0_tdata),
        .s_axis_hp0_tvalid      (s_axis_hp0_tvalid),
        .s_axis_hp0_tready      (s_axis_hp0_tready),
        .s_axis_hp1_tdata       (s_axis_hp1_tdata),
        .s_axis_hp1_tvalid      (s_axis_hp1_tvalid),
        .s_axis_hp1_tready      (s_axis_hp1_tready),
        .s_axis_hp2_tdata       (s_axis_hp2_tdata),
        .s_axis_hp2_tvalid      (s_axis_hp2_tvalid),
        .s_axis_hp2_tready      (s_axis_hp2_tready),
        .s_axis_hp3_tdata       (s_axis_hp3_tdata),
        .s_axis_hp3_tvalid      (s_axis_hp3_tvalid),
        .s_axis_hp3_tready      (s_axis_hp3_tready),
        .s_axis_acp_fmap_tdata  (s_axis_acp_fmap_tdata),
        .s_axis_acp_fmap_tvalid (s_axis_acp_fmap_tvalid),
        .s_axis_acp_fmap_tready (s_axis_acp_fmap_tready),
        .m_axis_acp_result_tdata  (m_axis_acp_result_tdata),
        .m_axis_acp_result_tvalid (m_axis_acp_result_tvalid),
        .m_axis_acp_result_tready (m_axis_acp_result_tready)
    );

endmodule
