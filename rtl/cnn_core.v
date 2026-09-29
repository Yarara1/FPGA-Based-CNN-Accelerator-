`timescale 1ns / 1ps

module cnn_core(
    input  wire clk,
    input  wire resetn,
    input  wire start,
    output wire done,

    input  wire        image_clka,
    input  wire        image_ena,
    input  wire        image_wea,
    input  wire [9:0]  image_addra,
    input  wire [7:0]  image_dina,
    output wire [7:0]  image_douta,

    input  wire        w1_clka,
    input  wire        w1_ena,
    input  wire        w1_wea,
    input  wire [6:0]  w1_addra,
    input  wire [7:0]  w1_dina,
    output wire [7:0]  w1_douta,

    input  wire        w2_clka,
    input  wire        w2_ena,
    input  wire        w2_wea,
    input  wire [10:0] w2_addra,
    input  wire [7:0]  w2_dina,
    output wire [7:0]  w2_douta,

    input  wire        fc_w_clka,
    input  wire        fc_w_ena,
    input  wire        fc_w_wea,
    input  wire [14:0] fc_w_addra,
    input  wire [7:0]  fc_w_dina,
    output wire [7:0]  fc_w_douta,

    input  wire        timer_start,
    output wire [31:0] timer_value,
        input  wire  timer_stop,   

    input  wire        fc_out_clka,
    input  wire        fc_out_ena,
    input  wire [0:0]  fc_out_wea,
    input  wire [3:0]  fc_out_addra,
    input  wire [31:0] fc_out_dina,
    output wire [31:0] fc_out_dout,

    output wire [3:0]         predicted_digit,
    output wire signed [31:0] max_logit
);

    // -------------------------------------------------------------------------
    // FSM states - T_DONE removed, done is now a latched register
    // -------------------------------------------------------------------------
    localparam T_IDLE        = 4'd0;
    localparam T_CONV1       = 4'd1;
    localparam T_CONV2       = 4'd2;
    localparam T_WAIT        = 4'd3;
    localparam T_MAXPOOL     = 4'd4;
    localparam T_FC_WAIT     = 4'd5;
    localparam T_FC          = 4'd6;
    localparam T_ARGMAX_WAIT = 4'd7;
    localparam T_ARGMAX      = 4'd8;

    reg [3:0] top_state;

    // done_reg: latched HIGH when argmax finishes, cleared when next start arrives
    // This keeps done=1 visible to MicroBlaze polling even after FSM returns to IDLE
    reg done_reg;
    assign done = done_reg;

    reg conv1_start;
    reg conv2_start;
    reg maxpool_start;
    reg fc_start;
    reg argmax_start;

    wire conv1_done;
    wire conv2_done;
    wire maxpool_done;
    wire fc_done;
    wire conv2_pass;
    wire argmax_done;

    always @(posedge clk) begin
        if (!resetn) begin
            top_state     <= T_IDLE;
            done_reg      <= 1'b0;
            conv1_start   <= 1'b0;
            conv2_start   <= 1'b0;
            maxpool_start <= 1'b0;
            fc_start      <= 1'b0;
            argmax_start  <= 1'b0;
        end else begin
            conv1_start   <= 1'b0;
            conv2_start   <= 1'b0;
            maxpool_start <= 1'b0;
            fc_start      <= 1'b0;
            argmax_start  <= 1'b0;

            case (top_state)
                T_IDLE: begin
                    if (start) begin
                        done_reg    <= 1'b0;   // clear done for new image
                        conv1_start <= 1'b1;
                        top_state   <= T_CONV1;
                    end
                end

                T_CONV1: begin
                    if (conv1_done) begin
                        conv2_start <= 1'b1;
                        top_state   <= T_CONV2;
                    end
                end

                T_CONV2: begin
                    if (conv2_done)
                        top_state <= T_WAIT;
                end

                T_WAIT: begin
                    maxpool_start <= 1'b1;
                    top_state     <= T_MAXPOOL;
                end

                T_MAXPOOL: begin
                    if (maxpool_done)
                        top_state <= T_FC_WAIT;
                end

                T_FC_WAIT: begin
                    fc_start  <= 1'b1;
                    top_state <= T_FC;
                end

                T_FC: begin
                    if (fc_done)
                        top_state <= T_ARGMAX_WAIT;
                end

                T_ARGMAX_WAIT: begin
                    argmax_start <= 1'b1;
                    top_state    <= T_ARGMAX;
                end

                T_ARGMAX: begin
                    if (argmax_done) begin
                        done_reg  <= 1'b1;   // latch done HIGH
                        top_state <= T_IDLE; // return to IDLE immediately
                        // done stays HIGH until next start clears it in T_IDLE
                    end
                end

                default:
                    top_state <= T_IDLE;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Internal wires
    // -------------------------------------------------------------------------
    wire [9:0]        conv1_img_addr;
    wire signed [7:0] conv1_img_dout;
    wire [6:0]        conv1_w_addr;
    wire signed [7:0] conv1_w_dout;
    wire [9:0]        conv1_fm1_addr;
    wire signed [7:0] conv1_fm1_din;
    wire              conv1_fm1_we;
    wire [2:0]        conv1_fm1_ch_sel;

    wire [9:0]        conv2_fm1_addr0, conv2_fm1_addr1;
    wire [9:0]        conv2_fm1_addr2, conv2_fm1_addr3;
    wire signed [7:0] conv2_fm1_dout0, conv2_fm1_dout1;
    wire signed [7:0] conv2_fm1_dout2, conv2_fm1_dout3;
    wire signed [7:0] fm1_ch0_dout, fm1_ch1_dout;
    wire signed [7:0] fm1_ch2_dout, fm1_ch3_dout;
    wire signed [7:0] fm1_ch4_dout, fm1_ch5_dout;
    wire signed [7:0] fm1_ch6_dout, fm1_ch7_dout;

    wire [10:0]        conv2_w_addr;
    wire signed [7:0]  conv2_w_dout;
    wire [13:0]        conv2_fm2_addr;
    wire signed [7:0]  conv2_fm2_din;
    wire               conv2_fm2_we;
    wire [13:0]        maxpool_fm2_addr;
    wire [7:0]         fm2_douta_int;
    wire [11:0]        pool_addr;
    wire signed [7:0]  pool_din;
    wire               pool_we;
    wire [11:0]        fc_pool_addr;
    wire signed [7:0]  fc_pool_dout;
    wire [14:0]        fc_w_addr_int;
    wire signed [7:0]  fc_w_dout_int;
    wire [3:0]         fc_out_addr_int;
    wire signed [31:0] fc_out_din_int;
    wire               fc_out_we_int;
    wire [7:0]         pool_mem_douta_int;
    wire [7:0]         fm2_doutb_int;
    wire [3:0]         argmax_fc_addr;
    wire signed [31:0] argmax_fc_dout;

    assign fc_pool_dout = pool_mem_douta_int;

    // -------------------------------------------------------------------------
    // Enables
    // -------------------------------------------------------------------------
    wire image_mem_en = (top_state == T_CONV1);
    wire w1_mem_en    = (top_state == T_CONV1);
    wire w2_mem_en    = (top_state == T_CONV2);
    wire fm1_mem_en   = (top_state == T_CONV1) || (top_state == T_CONV2);
    wire fm2_mem_en_b = (top_state == T_CONV2);

    // -------------------------------------------------------------------------
    // Sub-modules
    // -------------------------------------------------------------------------
    conv1 u_conv1 (
        .clk(clk), .resetn(resetn), .start(conv1_start), .done(conv1_done),
        .img_addr(conv1_img_addr), .img_dout(conv1_img_dout),
        .w_addr(conv1_w_addr),     .w_dout(conv1_w_dout),
        .fm1_addr(conv1_fm1_addr), .fm1_din(conv1_fm1_din),
        .fm1_we(conv1_fm1_we),     .fm1_ch_sel(conv1_fm1_ch_sel)
    );

    conv2 #(.NUM_OC_PAR(4)) u_conv2 (
        .clk(clk), .resetn(resetn), .start(conv2_start), .done(conv2_done),
        .fm1_addr0(conv2_fm1_addr0), .fm1_dout0(conv2_fm1_dout0),
        .fm1_addr1(conv2_fm1_addr1), .fm1_dout1(conv2_fm1_dout1),
        .fm1_addr2(conv2_fm1_addr2), .fm1_dout2(conv2_fm1_dout2),
        .fm1_addr3(conv2_fm1_addr3), .fm1_dout3(conv2_fm1_dout3),
        .w_addr(conv2_w_addr),       .w_dout(conv2_w_dout),
        .fm2_addr(conv2_fm2_addr),   .fm2_din(conv2_fm2_din),
        .fm2_we(conv2_fm2_we),       .pass_out(conv2_pass)
    );

    maxpool u_maxpool (
        .clk(clk), .resetn(resetn), .start(maxpool_start), .done(maxpool_done),
        .fm2_addr(maxpool_fm2_addr), .fm2_dout(fm2_douta_int),
        .pool_addr(pool_addr),       .pool_din(pool_din), .pool_we(pool_we)
    );

    FC u_fc (
        .clk(clk), .resetn(resetn), .start(fc_start), .done(fc_done),
        .pool_addr(fc_pool_addr),     .pool_dout(fc_pool_dout),
        .fc_w_addr(fc_w_addr_int),    .fc_w_dout(fc_w_dout_int),
        .fc_out_addr(fc_out_addr_int),.fc_out_din(fc_out_din_int),
        .fc_out_we(fc_out_we_int)
    );

    argmax10 u_argmax10 (
        .clk(clk), .resetn(resetn), .start(argmax_start), .done(argmax_done),
        .fc_out_addr(argmax_fc_addr), .fc_out_dout(argmax_fc_dout),
        .predicted_digit(predicted_digit), .max_logit(max_logit)
    );

    pl_timer u_pl_timer (
        .clk(clk), .resetn(resetn),
        .timer_start(timer_start), .timer_stop(timer_stop),
        .timer_running(), .timer_ms(timer_value)
    );

    // -------------------------------------------------------------------------
    // Memories
    // -------------------------------------------------------------------------
    image_mem u_image_mem (
        .clka(image_clka), .ena(image_ena), .wea(image_wea),
        .addra(image_addra), .dina(image_dina), .douta(image_douta),
        .clkb(clk), .enb(image_mem_en), .web(1'b0),
        .addrb(conv1_img_addr), .dinb(8'd0), .doutb(conv1_img_dout)
    );

    conv1_w_mem u_conv1_w_mem (
        .clka(w1_clka), .ena(w1_ena), .wea(w1_wea),
        .addra(w1_addra), .dina(w1_dina), .douta(w1_douta),
        .clkb(clk), .enb(w1_mem_en), .web(1'b0),
        .addrb(conv1_w_addr), .dinb(8'd0), .doutb(conv1_w_dout)
    );

    conv2_w_mem u_conv2_w_mem (
        .clka(w2_clka), .ena(w2_ena), .wea(w2_wea),
        .addra(w2_addra), .dina(w2_dina), .douta(w2_douta),
        .clkb(clk), .enb(w2_mem_en), .web(1'b0),
        .addrb(conv2_w_addr), .dinb(8'd0), .doutb(conv2_w_dout)
    );

    fc_w_mem u_fc_w_mem (
        .clka(fc_w_clka), .ena(fc_w_ena), .wea(fc_w_wea),
        .addra(fc_w_addra), .dina(fc_w_dina), .douta(fc_w_douta),
        .clkb(clk), .enb(top_state == T_FC), .web(1'b0),
        .addrb(fc_w_addr_int), .dinb(8'd0), .doutb(fc_w_dout_int)
    );

    // FM1 muxing
    assign conv2_fm1_dout0 = (conv2_pass == 1'b0) ? fm1_ch0_dout : fm1_ch4_dout;
    assign conv2_fm1_dout1 = (conv2_pass == 1'b0) ? fm1_ch1_dout : fm1_ch5_dout;
    assign conv2_fm1_dout2 = (conv2_pass == 1'b0) ? fm1_ch2_dout : fm1_ch6_dout;
    assign conv2_fm1_dout3 = (conv2_pass == 1'b0) ? fm1_ch3_dout : fm1_ch7_dout;

    wire fm1_ch0_we = conv1_fm1_we && (conv1_fm1_ch_sel == 3'd0);
    wire fm1_ch1_we = conv1_fm1_we && (conv1_fm1_ch_sel == 3'd1);
    wire fm1_ch2_we = conv1_fm1_we && (conv1_fm1_ch_sel == 3'd2);
    wire fm1_ch3_we = conv1_fm1_we && (conv1_fm1_ch_sel == 3'd3);
    wire fm1_ch4_we = conv1_fm1_we && (conv1_fm1_ch_sel == 3'd4);
    wire fm1_ch5_we = conv1_fm1_we && (conv1_fm1_ch_sel == 3'd5);
    wire fm1_ch6_we = conv1_fm1_we && (conv1_fm1_ch_sel == 3'd6);
    wire fm1_ch7_we = conv1_fm1_we && (conv1_fm1_ch_sel == 3'd7);

    fm1_ch0_mem u_fm1_ch0_mem (
        .clka(clk),.ena(1'b0),.wea(1'b0),.addra(10'd0),.dina(8'd0),.douta(),
        .clkb(clk),.enb(fm1_mem_en),.web(fm1_ch0_we),
        .addrb((top_state==T_CONV1)?conv1_fm1_addr:conv2_fm1_addr0),
        .dinb(conv1_fm1_din),.doutb(fm1_ch0_dout));
    fm1_ch1_mem u_fm1_ch1_mem (
        .clka(clk),.ena(1'b0),.wea(1'b0),.addra(10'd0),.dina(8'd0),.douta(),
        .clkb(clk),.enb(fm1_mem_en),.web(fm1_ch1_we),
        .addrb((top_state==T_CONV1)?conv1_fm1_addr:conv2_fm1_addr1),
        .dinb(conv1_fm1_din),.doutb(fm1_ch1_dout));
    fm1_ch2_mem u_fm1_ch2_mem (
        .clka(clk),.ena(1'b0),.wea(1'b0),.addra(10'd0),.dina(8'd0),.douta(),
        .clkb(clk),.enb(fm1_mem_en),.web(fm1_ch2_we),
        .addrb((top_state==T_CONV1)?conv1_fm1_addr:conv2_fm1_addr2),
        .dinb(conv1_fm1_din),.doutb(fm1_ch2_dout));
    fm1_ch3_mem u_fm1_ch3_mem (
        .clka(clk),.ena(1'b0),.wea(1'b0),.addra(10'd0),.dina(8'd0),.douta(),
        .clkb(clk),.enb(fm1_mem_en),.web(fm1_ch3_we),
        .addrb((top_state==T_CONV1)?conv1_fm1_addr:conv2_fm1_addr3),
        .dinb(conv1_fm1_din),.doutb(fm1_ch3_dout));
    fm1_ch4_mem u_fm1_ch4_mem (
        .clka(clk),.ena(1'b0),.wea(1'b0),.addra(10'd0),.dina(8'd0),.douta(),
        .clkb(clk),.enb(fm1_mem_en),.web(fm1_ch4_we),
        .addrb((top_state==T_CONV1)?conv1_fm1_addr:conv2_fm1_addr0),
        .dinb(conv1_fm1_din),.doutb(fm1_ch4_dout));
    fm1_ch5_mem u_fm1_ch5_mem (
        .clka(clk),.ena(1'b0),.wea(1'b0),.addra(10'd0),.dina(8'd0),.douta(),
        .clkb(clk),.enb(fm1_mem_en),.web(fm1_ch5_we),
        .addrb((top_state==T_CONV1)?conv1_fm1_addr:conv2_fm1_addr1),
        .dinb(conv1_fm1_din),.doutb(fm1_ch5_dout));
    fm1_ch6_mem u_fm1_ch6_mem (
        .clka(clk),.ena(1'b0),.wea(1'b0),.addra(10'd0),.dina(8'd0),.douta(),
        .clkb(clk),.enb(fm1_mem_en),.web(fm1_ch6_we),
        .addrb((top_state==T_CONV1)?conv1_fm1_addr:conv2_fm1_addr2),
        .dinb(conv1_fm1_din),.doutb(fm1_ch6_dout));
    fm1_ch7_mem u_fm1_ch7_mem (
        .clka(clk),.ena(1'b0),.wea(1'b0),.addra(10'd0),.dina(8'd0),.douta(),
        .clkb(clk),.enb(fm1_mem_en),.web(fm1_ch7_we),
        .addrb((top_state==T_CONV1)?conv1_fm1_addr:conv2_fm1_addr3),
        .dinb(conv1_fm1_din),.doutb(fm1_ch7_dout));

    fm2_mem u_fm2_mem (
        .clka(clk),.ena(top_state==T_MAXPOOL),.wea(1'b0),
        .addra(maxpool_fm2_addr),.dina(8'd0),.douta(fm2_douta_int),
        .clkb(clk),.enb(fm2_mem_en_b),.web(conv2_fm2_we),
        .addrb(conv2_fm2_addr),.dinb(conv2_fm2_din),.doutb(fm2_doutb_int)
    );

    pool_mem u_pool_mem (
        .clka(clk),.ena(top_state==T_FC),.wea(1'b0),
        .addra(fc_pool_addr),.dina(8'd0),.douta(pool_mem_douta_int),
        .clkb(clk),.enb(top_state==T_MAXPOOL),.web(pool_we),
        .addrb(pool_addr),.dinb(pool_din),.doutb()
    );

    // FC output memory
    // Port A: MicroBlaze read (always available)
    // Port B: FC write during T_FC, argmax read during T_ARGMAX
    fc_out_mem u_fc_out_mem (
        .clka(fc_out_clka),.ena(fc_out_ena),.wea(fc_out_wea),
        .addra(fc_out_addra),.dina(fc_out_dina),.douta(fc_out_dout),
        .clkb(clk),
        .enb((top_state==T_FC) || fc_out_we_int || (top_state==T_ARGMAX)),
        .web(fc_out_we_int),
        .addrb((top_state==T_ARGMAX) ? argmax_fc_addr : fc_out_addr_int),
        .dinb(fc_out_din_int),
        .doutb(argmax_fc_dout)
    );

endmodule
