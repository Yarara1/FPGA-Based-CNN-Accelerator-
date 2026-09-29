`timescale 1ns / 1ps
module conv1(
    input wire clk, 
    input wire resetn, 
    input wire start, 
    output reg done, 
  
      // image_mem read port
    output reg  [9:0] img_addr,
    input  wire signed [7:0] img_dout,

    // conv1 weight memory read port
    output reg  [6:0] w_addr,
    input  wire signed [7:0] w_dout,

    // fm1 output memory write port
    output reg  [9:0] fm1_addr,
    output reg  signed [7:0] fm1_din,
    output reg  fm1_we,
    
    output wire [2:0] fm1_ch_sel
      
    );
    localparam IMG_W  = 28; localparam IMG_H  = 28;
    localparam OUT_W  = 26; localparam OUT_H  = 26;
    localparam OUT_CH = 8; localparam K_SIZE = 3;

    localparam FM1_CH_SIZE = OUT_W * OUT_H; // 26 * 26 = 676

    
    reg [2:0] oc;      // output channel: 0 to 7
    reg [4:0] x;       // output x position: 0 to 25
    reg [4:0] y;       // output y position: 0 to 25
    reg [3:0] k;       // kernel index: 0 to 8
    
    reg signed [7:0] pix [0:8];
    reg signed [7:0] wt  [0:8];
    reg compute_valid; 
    wire mmu_valid; 
   
    
    wire signed [8*9-1:0] data_vec;
    wire signed [8*9-1:0] weight_vec;
    wire signed [31:0] mmu_acc;
    assign data_vec = {
    pix[8], pix[7], pix[6],
    pix[5], pix[4], pix[3],
    pix[2], pix[1], pix[0]
   };

    assign weight_vec = {
    wt[8], wt[7], wt[6],
    wt[5], wt[4], wt[3],
    wt[2], wt[1], wt[0]
    };

   MMU_pipe9 #(
    .DATA_W(8),
    .ACC_W(32)
) u_mmu (
    .clk             (clk),
    .resetn          (resetn),
    .valid_in        (compute_valid),
    .data_vec        (data_vec),
    .weight_vec      (weight_vec),
    .partial_sum_in  (32'sd0),
    .valid_out       (mmu_valid),
    .partial_sum_out (mmu_acc)
);
    wire signed [7:0] q_relu_out;
    wire q_relu_valid;

 
    localparam S_IDLE       = 4'd0;
    localparam S_LOAD_ADDR  = 4'd1;
    localparam S_WAIT_READ  = 4'd2;
    localparam S_STORE      = 4'd3;
    localparam S_COMPUTE    = 4'd4;
    localparam S_WRITE      = 4'd5;
    localparam S_NEXT       = 4'd6;
    localparam S_DONE       = 4'd7;
    localparam S_COMPUTE_WAIT= 4'd8;
    
    reg [3:0] state; 
    
    
    reg [1:0] ky; reg [1:0] kx; 
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
    
    //address calculation 
    
    wire [9:0] img_addr_calc;
    wire [6:0] w_addr_calc;
    wire [9:0] fm1_addr_calc;

    assign img_addr_calc = (y + ky) * IMG_W + (x + kx); //row*img_widt + col

    assign w_addr_calc = oc * 9 + k;

    assign fm1_addr_calc =  y * OUT_W + x;
    assign fm1_ch_sel = oc;

    reg signed [7:0] conv_out;

    // FSM
    
    integer i;
    always @(posedge clk ) begin
        if (!resetn) begin
                    state <= S_IDLE;
        done <= 1'b0;
        img_addr <= 10'd0;
        w_addr <= 7'd0;
        fm1_addr <= 10'd0;
        fm1_din <= 8'sd0;
        fm1_we <= 1'b0;

        compute_valid <= 1'b0;

        oc <= 3'd0;
        x <= 5'd0;
        y <= 5'd0;
        k <= 4'd0;

        conv_out <= 8'sd0;


    end else begin
        compute_valid <= 1'b0;

        case (state)
                // Wait for start signal

                S_IDLE: begin
                    done <= 1'b0;
                    fm1_we <= 1'b0;

                    oc <= 3'd0;
                    x <= 5'd0;
                    y <= 5'd0;
                    k <= 4'd0;

                    if (start) begin
                        state <= S_LOAD_ADDR;
                    end
                    else begin
                        state <= S_IDLE;
                    end
                end

                // Send address to image memory and weight memory
            
                S_LOAD_ADDR: begin
                    fm1_we <= 1'b0;
                    img_addr <= img_addr_calc;
                    w_addr   <= w_addr_calc;
                    state <= S_WAIT_READ;
                end

                // Wait one clock 
                S_WAIT_READ: begin
                    state <= S_STORE;
                end
      
                // Store read pixel and weight into registers     
                S_STORE: begin
                    pix[k] <= img_dout;
                    wt[k]  <= w_dout;

                    if (k < 4'd8) begin
                        k <= k + 4'd1;
                        state <= S_LOAD_ADDR;
                    end
                    else begin
                        k <= 4'd0;
                        state <= S_COMPUTE;
                    end
                end

                // Compute convolution using 9 parallel multipliers
               S_COMPUTE: begin
                compute_valid <= 1'b1;
                state <= S_COMPUTE_WAIT;
            end
            
            S_COMPUTE_WAIT: begin
                if (q_relu_valid) begin
                    conv_out <= q_relu_out;
                    state <= S_WRITE;
                end
            end 

                // Write result to fm1 memory
                S_WRITE: begin
                    fm1_addr <= fm1_addr_calc;
                    fm1_din  <= conv_out;
                    fm1_we   <= 1'b1;
                    state <= S_NEXT;
                end

                // Move to next output pixel/channel
                S_NEXT: begin
                    fm1_we <= 1'b0;

                    if (x < OUT_W - 1) begin
                        x <= x + 5'd1;
                        k <= 4'd0;
                        state <= S_LOAD_ADDR;
                    end

                    else if (y < OUT_H - 1) begin
                        x <= 5'd0;
                        y <= y + 5'd1;
                        k <= 4'd0;
                        state <= S_LOAD_ADDR;
                    end

                    else if (oc < OUT_CH - 1) begin
                        x <= 5'd0;
                        y <= 5'd0;
                        oc <= oc + 3'd1;
                        k <= 4'd0;
                        state <= S_LOAD_ADDR;
                    end

                    else begin
                        state <= S_DONE;
                    end
                end

             S_DONE: begin
                done <= 1'b1;
                fm1_we <= 1'b0;
                state <= S_IDLE;
            end 

                default: begin
                    state <= S_IDLE;
                end

            endcase
        end
    end
        quant_relu #(
            .IN_W (32),
            .OUT_W(8),
            .SHIFT(10)
        ) u_quant_relu (
            .clk      (clk),
            .resetn   (resetn),
            .valid_in (mmu_valid),       // driven by MMU valid_out
            .in_data  (mmu_acc),
            .valid_out(q_relu_valid),    // use THIS to advance FSM
            .out_data (q_relu_out)
        );
       
       
   endmodule


