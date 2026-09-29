`timescale 1ns / 1ps
module argmax10 (
    input wire clk,
    input wire resetn,
    input wire start,
    output reg done,
    output reg [3:0] fc_out_addr,
    input wire signed [31:0] fc_out_dout,
    output reg [3:0] predicted_digit,
    output reg signed [31:0] max_logit
);
    localparam S_IDLE  = 3'd0;
    localparam S_ADDR  = 3'd1;
    localparam S_WAIT1 = 3'd2;
    localparam S_WAIT2 = 3'd3;
    localparam S_CHECK = 3'd4;
    localparam S_NEXT  = 3'd5;
    localparam S_DONE  = 3'd6;
    reg [2:0] state;
    reg [3:0] idx;
    always @(posedge clk) begin
        if (!resetn) begin
            state <= S_IDLE;
            done <= 1'b0;
            idx <= 4'd0;
            fc_out_addr <= 4'd0;
            predicted_digit <= 4'd0;
            max_logit <= 32'sh80000000;
        end else begin
            case (state)
                S_IDLE: begin
                    done <= 1'b0;
                    idx <= 4'd0;
                    fc_out_addr <= 4'd0;
                    predicted_digit <= 4'd0;
                    max_logit <= 32'sh80000000;
                    if (start)
                        state <= S_ADDR;
                end
                S_ADDR: begin
                    fc_out_addr <= idx;
                    state <= S_WAIT1;
                end
                S_WAIT1: begin
                    state <= S_WAIT2;
                end
                S_WAIT2: begin
                    state <= S_CHECK;
                end
                S_CHECK: begin
                    if (fc_out_dout > max_logit) begin
                        max_logit <= fc_out_dout;
                        predicted_digit <= idx;
                    end
                    state <= S_NEXT;
                end
                S_NEXT: begin
                    if (idx < 4'd9) begin
                        idx <= idx + 4'd1;
                        state <= S_ADDR;
                    end else begin
                        state <= S_DONE;
                    end
                end
                S_DONE: begin
                    done <= 1'b1;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
