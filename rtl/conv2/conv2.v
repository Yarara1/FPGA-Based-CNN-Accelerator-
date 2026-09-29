`timescale 1ns / 1ps

module conv2 #(
    parameter NUM_OC_PAR = 4
)(
    input wire clk,
    input wire resetn,
    input wire start,
    output reg done,
    output reg [9:0]        fm1_addr0,
    output reg [9:0]        fm1_addr1,
    output reg [9:0]        fm1_addr2,
    output reg [9:0]        fm1_addr3,
    input wire signed [7:0] fm1_dout0,
    input wire signed [7:0] fm1_dout1,
    input wire signed [7:0] fm1_dout2,
    input wire signed [7:0] fm1_dout3,
    output reg  [10:0]       w_addr,
    input  wire signed [7:0] w_dout,
    output reg  [13:0]       fm2_addr,
    output reg  signed [7:0] fm2_din,
    output reg               fm2_we,
    output wire pass_out,
    output wire w_all_ren
);
    localparam FM1_W       = 26;
    localparam OUT_W       = 24;
    localparam OUT_H       = 24;
    localparam OUT_CH      = 16;
    localparam IN_CH       = 8;
    localparam FM2_CH_SIZE = OUT_W * OUT_H;
    localparam NUM_PASSES  = IN_CH / 4;
    localparam S_IDLE            = 4'd0;
    localparam S_PRELOAD_W_ADDR  = 4'd1;
    localparam S_PRELOAD_W_WAIT  = 4'd2;
    localparam S_PRELOAD_W_SAVE  = 4'd3;
    localparam S_LOAD_PIX        = 4'd4;
    localparam S_COMPUTE         = 4'd5;
    localparam S_COMPUTE_WAIT    = 4'd6;
    localparam S_WRITE           = 4'd7;
    localparam S_NEXT            = 4'd8;
    localparam S_DONE            = 4'd9;
    localparam S_PRELOAD_W_SAVE2 = 4'd10;
    reg [3:0] state;
    reg [3:0] oc_base;
    reg [4:0] x;
    reg [4:0] y;
    reg [1:0] pass;
    reg [3:0] k;
    reg [1:0] write_idx;
    reg       compute_valid;
    wire mmu_valid    [0:NUM_OC_PAR-1];
    wire q_relu_valid [0:NUM_OC_PAR-1];
    reg [1:0] pre_oc_idx;
    reg [6:0] pre_w_idx;
    reg signed [7:0] pix [0:35];
    reg signed [7:0] wt  [0:NUM_OC_PAR-1][0:71];
    reg signed [7:0] w_dout_reg;
    reg signed [31:0] partial_sum [0:NUM_OC_PAR-1];
    reg signed [7:0]  conv_out    [0:NUM_OC_PAR-1];
    assign pass_out = pass;
    integer i;
    function [10:0] conv2_weight_addr;
        input [3:0] oc;
        input [6:0] idx;
        begin
            conv2_weight_addr = oc * 11'd72 + idx;
        end
    endfunction

    reg [1:0] ky;
    reg [1:0] kx;

    always @(*) begin
        case (k)
            4'd0: begin ky = 2'd0; kx = 2'd0; end
            4'd1: begin ky = 2'd0; kx = 2'd1; end
            4'd2: begin ky = 2'd0; kx = 2'd2; end
            4'd3: begin ky = 2'd1; kx = 2'd0; end
            4'd4: begin ky = 2'd1; kx = 2'd1; end
            4'd5: begin ky = 2'd1; kx = 2'd2; end
            4'd6: begin ky = 2'd2; kx = 2'd0; end
            4'd7: begin ky = 2'd2; kx = 2'd1; end
            4'd8: begin ky = 2'd2; kx = 2'd2; end
            default: begin ky = 2'd0; kx = 2'd0; end
        endcase
    end

    wire [9:0] fm1_addr_calc;
    assign fm1_addr_calc = (y + ky) * FM1_W + (x + kx);

    wire [13:0] fm2_addr_calc [0:NUM_OC_PAR-1];

    genvar fi;
    generate
        for (fi = 0; fi < NUM_OC_PAR; fi = fi + 1) begin : FM2_ADDR_GEN
            assign fm2_addr_calc[fi] =
                (oc_base + fi) * FM2_CH_SIZE + y * OUT_W + x;
        end
    endgenerate

    wire signed [8*36-1:0] data_vec;
    assign data_vec = {
        pix[35], pix[34], pix[33], pix[32], pix[31], pix[30],
        pix[29], pix[28], pix[27], pix[26], pix[25], pix[24],
        pix[23], pix[22], pix[21], pix[20], pix[19], pix[18],
        pix[17], pix[16], pix[15], pix[14], pix[13], pix[12],
        pix[11], pix[10], pix[9],  pix[8],  pix[7],  pix[6],
        pix[5],  pix[4],  pix[3],  pix[2],  pix[1],  pix[0]
    };
    wire signed [8*36-1:0] weight_vec [0:NUM_OC_PAR-1];
    wire signed [31:0]     mmu_acc    [0:NUM_OC_PAR-1];
    genvar oi;
    generate
        for (oi = 0; oi < NUM_OC_PAR; oi = oi + 1) begin : OC_MMU
            assign weight_vec[oi] = (pass == 2'd0) ? {
                wt[oi][35], wt[oi][34], wt[oi][33], wt[oi][32],
                wt[oi][31], wt[oi][30], wt[oi][29], wt[oi][28],
                wt[oi][27], wt[oi][26], wt[oi][25], wt[oi][24],
                wt[oi][23], wt[oi][22], wt[oi][21], wt[oi][20],
                wt[oi][19], wt[oi][18], wt[oi][17], wt[oi][16],
                wt[oi][15], wt[oi][14], wt[oi][13], wt[oi][12],
                wt[oi][11], wt[oi][10], wt[oi][9],  wt[oi][8],
                wt[oi][7],  wt[oi][6],  wt[oi][5],  wt[oi][4],
                wt[oi][3],  wt[oi][2],  wt[oi][1],  wt[oi][0]
            } : {
                wt[oi][71], wt[oi][70], wt[oi][69], wt[oi][68],
                wt[oi][67], wt[oi][66], wt[oi][65], wt[oi][64],
                wt[oi][63], wt[oi][62], wt[oi][61], wt[oi][60],
                wt[oi][59], wt[oi][58], wt[oi][57], wt[oi][56],
                wt[oi][55], wt[oi][54], wt[oi][53], wt[oi][52],
                wt[oi][51], wt[oi][50], wt[oi][49], wt[oi][48],
                wt[oi][47], wt[oi][46], wt[oi][45], wt[oi][44],
                wt[oi][43], wt[oi][42], wt[oi][41], wt[oi][40],
                wt[oi][39], wt[oi][38], wt[oi][37], wt[oi][36]
            };

            MMU_pipe36 #(
                .DATA_W(8),
                .ACC_W (32)
            ) u_mmu (
                .clk            (clk),
                .resetn         (resetn),
                .valid_in       (compute_valid),
                .data_vec       (data_vec),
                .weight_vec     (weight_vec[oi]),
                .partial_sum_in (partial_sum[oi]),
                .valid_out      (mmu_valid[oi]),
                .partial_sum_out(mmu_acc[oi])
            );
        end
    endgenerate

        wire signed [7:0] q_relu_out [0:NUM_OC_PAR-1];
    
        genvar ri;
        generate
            for (ri = 0; ri < NUM_OC_PAR; ri = ri + 1) begin : RELU_GEN
                quant_relu #(
                    .IN_W (32),
                    .OUT_W(8),
                    .SHIFT(10)
                ) u_qr (
                    .clk      (clk),
                    .resetn   (resetn),
                    .valid_in (mmu_valid[ri]),
                    .in_data  (mmu_acc[ri]),
                    .valid_out(q_relu_valid[ri]),
                    .out_data (q_relu_out[ri])
                );
            end
    endgenerate

    assign w_all_ren =
        (state == S_PRELOAD_W_ADDR) ||
        (state == S_PRELOAD_W_WAIT) ||
        (state == S_PRELOAD_W_SAVE) ||
        (state == S_PRELOAD_W_SAVE2);

    always @(posedge clk) begin
        if (!resetn) begin
            state         <= S_IDLE;
            done          <= 1'b0;
            fm1_addr0     <= 10'd0;
            fm1_addr1     <= 10'd0;
            fm1_addr2     <= 10'd0;
            fm1_addr3     <= 10'd0;
            w_addr        <= 11'd0;
            fm2_addr      <= 14'd0;
            fm2_din       <= 8'sd0;
            fm2_we        <= 1'b0;
            oc_base       <= 4'd0;
            x             <= 5'd0;
            y             <= 5'd0;
            pass          <= 2'd0;
            k             <= 4'd0;
            write_idx     <= 2'd0;
            compute_valid <= 1'b0;
            pre_oc_idx    <= 2'd0;
            pre_w_idx     <= 7'd0;
            w_dout_reg    <= 8'sd0;

            for (i = 0; i < 36; i = i + 1)
                pix[i] <= 8'sd0;
            for (i = 0; i < NUM_OC_PAR; i = i + 1) begin
                partial_sum[i] <= 32'sd0;
                conv_out[i]    <= 8'sd0;
            end

        end else begin
            compute_valid <= 1'b0;
            case (state)
                S_IDLE: begin
                    done       <= 1'b0;
                    fm2_we     <= 1'b0;
                    oc_base    <= 4'd0;
                    x          <= 5'd0;
                    y          <= 5'd0;
                    pass       <= 2'd0;
                    k          <= 4'd0;
                    write_idx  <= 2'd0;
                    pre_oc_idx <= 2'd0;
                    pre_w_idx  <= 7'd0;
                    for (i = 0; i < NUM_OC_PAR; i = i + 1)
                        partial_sum[i] <= 32'sd0;

                    if (start)
                        state <= S_PRELOAD_W_ADDR;
                end
                S_PRELOAD_W_ADDR: begin
                    fm2_we <= 1'b0;
                    w_addr <= conv2_weight_addr(oc_base + pre_oc_idx, pre_w_idx);
                    state  <= S_PRELOAD_W_WAIT;
                end
                S_PRELOAD_W_WAIT: begin
                    state <= S_PRELOAD_W_SAVE;
                end
                S_PRELOAD_W_SAVE: begin
                    w_dout_reg <= w_dout;
                    state      <= S_PRELOAD_W_SAVE2;
                end
                S_PRELOAD_W_SAVE2: begin
                    wt[pre_oc_idx][pre_w_idx] <= w_dout_reg;
                    if (pre_w_idx < 7'd71) begin
                        pre_w_idx <= pre_w_idx + 7'd1;
                        state     <= S_PRELOAD_W_ADDR;
                    end else if (pre_oc_idx < NUM_OC_PAR - 1) begin
                        pre_oc_idx <= pre_oc_idx + 2'd1;
                        pre_w_idx  <= 7'd0;
                        state      <= S_PRELOAD_W_ADDR;
                    end else begin
                        pre_oc_idx <= 2'd0;
                        pre_w_idx  <= 7'd0;
                        x          <= 5'd0;
                        y          <= 5'd0;
                        pass       <= 2'd0;
                        k          <= 4'd0;

                        for (i = 0; i < NUM_OC_PAR; i = i + 1)
                            partial_sum[i] <= 32'sd0;
                        state <= S_LOAD_PIX;
                    end
                end
                S_LOAD_PIX: begin
                    fm2_we <= 1'b0;

                    if (k <= 4'd8) begin
                        fm1_addr0 <= fm1_addr_calc;
                        fm1_addr1 <= fm1_addr_calc;
                        fm1_addr2 <= fm1_addr_calc;
                        fm1_addr3 <= fm1_addr_calc;
                    end
                    if (k >= 4'd2) begin
                        pix[k-2]    <= fm1_dout0;
                        pix[k-2+9]  <= fm1_dout1;
                        pix[k-2+18] <= fm1_dout2;
                        pix[k-2+27] <= fm1_dout3;
                    end
                    if (k < 4'd10) begin
                        k <= k + 4'd1;
                    end else begin
                        k     <= 4'd0;
                        state <= S_COMPUTE;
                    end
                end
                S_COMPUTE: begin
                    fm2_we        <= 1'b0;
                    compute_valid <= 1'b1;
                    state         <= S_COMPUTE_WAIT;
                end
                S_COMPUTE_WAIT: begin
                    fm2_we        <= 1'b0;
                    compute_valid <= 1'b0;

                    if (pass < NUM_PASSES - 1) begin
                        if (mmu_valid[0]) begin
                            for (i = 0; i < NUM_OC_PAR; i = i + 1)
                                partial_sum[i] <= mmu_acc[i];

                            pass  <= pass + 2'd1;
                            k     <= 4'd0;
                            state <= S_LOAD_PIX;
                        end
                    end else begin
                        if (q_relu_valid[0]) begin
                            for (i = 0; i < NUM_OC_PAR; i = i + 1) begin
                                conv_out[i]    <= q_relu_out[i];
                                partial_sum[i] <= 32'sd0;
                            end

                            pass      <= 2'd0;
                            k         <= 4'd0;
                            write_idx <= 2'd0;
                            state     <= S_WRITE;
                        end
                    end
                end
                S_WRITE: begin
                    fm2_addr <= fm2_addr_calc[write_idx];
                    fm2_din  <= conv_out[write_idx];
                    fm2_we   <= 1'b1;

                    if (write_idx < NUM_OC_PAR - 1) begin
                        write_idx <= write_idx + 2'd1;
                    end else begin
                        write_idx <= 2'd0;
                        state     <= S_NEXT;
                    end
                end
                S_NEXT: begin
                    fm2_we <= 1'b0;

                    if (x < OUT_W - 1) begin
                        x    <= x + 5'd1;
                        pass <= 2'd0;
                        k    <= 4'd0;

                    for (i = 0; i < NUM_OC_PAR; i = i + 1)
                        partial_sum[i] <= 32'sd0;
                        state <= S_LOAD_PIX;
                    end else if (y < OUT_H - 1) begin
                        x    <= 5'd0;
                        y    <= y + 5'd1;
                        pass <= 2'd0;
                        k    <= 4'd0;
                        for (i = 0; i < NUM_OC_PAR; i = i + 1)
                            partial_sum[i] <= 32'sd0;
                        state <= S_LOAD_PIX;
                    end else if (oc_base < OUT_CH - NUM_OC_PAR) begin
                        oc_base    <= oc_base + NUM_OC_PAR;
                        x          <= 5'd0;
                        y          <= 5'd0;
                        pass       <= 2'd0;
                        k          <= 4'd0;
                        pre_oc_idx <= 2'd0;
                        pre_w_idx  <= 7'd0;
                        for (i = 0; i < NUM_OC_PAR; i = i + 1)
                            partial_sum[i] <= 32'sd0;
                        state <= S_PRELOAD_W_ADDR;
                    end else begin
                        state <= S_DONE;
                    end
                    end
                    S_DONE: begin
                        done   <= 1'b1;
                        fm2_we <= 1'b0;
                        state  <= S_IDLE;
                    end
                    default: begin
                        state <= S_IDLE;
                    end

            endcase
        end
    end

endmodule
