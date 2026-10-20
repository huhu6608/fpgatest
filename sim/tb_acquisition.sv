`timescale 1ns/1ps
// Procedural clocks/scoreboards intentionally use blocking assignments.
/* verilator lint_off BLKSEQ */
// Testbench monitors sample reset synchronously; RTL uses asynchronous reset.
/* verilator lint_off SYNCASYNCNET */
module acquisition_case #(
    parameter integer ID=0, CHANNELS=16, BITS=14, DEPTH=16,
    parameter real OUT_HALF=3.5,
    parameter integer SEED=1
)(output reg done=0);
    localparam integer SEQ_W=8; // Deliberately wrap repeatedly during regression.
    localparam integer DW=CHANNELS*BITS;
    reg adc_clk=0, out_clk=0, arst_n=1, enable=0;
    always #10 adc_clk=~adc_clk; // 50 MSPS
    initial begin #1.137; forever #(OUT_HALF) out_clk=~out_clk; end
    wire adc_rst_n, out_rst_n, adc_valid, adc_ready;
    wire [DW-1:0] adc_data, out_data;
    wire [SEQ_W-1:0] adc_seq, out_seq;
    wire out_valid, drop_pulse, overflow_sticky, gap_pulse, gap_sticky;
    wire [31:0] dropped_frames, gap_events;
    reg out_ready=0;
    integer mode=0;
    reg [31:0] rng=SEED;
    adc_model #(.CHANNELS(CHANNELS),.BITS(BITS),.SEQ_W(SEQ_W)) source (
        .clk(adc_clk),.rst_n(adc_rst_n),.enable(enable),
        .valid(adc_valid),.data(adc_data),.seq(adc_seq));
    acquisition #(.CHANNELS(CHANNELS),.BITS(BITS),.SEQ_W(SEQ_W),.FIFO_DEPTH(DEPTH)) dut (
        .arst_n(arst_n),.adc_clk(adc_clk),.out_clk(out_clk),
        .adc_valid(adc_valid),.adc_data(adc_data),.adc_seq(adc_seq),
        .adc_ready(adc_ready),.drop_pulse(drop_pulse),
        .overflow_sticky(overflow_sticky),.dropped_frames(dropped_frames),
        .out_valid(out_valid),.out_ready(out_ready),.out_data(out_data),.out_seq(out_seq),
        .gap_pulse(gap_pulse),.gap_sticky(gap_sticky),.gap_events(gap_events),
        .adc_rst_n(adc_rst_n),.out_rst_n(out_rst_n));

    // Scoreboard contains exactly the frames accepted at the ADC/FIFO boundary.
    reg [DW+SEQ_W-1:0] expected [0:32767];
    integer sent=0, accepted=0, dropped=0, received=0, gaps=0;
    integer total_dropped=0, total_received=0, full_cycles=0, stall_cycles=0;
    integer wraps=0;
    reg have_prev=0, held=0;
    reg [SEQ_W-1:0] prev_seq=0;
    reg [DW+SEQ_W-1:0] held_data;
    reg expected_drop, expected_gap;
    integer c;

    always @(negedge out_clk) begin
        rng = rng ^ (rng << 13);
        rng = rng ^ (rng >> 17);
        rng = rng ^ (rng << 5);
        case (mode)
            0: out_ready=1;
            1: out_ready=(rng[3:0] != 0); // short random stalls
            2: out_ready=0;             // guaranteed overflow
            3: out_ready=rng[0];        // sustained random backpressure
            default: out_ready=1;
        endcase
    end
    always @(posedge adc_clk) begin
        if (adc_rst_n) begin
            expected_drop=adc_valid && !adc_ready;
            if (adc_valid) begin
                sent=sent+1;
                for (c=0;c<CHANNELS;c=c+1)
                    if (adc_data[c*BITS +: BITS] !== BITS'(adc_seq*17+c*257))
                        $fatal(1,"case %0d ADC pattern channel %0d",ID,c);
                if (adc_ready) begin
                    if (accepted>=32768) $fatal(1,"scoreboard capacity");
                    expected[accepted]={adc_seq,adc_data};
                    accepted=accepted+1;
                end else begin
                    dropped=dropped+1; total_dropped=total_dropped+1;
                    full_cycles=full_cycles+1;
                end
            end
            #0.001;
            if (drop_pulse !== expected_drop || dropped_frames !== 32'(dropped)
                || overflow_sticky !== (dropped != 0))
                $fatal(1,"case %0d drop status mismatch",ID);
        end
    end
    always @(posedge out_clk) begin
        if (out_rst_n) begin
            expected_gap=0;
            if (held && (!out_valid || {out_seq,out_data} !== held_data))
                $fatal(1,"case %0d output changed under backpressure",ID);
            held=out_valid && !out_ready;
            if (held) begin held_data={out_seq,out_data}; stall_cycles=stall_cycles+1; end
            if (out_valid && out_ready) begin
                if (received>=accepted) $fatal(1,"case %0d phantom output",ID);
                if ({out_seq,out_data} !== expected[received])
                    $fatal(1,"case %0d corrupt/reordered/duplicate frame %0d",ID,received);
                expected_gap=have_prev && out_seq != SEQ_W'(int'(prev_seq)+1);
                if (expected_gap) gaps=gaps+1;
                if (have_prev && prev_seq==8'hff && out_seq==0) wraps=wraps+1;
                prev_seq=out_seq; have_prev=1;
                received=received+1; total_received=total_received+1;
            end
            #0.001;
            if (gap_pulse !== expected_gap || gap_events !== 32'(gaps)
                || gap_sticky !== (gaps != 0))
                $fatal(1,"case %0d gap status mismatch",ID);
        end else begin held=0; end
    end
    task reset_epoch;
        begin
            // Called away from active edges. Reset deliberately flushes in-flight data.
            arst_n=0; enable=0;
            #2;
            if (out_valid !== 0 || adc_ready !== 0 || dropped_frames !== 0
                || gap_events !== 0 || overflow_sticky !== 0 || gap_sticky !== 0)
                $fatal(1,"case %0d reset status",ID);
            sent=0; accepted=0; dropped=0; received=0; gaps=0;
            have_prev=0; held=0; prev_seq=0;
            #81; arst_n=1;
            wait(adc_rst_n && out_rst_n);
            @(negedge adc_clk);
        end
    endtask
    task drain;
        integer timeout;
        begin
            @(negedge adc_clk); enable=0; mode=0;
            timeout=0;
            while ((received != accepted || out_valid) && timeout<20000) begin
                @(negedge out_clk); timeout=timeout+1;
            end
            repeat(8) @(negedge out_clk);
            if (received != accepted || out_valid || sent != received+dropped)
                $fatal(1,"case %0d conservation sent=%0d received=%0d dropped=%0d accepted=%0d",
                    ID,sent,received,dropped,accepted);
        end
    endtask
    initial begin
        #0.731; reset_epoch();
        // Full-rate lossless run also exercises FIFO pointers and sequence wrap.
        enable=1; mode=0;
        repeat(1200) @(negedge adc_clk);
        drain();
        if (OUT_HALF<10 && (dropped != 0 || gaps != 0 || wraps<3))
            $fatal(1,"case %0d lossless/wrap test drops=%0d gaps=%0d wraps=%0d",ID,dropped,gaps,wraps);
        mode=1; enable=1;
        repeat(600) @(negedge adc_clk);
        drain();
        // Check an exactly full FIFO with the consumer stopped.
        reset_epoch(); mode=2;
        repeat(4) @(negedge out_clk);
        @(negedge adc_clk); enable=1;
        repeat(DEPTH) @(negedge adc_clk);
        enable=0;
        if (accepted != DEPTH || dropped != 0 || adc_ready !== 0)
            $fatal(1,"case %0d exact FIFO capacity accepted=%0d drop=%0d ready=%b",ID,accepted,dropped,adc_ready);
        enable=1;
        repeat(120) @(negedge adc_clk);
        enable=0;
        if (dropped != 120) $fatal(1,"case %0d overflow count",ID);
        drain();
        // Resume after overflow so a sequence gap becomes observable downstream.
        enable=1; mode=0;
        repeat(100) @(negedge adc_clk);
        drain();
        if (gaps==0 || !overflow_sticky) $fatal(1,"case %0d missing loss detection",ID);
        mode=3; enable=1;
        repeat(1500) @(negedge adc_clk);
        drain();
        // Reset while stalled/full: old frames must not escape into the next epoch.
        enable=1; mode=2;
        repeat(DEPTH+30) @(negedge adc_clk);
        #0.233; reset_epoch();
        mode=0; enable=1;
        repeat(700) @(negedge adc_clk);
        drain();
        if (OUT_HALF<10 && (dropped != 0 || gaps != 0))
            $fatal(1,"case %0d post-reset data loss",ID);
        if (total_dropped==0 || full_cycles==0 || stall_cycles==0)
            $fatal(1,"case %0d missing stress coverage",ID);
        $display("PASS case=%0d channels=%0d bits=%0d depth=%0d sink_half=%0f received=%0d drops=%0d stalls=%0d wraps=%0d",
            ID,CHANNELS,BITS,DEPTH,OUT_HALF,total_received,total_dropped,stall_cycles,wraps);
        done=1;
    end
endmodule

module tb_acquisition;
    wire [4:0] done;
    acquisition_case #(.ID(0),.DEPTH(16),.SEED(32'h1234)) c0(done[0]);
    acquisition_case #(.ID(1),.DEPTH(4),.OUT_HALF(2.3),.SEED(32'h5678)) c1(done[1]);
    acquisition_case #(.ID(2),.DEPTH(64),.OUT_HALF(6.3),.SEED(32'h9abc)) c2(done[2]);
    acquisition_case #(.ID(3),.CHANNELS(3),.BITS(12),.DEPTH(8),.OUT_HALF(2.9),.SEED(32'hdef1)) c3(done[3]);
    acquisition_case #(.ID(4),.DEPTH(8),.OUT_HALF(13.1),.SEED(32'h2468)) c4(done[4]);
    initial begin
        if ($test$plusargs("vcd")) begin
            $dumpfile("build/acquisition.vcd"); $dumpvars(0,tb_acquisition);
        end
        wait (&done);
        $display("ALL TESTS PASSED (5 configurations)");
        $finish;
    end
    initial begin #2000000; $fatal(1,"Global timeout"); end
endmodule
