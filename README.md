
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
<img width="1053" height="514" alt="image" src="https://github.com/user-attachments/assets/d06cebe6-4df3-48ea-8676-0b7d565e226f" />
## Hardware Architecture

### Conv1

The first convolution layer processes the 28×28 grayscale input using
eight 3×3 kernels and generates eight 26×26 output feature maps.

A custom **MMU_pipe9** datapath performs nine multiplications in parallel
using DSP resources. The MAC operation is divided into a 6-stage pipeline
to reduce the critical path.

<img width="1074" height="591" alt="image" src="https://github.com/user-attachments/assets/6b220ced-a4eb-4009-bf75-7a2db5700674" />


### Conv2

Conv2 receives eight input feature-map channels and generates sixteen
24×24 output channels.

To increase throughput:

- Four output channels are processed in parallel.
- Four MMU_pipe36 engines operate concurrently.
- Each MMU_pipe36 performs 36 parallel multiplications.
- Feature Map 1 is partitioned into eight independent BRAM banks.
- Weights are preloaded locally before computation.
- Computation is divided into two input-channel passes.

<img width="1088" height="604" alt="image" src="https://github.com/user-attachments/assets/eb59ca53-175d-486f-902b-51d7baa33ac0" />


### Pipelined MAC Units

Two custom multiply-accumulate architectures were implemented:

- **MMU_pipe9:** 9 parallel MAC operations, 6-stage pipeline
- **MMU_pipe36:** 36 parallel multiplications, 8-stage pipeline

The pipelined adder-tree architecture reduces the combinational critical
path and enabled timing closure at 100 MHz.

<img width="1077" height="598" alt="image" src="https://github.com/user-attachments/assets/aa51906f-3277-4840-bc2a-5ed9f088a9a5" />


## Memory Architecture

The accelerator uses distributed BRAM storage rather than a single shared
memory.

Key design decisions include:

- Dedicated BRAMs for input images and weights
- Eight independent BRAM banks for Conv1 feature maps
- Parallel BRAM access for Conv2
- Separate memories for Conv2 output, pooled features, FC weights, and logits
- Dual-port memories to allow MicroBlaze and accelerator access

This memory banking architecture provides the bandwidth required by the
parallel convolution datapath.

## Quantization

The CNN uses fixed-point arithmetic:

- 8-bit signed activations and weights
- 32-bit accumulators
- Arithmetic right shift by 10 bits for requantization
- Saturation to signed 8-bit range
- ReLU activation after convolution layers

Using fixed-point arithmetic reduces FPGA resource requirements compared
with floating-point implementation.

## Fully Connected Layer

The final pooled feature map contains:
The fully connected layer maps these **2304 features to 10 output logits**.

A pipelined MAC architecture overlaps memory access, multiplication, and
accumulation instead of executing them sequentially.

## Hardware / Software Integration

The MicroBlaze processor is responsible for:

1. Loading input images into BRAM
2. Loading trained CNN weights
3. Starting the hardware accelerator
4. Polling accelerator status
5. Reading the final prediction

The computationally intensive CNN operations are executed in programmable
logic.

## Verification

The design was verified at multiple levels:

- RTL simulation
- Comparison against golden-reference FC logits
- Signed arithmetic verification
- Quantization verification
- Timing analysis
- FPGA hardware testing
- Complete 10,000-image MNIST test set

Simulation produced bit-exact agreement with the expected output logits.

## Results

<img width="641" height="334" alt="image" src="https://github.com/user-attachments/assets/3ad2a707-f96f-4c58-953b-aefc76ce38ff" />

The final hardware implementation classified all **10,000 MNIST test
images correctly**.

### Timing

The design achieved timing closure at **100 MHz**:

| Timing Metric | Result |
|---|---:|
| WNS | +0.252 ns |
| TNS | 0.000 ns |
| Setup Violations | 0 |
| Worst Hold Slack | +0.008 ns |
| Hold Violations | 0 |

### FPGA Resource Utilization

| Resource | Used | Utilization |
|---|---:|---:|
| LUT | 21,603 | 34.07% |
| FF | 24,141 | 19.04% |
| LUTRAM | 1,810 | 9.53% |
| BRAM | 27 | 20.00% |
| DSP | 159 | 66.25% |

<img width="1193" height="664" alt="image" src="https://github.com/user-attachments/assets/19ae5f71-6653-4ba1-b957-5d2c85ae0c1f" />


## Design Optimizations

Several optimizations were applied during development:

- DSP-based parallel MAC units
- Multi-stage pipelined adder trees
- Eight-bank feature-map memory architecture
- Four-way Conv2 output-channel parallelism
- Local weight preloading
- Fixed-point quantization
- Fully connected MAC pipelining
- BRAM-aware dataflow
- MicroBlaze software-overhead reduction

## Tools

- Verilog / SystemVerilog
- Xilinx Vivado
- Xilinx Vitis
- MicroBlaze
- AXI
- Block RAM
- Xilinx DSP48 resources
- Arty A7-100T


