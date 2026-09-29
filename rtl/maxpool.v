`timescale 1ns / 1ps

module maxpool (
    input wire clk,
    input wire resetn,
    input wire start,
    output reg done,
    // fm2 single read port
    output reg [13:0] fm2_addr,
    input wire signed [7:0] fm2_dout,
    // pool output memory write port
    output reg [11:0] pool_addr,
    output reg signed [7:0] pool_din,
    output reg pool_we
);
    localparam IN_W  = 24;
    localparam OUT_W = 12;
    localparam OUT_H = 12;
    localparam CH    = 16;
    localparam FM2_CH_SIZE  = 576;
    localparam POOL_CH_SIZE = 144;
    reg [3:0] ch;
    reg [4:0] x;
    reg [4:0] y;
    reg signed [7:0] max_val;
    wire [5:0] in_x = x << 1;
    wire [5:0] in_y = y << 1;
    wire [13:0] addr_a = ch * FM2_CH_SIZE + in_y * IN_W + in_x;
    wire [13:0] addr_b = ch * FM2_CH_SIZE + in_y * IN_W + in_x + 1;
    wire [13:0] addr_c = ch * FM2_CH_SIZE + (in_y + 1) * IN_W + in_x;
    wire [13:0] addr_d = ch * FM2_CH_SIZE + (in_y + 1) * IN_W + in_x + 1;

    wire [11:0] pool_addr_calc = ch * POOL_CH_SIZE + y * OUT_W + x;
    localparam S_IDLE    = 4'd0;
    localparam S_READ_A  = 4'd1;
    localparam S_WAIT_A  = 4'd2;
    localparam S_STORE_A = 4'd3;
    localparam S_READ_B  = 4'd4;
    localparam S_WAIT_B  = 4'd5;
    localparam S_STORE_B = 4'd6;
    localparam S_READ_C  = 4'd7;
    localparam S_WAIT_C  = 4'd8;
    localparam S_STORE_C = 4'd9;
    localparam S_READ_D  = 4'd10;
    localparam S_WAIT_D  = 4'd11;
    localparam S_STORE_D = 4'd12;
    localparam S_WRITE   = 4'd13;  // NEW: dedicated write state
    localparam S_NEXT    = 4'd14;
    localparam S_DONE    = 4'd15;
    reg [3:0] state;
    always @(posedge clk) begin
        if (!resetn) begin
            state    <= S_IDLE;
            done     <= 1'b0;
            fm2_addr <= 14'd0;
            pool_addr <= 12'd0;
            pool_din  <= 8'sd0;
            pool_we   <= 1'b0;
            ch <= 4'd0;
            x  <= 5'd0;
            y  <= 5'd0;

                 max_val <= 8'sd0;
                end else begin
                    case (state)

                S_IDLE: begin
                    done    <= 1'b0;
                    pool_we <= 1'b0;
                    ch      <= 4'd0;
                    x       <= 5'd0;
                    y       <= 5'd0;
                    if (start)
                        state <= S_READ_A;
                end
                S_READ_A: begin
                    pool_we  <= 1'b0;
                    fm2_addr <= addr_a;
                    state    <= S_WAIT_A;
                end
                S_WAIT_A: begin
                    state <= S_STORE_A;
                end
                S_STORE_A: begin
                    max_val <= fm2_dout;
                    state   <= S_READ_B;
                end
                S_READ_B: begin
                    fm2_addr <= addr_b;
                    state    <= S_WAIT_B;
                end
                S_WAIT_B: begin
                    state <= S_STORE_B;
                end
                S_STORE_B: begin
                    if (fm2_dout > max_val)
                        max_val <= fm2_dout;
                    state <= S_READ_C;
                end
                S_READ_C: begin
                    fm2_addr <= addr_c;
                    state    <= S_WAIT_C;
                end
                S_WAIT_C: begin
                    state <= S_STORE_C;
                end
                S_STORE_C: begin
                    if (fm2_dout > max_val)
                        max_val <= fm2_dout;
                    state <= S_READ_D;
                end
                S_READ_D: begin
                    fm2_addr <= addr_d;
                    state    <= S_WAIT_D;
                end
                S_WAIT_D: begin
                    state <= S_STORE_D;
                end
                // FIX: S_STORE_D now only latches the final max and          
                S_STORE_D: begin
                    pool_we  <= 1'b0;
                    pool_addr <= pool_addr_calc;   // register the address now
                    if (fm2_dout > max_val) begin
                     max_val  <= fm2_dout;
                    pool_din <= fm2_dout;
                 end else begin
                      pool_din <= max_val;
                  end
                    state <= S_WRITE;
                end
                // FIX: One cycle later, pool_addr and pool_din are fully
                S_WRITE: begin
                    pool_we <= 1'b1;
                    state   <= S_NEXT;
                end
                S_NEXT: begin
                    pool_we <= 1'b0;

                    if (x < OUT_W - 1) begin
                        x     <= x + 5'd1;
                        state <= S_READ_A;
                    end
                    else if (y < OUT_H - 1) begin
                        x     <= 5'd0;
                        y     <= y + 5'd1;
                        state <= S_READ_A;
                    end
                    else if (ch < CH - 1) begin
                        x     <= 5'd0;
                        y     <= 5'd0;
                        ch    <= ch + 4'd1;
                        state <= S_READ_A;
                    end
                    else begin
                        state <= S_DONE;
                    end
                end
                S_DONE: begin
                    done    <= 1'b1;
                    pool_we <= 1'b0; 
                        state <= S_IDLE;
                end
                default: begin
                    state <= S_IDLE;
                end

            endcase
        end
    end

endmodule
