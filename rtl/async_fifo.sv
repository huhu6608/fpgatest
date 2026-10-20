`timescale 1ns/1ps
// Portable behavioral dual-clock FIFO, first-word fall-through read interface.
// DEPTH must be a power of two >= 4. Both domains must reset together.
module async_fifo #(
    parameter integer WIDTH = 256,
    parameter integer DEPTH = 16,
    parameter integer ADDR_W = $clog2(DEPTH)
)(
    input wire wr_clk, wr_rst_n,
    input wire [WIDTH-1:0] wr_data,
    input wire wr_valid, output wire wr_ready,
    input wire rd_clk, rd_rst_n,
    output wire [WIDTH-1:0] rd_data,
    output wire rd_valid, input wire rd_ready
);
    reg [WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_W:0] wbin, wgray, rbin, rgray;
    (* ASYNC_REG = "TRUE" *) reg [ADDR_W:0] rq1_wgray, rq2_wgray;
    (* ASYNC_REG = "TRUE" *) reg [ADDR_W:0] wq1_rgray, wq2_rgray;
    reg full, empty;
    wire push = wr_valid && wr_ready;
    wire pop = rd_valid && rd_ready;
    wire [ADDR_W:0] wnext = wbin + {{ADDR_W{1'b0}},push};
    wire [ADDR_W:0] rnext = rbin + {{ADDR_W{1'b0}},pop};
    wire [ADDR_W:0] wg_next = (wnext >> 1) ^ wnext;
    wire [ADDR_W:0] rg_next = (rnext >> 1) ^ rnext;
    wire [ADDR_W:0] full_compare = {~wq2_rgray[ADDR_W:ADDR_W-1],
                                                  wq2_rgray[ADDR_W-2:0]};
    assign wr_ready = wr_rst_n && !full;
    assign rd_valid = rd_rst_n && !empty;
    assign rd_data = mem[rbin[ADDR_W-1:0]];
    initial begin
        if (WIDTH < 1 || DEPTH < 4 || (DEPTH & (DEPTH-1)) != 0
            || ADDR_W != $clog2(DEPTH))
            $fatal(1, "Invalid FIFO parameters");
    end
    always @(posedge wr_clk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            wbin <= 0; wgray <= 0; full <= 0;
            wq1_rgray <= 0; wq2_rgray <= 0;
        end else begin
            wq1_rgray <= rgray; wq2_rgray <= wq1_rgray;
            wbin <= wnext; wgray <= wg_next;
            full <= (wg_next == full_compare);
            if (push) mem[wbin[ADDR_W-1:0]] <= wr_data;
        end
    end
    always @(posedge rd_clk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            rbin <= 0; rgray <= 0; empty <= 1;
            rq1_wgray <= 0; rq2_wgray <= 0;
        end else begin
            rq1_wgray <= wgray; rq2_wgray <= rq1_wgray;
            rbin <= rnext; rgray <= rg_next;
            empty <= (rg_next == rq2_wgray);
        end
    end
endmodule
