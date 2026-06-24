# RS(15,11) Encoder — SystemVerilog

A fully verified, synthesizable Reed-Solomon encoder core implemented in SystemVerilog.

- **Code:** RS(15,11) systematic code over GF(16)
- **Field polynomial:** p(x) = x⁴ + x + 1
- **Generator polynomial:** g(x) = x⁴ + 15x³ + 3x² + x + 12
- **Error correction capability:** t = 2 symbol errors per codeword
- **Interface:** AXI-stream-style valid/ready handshake on both input and output

---

## Features

- Systematic encoding — data symbols pass through unchanged, 4 parity symbols appended
- Valid/ready backpressure on both input and output sides
- Asynchronous active-low reset
- Single-cycle-per-symbol throughput (no latency bubble between data and parity phases)
- Pure combinational GF multipliers — dedicated XOR logic, zero lookup tables
- Synthesizable on any FPGA family (no vendor primitives)

---

## Directory Structure

```
.
├── rtl/
│   └── rs_encoder.sv        # RTL implementation
├── verif/
│   └── tb_rs_encoder.sv     # Self-checking testbench (4 test scenarios)
├── doc/
│   └── rs_encoder_design.md # Design specification (Chinese, detailed)
└── README.md
```

---

## Interface

| Signal        | Dir | Width | Description                                                            |
|---------------|-----|-------|------------------------------------------------------------------------|
| `clk`         | in  | 1     | Clock — rising-edge sampling                                           |
| `rst_n`       | in  | 1     | Asynchronous active-low reset                                          |
| `start`       | in  | 1     | Pulse high on the same cycle as the first `din` symbol of a new codeword |
| `din`         | in  | 4     | Input data symbol (GF(16), MSB = x³)                                  |
| `din_valid`   | in  | 1     | `din` is valid this cycle                                              |
| `din_ready`   | out | 1     | Encoder can accept `din` — handshake fires when both are high          |
| `dout`        | out | 4     | Output symbol (data pass-through, then parity)                         |
| `dout_valid`  | out | 1     | `dout` is valid this cycle                                             |
| `dout_ready`  | in  | 1     | Downstream ready — backpressure applies to both data and parity phases |
| `parity_phase`| out | 1     | High during the 4 parity output cycles                                 |

### Handshake Rules

- **Data phase:** `din_ready = dout_ready`. Input and output are coupled — a downstream stall freezes the LFSR and blocks the input simultaneously.
- **Parity phase:** `din_ready = 0`. No input is accepted; the 4 parity symbols are shifted out one per accepted cycle.
- A transfer is committed when `valid & ready` are both high on the rising clock edge.

---

## Architecture

```
             fb = din XOR R3   (data phase)
             │
┌──[×12]─────┤    ┌──[×1]────┐   ┌──[×3]────┐   ┌──[×15]───┐
▼            │    ▼           │   ▼           │   ▼          │
[R0]        (⊕)  [R1]        (⊕) [R2]        (⊕) [R3]     ──┘ feedback / output tap
```

### FSM

```
IDLE ──(start)──▶ DATA ──(11th symbol accepted)──▶ PARITY ──(4th parity accepted)──▶ IDLE
```

| State    | `din_ready`   | `dout` source | `parity_phase` |
|----------|--------------|---------------|----------------|
| `IDLE`   | 0            | —             | 0              |
| `DATA`   | `dout_ready` | `din`         | 0              |
| `PARITY` | 0            | `lfsr[3]`     | 1              |

### GF(16) Constant Multipliers

All multipliers are dedicated XOR networks (p(x) = x⁴+x+1 baked in). Bit convention: `a[0]` = LSB = x⁰ coefficient.

```
×1  : o = a                              (wire)

×3  : o[3] = a[2]^a[3]
      o[2] = a[1]^a[2]
      o[1] = a[0]^a[1]^a[3]
      o[0] = a[0]^a[3]

×12 : o[3] = a[0]^a[1]^a[3]
      o[2] = a[0]^a[2]
      o[1] = a[1]^a[3]
      o[0] = a[1]^a[2]

×15 : o[3] = a[0]^a[1]^a[2]
      o[2] = a[0]^a[1]
      o[1] = a[0]
      o[0] = a[0]^a[1]^a[2]^a[3]
```

---

## Golden Vector

For input symbols `1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11` (with `start` asserted on symbol 1):

```
Output: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,  3,  3, 12, 12
        |<------- 11 data (pass-through) -------->|<-- parity -->|
```

---



### Expected Output

```
--- TEST1: basic golden vector ---
[...] OK  dout=1 (exp_idx=0)
...
>>> TEST1 basic PASSED (15/15 symbols)

--- TEST2: backpressure (dout_ready toggling) ---
>>> TEST2 backpressure PASSED (15/15 symbols)

--- TEST3: back-to-back two codewords ---
>>> TEST3 back-to-back x2 PASSED (30/30 symbols)

--- TEST4: reset mid-operation then recover ---
>>> TEST4 reset-recovery PASSED (15/15 symbols)

======== SUMMARY ========
ALL TESTS PASSED
```

---

## Test Coverage

| Test | Scenario | Checks |
|------|----------|--------|
| TEST1 | Basic golden vector | All 15 output symbols match expected |
| TEST2 | Backpressure — `dout_ready` toggles every cycle | Symbols preserved across stalls; no symbol dropped |
| TEST3 | Back-to-back two codewords | LFSR clears between codewords; both codewords correct |
| TEST4 | Async reset mid-operation + recovery | White-box: `lfsr`, `sym_cnt`, `state` all zero after reset; full codeword correct after release |

---

## Parameters

| Parameter | Default | Description              |
|-----------|---------|--------------------------|
| `SYM_W`   | 4       | Symbol width in bits — fixed at 4 for GF(16) |

The code is written for RS(15,11)/GF(16). Scaling to a larger code (e.g., RS(254,250)/GF(2¹⁰) for DisplayPort FEC) requires changing `SYM_W`, the generator polynomial coefficients, and the GF multiplier logic.

---

## License

MIT License. See [LICENSE](LICENSE).

---

## Author

H'ng Kean Teong  
Junior IC Digital Design Engineer
