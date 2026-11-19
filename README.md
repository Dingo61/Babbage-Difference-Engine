# Babbage Difference Engine in SQL Server

This project models a hypothetical electronic version of Charles Babbage's
Difference Engine using SQL Server state, binary words, packed BCD, combinational
adder signals, and edge-triggered register transfers.

The model supports polynomials through degree seven using eight difference
registers. It is a logic simulation, not an analogue electrical simulator.

## Requirements

- SQL Server 2022 or later; developed and tested on SQL Server 2025.
- A database named `difference_engine`.
- Permission to create tables, scalar/table-valued functions, and procedures.
- Python 3.14 or another version supported by the listed dependencies.

## Script order

Run the numbered scripts in order:

1. `1_hardware.sql` — quadratic eight-bit binary introduction.
2. `2_BCD_2Digit.sql` — two-digit BCD addition.
3. `3_format_BCD.sql` — quadratic two-digit BCD engine.
4. `4_7th_Order_Binary.sql` — configurable eight-register binary engine.
5. `5_Cubic_BCD_4Digit.sql` — four-digit BCD components and cubic bridge.
6. `6_7th_Order_BCD_4Digit.sql` — eight-register four-digit BCD engine.
7. `7_Verification.sql` — arithmetic and polynomial acceptance tests.
8. `8_Logic_Signal_Model.sql` — BCD gates, carries, and clock-edge traces.
9. `9_Logic_Verification.sql` — signal-level acceptance tests.
10. `10_Publication_Demo.sql` — compact article-ready demonstrations.
11. `11_Streamlit_Run_Model.sql` — isolated experiments for the GUI.
12. `12_Configurable_BCD_Run_Model.sql` — four/eight-digit GUI registers.

Script 12 must remain the final database upgrade. Rerunning script 11 afterward
restores its older four-digit procedure definitions; rerun script 12 to upgrade
them again. Existing experiment rows do not need to be rebuilt.

Every script contains tutorial comments. Run them in numeric order; scripts
1–10 reset their own demonstration state, while scripts 11–12 preserve isolated
Streamlit experiments unless an experiment is explicitly deleted.

## Interactive Streamlit application

Create and activate the project virtual environment, then install dependencies:

```powershell
python -m pip install -r requirements.txt
```

After running SQL scripts 1 through 12, start the application from the project
folder:

```powershell
streamlit run streamlit_app.py
```

The default connection uses local Windows authentication with ODBC Driver 17.
Override it without editing source by setting:

```powershell
$env:DIFFERENCE_ENGINE_CONNECTION_STRING = "your ODBC connection string"
```

Each experiment receives a `RunID`; one browser session no longer truncates or
overwrites another experiment's state.

The interface includes presets for squares, cubes, fourth powers, decimal carry,
Euler's prime polynomial, seventh powers, and the seventh-order falling
factorial. Each new experiment can use four or eight packed-BCD digits. It displays
the initial forward-difference triangle and compares the exact polynomial value
with the limited-width electronic result at every crank, identifying the first
point at which limited-width arithmetic diverges.

### Important usage notes

- Run script 12 last. If script 11 is rerun, rerun script 12 before refreshing
  Streamlit; no table rebuild is required.
- Existing runs created before the width upgrade remain four-digit runs.
- Four-digit registers store `0000`–`9999`; eight-digit registers store
  `00000000`–`99999999`.
- BCD initial differences must be non-negative and fit the selected width.
- The initial display is already the value at `x0`; `N` cranks ends at `x0+N`.
- Logic capture stores 28 rows per four-digit crank or 56 per eight-digit crank.
- Exact polynomial values can differ from the electronic state after any
  internal register overflows, not only after `R0` visibly wraps.

## Principal demonstrations

### Binary seventh order

`4_7th_Order_Binary.sql` demonstrates \(f(x)=x^7\). The constant seventh
difference is `5040`, or \(7!\).

### Four-digit BCD cubic bridge

`5_Cubic_BCD_4Digit.sql` demonstrates \(f(x)=x^3\), whose constant third
difference is `0006`.

### Four-digit BCD seventh order

The BCD model uses the falling factorial

\[
f(x)=x(x-1)(x-2)(x-3)(x-4)(x-5)(x-6).
\]

Its initial registers are zero except `R7=5040`. At `x=8`, the mathematical
result `40320` appears as `0320` because the four-digit engine wraps modulo
10,000. The thousands-digit carry remains visible in the signal trace.

### Eight-digit BCD seventh powers

The Streamlit preset `Seventh powers · k⁷ (eight digits)` demonstrates the
natural seventh-order polynomial. It remains exact through `13⁷=62748517`.
At `x=14`, the exact value `105413504` is stored as `05413504`, and the GUI
reports the first divergence and eight-digit overflow.

## Project documents

- `BUILD_PLAN.md` — milestones and recorded progress.
- `difference_engine_notes.md` — canonical user notes, tutorial, examples, and
  operational gotchas.
- `THEORETICAL_ELECTRONIC_DESIGN.md` — the electronic Babbage design premise.
- `ELECTRONIC_BUILD.md` — corrected logical schematics, four/eight-digit scaling,
  and physical implications.

## Modelling boundary

SQL can model Boolean signals, corrected decimal carry, multiplexed state,
clock ordering, overflow, and faults. It cannot credibly predict real voltage,
current, heat, propagation-delay variation, metastability, or signal integrity.
Those limitations are part of the model rather than omissions to hide.
