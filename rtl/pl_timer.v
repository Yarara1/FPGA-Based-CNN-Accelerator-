module pl_timer (
    input  wire clk,
    input  wire resetn,
    input  wire timer_start,
    input  wire timer_stop,
    output reg  timer_running,
    output reg [31:0] timer_ms
);
    localparam integer CYCLES_PER_MS = 100000; // 100 MHz
    reg [16:0] ms_counter; // needs to count 0 to 99999
    always @(posedge clk) begin
        if (!resetn) begin
            timer_running <= 1'b0;
            timer_ms      <= 32'd0;
            ms_counter    <= 17'd0;
        end else begin
            if (timer_start) begin
                timer_running <= 1'b1;
                timer_ms      <= 32'd0;
                ms_counter    <= 17'd0;
            end else if (timer_stop) begin
                timer_running <= 1'b0;
            end else if (timer_running) begin
                if (ms_counter == CYCLES_PER_MS - 1) begin
                    ms_counter <= 17'd0;
                    timer_ms   <= timer_ms + 32'd1;
                end else begin
                    ms_counter <= ms_counter + 17'd1;
                end
            end
        end
    end

endmodule
