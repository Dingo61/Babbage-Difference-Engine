# If Babbage Had Electronic Logic

This is a design thought experiment: how might the Difference Engine's visible,
decimal, repeated structure translate into electronic logic? It does not claim
that Charles Babbage would necessarily have selected these exact components.

## Principles retained from the mechanical engine

- Decimal columns remain visible rather than being hidden behind a general CPU.
- Finite differences remain the algorithm; multiplication is used only while
  preparing the initial state in SQL.
- Each order of difference is a repeated, inspectable module.
- One deliberate crank event advances the whole mathematical state.
- Carries and overflow are observable events, not silent implementation details.
- A table of results is the product, so output and auditability matter.

## Electronic reinterpretation

Each decimal difference column becomes an edge-triggered register. The outputs
of adjacent registers feed a corrected BCD adder. A setup/run multiplexer selects
either initial data or the settled adder output. A common clock edge transfers
the selected values into all registers simultaneously.

```text
 Ri.Q ───────────┐  ┌───────────────┐
                 ├─>│ corrected BCD │── Run data ──┐
 R(i+1).Q ───────┘  │     adder     │              │
                    └───────────────┘              ▼
 Setup data ───────────────────────────────> [setup/run mux] ──> Ri.D
                                                                  │
 Common crank clock ─────────────────────────────────────────────>│CLK
                                                             [Ri register]
```

This architecture preserves the essential rule that every new difference uses
the complete previous state. It avoids extending the quadratic demonstration's
two named phases into an incorrect odd/even update scheme.

The current Streamlit model offers four digits (`0000`–`9999`) or eight digits
(`00000000`–`99999999`). Eight digits are treated as two cascaded four-digit
groups with carry between them. The conceptual architecture is otherwise the
same; only the word width and carry-chain length change.

## Hypothetical control panel

A conceptual operator's panel could expose:

- setup/run mode;
- coefficient or initial-difference loading;
- manual single crank and automatic clock modes;
- current `R0` result and selectable internal difference columns;
- carry-out and overflow indicators;
- invalid-BCD and uninitialised-state indicators; and
- a step counter corresponding to the tabulated value of `x`.

The SQL procedures play the role of this control system. Initialisation derives
and loads the difference columns; a step procedure generates a clock event; and
the history table provides the inspection and printed record.

One crank produces 28 settled digit paths in four-digit mode or 56 in
eight-digit mode: seven adjacent-register adders multiplied by the selected
number of decimal digits.

## Why model signals below the register level?

The register-transfer model proves the recurrence but hides how decimal carry is
formed. The next SQL layer exposes, for every BCD digit:

- operand nibbles and carry-in;
- initial four-bit binary sum and `C4`;
- sum bits `S3..S0`;
- correction terms `S3·S2` and `S3·S1`;
- correction signal `K`;
- corrected digit and decimal carry-out.

That is far enough down to connect the mathematics to recognizable TTL logic,
while stopping short of transistor voltages and propagation physics that SQL is
not suited to simulate.

## Practical boundary of the SQL model

The model can reasonably cover:

- Boolean and bitwise logic;
- combinational adder and BCD correction signals;
- carry propagation between decimal digits;
- register state before and after a clock edge;
- setup/run multiplexing;
- finite word width and overflow;
- invalid-state detection;
- deterministic fault injection; and
- timing as an abstract ordered sequence of events.

It should not pretend to predict:

- actual nanosecond propagation delays;
- glitches caused by unequal physical paths;
- metastability probabilities;
- voltage thresholds, current, heat, or power-supply noise;
- breadboard capacitance or wiring inductance; or
- whether a particular collection of real ICs would meet timing.

Those limitations should remain visible in any published article so the model is
described accurately as a logic and state simulation.
