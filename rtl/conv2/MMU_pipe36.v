`timescale 1ns / 1ps
module MMU_pipe36 #(
    parameter DATA_W = 8,
    parameter ACC_W  = 32
)(
    input  wire clk,
    input  wire resetn,
    input  wire valid_in,
    input  wire signed [DATA_W*36-1:0] data_vec,
    input  wire signed [DATA_W*36-1:0] weight_vec,
    input  wire signed [ACC_W-1:0]     partial_sum_in,
    output reg  valid_out,
    output reg  signed [ACC_W-1:0]     partial_sum_out
);
    integer i;
    wire signed [DATA_W-1:0] data   [0:35];
    wire signed [DATA_W-1:0] weight [0:35];
    genvar gi;
    generate
        for (gi = 0; gi < 36; gi = gi + 1) begin : UNPACK
            assign data[gi]   = data_vec[gi*DATA_W +: DATA_W];
            assign weight[gi] = weight_vec[gi*DATA_W +: DATA_W];
        end
    endgenerate

    // Stage 1: 36 DSP multiplications
    // prod_reg[i] = data[i] * weight[i]
    (* use_dsp = "yes" *) reg signed [15:0] prod_reg [0:35];

    // Stage 1.5 (NEW): register DSP outputs before adder tree
    reg signed [15:0] prod_pipe [0:35];
    reg signed [ACC_W-1:0] sum18_reg [0:17];
    reg signed [ACC_W-1:0] sum9_reg  [0:8];
    reg signed [ACC_W-1:0] sum5_reg  [0:4];
    reg signed [ACC_W-1:0] sum3_reg  [0:2];
    // ps delay chain extended by 1 for new Stage 1.5
    reg signed [ACC_W-1:0] ps_d1, ps_d1b, ps_d2, ps_d3, ps_d4, ps_d5;
    // Stage 6.5 registers
    reg signed [ACC_W-1:0] sum_AB;
    reg signed [ACC_W-1:0] ps_plus_C;

    // Valid pipeline
    reg [6:0] valid_pipe;  // 7 bits for 8-stage pipeline
    always @(posedge clk) begin
        if (!resetn) begin
            valid_pipe      <= 7'd0;
            valid_out       <= 1'b0;
            partial_sum_out <= {ACC_W{1'b0}};
            ps_d1  <= 0;
            ps_d1b <= 0;
            ps_d2  <= 0;
            ps_d3  <= 0;
            ps_d4  <= 0;
            ps_d5  <= 0;
            sum_AB    <= 0;
            ps_plus_C <= 0;
            for (i = 0; i < 36; i = i + 1) begin
                prod_reg[i]  <= 16'sd0;
                prod_pipe[i] <= 16'sd0;
            end
            for (i = 0; i < 18; i = i + 1)
                sum18_reg[i] <= {ACC_W{1'b0}};
            for (i = 0; i < 9; i = i + 1)
                sum9_reg[i]  <= {ACC_W{1'b0}};
            for (i = 0; i < 5; i = i + 1)
                sum5_reg[i]  <= {ACC_W{1'b0}};
            for (i = 0; i < 3; i = i + 1)
                sum3_reg[i]  <= {ACC_W{1'b0}};
        end else begin

            // Valid pipeline: 7-bit shift, read bit 6
            valid_pipe <= {valid_pipe[5:0], valid_in};
            valid_out  <= valid_pipe[6];
            // Stage 1: 36 parallel DSP multiplications
            // Critical path: data/weight → DSP → prod_reg (~2ns in DSP)
            for (i = 0; i < 36; i = i + 1)
                prod_reg[i] <= data[i] * weight[i];
            ps_d1 <= partial_sum_in;
            // Stage 1.5 (NEW): pipeline register after DSP outputs
            for (i = 0; i < 36; i = i + 1)
                prod_pipe[i] <= prod_reg[i];
            ps_d1b <= ps_d1;
            // Stage 2: 36 → 18  (uses prod_pipe NOT prod_reg)
            for (i = 0; i < 18; i = i + 1)
                sum18_reg[i] <= $signed(prod_pipe[2*i])
                              + $signed(prod_pipe[2*i+1]);
            ps_d2 <= ps_d1b;
            // Stage 3: 18 → 9
            for (i = 0; i < 9; i = i + 1)
                sum9_reg[i] <= sum18_reg[2*i] + sum18_reg[2*i+1];
            ps_d3 <= ps_d2;
            // Stage 4: 9 → 5
            sum5_reg[0] <= sum9_reg[0] + sum9_reg[1];
            sum5_reg[1] <= sum9_reg[2] + sum9_reg[3];
            sum5_reg[2] <= sum9_reg[4] + sum9_reg[5];
            sum5_reg[3] <= sum9_reg[6] + sum9_reg[7];
            sum5_reg[4] <= sum9_reg[8];
            ps_d4 <= ps_d3;
            // Stage 5: 5 → 3
            sum3_reg[0] <= sum5_reg[0] + sum5_reg[1];
            sum3_reg[1] <= sum5_reg[2] + sum5_reg[3];
            sum3_reg[2] <= sum5_reg[4];
            ps_d5 <= ps_d4;
            // Stage 6.5: two parallel additions
            sum_AB    <= sum3_reg[0] + sum3_reg[1];
            ps_plus_C <= ps_d5      + sum3_reg[2];
            // Stage 7: single final addition
            partial_sum_out <= sum_AB + ps_plus_C;

        end
    end
endmodule
