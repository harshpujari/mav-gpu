# Memory Controller - Line by Line Explanation

This document explains every line of `controller.sv` for learning purposes.

---

## What the Controller Does

The controller is an **arbiter**. Many requesters ("consumers") want memory, but
there are only a few physical memory channels. The controller funnels the many
onto the few, one request at a time per channel.

```
   consumer 0 ─┐                                  ┌─▶ mem channel 0
   consumer 1 ─┤   ┌────────────────────────┐     │
   consumer 2 ─┼──▶│   Memory Controller     │─────┤   (NUM_CHANNELS of them)
   consumer 3 ─┘   │   (NUM_CHANNELS FSMs)   │     │
   (NUM_CONSUMERS) └────────────────────────┘     └─▶ ...
```

Each physical channel runs an independent little FSM:

| Step             | What happens                                              |
|------------------|-----------------------------------------------------------|
| `IDLE`           | pick a pending consumer request (lowest index first)      |
| `READ/WRITE_WAITING`  | forward it to memory, wait for `mem_*_ready`         |
| `READ/WRITE_RELAYING` | hand the response back, wait for the consumer to ack |
| → `IDLE`         | free the channel (and the consumer) for the next request  |

**Used twice in the GPU:** once for program memory (consumers = each core's
fetcher) and once for data memory (consumers = all the thread LSUs).

---

## File Header (Lines 1-2)

```systemverilog
`default_nettype none
`timescale 1ns/1ns
```
Disable implicit nets and set the simulation time unit/precision to 1ns.

---

## A Note on Flattened Buses (Lines 17-19)

```systemverilog
// Per-consumer / per-channel buses are FLATTENED into packed vectors (consumer
// k's address = consumer_read_address[k*ADDR_BITS +: ADDR_BITS]).
```

Instead of unpacked arrays (`addr [N-1:0]`), the per-consumer signals are packed
into one wide vector. Consumer `k`'s slice is `[k*WIDTH +: WIDTH]`.

**Why?** Some simulators (including the Icarus Verilog used here) choke on
unpacked array *ports*. Flattening keeps the module portable. The `+:` operator
is an **indexed part-select**: `base +: width` means "`width` bits starting at
`base`", and crucially `base` may be a variable while `width` stays constant.

---

## Module Declaration (Lines 20-25)

```systemverilog
module controller #(
    parameter ADDR_BITS     = 8,
    parameter DATA_BITS     = 16,
    parameter NUM_CONSUMERS = 4,    // request channels coming in (>= 2)
    parameter NUM_CHANNELS  = 1     // physical memory channels going out
) (
```

| Parameter       | Default | Purpose                                          |
|-----------------|---------|--------------------------------------------------|
| `ADDR_BITS`     | 8       | Memory address width                             |
| `DATA_BITS`     | 16      | Memory word width (16 for program, 8 for data)   |
| `NUM_CONSUMERS` | 4       | How many requesters feed in (must be ≥ 2)        |
| `NUM_CHANNELS`  | 1       | How many physical memory ports go out            |

The `NUM_CONSUMERS : NUM_CHANNELS` ratio is the contention factor — more
consumers per channel means more serialization.

---

## Ports

### Consumer Side (Lines 29-37)

```systemverilog
input  wire [NUM_CONSUMERS-1:0]           consumer_read_valid,
input  wire [NUM_CONSUMERS*ADDR_BITS-1:0] consumer_read_address,
output reg  [NUM_CONSUMERS-1:0]           consumer_read_ready,
output reg  [NUM_CONSUMERS*DATA_BITS-1:0] consumer_read_data,
input  wire [NUM_CONSUMERS-1:0]           consumer_write_valid,
input  wire [NUM_CONSUMERS*ADDR_BITS-1:0] consumer_write_address,
input  wire [NUM_CONSUMERS*DATA_BITS-1:0] consumer_write_data,
output reg  [NUM_CONSUMERS-1:0]           consumer_write_ready,
```

This is `NUM_CONSUMERS` copies of a **valid/ready** handshake — the *memory* end
of the same handshake the fetcher and LSU drive. Each consumer asserts
`*_valid` and waits for the controller to assert its `*_ready`.

| `*_valid` bit | per-consumer scalar (one bit each)        |
|---------------|-------------------------------------------|
| `*_address`   | flattened: consumer `k` = `[k*ADDR_BITS +: ADDR_BITS]` |
| `*_data`      | flattened: consumer `k` = `[k*DATA_BITS +: DATA_BITS]` |

### Memory Side (Lines 39-47)

```systemverilog
output reg  [NUM_CHANNELS-1:0]            mem_read_valid,
output reg  [NUM_CHANNELS*ADDR_BITS-1:0]  mem_read_address,
input  wire [NUM_CHANNELS-1:0]            mem_read_ready,
input  wire [NUM_CHANNELS*DATA_BITS-1:0]  mem_read_data,
output reg  [NUM_CHANNELS-1:0]            mem_write_valid,
output reg  [NUM_CHANNELS*ADDR_BITS-1:0]  mem_write_address,
output reg  [NUM_CHANNELS*DATA_BITS-1:0]  mem_write_data,
input  wire [NUM_CHANNELS-1:0]            mem_write_ready
```

The *other* end: `NUM_CHANNELS` copies of the same handshake, now with the
controller playing the consumer role toward real memory.

---

## Internal State (Lines 50-71)

```systemverilog
localparam CONSUMER_IDX_BITS = $clog2(NUM_CONSUMERS);

localparam IDLE           = 3'b000,
           READ_WAITING   = 3'b001,
           WRITE_WAITING  = 3'b010,
           READ_RELAYING  = 3'b011,
           WRITE_RELAYING = 3'b100;

reg [2:0]                   channel_state    [NUM_CHANNELS-1:0];
reg [CONSUMER_IDX_BITS-1:0] current_consumer [NUM_CHANNELS-1:0];
reg [NUM_CONSUMERS-1:0]     consumer_busy;
```

| Signal             | Purpose                                                |
|--------------------|--------------------------------------------------------|
| `channel_state[]`  | the 5-state FSM, one per physical channel              |
| `current_consumer[]` | which consumer each channel is currently serving     |
| `consumer_busy`    | scoreboard — bit `k` set means consumer `k` is claimed |

**Internal unpacked arrays are fine** (`channel_state`, `current_consumer`) —
only *ports* needed flattening.

**The scoreboard matters for `NUM_CHANNELS > 1`:** it prevents two channels from
grabbing the same consumer in the same cycle. It is **blocking**-assigned (`=`)
so a claim made by channel 0 is visible to channel 1 *within the same clock
evaluation* (see Gotcha #4).

---

## The Always Block (Lines 73-159)

### Reset (Lines 74-87)

```systemverilog
if (reset) begin
    consumer_read_ready  <= {NUM_CONSUMERS{1'b0}};
    ...
    consumer_busy         = {NUM_CONSUMERS{1'b0}};
    for (c = 0; c < NUM_CHANNELS; c = c + 1) begin
        channel_state[c]    <= IDLE;
        current_consumer[c] <= {CONSUMER_IDX_BITS{1'b0}};
    end
end
```

Clears every ready/valid and parks all channels in IDLE.

---

### The Per-Channel Loop (Lines 89-90)

```systemverilog
for (c = 0; c < NUM_CHANNELS; c = c + 1) begin
    case (channel_state[c])
```

Each physical channel is an **independent FSM**, processed in turn each cycle.

---

### State: IDLE (Lines 91-118)

```systemverilog
found = 1'b0;
for (k = 0; k < NUM_CONSUMERS; k = k + 1) begin
    if (!found && !consumer_busy[k]) begin
        if (consumer_read_valid[k]) begin
            found                = 1'b1;
            consumer_busy[k]      = 1'b1;
            current_consumer[c]  <= k[CONSUMER_IDX_BITS-1:0];
            mem_read_valid[c]    <= 1'b1;
            mem_read_address[c*ADDR_BITS +: ADDR_BITS]
                <= consumer_read_address[k*ADDR_BITS +: ADDR_BITS];
            channel_state[c]     <= READ_WAITING;
        end else if (consumer_write_valid[k]) begin
            ... WRITE_WAITING ...
        end
    end
end
```

Scan consumers from index 0 up. The **`found` flag** makes the loop pick only the
*first* pending consumer (Verilog has no clean `break` here). On a match:
- claim it (`consumer_busy[k] = 1`),
- remember it (`current_consumer[c] <= k`),
- forward its request onto this channel's memory port,
- go to READ_WAITING or WRITE_WAITING.

**Reads win ties:** a consumer with both valid bits set is served as a read
first. (In practice a consumer asserts only one.)

---

### State: READ_WAITING (Lines 120-129)

```systemverilog
if (mem_read_ready[c]) begin
    mem_read_valid[c]                       <= 1'b0;
    consumer_read_ready[current_consumer[c]] <= 1'b1;
    consumer_read_data[current_consumer[c]*DATA_BITS +: DATA_BITS]
        <= mem_read_data[c*DATA_BITS +: DATA_BITS];
    channel_state[c]                        <= READ_RELAYING;
end
```

When memory answers: drop the memory request, raise the **consumer's** ready, and
copy the returned word into that consumer's data slice. Then go to RELAYING.

---

### State: WRITE_WAITING (Lines 131-137)

```systemverilog
if (mem_write_ready[c]) begin
    mem_write_valid[c]                        <= 1'b0;
    consumer_write_ready[current_consumer[c]] <= 1'b1;
    channel_state[c]                          <= WRITE_RELAYING;
end
```

Same shape as a read, but there is no data to relay back — just acknowledge.

---

### State: READ_RELAYING / WRITE_RELAYING (Lines 139-155)

```systemverilog
READ_RELAYING: begin
    if (!consumer_read_valid[current_consumer[c]]) begin
        consumer_busy[current_consumer[c]]       = 1'b0;
        consumer_read_ready[current_consumer[c]] <= 1'b0;
        channel_state[c]                         <= IDLE;
    end
end
```

**Hold** the response until the consumer drops its `*_valid` (its way of saying
"got it"). Then release the scoreboard bit, drop ready, and free the channel back
to IDLE. The write variant is identical with the write signals.

**Why wait for the consumer to drop valid?** It guarantees the consumer saw the
ready/data before the channel moves on — a clean four-phase handshake.

---

## Arbitration Timing (4 consumers, 1 channel)

```
consumer:   0    1    2    3      (all assert read_valid at once)
channel:   ─serve 0─▶─serve 1─▶─serve 2─▶─serve 3─▶ idle
                │        │        │        │
            relay→0   relay→1  relay→2  relay→3
                ▲        ▲        ▲        ▲
           c0 acks   c1 acks  c2 acks  c3 acks (drops its valid)
```

With one channel the requests are **serialized**; lowest index goes first. More
channels would serve that many consumers in parallel.

---

## Hardware Synthesized

```
   ┌──────────────────────── MEMORY CONTROLLER ────────────────────────┐
   │  consumer_*_valid ─▶┌───────────┐                                 │
   │  consumer_*_addr ──▶│ arbiter:  │── mem_*_valid ──────────────────┼─▶
   │  consumer_*_data ──▶│ pick      │── mem_*_address ────────────────┼─▶
   │                     │ lowest    │── mem_*_data ───────────────────┼─▶
   │  consumer_*_ready ◀─│ pending   │                                 │
   │  consumer_read_data◀│ via       │◀── mem_*_ready ─────────────────┼──
   │                     │ found+    │◀── mem_read_data ───────────────┼──
   │                     │ scoreboard│                                 │
   │  ┌───────────────┐  │           │   ┌──────────────────────────┐  │
   │  │ consumer_busy │◀▶│ per-chan  │◀─▶│ channel_state[] (5-state)│  │
   │  │ scoreboard    │  │  FSMs ×N  │   │ current_consumer[]       │  │
   │  └───────────────┘  └───────────┘   └──────────────────────────┘  │
   └────────────────────────────────────────────────────────────────────┘
```

---

## Common Gotchas

1. **Flattened buses, not arrays.** Index consumer `k` with
   `signal[k*WIDTH +: WIDTH]`, never `signal[k]` (that would grab a single bit).
   The `valid`/`ready` signals *are* per-bit, so those use `[k]`.

2. **`found` replaces `break`.** The IDLE scan keeps looping but only acts on the
   first eligible consumer. Drop the `!found` guard and a channel would try to
   serve every pending consumer at once.

3. **The four-phase handshake needs the consumer to drop valid.** A channel sits
   in RELAYING until `consumer_*_valid` goes low. A consumer that never
   de-asserts after getting its data will wedge that channel forever.

4. **`consumer_busy` is blocking-assigned on purpose.** With multiple channels in
   one cycle, channel 1 must see channel 0's claim immediately, so the scoreboard
   uses `=` (blocking) while the real registers use `<=` (non-blocking). This is
   the one place the two assignment styles are deliberately mixed.

5. **`NUM_CONSUMERS` must be ≥ 2.** `$clog2(1) = 0` would make
   `current_consumer` a `[-1:0]` (illegal) reg. With one consumer you would not
   need a controller anyway.

6. **Lowest-index priority is not fair.** Consumer 0 always wins ties. For a busy
   system this can starve high-index consumers; a real GPU would rotate priority
   (round-robin). Fine for this learning design.
