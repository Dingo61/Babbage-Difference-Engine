# Modelling Babbage's Difference Engine with TTL Logic and SQL Server

> Working notes for a possible Medium article. The SQL is an architectural
> simulation of registers, adders, and clock phases—not an electrical simulator.

Charles Babbage's Difference Engine evaluates polynomial tables through finite
differences. It does not need general multiplication for each new table entry.
Once its difference columns have been loaded, repeated addition is enough.

This makes the machine an appealing bridge between Victorian mechanical
computing, 74-series digital logic, and a small state machine written in T-SQL.

## The mathematical idea

For a quadratic

\[
f(x)=ax^2+bx+c
\]

sampled at integer intervals, maintain three registers:

- `R0`: the current value, \(f(x)\)
- `R1`: the first forward difference, \(f(x+1)-f(x)\)
- `R2`: the second forward difference, which is the constant \(2a\)

At a chosen starting point \(x_0\), load:

\[
R_0=ax_0^2+bx_0+c
\]

\[
R_1=2ax_0+a+b
\]

\[
R_2=2a
\]

One complete step then performs the operations in this order:

\[
R_0 \leftarrow R_0+R_1
\]

\[
R_1 \leftarrow R_1+R_2
\]

The order matters: `R0` must use the old value of `R1`. Two clock phases are
one simple way to make that dependency visible.

For example, \(f(x)=x^2+x+1\) at \(x_0=0\) loads `R0=1`, `R1=2`, and
`R2=2`. Successive outputs are 3, 7, 13, 21, 31, and so on.

## A possible TTL/CMOS interpretation

Each difference column can be represented by a register feeding an adder. A
small quadratic demonstration might use:

- edge-triggered registers such as the 74LS273 or 74LS374;
- 74LS283 four-bit binary adders, cascaded when a wider word is needed;
- 74LS157 multiplexers to select setup values or adder feedback;
- a debounced manual clock and control logic for visible single-stepping; and
- LEDs or BCD-to-seven-segment drivers for display.

The adder is combinational: while register outputs remain stable, it continually
produces a candidate next value. A clock edge transfers that value into the
destination register.

### Binary or BCD?

An eight-bit binary version is the simpler circuit. Two cascaded 74LS283s form
an eight-bit adder, and a `TINYINT` is a convenient SQL representation of its
register. Discarding the final carry makes the value wrap modulo 256.

Packed binary-coded decimal (BCD) more closely resembles decimal wheels and is
easier to display. Each four-bit nibble represents one digit from 0 to 9. Values
from hexadecimal `A` through `F` are invalid BCD digits.

After adding one BCD digit with a binary adder, correction is required when the
binary adder produces a carry or its four-bit sum exceeds 9. The usual correction
condition is:

\[
K=C_4+(S_3S_2)+(S_3S_1)
\]

When \(K=1\), a second adder adds `0110` (decimal 6). The corrected four-bit
result is a decimal digit and `K` supplies the decimal carry to the next digit.

Important component-count correction: one corrected BCD digit normally needs
two 74LS283 adders—one for the initial sum and one for the add-six correction.
A two-digit BCD adder therefore needs four 74LS283 packages, not two, plus the
correction gates. A 74LS32 contains two-input OR gates; implementing the
three-term expression above requires two of its gates rather than a nonexistent
three-input gate.

## What the SQL model represents

The scripts deliberately model the system at register-transfer level:

| Hardware idea | T-SQL representation |
|---|---|
| Register outputs | Columns in the latest state row |
| Rising clock edge | Inserting the next state row |
| Binary adder | Integer addition followed by modulo 256 |
| BCD adder | `Add_BCD_2Digit`, `Add_BCD_4Digit`, or width-aware `Add_PackedBCD` |
| Setup multiplexer | Initialisation stored procedure parameters |
| Decimal display | `Format_BCD`, `Format_BCD4`, or width-aware `Format_PackedBCD` |
| Hand crank | Step procedure with `@Cranks` |

The introductory quadratic history retains both named phases. The expanded
engines record one atomic row per complete crank because all next-register
values are calculated from the same old state before the conceptual clock edge.

It is not a transistor-, gate-delay-, or signal-integrity simulation. It does
not model propagation delay, fan-out, voltage thresholds, switch bounce,
metastability, clock skew, power supply behaviour, or the internal mechanics of
Babbage's machine. Calling it an *IC-level simulation* would overstate its
fidelity; *register-transfer model inspired by TTL components* is more accurate.

## Running the tutorial

Create a SQL Server database named `difference_engine`, then run the numbered
scripts in order:

1. `1_hardware.sql` — quadratic eight-bit binary introduction.
2. `2_BCD_2Digit.sql` — two-digit packed-BCD addition.
3. `3_format_BCD.sql` — quadratic two-digit BCD engine.
4. `4_7th_Order_Binary.sql` — eight-register binary engine.
5. `5_Cubic_BCD_4Digit.sql` — four-digit BCD and cubic bridge.
6. `6_7th_Order_BCD_4Digit.sql` — four-digit seventh-order engine.
7. `7_Verification.sql` — arithmetic and polynomial acceptance tests.
8. `8_Logic_Signal_Model.sql` — correction gates and clock-edge traces.
9. `9_Logic_Verification.sql` — signal-level acceptance tests.
10. `10_Publication_Demo.sql` — compact result tables.
11. `11_Streamlit_Run_Model.sql` — isolated experiments using `RunID`.
12. `12_Configurable_BCD_Run_Model.sql` — configurable four/eight-digit runs.

Script 12 must remain the last database upgrade. Script 11 contains the older
four-digit procedure definitions; if it is rerun later, rerun script 12. This
upgrades the procedures without rebuilding tables or deleting experiments.

The examples use named parameters so the polynomial is visible at the call site:

```sql
-- f(x) = 2x^2 + 3x + 4, starting at x = 0
EXEC dbo.InitialiseDifferenceEngineBinary
    @A = 2,
    @B = 3,
    @C = 4,
    @X0 = 0;

EXEC dbo.StepDifferenceEngine @Cranks = 8;
```

The initial registers are calculated by the procedure. A reader no longer has
to derive and hard-code the differences before experimenting.

The BCD version uses the same interface:

```sql
EXEC dbo.InitialiseDifferenceEngineBCD
    @A = 2,
    @B = 3,
    @C = 4,
    @X0 = 0;

EXEC dbo.StepDifferenceEngine_BCD @Cranks = 8;
```

For clarity, the two-digit BCD initialiser accepts only initial register values
from 0 through 99. During stepping, the simulated two-digit hardware wraps at
100. Negative BCD values are not silently invented: they require a documented
representation such as a separate sign or ten's-complement arithmetic.

To run the interactive application, activate the project virtual environment,
install its dependencies, and start Streamlit:

```powershell
python -m pip install -r requirements.txt
streamlit run streamlit_app.py
```

The default connection uses local Windows authentication and ODBC Driver 17.
Set `DIFFERENCE_ENGINE_CONNECTION_STRING` to override it without editing source.

## Assumptions and limitations worth stating in the article

### The introductory model and expanded model differ

Scripts 1–3 use three registers and therefore evaluate quadratics. The expanded
models use eight registers and evaluate polynomials through degree seven. In
general, a degree-\(n\) polynomial needs \(n+1\) difference registers.

### Overflow changes the mathematical sequence

The introductory binary model wraps at 256 and the two-digit BCD model wraps at
100. Streamlit runs wrap at 10,000 in four-digit mode or 100,000,000 in
eight-digit mode. After any internal register wraps, later electronic results
can diverge from the exact polynomial even before `R0` itself shows an overflow.
The GUI therefore reports per-register overflow and separately compares exact
and limited-width results.

### Unsigned BCD is a deliberate restriction

Some coefficient and starting-point combinations produce negative values or
negative forward differences. The current BCD tutorial rejects those initial
states. A later article could introduce ten's-complement arithmetic and an
extra sign convention.

### Two phases are a teaching abstraction

For this quadratic recurrence, phase 1 updates `R0` from the old `R1`, and phase
2 then updates `R1`. Real Difference Engine mechanisms and practical TTL control
circuits have more detailed carry and timing behaviour. Higher-order machines
also need a more careful schedule than simply repeating these two statements.

### Clocking needs real hardware care

A raw push-button is not a clean clock. It can create several edges per press.
Use a debounce circuit or a suitable single-step clock. Avoid casually gating
clock signals with combinational logic; glitches and skew can produce unintended
register edges. A synchronous design with clock enables is preferable when the
chosen register family supports it.

### Logic-family compatibility is not automatic

“TTL/CMOS” should not imply that arbitrary LS-TTL and 4000-series CMOS parts can
be mixed directly. Supply voltage, logic thresholds, drive current, fan-out,
edge rate, and unused-input rules depend on the exact family. A 74HCT part is
often a more convenient CMOS companion to TTL-level signals, but every proposed
connection should be checked against its manufacturer datasheets.

### Display drivers have electrical requirements

The 74LS47 is intended for common-anode displays and has active-low,
open-collector segment outputs. Segment current-limiting resistors are required.
Pin numbers, resistor values, supply decoupling, and display current should be
verified against the exact parts selected rather than copied from an ASCII
sketch.

## Suggested logic-modelling progression

1. Demonstrate a single four-bit binary adder and register.
2. Cascade two adders and verify eight-bit carry and wrap-around.
3. Model and exhaustively test one corrected BCD digit.
4. Cascade four corrected digits and inspect decimal carry.
5. Add the cubic four-register bridge.
6. Expand to eight difference registers.
7. Cascade two four-digit groups for eight-digit operation.
8. Compare the exact polynomial, register history, and logic trace.

This progression makes each SQL layer a test oracle for the next. The trace is a
model of settled logic values, not a prediction of physical timing.

## Publication checklist

- Cite primary museum sources for historical claims about Babbage's engines.
- Cite manufacturer datasheets for component behaviour and pin assignments.
- Include one register-transfer block diagram rather than presenting an ASCII
  drawing as a construction-ready schematic.
- Clearly label the SQL as a conceptual register-transfer simulation.
- Show expected output for at least two different coefficient sets.
- Include an overflow demonstration and explain why it is correct for the chosen
  register width.
- Have register-transfer diagrams independently checked against the SQL model.

## Possible follow-up articles

- signed BCD using a documented complement convention;
- configurable widths beyond eight decimal digits;
- a set-based SQL implementation for mathematical table generation;
- a generic degree-\(n\) finite-difference engine; and
- an FPGA version whose timing and register-transfer logic can be synthesised.

## Expanded engine now implemented

The project now includes an eight-register binary model and an eight-register,
packed-BCD model with selectable four- or eight-digit registers:

- `4_7th_Order_Binary.sql` implements configurable 4-to-62-bit registers;
- `5_Cubic_BCD_4Digit.sql` introduces the wider BCD components through a cubic
  bridge model;
- `6_7th_Order_BCD_4Digit.sql` expands those components to all eight registers;
- `7_Verification.sql` compares the engines with direct polynomial evaluation;
- `8_Logic_Signal_Model.sql` exposes the settled signals inside all corrected
  BCD digit adders;
- `9_Logic_Verification.sql` verifies those traces over 10,000 operand pairs and
  complete eight-register clock edges;
- `10_Publication_Demo.sql` produces compact article-ready result tables;
- `11_Streamlit_Run_Model.sql` adds isolated saved experiments;
- `12_Configurable_BCD_Run_Model.sql` generalises those experiments to four or
  eight digits;
- `BUILD_PLAN.md` records milestone status and acceptance criteria; and
- `THEORETICAL_ELECTRONIC_DESIGN.md` explains the electronic Babbage thought
  experiment and its practical modelling boundary.

Unlike the earlier phase-by-phase quadratic demonstration, the expanded models
record one row per crank. All next-register values are calculated from the same
previous row, representing parallel combinational adders followed by one shared
edge-triggered register clock.

Four-digit runs generate 28 digit-level trace rows per crank: seven adders times
four digits. Eight-digit runs generate 56. Eight-digit packed BCD uses SQL
`BIGINT`; the earlier four-digit values remain valid after this widening.

## Streamlit tutorial and gotchas

### Choosing a register width

Use four digits when the goal is to make carry and overflow easy to observe.
Use eight digits when a polynomial's initial differences do not fit in four
digits or when a longer exact run is useful. Eight digits are modelled as two
cascaded four-digit groups with carry between them.

| Mode | Stored range | Modulus | Trace rows per crank |
|---|---:|---:|---:|
| 4 digits | `0000`–`9999` | 10,000 | 28 |
| 8 digits | `00000000`–`99999999` | 100,000,000 | 56 |

Existing experiments created before the width upgrade remain four-digit runs.
Width is selected when an experiment is created and is not changed afterward.

### Initialisation restrictions

The BCD engine is unsigned. Every initial difference `R0` through `R7` must be
non-negative and fit the selected width. A polynomial can have a positive
output but still be rejected because one of its higher differences is negative
or too large. Choose eight digits if size is the problem; changing width does
not solve negative differences.

For degrees 1–7, the selected degree's leading coefficient must be nonzero, and
coefficients above that degree must be zero. Presets populate these fields
correctly. Degree 0 may represent a constant, including zero.

### Cranks and the starting value

Initialisation records step 0 at `x0`. The starting value is already displayed;
after `N` cranks the engine is at `x0+N`. Euler's example therefore needs 39
cranks to show `k=1` through `k=40`, not 40 cranks.

### Overflow and exact values

An overflow event reports the sum seen by a particular packed-BCD adder. It is
not necessarily the unbounded polynomial value. Once any internal difference
register wraps, later register values are based on the wrapped state. The GUI's
exact-versus-electronic table is the authoritative way to find the first
divergence.

Disabling detailed logic capture saves trace rows, but overflow history is still
derived from consecutive register states. With capture enabled, storage grows by
28 rows per four-digit crank or 56 rows per eight-digit crank.

### Database upgrade order

Run scripts 1–12 in order and leave script 12 last. Accidentally rerunning script
11 restores its older four-digit stored procedures and causes the GUI error
`CreateDifferenceEngineRun has too many arguments specified`. Rerun script 12
to repair the procedures; tables and saved experiments do not need rebuilding.
The app now checks this condition at startup and gives a direct instruction.

### Saved experiments and sessions

Each experiment uses a `RunID`, so browser sessions do not overwrite one
another. The GUI's **Delete** button removes the active experiment. The SQL
options below are useful for bulk cleanup.

## Managing saved Streamlit experiments

The Streamlit interface can delete the active experiment with its **Delete**
button. Experiments can also be reviewed or removed directly from Visual Studio
Code, SQL Server Management Studio, or another T-SQL client.

First, review the saved experiments and copy any `RunID` that should be retained:

```sql
USE difference_engine;
GO

SELECT
    RunID,
    RunName,
    Degree,
    RegisterDigits,
    X0,
    CreatedAt,
    CreatedBy
FROM dbo.DifferenceEngineRun
ORDER BY CreatedAt DESC;
GO
```

Delete one experiment by its `RunID`:

```sql
EXEC dbo.DeleteDifferenceEngineRun
    @RunID = '00000000-0000-0000-0000-000000000000';
GO
```

Replace the example identifier with the `RunID` shown by the review query.

To delete every experiment except one that should be retained:

```sql
DELETE FROM dbo.DifferenceEngineRun
WHERE RunID <> '00000000-0000-0000-0000-000000000000';
GO
```

To delete every saved Streamlit experiment:

```sql
DELETE FROM dbo.DifferenceEngineRun;
GO
```

These operations are permanent. Deleting a row from `DifferenceEngineRun`
automatically deletes its register history and logic traces through the schema's
cascading foreign keys. The original tutorial tables and SQL objects are not
removed.

## Examples

The following examples form a useful progression from a simple quadratic to a
polynomial that exercises all eight difference registers. Coefficients not
listed in an example should be left at zero.

### Squares

The polynomial

\[
f(k)=k^2
\]

is the simplest demonstration of a quadratic difference engine. Its second
difference is the constant 2.

Enter:

- Degree: `2`
- Starting x: `0`
- `A2`: `1`
- `A1`: `0`
- `A0`: `0`

The output begins:

```text
0, 1, 4, 9, 16, 25, 36, 49, 64, 81, 100, ...
```

If the four-digit engine is advanced to \(k=100\), the mathematical result
10,000 appears as `0000`. This is correct for a four-digit register because the
carry beyond the thousands digit is discarded.

### Cubes

The polynomial

\[
f(k)=k^3
\]

introduces a fourth register. Its third difference is the constant
\(6=3!\).

Enter:

- Degree: `3`
- Starting x: `0`
- `A3`: `1`

The output begins:

```text
0, 1, 8, 27, 64, 125, 216, 343, 512, 729, 1000, ...
```

### Fourth powers

The polynomial

\[
f(k)=k^4
\]

has the constant fourth difference \(24=4!\).

Enter:

- Degree: `4`
- Starting x: `0`
- `A4`: `1`

The output begins:

```text
0, 1, 16, 81, 256, 625, 1296, 2401, 4096, 6561, ...
```

The next value, \(10^4=10{,}000\), wraps to `0000` in the four-digit model.

### A decimal carry test

The linear polynomial

\[
f(k)=99k+1
\]

is useful for inspecting carry propagation even though it requires only two
active registers.

Enter:

- Degree: `1`
- Starting x: `0`
- `A1`: `99`
- `A0`: `1`

The output begins:

```text
0001, 0100, 0199, 0298, 0397, 0496, ...
```

Select a clock edge in the logic inspector to see correction and carry signals
move from the ones digit into the tens and hundreds digits.

### Euler's prime-generating polynomial

Leonhard Euler studied the polynomial

\[
f(k)=k^2-k+41,
\]

which produces a prime number for every integer value of \(k\) from 1 through
40.

Enter:

- Experiment name: `Euler primes`
- Degree: `2`
- Starting x: `1`
- `A2`: `1`
- `A1`: `-1`
- `A0`: `41`

The initial state already displays \(f(1)=41\). Turn the crank 39 times to
finish at \(k=40\), giving 40 values in total:

```text
41, 43, 47, 53, 61, 71, 83, 97, 113, 131,
151, 173, 197, 223, 251, 281, 313, 347, 383, 421,
461, 503, 547, 593, 641, 691, 743, 797, 853, 911,
971, 1033, 1097, 1163, 1231, 1301, 1373, 1447, 1523, 1601
```

One more crank reaches \(k=41\), where the pattern ends:

\[
f(41)=41^2-41+41=1681=41^2.
\]

### Seventh powers with eight digits

The natural seventh-order polynomial

\[
f(k)=k^7
\]

cannot be loaded into the four-digit engine because two of its initial
differences exceed 9,999. Select the **8 digits** register width, which models
two cascaded four-digit BCD display modules.

Enter:

- Preset: `Seventh powers · k⁷ (eight digits)`
- Degree: `7`
- Register width: `8 digits`
- Starting x: `0`
- `A7`: `1`
- `A0` through `A6`: `0`

The initial register state is:

```text
R0 = 00000000    R4 = 00008400
R1 = 00000001    R5 = 00016800
R2 = 00000126    R6 = 00015120
R3 = 00001806    R7 = 00005040
```

The output remains exact through \(k=13\):

```text
13^7 = 62748517
```

At \(k=14\), the exact value exceeds eight digits and the engine wraps:

```text
Exact:   105413504
Stored:   05413504
```

The GUI reports the eight-digit overflow and identifies this as the first point
where the limited-width engine diverges from the exact polynomial.

### Seventh-order falling factorial

The following example exercises all eight difference registers:

\[
\begin{aligned}
f(k)
  &=k(k-1)(k-2)(k-3)(k-4)(k-5)(k-6)\\
  &=k^7-21k^6+175k^5-735k^4\\
  &\quad+1624k^3-1764k^2+720k.
\end{aligned}
\]

Enter:

- Degree: `7`
- Starting x: `0`
- `A7`: `1`
- `A6`: `-21`
- `A5`: `175`
- `A4`: `-735`
- `A3`: `1624`
- `A2`: `-1764`
- `A1`: `720`
- `A0`: `0`

At \(k=0\), all initial registers are zero except `R7`, which contains
\(5040=7!\). The nonzero seventh difference then propagates down through the
register chain:

```text
k = 0 through 6: 0000
k = 7:           5040
k = 8:           0320   (mathematical value 40,320)
k = 9:           1440   (mathematical value 181,440)
k = 10:          4800   (mathematical value 604,800)
```

This example demonstrates seventh-order operation, the constant highest
difference, propagation through all eight registers, and four-digit overflow.
