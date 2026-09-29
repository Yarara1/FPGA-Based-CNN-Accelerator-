`timescale 1ns / 1ps

module tb_top;

    reg clk;
    reg resetn;
    reg start;
    wire done;

    // ------------------------------------------------------------
    // PL timer control/status
    // ------------------------------------------------------------
    reg         timer_start;
    reg         timer_stop;
    wire [31:0] timer_value;   // milliseconds from PL timer

    // image_mem external write port
    reg        image_ena;
    reg        image_wea;
    reg [9:0]  image_addra;
    reg [7:0]  image_dina;

    // conv1_w_mem external write port
    reg        w1_ena;
    reg        w1_wea;
    reg [6:0]  w1_addra;
    reg [7:0]  w1_dina;

    // conv2_w_mem external write port
    reg        w2_ena;
    reg        w2_wea;
    reg [10:0] w2_addra;
    reg [7:0]  w2_dina;

    // FC weight memory external write port
    reg        fc_w_ena;
    reg        fc_w_wea;
    reg [14:0] fc_w_addra;
    reg [7:0]  fc_w_dina;
    // FC output memory external read port
    reg        fc_out_ena;
    reg [0:0]  fc_out_wea;
    reg [3:0]  fc_out_addra;
    reg [31:0] fc_out_dina;
    wire [31:0] fc_out_dout;

    // ------------------------------------------------------------
    // Test data arrays
    // ------------------------------------------------------------
    reg [7:0]  image_data      [0:783];
    reg [7:0]  w1_data         [0:71];
    reg [7:0]  w2_data         [0:1151];
    reg [7:0]  expected_fc_w   [0:23039];
    reg [31:0] expected_fc_out [0:9];

    integer i;
    integer error_count;

    //wire [3:0] predicted_digit;
   // wire signed [31:0] max_logit;

    // ------------------------------------------------------------
    // Testbench reference timer
    // ------------------------------------------------------------
    integer tb_timer_cycles;
    integer tb_timer_ms;
    integer timer_diff_ms;
    reg     tb_timer_counting;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            tb_timer_cycles   <= 0;
            tb_timer_counting <= 1'b0;
        end else begin
            if (timer_start) begin
                tb_timer_cycles   <= 0;
                tb_timer_counting <= 1'b1;
            end else if (timer_stop) begin
                tb_timer_counting <= 1'b0;
            end else if (tb_timer_counting) begin
                tb_timer_cycles <= tb_timer_cycles + 1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    cnn_core dut (
        .clk             (clk),
        .resetn          (resetn),
        .start           (start),
        .done            (done),

        // image input memory write port
        .image_clka      (clk),
        .image_ena       (image_ena),
        .image_wea       (image_wea),
        .image_addra     (image_addra),
        .image_dina      (image_dina),

        // conv1 weight memory write port
        .w1_clka         (clk),
        .w1_ena          (w1_ena),
        .w1_wea          (w1_wea),
        .w1_addra        (w1_addra),
        .w1_dina         (w1_dina),

        // conv2 weight memory write port
        .w2_clka         (clk),
        .w2_ena          (w2_ena),
        .w2_wea          (w2_wea),
        .w2_addra        (w2_addra),
        .w2_dina         (w2_dina),

        // FC weight memory write port
        .fc_w_clka       (clk),
        .fc_w_ena        (fc_w_ena),
        .fc_w_wea        (fc_w_wea),
        .fc_w_addra      (fc_w_addra),
        .fc_w_dina       (fc_w_dina),

        // results
       // .predicted_digit (predicted_digit),
       // .max_logit       (max_logit),

        // PL timer controls
        .timer_start     (timer_start),
      
        .timer_value     (timer_value),
        .fc_out_clka   (clk),
        .fc_out_ena    (fc_out_ena),
        .fc_out_wea    (fc_out_wea),
        .fc_out_addra  (fc_out_addra),
        .fc_out_dina   (fc_out_dina),
        .fc_out_dout   (fc_out_dout)
    );

    // -------------------------------------------------------------------------
    // Clock: 100 MHz
    // -------------------------------------------------------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // -------------------------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------------------------
    initial begin
        $readmemh("C:/Users/Yara/Downloads/params/npy/hex_outputs/input_784.hex",   image_data);
        $readmemh("C:/Users/Yara/Downloads/params/npy/hex_outputs/conv1_w_72.hex",  w1_data);
        $readmemh("C:/Users/Yara/Downloads/params/npy/hex_outputs/conv2_w_1152.hex", w2_data);
        $readmemh("C:/Users/Yara/Downloads/params/npy/hex_outputs/fc1_w_23040.hex",  expected_fc_w);
        $readmemh("C:/Users/Yara/Downloads/params/npy/hex_outputs/output_10.hex",    expected_fc_out);

        resetn        = 1'b0;
        start         = 1'b0;
        timer_start   = 1'b0;
        timer_stop    = 1'b0;

        image_ena     = 1'b0;
        image_wea     = 1'b0;
        image_addra   = 10'd0;
        image_dina    = 8'd0;

        w1_ena        = 1'b0;
        w1_wea        = 1'b0;
        w1_addra      = 7'd0;
        w1_dina       = 8'd0;

        w2_ena        = 1'b0;
        w2_wea        = 1'b0;
        w2_addra      = 11'd0;
        w2_dina       = 8'd0;
        fc_out_ena   = 1'b0;
        fc_out_wea   = 1'b0;
        fc_out_addra = 4'd0;
        fc_out_dina  = 32'd0;
        fc_w_ena      = 1'b0;
        fc_w_wea      = 1'b0;
        fc_w_addra    = 15'd0;
        fc_w_dina     = 8'd0;

        error_count   = 0;
        tb_timer_ms   = 0;
        timer_diff_ms = 0;

        repeat(10) @(posedge clk);
        resetn = 1'b1;
        repeat(5) @(posedge clk);

        // ------------------------------------------------------------
        // Start PL timer before first weight transfer
        // ------------------------------------------------------------
        $display("[%0t] Starting PL timer before first weight transfer...", $time);

        @(posedge clk);
        timer_start <= 1'b1;
        @(posedge clk);
        timer_start <= 1'b0;

        // ------------------------------------------------------------
        // Load conv1 weights
        // ------------------------------------------------------------
        $display("[%0t] Loading conv1_w_mem...", $time);

        for (i = 0; i < 72; i = i + 1) begin
            @(posedge clk);
            w1_ena   <= 1'b1;
            w1_wea   <= 1'b1;
            w1_addra <= i[6:0];
            w1_dina  <= w1_data[i];
        end

        @(posedge clk);
        w1_ena   <= 1'b0;
        w1_wea   <= 1'b0;
        w1_addra <= 7'd0;
        w1_dina  <= 8'd0;
        repeat(2) @(posedge clk);

        // ------------------------------------------------------------
        // Load conv2 weights
        // ------------------------------------------------------------
        $display("[%0t] Loading conv2_w_mem...", $time);

        for (i = 0; i < 1152; i = i + 1) begin
            @(posedge clk);
            w2_ena   <= 1'b1;
            w2_wea   <= 1'b1;
            w2_addra <= i[10:0];
            w2_dina  <= w2_data[i];
        end

        @(posedge clk);
        w2_ena   <= 1'b0;
        w2_wea   <= 1'b0;
        w2_addra <= 11'd0;
        w2_dina  <= 8'd0;
        repeat(2) @(posedge clk);

        // ------------------------------------------------------------
        // Load FC weights
        // ------------------------------------------------------------
        $display("[%0t] Loading fc_w_mem...", $time);

        for (i = 0; i < 23040; i = i + 1) begin
            @(posedge clk);
            fc_w_ena   <= 1'b1;
            fc_w_wea   <= 1'b1;
            fc_w_addra <= i[14:0];
            fc_w_dina  <= expected_fc_w[i];
        end

        @(posedge clk);
        fc_w_ena   <= 1'b0;
        fc_w_wea   <= 1'b0;
        fc_w_addra <= 15'd0;
        fc_w_dina  <= 8'd0;
        repeat(5) @(posedge clk);

        // ------------------------------------------------------------
        // Load image
        // ------------------------------------------------------------
        $display("[%0t] Loading image_mem...", $time);

        for (i = 0; i < 784; i = i + 1) begin
            @(posedge clk);
            image_ena   <= 1'b1;
            image_wea   <= 1'b1;
            image_addra <= i[9:0];
            image_dina  <= image_data[i];
        end

        @(posedge clk);
        image_ena   <= 1'b0;
        image_wea   <= 1'b0;
        image_addra <= 10'd0;
        image_dina  <= 8'd0;
        repeat(2) @(posedge clk);

        // ------------------------------------------------------------
        // Start CNN
        // ------------------------------------------------------------
        $display("[%0t] Starting CNN pipeline...", $time);

        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        wait(done == 1'b1);
        $display("[%0t] Pipeline done.", $time);

        repeat(20) @(posedge clk);

        // ------------------------------------------------------------
        // Check final FC logits
        // ------------------------------------------------------------
        $display("[%0t] Checking final output logits...", $time);

        error_count = 0;

        for (i = 0; i < 10; i = i + 1) begin
            check_fc_out(i[3:0], expected_fc_out[i]);
        end

        // ------------------------------------------------------------
        // Stop PL timer after final output read
        // ------------------------------------------------------------
        @(posedge clk);
        timer_stop <= 1'b1;
        @(posedge clk);
        timer_stop <= 1'b0;

        repeat(2) @(posedge clk);

        tb_timer_ms = tb_timer_cycles / 100000;

        $display("========================================");
        $display("PL TIMER RESULT");
        $display("PL timer value     = %0d ms", timer_value);
        $display("TB reference timer = %0d cycles", tb_timer_cycles);
        $display("TB reference time  = %0d ms", tb_timer_ms);
        $display("TB reference time  = %.2f us / %.5f ms at 100 MHz",
                 tb_timer_cycles * 0.01,
                 tb_timer_cycles * 0.00001);

        timer_diff_ms = timer_value - tb_timer_ms;
        if (timer_diff_ms < 0)
            timer_diff_ms = -timer_diff_ms;

        if (timer_diff_ms <= 1)
            $display("PL TIMER CHECK PASSED. Difference = %0d ms", timer_diff_ms);
        else
            $display("PL TIMER CHECK FAILED. Difference = %0d ms", timer_diff_ms);

        $display("========================================");
       // $display("Predicted digit = %0d", predicted_digit);
       // $display("Max logit       = %0d (0x%08h)", max_logit, max_logit);
        $display("========================================");

        if (error_count == 0) begin
            $display("TEST PASSED: all 10 FC logits correct.");
        end else begin
            $display("TEST FAILED: %0d errors.", error_count);
        end

        repeat(10) @(posedge clk);
        $stop;
    end

    // -------------------------------------------------------------------------
    // FC output check task
    // -------------------------------------------------------------------------
   task check_fc_out;
    input [3:0]  addr;
    input [31:0] expected;

    reg [31:0] got;

    begin
        @(posedge clk);
        fc_out_ena   <= 1'b1;
        fc_out_wea   <= 1'b0;
        fc_out_addra <= addr;

        @(posedge clk);
        @(posedge clk);

        got = fc_out_dout;

        @(posedge clk);
        fc_out_ena <= 1'b0;

        if (got !== expected) begin
            $display("FAIL FC_OUT[%0d]: got %0d (0x%08h), expected %0d (0x%08h)",
                     addr, $signed(got), got,
                     $signed(expected), expected);
            error_count = error_count + 1;
        end else begin
            $display("PASS FC_OUT[%0d]: got %0d (0x%08h), expected %0d (0x%08h)",
                     addr, $signed(got), got,
                     $signed(expected), expected);
        end
    end
endtask

    // -------------------------------------------------------------------------
    // Core latency only: start -> done
    // -------------------------------------------------------------------------
    integer latency_cycles;
    reg     counting;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            latency_cycles <= 0;
            counting       <= 1'b0;
        end else begin
            if (start) begin
                latency_cycles <= 0;
                counting       <= 1'b1;
            end else if (counting && !done) begin
                latency_cycles <= latency_cycles + 1;
            end else if (counting && done) begin
                counting <= 1'b0;
                $display("========================================");
                $display("CORE LATENCY ONLY");
                $display("Latency = %0d cycles", latency_cycles);
                $display("At 100 MHz = %.2f us / %.5f ms",
                         latency_cycles * 0.01,
                         latency_cycles * 0.00001);
                $display("========================================");
            end
        end
    end

endmodule
