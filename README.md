# FPGA-Based-CNN-Accelerator-
# FPGA-Based CNN Accelerator for MNIST Classification

An FPGA-based convolutional neural network accelerator implemented on the
**Xilinx Arty A7-100T**, using custom pipelined RTL, BRAM-based memory
architecture, and MicroBlaze control.

The design performs complete MNIST inference in programmable logic using
two convolution layers, max pooling, a fully connected classifier, and
Argmax prediction.

## Key Results

| Metric | Result |
|---|---:|
| FPGA Platform | Xilinx Arty A7-100T |
| Clock Frequency | 100 MHz |
| MNIST Test Images | 10,000 |
| Correct Predictions | 10,000 |
| Accuracy | 100% |
| Total Runtime | 97,777 ms |
| Average Runtime | ~9.78 ms/image |
| Throughput | ~102 images/s |
| WNS | +0.252 ns |
| On-Chip Power | 1.059 W |
| DSP Utilization | 159 / 240 (66.25%) |

## System Architecture

The accelerator is controlled by a **MicroBlaze soft-core processor**
through an AXI-based interface. Input images, trained weights, intermediate
feature maps, and output logits are stored in dedicated BRAM memories.

The CNN Design Overview is: 
<img width="1053" height="514" alt="image" src="https://github.com/user-attachments/assets/d06cebe6-4df3-48ea-8676-0b7d565e226f" />

