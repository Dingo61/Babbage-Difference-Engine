# Theoretical Electronic Architecture

This document maps the tested SQL register-transfer model to a hypothetical
electronic Difference Engine. It is a logic and scaling document, not a
construction-ready schematic. The deliverable is the SQL Server model.

The Streamlit engine supports either four decimal digits or eight decimal
digits. Eight digits represent two cascaded four-digit display/adder modules.

## Corrected difference-slice schematic

Registers `R0` through `R6` each use one adjacent difference register as an
adder input. Setup data and the settled adder output meet at a setup/run
multiplexer before the destination register:

```text
                               final decimal carry ──> overflow indicator
                                                     (not stored)
 Ri.Q ──────────────── A ┌───────────────────────────┐
                         │ corrected packed-BCD adder├── Run data ──┐
 R(i+1).Q ─────────── B └───────────────────────────┘              │
                                                                   ▼
 Setup switches / loader ─────────────────────────────────> ┌────────────┐
                                                           │ setup/run  │
 Setup mode ───────────────────────────────────────────────>│ multiplexer├──> Ri.D
                                                           └────────────┘
                                                                            │
 Common crank clock ────────────────────────────────────────────────────────>│CLK
                                                                       ┌────▼────┐
                                                                       │ register│
                                                                       └────┬────┘
                                                                            └──> Ri.Q
```

All destination registers latch on the same conceptual clock edge. Every adder
therefore reads the complete old state. `R7` is constant: in run mode its Q
output feeds its D input instead of passing through another adder.

The diagram shows logical connectivity only. It omits exact pins, buffers,
power, decoupling, timing, and electrical loading.

## One corrected BCD digit

For each decimal digit, the model assumes:

- one 74LS283 for `A + B + carry-in`;
- correction detection
  \(K=C_4+(S_3S_2)+(S_3S_1)\);
- two two-input AND gates for `S3·S2` and `S3·S1`;
- two two-input OR gates to combine the three correction terms; and
- a second 74LS283 that adds `0110` when `K=1`.

`K` is also the decimal carry into the next digit. The SQL signal trace exposes
`C4`, `S3..S0`, both AND terms, `K`, the correction addend, corrected digit, and
carry-out.

## Four- and eight-digit modules

All five integrated circuits in your BCD adder and register build use Low-Power Schottky TTL (74LS) logic, divided into combinational and sequential functions.
Here is the updated build table including the Logic Family (electrical technology) and Circuit Logic Type (functional behavior) for each IC component:


| Function / Component | Logic Family | Circuit Logic Type | Four digits | Eight digits |
|---|---|---|---:|---:|
| Decimal digits | — | — | 4 | 8 |
| Data bits per register | — | — | 16 | 32 |
| **74LS283** packages per complete adder (4-bit Binary Full Adder) | TTL (Low-Power Schottky) | **Combinational** (Arithmetic) | 8 | 16 |
| **74LS08** packages per complete adder (Quad 2-Input AND Gate) | TTL (Low-Power Schottky) | **Combinational** (Basic Gate) | 2 | 4 |
| **74LS32** packages per complete adder (Quad 2-Input OR Gate) | TTL (Low-Power Schottky) | **Combinational** (Basic Gate) | 2 | 4 |
| **74LS273** packages per register (Octal D-Type Flip-Flop w/ Clear) | TTL (Low-Power Schottky) | **Sequential** (Edge-Triggered Memory) | 2 | 4 |
| **74LS157** packages per register loader (Quad 2-to-1 Multiplexer) | TTL (Low-Power Schottky) | **Combinational** (Data Routing) | 4 | 8 |
| Signal-trace rows per seven-adder crank | — | — | 28 | 56 |
| Stored numeric range | — | — | 0000–9999 | 00000000–99999999 |



Component Breakdown by Logic Role

### Combinational Logic (Output depends only on current inputs):

74LS283, 74LS08, and 74LS32:
Work together to perform Binary-Coded Decimal (BCD) addition. The first stage adds two 4-bit BCD digits, while the AND/OR gates detect sums greater than 9 to trigger a "+6" correction in the second adder stage.

74LS157:
Acts as a digital switch to route either new external input data or the output of your adder back into the register inputs.

### Sequential Logic (Output depends on clock edges and stored state):

74LS273:
Captures and holds the 4-bit BCD values on the rising edge of your clock signal, acting as the memory register between adder cycles.

The decimal carry ripples from the least-significant digit to the
most-significant digit. Carry beyond digit 4 or digit 8 is reported as overflow
and discarded from the stored word.

## Full parallel eight-register estimate

The following package counts illustrate scale only:

| Function | Four-digit engine | Eight-digit engine |
|---|---:|---:|
| 74LS283 | 56 | 112 |
| 74LS08 | 14 | 28 |
| 74LS32 | 14 | 28 |
| 74LS273 | 16 | 32 |
| 74LS157 | 32 | 64 |

Displaying every difference register would require 32 decimal displays and
drivers in four-digit mode or 64 in eight-digit mode. Displaying only `R0`
would require four or eight respectively.

These figures exclude clock conditioning, overflow indicators, buffers, power
distribution, connectors, and test points. They are not a bill of materials.

## Staged logic modelling

### Model A — Correct one decimal digit

Test every valid pair of decimal digits and carry-in. Verify that the Boolean
correction signal agrees with the packed-BCD arithmetic.

### Model B — Cascade four digits

Verify long carries such as `0099 + 0001` and overflow such as
`9999 + 0001`. This is implemented by `Add_BCD_4Digit` and the signal trace.

### Model C — Cubic register bank

Load the `x³` differences `0000`, `0001`, `0006`, `0006`. Three adders and four
registers demonstrate simultaneous state transfer before all eight columns are
introduced.

### Model D — Eight difference registers

Add `R4` through `R7`. The four-digit falling-factorial example starts with
every register zero except `R7=5040`; after seven clocks `R0=5040`.

### Model E — Cascade to eight digits

Model two four-digit groups with carry between them. The natural `k⁷` example
then loads successfully:

```text
R0=00000000  R1=00000001  R2=00000126  R3=00001806
R4=00008400  R5=00016800  R6=00015120  R7=00005040
```

It remains exact through `13⁷=62748517`; `14⁷=105413504` overflows and is
stored as `05413504`.

## Physical implications and limitations

If the theoretical design were translated into hardware, it would still need:

- an exact logic-family and supply-voltage selection;
- manufacturer datasheets and verified pin assignments;
- DC fan-out and display loading calculations;
- worst-case carry-chain propagation-delay analysis;
- clock setup/hold margin;
- decoupling and power-distribution design;
- defined states for unused inputs; and
- mechanical, PCB, connector, and test arrangements.

SQL Server does not reproduce voltage thresholds, propagation-delay variation,
glitches, metastability, switch bounce, fan-out failure, power integrity,
temperature, or manufacturing variation. It models settled Boolean signals,
carry order, finite-width overflow, illegal BCD, and atomic register transfer.

Any package counts or diagrams in this project are explanatory consequences of
the chosen register-transfer architecture. They are reasoned design
speculation—not historical claims about Babbage and not validated schematics.
