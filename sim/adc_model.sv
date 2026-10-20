`timescale 1ns/1ps
// One simultaneous multi-channel frame per enabled ADC clock, no backpressure.
module adc_model #(
    parameter integer CHANNELS=16, BITS=14, SEQ_W=32
)(
    input wire clk, rst_n, enable,
    output wire valid,
    output reg [CHANNELS*BITS-1:0] data,
    output reg [SEQ_W-1:0] seq
);
    assign valid = rst_n && enable;
    always @* begin
        for (integer c=0; c<CHANNELS; c=c+1)
            data[c*BITS +: BITS] = BITS'(seq * 17 + c * 257);
    end
    always @(posedge clk or negedge rst_n)
        if (!rst_n) seq <= 0;
        else if (enable) seq <= seq + 1'b1;
endmodule
