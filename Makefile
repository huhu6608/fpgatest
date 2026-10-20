IVERILOG ?= iverilog
VVP ?= vvp
VERILATOR ?= verilator
SOURCES = rtl/reset_sync.sv rtl/async_fifo.sv rtl/acquisition.sv sim/adc_model.sv sim/tb_acquisition.sv
.PHONY: test waves lint test-verilator clean
build/sim.vvp: $(SOURCES)
	mkdir -p build
	$(IVERILOG) -g2012 -Wall -s tb_acquisition -o $@ $(SOURCES)
test: build/sim.vvp
	$(VVP) $<
waves: build/sim.vvp
	$(VVP) $< +vcd
lint:
	$(VERILATOR) --lint-only -Wall --top-module acquisition rtl/reset_sync.sv rtl/async_fifo.sv rtl/acquisition.sv
	$(VERILATOR) --lint-only --timing -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL --top-module tb_acquisition $(SOURCES)
test-verilator:
	mkdir -p build
	$(VERILATOR) --binary --timing -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL --top-module tb_acquisition --Mdir build/verilator $(SOURCES)
	./build/verilator/Vtb_acquisition
clean:
	rm -rf build
