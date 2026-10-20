`timescale 1ns/1ps
module acquisition #(
    parameter integer CHANNELS=16, BITS=14, SEQ_W=32, FIFO_DEPTH=16
)(
    input wire arst_n, adc_clk, out_clk,
    input wire adc_valid,
    input wire [CHANNELS*BITS-1:0] adc_data,
    input wire [SEQ_W-1:0] adc_seq,
    output wire adc_ready,
    output reg drop_pulse, overflow_sticky,
    output reg [31:0] dropped_frames,
    output wire out_valid, input wire out_ready,
    output wire [CHANNELS*BITS-1:0] out_data,
    output wire [SEQ_W-1:0] out_seq,
    output reg gap_pulse, gap_sticky,
    output reg [31:0] gap_events,
    output wire adc_rst_n, out_rst_n
);
    localparam integer DATA_W=CHANNELS*BITS;
    wire [DATA_W+SEQ_W-1:0] fifo_data;
    reg have_previous;
    reg [SEQ_W-1:0] previous_seq;
    reset_sync adc_reset(adc_clk, arst_n, adc_rst_n);
    reset_sync out_reset(out_clk, arst_n, out_rst_n);
    async_fifo #(.WIDTH(DATA_W+SEQ_W), .DEPTH(FIFO_DEPTH)) fifo (
        .wr_clk(adc_clk), .wr_rst_n(adc_rst_n),
        .wr_data({adc_seq, adc_data}), .wr_valid(adc_valid), .wr_ready(adc_ready),
        .rd_clk(out_clk), .rd_rst_n(out_rst_n),
        .rd_data(fifo_data), .rd_valid(out_valid), .rd_ready(out_ready)
    );
    assign {out_seq, out_data} = fifo_data;
    // These status signals belong to adc_clk; never sample them unsynchronized.
    always @(posedge adc_clk or negedge adc_rst_n) begin
        if (!adc_rst_n) begin
            drop_pulse <= 0; overflow_sticky <= 0; dropped_frames <= 0;
        end else begin
            drop_pulse <= adc_valid && !adc_ready;
            if (adc_valid && !adc_ready) begin
                overflow_sticky <= 1;
                dropped_frames <= dropped_frames + 1'b1;
            end
        end
    end
    // Gap events count discontinuities, not number of missing frames.
    // First frame after reset establishes a baseline. Arithmetic wraps at SEQ_W.
    always @(posedge out_clk or negedge out_rst_n) begin
        if (!out_rst_n) begin
            have_previous <= 0; previous_seq <= 0;
            gap_pulse <= 0; gap_sticky <= 0; gap_events <= 0;
        end else begin
            gap_pulse <= 0;
            if (out_valid && out_ready) begin
                have_previous <= 1;
                previous_seq <= out_seq;
                if (have_previous && out_seq != (previous_seq + {{(SEQ_W-1){1'b0}},1'b1})) begin
                    gap_pulse <= 1; gap_sticky <= 1;
                    gap_events <= gap_events + 1'b1;
                end
            end
        end
    end
    initial if (CHANNELS < 1 || BITS < 1 || SEQ_W < 2)
        $fatal(1, "Invalid acquisition parameters");
endmodule
