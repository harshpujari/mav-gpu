<details><summary>What is a GPU and TPU? How are they same or different ?</summary>

## First: what they have in common (build from basics)

Think at a high level first.

Both **GPU** and **TPU** are:

* **Accelerators**, not general-purpose CPUs
* Designed to handle **massive parallel computation**
* Especially good at **matrix and vector math**
* Used heavily in **machine learning workloads**

Guiding question for you:
👉 *Why do you think matrix math is so important in AI models?*
(Answer in one line; we’ll build from that.)

---

## How they are the same (conceptually)

At an architectural level, both:

* Execute **many simple operations simultaneously**
* Trade **flexibility** for **throughput**
* Are optimized for:

  * Multiply–accumulate operations
  * High data reuse
  * Minimizing control logic

In short:
**Both exist because CPUs are inefficient at large-scale parallel math.**

---

## Key differences (this is where they diverge)

Let’s compare them along one dimension at a time.

### 1. Purpose & Design Philosophy

**GPU**

* Originally designed for **graphics rendering**
* Later adapted for general parallel computing (CUDA, OpenCL)
* Flexible: supports many workloads

**TPU**

* Designed **from day one** for **neural networks**
* Built by Google specifically for TensorFlow-style computation
* Narrower scope, extreme optimization

Question for you:
👉 *Which do you think would be faster: a flexible tool or a highly specialized one, if both do the same task? Why?*

---

### 2. Instruction & Programming Model

**GPU**

* Programmer controls:

  * Threads
  * Memory hierarchy
  * Execution flow
* Can run:

  * Graphics
  * Scientific computing
  * ML
  * Simulations

**TPU**

* Programmer has **less low-level control**
* Relies on:

  * Static computation graphs
  * Compiler-driven optimizations
* Best when computation is predictable and structured

Key takeaway:
**GPUs are programmable workhorses; TPUs are domain-specific engines.**

---

### 3. Performance vs Flexibility Trade-off

**GPU**

* Slightly less efficient per operation
* Much more adaptable
* Industry standard across vendors (NVIDIA, AMD, etc.)

**TPU**

* Extremely efficient (performance per watt)
* Locked to specific frameworks and environments
* Mostly available via Google Cloud

Think about this scenario:
👉 *If you were researching a new ML algorithm, would you prefer GPU or TPU? Why?*

---

### 4. Typical Usage

| Use Case               | GPU | TPU               |
| ---------------------- | --- | ----------------- |
| Training custom models | Yes | Sometimes         |
| Inference at scale     | Yes | Yes (very strong) |
| Non-ML computation     | Yes | No                |
| Cloud-only dependency  | No  | Yes               |

---

</details>

<details>
<summary>
What is the usage of each componenet in arachitecture.md?
</summary>

## 1. Device Control Register

**What it is**
A set of special registers that the **CPU uses to control the GPU**.

**What it does**

* Start / stop execution
* Configure modes (power, performance, scheduling)
* Report status, errors, completion signals

**Real use case**

* When you call a CUDA kernel or start a graphics frame, the CPU writes into these registers.
* Example: “Start kernel X with grid size Y.”

**Why it exists**

* GPUs are **devices**, not autonomous computers.
* The CPU must have a **low-level control interface**.

Think of it as:
**“The on/off switches and knobs of the GPU.”**

Quick check:
👉 Who do you think writes to these registers — your program directly, or the driver?

---

## 2. Dispatcher

**What it is**
The **work scheduler** of the GPU.

**What it does**

* Receives work (kernels, shaders, compute tasks)
* Breaks them into:

  * Thread blocks
  * Warps / wavefronts
* Assigns them to available compute cores

**Real use case**

* In ML: dispatches thousands of matrix-multiply threads
* In graphics: dispatches pixel/vertex shaders

**Why it exists**

* GPUs execute **millions of threads**
* Someone must decide:

  * Which core runs what
  * When stalled threads are swapped out

Mental model:
**Dispatcher = traffic controller for parallel work**

---

## 3. Compute Cores (the 4 big boxes)

**What they are**
The **actual execution units** of the GPU.

> In real GPUs, these are SMs (NVIDIA) or CUs (AMD).

**What they do**

* Execute instructions like:

  * add
  * multiply
  * fused multiply-add
* Run **many threads in lockstep** (SIMT model)

**Real use case**

* Training a neural network
* Image processing
* Physics simulation
* Video encoding

**Why they exist**

* Instead of a few powerful cores (CPU),
* GPUs use **many simpler cores** to maximize throughput.

Key difference vs CPU:

* CPUs optimize **latency**
* GPUs optimize **throughput**

Pause and think:
👉 Why is “many slow cores” better than “few fast cores” for matrix multiplication?

---

## 4. Cache

**What it is**
Fast, on-chip memory shared by compute cores.

**What it does**

* Stores frequently used data
* Reduces expensive global memory access
* Improves memory bandwidth efficiency

**Real use case**

* Reusing matrix tiles in ML
* Reusing nearby pixel data in graphics

**Why it exists**

* Global memory is **slow and far away**
* Cache hides memory latency

Important GPU-specific point:

* GPU caches are optimized for **bandwidth**, not low latency like CPU caches.

---

## 5. Program Memory Controller

**What it is**
Controls access to **program instructions** stored in global memory.

**What it does**

* Fetches kernels / shader code
* Feeds instructions to compute cores
* Handles instruction caching and alignment

**Real use case**

* Fetching CUDA/PTX instructions
* Fetching shader programs

**Why it exists**

* Instructions live in memory, just like data
* Instruction flow must be managed efficiently

Think:
👉 Why separate program memory from data memory?

---

## 6. Data Memory Controller

**What it is**
Controls access to **data stored in global memory**.

**What it does**

* Handles:

  * Loads
  * Stores
  * Coalescing memory accesses
* Optimizes bandwidth usage

**Real use case**

* Reading tensors
* Writing output matrices
* Accessing textures or buffers

**Why it exists**

* GPUs depend on **very high memory bandwidth**
* Poor access patterns can destroy performance

Key idea:

> On GPUs, *how* you access memory often matters more than *how many* operations you do.

---

## 7. Global Memory (bottom section)

### 7a. Program Memory

**What it is**

* Stores executable GPU code (kernels, shaders)

**Real use case**

* CUDA kernels
* OpenCL programs
* Graphics shaders

**Key property**

* Read-only during execution
* Large but slow compared to cache

---

### 7b. Data Memory

**What it is**

* Stores all runtime data

**Real use case**

* Neural network weights
* Input images
* Simulation state

**Key properties**

* Very large (GBs)
* High bandwidth
* High latency

---

## Big Picture Flow (very important)

When a GPU program runs:

1. CPU writes commands → **Device Control Registers**
2. Work enters → **Dispatcher**
3. Threads assigned → **Compute Cores**
4. Instructions fetched → **Program Memory Controller**
5. Data fetched/stored → **Data Memory Controller**
6. Cache used to reduce memory cost
7. Results written back to global memory

---

## Why this matters for TPU comparison (preview)

This diagram already hints why GPUs are flexible:

* General dispatcher
* General compute cores
* General memory system

TPUs will:

* Remove much of this flexibility
* Replace compute cores with **matrix engines**
* Restrict memory access patterns

We will map **this exact diagram** to a TPU next.

---

Before moving on, do this:
👉 In one sentence, tell me **which block actually “does the math”** and **which block decides *where* the math runs**.

</details>