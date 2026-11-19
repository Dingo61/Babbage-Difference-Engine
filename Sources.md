# Source info for the study

## Components

A list for the 7400 Series IC is here: https://www.build-electronic-circuits.com/7400-series-integrated-circuits/



74LS283 - Full adder
A full adder is a combinational logic circuit that adds three single-bit binary inputs (A, B, and a Carry-In) to produce a two-bit binary output consisting of a Sum and a Carry-Out. The full adder evaluates all eight possible combinations of its three inputs. The Sum output behaves like a 3-input XOR gate (it goes HIGH when an odd number of inputs are HIGH), while the Carry-Out goes HIGH when at least two inputs are HIGH (majority logic).

| Carry-In (Cin) | Input A | Input B | Sum (S) | Carry-Out (Cout) | Decimal Equivalent |
| --- | --- | --- | --- | --- | --- |
| 0 | 0 | 0 | 0 | 0 | 0 + 0 + 0 = 0 |
| 0 | 0 | 1 | 1 | 0 | 0 + 0 + 1 = 1 |
| 0 | 1 | 0 | 1 | 0 | 0 + 1 + 0 = 1 |
| 0 | 1 | 1 | 0 | 1 | 0 + 1 + 1 = 2 |
| 1 | 0 | 0 | 1 | 0 | 1 + 0 + 0 = 1 |
| 1 | 0 | 1 | 0 | 1 | 1 + 0 + 1 = 2 |
| 1 | 1 | 0 | 0 | 1 | 1 + 1 + 0 = 2 |
| 1 | 1 | 1 | 1 | 1 | 1 + 1 + 1 = 3 |

https://electricalflux.com/learn-guides/full-adder-schematic-logic-gates-74ls283

https://www.build-electronic-circuits.com/7400-series-integrated-circuits/74hc08-74ls08/#7408-pinout
