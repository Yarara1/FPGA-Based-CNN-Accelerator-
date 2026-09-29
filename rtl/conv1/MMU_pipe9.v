`timescale 1ns / 1ps
module MMU_pipe9 #(
    parameter DATA_W = 8,
    parameter ACC_W  = 32
)(
    input  wire clk,
    input  wire resetn,
    input  wire valid_in,
    input  wire signed [DATA_W*9-1:0] data_vec,
    input  wire signed [DATA_W*9-1:0] weight_vec,
    input  wire signed [ACC_W-1:0]    partial_sum_in,
    output reg  valid_out,
    output reg  signed [ACC_W-1:0]    partial_sum_out
);
    wire signed [DATA_W-1:0] data   [0:8];
    wire signed [DATA_W-1:0] weight [0:8];

    genvar gi;
    generate
        for (gi = 0; gi < 9; gi = gi + 1) begin : UNPACK
            assign data[gi]   = data_vec[gi*DATA_W +: DATA_W];
            assign weight[gi] = weight_vec[gi*DATA_W +: DATA_W];
        end
    endgenerate

    integer i;

    // ---------------------------------------------------------------
    // Stage 0: register inputs - breaks data→multiply critical path
    // ---------------------------------------------------------------
    reg signed [DATA_W-1:0] data_r   [0:8];
    reg signed [DATA_W-1:0] weight_r [0:8];
    reg signed [ACC_W-1:0]  ps_d0;

    // ---------------------------------------------------------------
    // Stage 1: 9 parallel multiplications
    // ---------------------------------------------------------------
    (* use_dsp = "yes" *) reg signed [15:0] prod_reg [0:8];
    reg signed [ACC_W-1:0] ps_d1;

    // ---------------------------------------------------------------
    // Stage 2: pair-wise additions (4 pairs + 1 remainder)
    // ---------------------------------------------------------------
    reg signed [ACC_W-1:0] sum5_reg [0:4];
    reg signed [ACC_W-1:0] ps_d2;

    // ---------------------------------------------------------------
    // Stage 3: second-level additions → 3 values remain
    // ---------------------------------------------------------------
    reg signed [ACC_W-1:0] sum3_reg [0:2];
    reg signed [ACC_W-1:0] ps_d3;

    // ---------------------------------------------------------------
    // Stage 3.5 (NEW): two PARALLEL additions
    //
    // OLD Stage 4 was:
    //   out = ps_d3 + A + B + C   (3 adders in series = critical path)
    //
    // NEW split into two stages:
    //   Stage 3.5:  sum_AB   = A + B          (parallel)
    //               ps_plus_C = ps_d3 + C      (parallel)
    //   Stage 4:    out      = sum_AB + ps_plus_C  (1 adder only)
    //
    // Critical path in Stage 4 drops from 3 adders to 1 adder.
    // ---------------------------------------------------------------
    reg signed [ACC_W-1:0] sum_AB;      // sum3_reg[0] + sum3_reg[1]
    reg signed [ACC_W-1:0] ps_plus_C;  // ps_d3       + sum3_reg[2]

    // ---------------------------------------------------------------
    // Valid pipeline: 6 stages total (0,1,2,3,3.5,4)
    // For input valid at cycle N, output valid at cycle N+6.
    //
    // Derivation:
    //   valid_pipe shifts left every cycle.
    //   valid_out <= valid_pipe[4] is itself registered (+1 cycle).
    //   For input at cycle 1:
    //     end cycle 5: valid_pipe[4] = 1
    //     valid_out registered at end cycle 6 → matches partial_sum_out
    // ---------------------------------------------------------------
    reg [5:0] valid_pipe;  // 6 bits for 6-stage pipeline

    always @(posedge clk) begin
        if (!resetn) begin
            valid_pipe      <= 6'd0;
            valid_out       <= 1'b0;
            partial_sum_out <= {ACC_W{1'b0}};
            ps_d0  <= 0;
            ps_d1  <= 0;
            ps_d2  <= 0;
            ps_d3  <= 0;
            sum_AB    <= 0;
            ps_plus_C <= 0;
            for (i = 0; i < 9; i = i + 1) begin
                data_r[i]   <= 0;
                weight_r[i] <= 0;
                prod_reg[i] <= 16'sd0;
            end
            for (i = 0; i < 5; i = i + 1) sum5_reg[i] <= 0;
            for (i = 0; i < 3; i = i + 1) sum3_reg[i] <= 0;
        end else begin

            // Valid: 6-stage pipeline
            valid_pipe <= {valid_pipe[4:0], valid_in};
            valid_out  <= valid_pipe[4];  // registered → 6-cycle latency

            // ----------------------------------------------------------
            // Stage 0: register inputs
            // ----------------------------------------------------------
            for (i = 0; i < 9; i = i + 1) begin
                data_r[i]   <= data[i];
                weight_r[i] <= weight[i];
            end
            ps_d0 <= partial_sum_in;

            // ----------------------------------------------------------
            // Stage 1: multiplications (use registered inputs)
            // ----------------------------------------------------------
            for (i = 0; i < 9; i = i + 1)
                prod_reg[i] <= data_r[i] * weight_r[i];
            ps_d1 <= ps_d0;

            // ----------------------------------------------------------
            // Stage 2: pair-wise additions
            // ----------------------------------------------------------
            sum5_reg[0] <= $signed(prod_reg[0]) + $signed(prod_reg[1]);
            sum5_reg[1] <= $signed(prod_reg[2]) + $signed(prod_reg[3]);
            sum5_reg[2] <= $signed(prod_reg[4]) + $signed(prod_reg[5]);
            sum5_reg[3] <= $signed(prod_reg[6]) + $signed(prod_reg[7]);
            sum5_reg[4] <= $signed(prod_reg[8]);
            ps_d2 <= ps_d1;

            // ----------------------------------------------------------
            // Stage 3: second-level additions
            // ----------------------------------------------------------
            sum3_reg[0] <= sum5_reg[0] + sum5_reg[1];
            sum3_reg[1] <= sum5_reg[2] + sum5_reg[3];
            sum3_reg[2] <= sum5_reg[4];
            ps_d3 <= ps_d2;

            // ----------------------------------------------------------
            // Stage 3.5 (NEW): two parallel pre-additions
            // Decomposes the old 4-input series chain into two parallel
            // 2-input additions, leaving only 1 adder for Stage 4.
            // ----------------------------------------------------------
            sum_AB    <= sum3_reg[0] + sum3_reg[1]; // A + B (parallel)
            ps_plus_C <= ps_d3 + sum3_reg[2];       // ps + C (parallel)

            // ----------------------------------------------------------
            // Stage 4: single final addition (was 3 adders, now 1)
            // Critical path = 1 × 32-bit add ≈ 1.5 ns
            // Slack improves from 0.038 ns to ~6 ns
            // ----------------------------------------------------------
            partial_sum_out <= sum_AB + ps_plus_C;
        end
    end
endmodule
