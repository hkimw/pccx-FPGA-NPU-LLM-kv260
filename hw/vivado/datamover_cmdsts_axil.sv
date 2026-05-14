// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 pccxai
//
// AXI-Lite command/status bridge for AXI DataMover command streams.
// This is a BD-side helper: PS writes one staged DataMover command into a
// small FIFO and reads one status byte from a matching status FIFO.

`timescale 1ns / 1ps

module datamover_cmdsts_axil #(
    parameter integer AXIL_ADDR_W = 12,
    parameter integer AXIL_DATA_W = 32,
    parameter integer CMD_WIDTH   = 72,
    parameter integer STS_WIDTH   = 8,
    parameter integer FIFO_DEPTH  = 8
) (
    input  wire                       s_axil_aclk,
    input  wire                       s_axil_aresetn,

    input  wire [AXIL_ADDR_W-1:0]     s_axil_awaddr,
    input  wire                       s_axil_awvalid,
    output wire                       s_axil_awready,
    input  wire [AXIL_DATA_W-1:0]     s_axil_wdata,
    input  wire [(AXIL_DATA_W/8)-1:0] s_axil_wstrb,
    input  wire                       s_axil_wvalid,
    output wire                       s_axil_wready,
    output wire [1:0]                 s_axil_bresp,
    output wire                       s_axil_bvalid,
    input  wire                       s_axil_bready,
    input  wire [AXIL_ADDR_W-1:0]     s_axil_araddr,
    input  wire                       s_axil_arvalid,
    output wire                       s_axil_arready,
    output wire [AXIL_DATA_W-1:0]     s_axil_rdata,
    output wire [1:0]                 s_axil_rresp,
    output wire                       s_axil_rvalid,
    input  wire                       s_axil_rready,

    output wire [CMD_WIDTH-1:0]       m_axis_cmd_tdata,
    output wire                       m_axis_cmd_tvalid,
    input  wire                       m_axis_cmd_tready,

    input  wire [STS_WIDTH-1:0]       s_axis_sts_tdata,
    input  wire                       s_axis_sts_tvalid,
    output wire                       s_axis_sts_tready,
    input  wire                       s_axis_sts_tlast,
    input  wire [(STS_WIDTH+7)/8-1:0] s_axis_sts_tkeep
);
    localparam integer ADDR_LSB = 2;
    localparam integer CMD_LO   = 10'h000;
    localparam integer CMD_HI   = 10'h001;
    localparam integer CMD_EXT  = 10'h002;
    localparam integer CMD_PUSH = 10'h003;
    localparam integer STS_POP  = 10'h004;
    localparam integer FLAGS    = 10'h005;
    localparam integer CMD_LVL  = 10'h006;
    localparam integer STS_LVL  = 10'h007;
    localparam integer ERR_W1C  = 10'h008;

    localparam integer PTR_W        = (FIFO_DEPTH <= 2) ? 1 : $clog2(FIFO_DEPTH);
    localparam integer CMD_EXT_BITS = CMD_WIDTH - 64;
    localparam logic [PTR_W:0] FIFO_DEPTH_VALUE = FIFO_DEPTH;

    logic [AXIL_ADDR_W-1:0]     awaddr_q;
    logic [AXIL_DATA_W-1:0]     wdata_q;
    logic [(AXIL_DATA_W/8)-1:0] wstrb_q;
    logic                       aw_hold_q;
    logic                       w_hold_q;
    logic                       bvalid_q;
    logic [AXIL_DATA_W-1:0]     rdata_q;
    logic                       rvalid_q;

    logic [CMD_WIDTH-1:0]       cmd_stage_q;
    logic [CMD_WIDTH-1:0]       cmd_fifo_q [0:FIFO_DEPTH-1];
    logic [STS_WIDTH-1:0]       sts_fifo_q [0:FIFO_DEPTH-1];
    logic [PTR_W-1:0]           cmd_wr_ptr_q;
    logic [PTR_W-1:0]           cmd_rd_ptr_q;
    logic [PTR_W-1:0]           sts_wr_ptr_q;
    logic [PTR_W-1:0]           sts_rd_ptr_q;
    logic [PTR_W:0]             cmd_count_q;
    logic [PTR_W:0]             sts_count_q;
    logic [3:0]                 err_sticky_q;

    wire cmd_empty = (cmd_count_q == '0);
    wire cmd_full  = (cmd_count_q == FIFO_DEPTH_VALUE);
    wire sts_empty = (sts_count_q == '0);
    wire sts_full  = (sts_count_q == FIFO_DEPTH_VALUE);

    wire write_fire = aw_hold_q && w_hold_q && !bvalid_q;
    wire [9:0] write_addr = awaddr_q[ADDR_LSB +: 10];
    wire [9:0] read_addr  = s_axil_araddr[ADDR_LSB +: 10];

    assign s_axil_awready = !aw_hold_q;
    assign s_axil_wready  = !w_hold_q;
    assign s_axil_bresp   = 2'b00;
    assign s_axil_bvalid  = bvalid_q;
    assign s_axil_arready = !rvalid_q;
    assign s_axil_rdata   = rdata_q;
    assign s_axil_rresp   = 2'b00;
    assign s_axil_rvalid  = rvalid_q;

    assign m_axis_cmd_tdata  = cmd_fifo_q[cmd_rd_ptr_q];
    assign m_axis_cmd_tvalid = !cmd_empty;
    assign s_axis_sts_tready = !sts_full;

    wire cmd_pop      = m_axis_cmd_tvalid && m_axis_cmd_tready;
    wire cmd_push_req = write_fire && (write_addr == CMD_PUSH);
    wire cmd_push_ok  = cmd_push_req && !cmd_full;
    wire sts_push     = s_axis_sts_tvalid && s_axis_sts_tready;
    wire sts_pop_req  = s_axil_arvalid && s_axil_arready && (read_addr == STS_POP);
    wire sts_pop_ok   = sts_pop_req && !sts_empty;

    function automatic [AXIL_DATA_W-1:0] apply_wstrb(
        input [AXIL_DATA_W-1:0] old_value,
        input [AXIL_DATA_W-1:0] new_value,
        input [(AXIL_DATA_W/8)-1:0] strb
    );
        integer i;
        begin
            apply_wstrb = old_value;
            for (i = 0; i < (AXIL_DATA_W/8); i = i + 1) begin
                if (strb[i]) begin
                    apply_wstrb[i*8 +: 8] = new_value[i*8 +: 8];
                end
            end
        end
    endfunction

    function automatic [AXIL_DATA_W-1:0] flags_word;
        begin
            flags_word = '0;
            flags_word[0] = cmd_empty;
            flags_word[1] = cmd_full;
            flags_word[2] = sts_empty;
            flags_word[3] = sts_full;
            flags_word[7:4] = err_sticky_q;
        end
    endfunction

    function automatic [CMD_EXT_BITS-1:0] apply_ext_wstrb(
        input [CMD_EXT_BITS-1:0] old_value,
        input [AXIL_DATA_W-1:0]  new_value,
        input [(AXIL_DATA_W/8)-1:0] strb
    );
        logic [AXIL_DATA_W-1:0] merged;
        begin
            merged = '0;
            merged[CMD_EXT_BITS-1:0] = old_value;
            merged = apply_wstrb(merged, new_value, strb);
            apply_ext_wstrb = merged[CMD_EXT_BITS-1:0];
        end
    endfunction

    always_ff @(posedge s_axil_aclk) begin
        if (!s_axil_aresetn) begin
            awaddr_q     <= '0;
            wdata_q      <= '0;
            wstrb_q      <= '0;
            aw_hold_q    <= 1'b0;
            w_hold_q     <= 1'b0;
            bvalid_q     <= 1'b0;
            rdata_q      <= '0;
            rvalid_q     <= 1'b0;
            cmd_stage_q  <= '0;
            cmd_wr_ptr_q <= '0;
            cmd_rd_ptr_q <= '0;
            sts_wr_ptr_q <= '0;
            sts_rd_ptr_q <= '0;
            cmd_count_q  <= '0;
            sts_count_q  <= '0;
            err_sticky_q <= '0;
        end else begin
            if (s_axil_awvalid && s_axil_awready) begin
                awaddr_q  <= s_axil_awaddr;
                aw_hold_q <= 1'b1;
            end
            if (s_axil_wvalid && s_axil_wready) begin
                wdata_q  <= s_axil_wdata;
                wstrb_q  <= s_axil_wstrb;
                w_hold_q <= 1'b1;
            end
            if (bvalid_q && s_axil_bready) begin
                bvalid_q <= 1'b0;
            end

            if (cmd_pop) begin
                cmd_rd_ptr_q <= cmd_rd_ptr_q + {{(PTR_W-1){1'b0}}, 1'b1};
            end

            if (sts_push) begin
                sts_fifo_q[sts_wr_ptr_q] <= s_axis_sts_tdata;
                sts_wr_ptr_q <= sts_wr_ptr_q + {{(PTR_W-1){1'b0}}, 1'b1};
            end else if (s_axis_sts_tvalid && sts_full) begin
                err_sticky_q[1] <= 1'b1;
            end

            unique case ({cmd_push_ok, cmd_pop})
                2'b10: cmd_count_q <= cmd_count_q + {{PTR_W{1'b0}}, 1'b1};
                2'b01: cmd_count_q <= cmd_count_q - {{PTR_W{1'b0}}, 1'b1};
                default: begin
                end
            endcase

            unique case ({sts_push, sts_pop_ok})
                2'b10: sts_count_q <= sts_count_q + {{PTR_W{1'b0}}, 1'b1};
                2'b01: sts_count_q <= sts_count_q - {{PTR_W{1'b0}}, 1'b1};
                default: begin
                end
            endcase

            if (write_fire) begin
                unique case (write_addr)
                    CMD_LO: begin
                        cmd_stage_q[31:0] <= apply_wstrb(
                            cmd_stage_q[31:0], wdata_q, wstrb_q
                        );
                    end
                    CMD_HI: begin
                        cmd_stage_q[63:32] <= apply_wstrb(
                            cmd_stage_q[63:32], wdata_q, wstrb_q
                        );
                    end
                    CMD_EXT: begin
                        cmd_stage_q[CMD_WIDTH-1:64] <= apply_ext_wstrb(
                            cmd_stage_q[CMD_WIDTH-1:64], wdata_q, wstrb_q
                        );
                    end
                    CMD_PUSH: begin
                        if (cmd_push_ok) begin
                            cmd_fifo_q[cmd_wr_ptr_q] <= cmd_stage_q;
                            cmd_wr_ptr_q <= cmd_wr_ptr_q + {{(PTR_W-1){1'b0}}, 1'b1};
                        end else begin
                            err_sticky_q[0] <= 1'b1;
                        end
                    end
                    ERR_W1C: begin
                        err_sticky_q <= err_sticky_q & ~wdata_q[3:0];
                    end
                    default: begin
                    end
                endcase
                aw_hold_q <= 1'b0;
                w_hold_q  <= 1'b0;
                bvalid_q  <= 1'b1;
            end

            if (s_axil_arvalid && s_axil_arready) begin
                unique case (read_addr)
                    CMD_LO: rdata_q <= cmd_stage_q[31:0];
                    CMD_HI: rdata_q <= cmd_stage_q[63:32];
                    CMD_EXT: begin
                        rdata_q <= '0;
                        rdata_q[CMD_WIDTH-65:0] <= cmd_stage_q[CMD_WIDTH-1:64];
                    end
                    STS_POP: begin
                        rdata_q <= '0;
                        if (sts_pop_ok) begin
                            rdata_q[STS_WIDTH-1:0] <= sts_fifo_q[sts_rd_ptr_q];
                            sts_rd_ptr_q <= sts_rd_ptr_q + {{(PTR_W-1){1'b0}}, 1'b1};
                        end else begin
                            err_sticky_q[2] <= 1'b1;
                        end
                    end
                    FLAGS:   rdata_q <= flags_word();
                    CMD_LVL: begin
                        rdata_q <= '0;
                        rdata_q[PTR_W:0] <= cmd_count_q;
                    end
                    STS_LVL: begin
                        rdata_q <= '0;
                        rdata_q[PTR_W:0] <= sts_count_q;
                    end
                    ERR_W1C: begin
                        rdata_q <= '0;
                        rdata_q[3:0] <= err_sticky_q;
                    end
                    default: rdata_q <= '0;
                endcase
                rvalid_q <= 1'b1;
            end else if (rvalid_q && s_axil_rready) begin
                rvalid_q <= 1'b0;
            end
        end
    end

    // DataMover status sidebands are accepted to preserve the full AXIS
    // interface shape. Current software consumes only the 8-bit status code.
    wire unused_status_sideband = s_axis_sts_tlast ^ ^s_axis_sts_tkeep;

endmodule
