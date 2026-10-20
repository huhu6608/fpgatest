# fpgatest — FPGA 数据采集仿真工程

不依赖 FPGA 厂商、开发板、ADC 串行接口或 PCIe IP 的 SystemVerilog 起点。
**这是数字采集链路的功能仿真，尚未实现 AFE5818 接口、PCIe/DMA 或板级约束。**

## 快速运行

Linux / WSL，安装 GNU Make、Icarus Verilog 11+；第二仿真器可选 Verilator 5+（需要 C++ 编译器）。

```sh
sudo apt-get update
sudo apt-get install -y make iverilog verilator g++
make test             # 自动验证，失败返回非零
make waves            # 同样运行验证，另生成 build/acquisition.vcd
# 可选：gtkwave build/acquisition.vcd
make lint
make test-verilator   # 用第二个仿真器独立执行相同回归
make clean
```

成功结束会输出各配置的 `PASS case=...` 及 `ALL TESTS PASSED (5 configurations)`。
所有构建结果在 `build/`，没有厂商工具或第三方 HDL 库依赖。

## 数据路径

`adc_model` 在 50 MHz 输入域生成帧，`acquisition` 将序号与数据一起写入异步 FIFO，
再由独立 `out_clk` 域的消费者通过 ready/valid 握手读取。

一次采样形成一帧：16 通道同时采样，每通道 14 bit，数据宽度 224 bit。
50 MSPS 对应 **11.2 Gbit/s = 1.4 GB/s** 原始数据，不含序号和传输协议开销。
默认序号为 32 bit，仿真内部帧宽 256 bit，对应 12.8 Gbit/s 内部吞吐；此宽度不代表已设计 PCIe 包格式。
输出每次握手传输一个完整帧，无串行化；要长期无损，平均输出帧率必须至少达到输入帧率。

ADC 模型不接受背压，`enable=1` 时每个 ADC 时钟产生一帧。FIFO 满时丢弃**新帧**，不覆盖已缓存数据。
输出 `valid && ready` 才消费；`valid && !ready` 时有效数据保持稳定。
`adc_ready` 只是 FIFO 接受能力，不能用来暂停真实 ADC 的采样时钟。

## 文件

| 路径 | 用途 |
|---|---|
| `rtl/reset_sync.sv` | 每时钟域异步置位复位、两级同步释放 |
| `rtl/async_fifo.sv` | 参数化双时钟 FIFO、Gray 指针跨域 |
| `rtl/acquisition.sv` | 帧封装、丢样统计、序号连续性检测 |
| `sim/adc_model.sv` | 可重复的多通道模拟数据源 |
| `sim/tb_acquisition.sv` | 自检记分板、时钟/背压/复位场景 |
| `docs/design.md` | 接口、CDC、复位和硬件落地约束 |
| `docs/testing.md` | 测试矩阵、判据与复现方法 |
| `.github/workflows/simulation.yml` | push / PR 自动仿真 |

模型按 `sample[channel] = (sequence × 17 + channel × 257) mod 2^BITS` 产生数据，通道 0 位于最低 `BITS` 位。
这是数字模式源，不模拟 ADC 模拟噪声、失真、量化过程或 LVDS 时序。

修改参数可从 `acquisition_case` 的实例开始。`CHANNELS`、`BITS`、`SEQ_W`、`FIFO_DEPTH` 可配置，FIFO 深度须为不小于 4 的 2 次幂。

详见 [设计说明](docs/design.md) 和 [测试说明](docs/testing.md)。
