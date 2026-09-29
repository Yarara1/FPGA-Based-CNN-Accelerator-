`timescale 1ns / 1ps

module quant_relu #(
    parameter IN_W  = 32,
    parameter OUT_W = 8,
    parameter SHIFT = 10
)(
    input  wire                    clk,      // ADD clock
    input  wire                    resetn,   // ADD reset
    input  wire                    valid_in, // ADD valid handshake
    input  wire signed [IN_W-1:0]  in_data,
    output reg                     valid_out,// ADD valid out
    output reg  signed [OUT_W-1:0] out_data
);
    // Combinational intermediate
    wire signed [IN_W-1:0]  shifted   = in_data >>> SHIFT;
    wire signed [OUT_W-1:0] saturated = (shifted > 32'sd127)  ? 8'sd127  :
                                        (shifted < -32'sd128) ? -8'sd128 :
                                         shifted[OUT_W-1:0];
    wire signed [OUT_W-1:0] relu_out  = (saturated < 0) ? 8'sd0 : saturated;

    // Register the result - breaks the combinational path
    always @(posedge clk) begin
        if (!resetn) begin
            out_data  <= 8'sd0;
            valid_out <= 1'b0;
        end else begin
            out_data  <= relu_out;   // registered: closes timing
            valid_out <= valid_in;   // propagate valid 1 cycle later
        end
    end
endmodule
