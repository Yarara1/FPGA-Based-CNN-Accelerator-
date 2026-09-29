`timescale 1ns / 1ps
module FC(
    input  wire        clk, 
    input  wire        resetn, 
    input  wire        start, 
    output reg         done, 
    output reg  [11:0] pool_addr, 
    input  wire signed [7:0] pool_dout, 
    output reg  [14:0] fc_w_addr, 
    input  wire signed [7:0] fc_w_dout, 
    output reg  [3:0]  fc_out_addr, 
    output reg  signed [31:0] fc_out_din, 
    output reg         fc_out_we
);
    localparam IN_SIZE   = 12'd2304;
    localparam OUT_SIZE  = 4'd10;
    // Pipeline depth from address issue to accumulation = 4 cycles:
    localparam LAST_CYCLE = IN_SIZE + 12'd3;  // 2307
    // States - removed S_LOAD_ADDR, S_WAIT_READ, S_PIPE1, S_MULT, S_ACCUM
    localparam S_IDLE     = 3'd0;
    localparam S_FC_PIPE  = 3'd1;   // pipelined MAC loop
    localparam S_WRITE    = 3'd2;
    localparam S_NEXT_OUT = 3'd3;
    localparam S_DONE     = 3'd4;
    reg [2:0]  state;
    reg [11:0] cycle_cnt;    // 0..LAST_CYCLE (2307)
    reg [3:0]  out_idx;
    reg signed [31:0] acc;
    reg signed [31:0] final_acc;
    reg [14:0] row_base_addr;
    // Pipeline registers (same as before, now used every cycle)
    reg signed [7:0]  pool_dout_reg;
    reg signed [7:0]  fc_w_dout_reg;
    (* use_dsp = "yes" *) reg signed [15:0] mult_reg;
    always @(posedge clk) begin
        if (!resetn) begin
            state         <= S_IDLE;
            done          <= 1'b0;
            pool_addr     <= 12'd0;
            fc_w_addr     <= 15'd0;
            fc_out_addr   <= 4'd0;
            fc_out_din    <= 32'sd0;
            fc_out_we     <= 1'b0;
            cycle_cnt     <= 12'd0;
            out_idx       <= 4'd0;
            acc           <= 32'sd0;
            final_acc     <= 32'sd0;
            row_base_addr <= 15'd0;
            pool_dout_reg <= 8'sd0;
            fc_w_dout_reg <= 8'sd0;
            mult_reg      <= 16'sd0;
        end else begin
            case (state)
                S_IDLE: begin
                    done          <= 1'b0;
                    fc_out_we     <= 1'b0;
                    cycle_cnt     <= 12'd0;
                    out_idx       <= 4'd0;
                    acc           <= 32'sd0;
                    final_acc     <= 32'sd0;
                    row_base_addr <= 15'd0;
                    pool_dout_reg <= 8'sd0;
                    fc_w_dout_reg <= 8'sd0;
                    mult_reg      <= 16'sd0;
                    if (start) state <= S_FC_PIPE;
                end
                // S_FC_PIPE: Pipelined MAC loop
                S_FC_PIPE: begin
                    fc_out_we <= 1'b0;

                    // STAGE 0: address issue (stops after last input)
                    if (cycle_cnt < IN_SIZE) begin
                        pool_addr <= cycle_cnt;
                        fc_w_addr <= row_base_addr + {3'd0, cycle_cnt};
                    end
                    // STAGE 2: register BRAM outputs
                    // pool_dout = data[cycle_cnt - 2] (2-cycle BRAM latency)
                    if (cycle_cnt >= 12'd2) begin
                        pool_dout_reg <= pool_dout;
                        fc_w_dout_reg <= fc_w_dout;
                    end
                    // STAGE 3: multiply registered inputs
                    // mult result = data[cycle_cnt - 3] x w[cycle_cnt - 3]
                    if (cycle_cnt >= 12'd3) begin
                        mult_reg <= pool_dout_reg * fc_w_dout_reg;
                    end
                    // STAGE 4: accumulate OR capture final result
                    if (cycle_cnt == LAST_CYCLE) begin
                        // Final cycle: capture last MAC (data[2303]xw[2303]) directly.
                        // acc (before this posedge) = sum(k=0..2302)
                        // mult_reg (before this posedge) = data[2303]xw[2303]
                        // => final_acc = sum(k=0..2303)
                        final_acc <= acc + {{16{mult_reg[15]}}, mult_reg};
                        cycle_cnt <= 12'd0;
                        state     <= S_WRITE;

                    end else if (cycle_cnt >= 12'd4) begin
                        // Normal accumulation: cycle 4..2306
                        acc <= acc + {{16{mult_reg[15]}}, mult_reg};
                        cycle_cnt <= cycle_cnt + 12'd1;
                    end else begin
                        cycle_cnt <= cycle_cnt + 12'd1;
                    end
                end
                // Write quantised logit for current output neuron
                S_WRITE: begin
                    fc_out_addr <= out_idx;
                    fc_out_din  <= final_acc >>> 10;
                    fc_out_we   <= 1'b1;
                    state       <= S_NEXT_OUT;
                end
                // Advance to next output neuron or finish
                S_NEXT_OUT: begin
                    fc_out_we <= 1'b0;
                    if (out_idx < OUT_SIZE - 1) begin
                        out_idx       <= out_idx + 4'd1;
                        row_base_addr <= row_base_addr + 15'd2304;
                        cycle_cnt     <= 12'd0;
                        acc           <= 32'sd0;
                        final_acc     <= 32'sd0;
                        mult_reg      <= 16'sd0;
                        pool_dout_reg <= 8'sd0;
                        fc_w_dout_reg <= 8'sd0;
                        state         <= S_FC_PIPE;
                    end else begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    done      <= 1'b1;
                    fc_out_we <= 1'b0;
                    state     <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
