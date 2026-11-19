# Seventh-Order Difference Engine Build Plan

This document tracks the expansion from the existing quadratic demonstration to
an eight-register model capable of evaluating seventh-order polynomials.

Status values: `PLANNED`, `IN PROGRESS`, `BLOCKED`, or `COMPLETE`.

## Design decisions

- A degree-seven polynomial requires eight registers, `R0` through `R7`.
- Each crank uses the previous state of every register.
- The SQL implementation records one atomic row per complete crank.
- The theoretical electronic design is parallel: seven combinational adders
  feed eight edge-triggered registers sharing a clock.
- Polynomial order and register width remain separate design choices.
- The tutorial progresses from two digits to four digits; Streamlit runs can use
  four digits or two cascaded four-digit groups (eight digits).
- Signed BCD is deferred until an explicit representation is selected.

## Milestone 1 — Preserve and verify the quadratic baseline

**Status:** COMPLETE

Deliverables:

- [x] Parameterised binary quadratic initialisation.
- [x] Parameterised two-digit BCD initialisation.
- [x] Student-oriented comments and corrected hardware assumptions.
- [x] Live execution against SQL Server 2025.
- [x] Exhaustive two-digit BCD addition test.

Acceptance evidence:

- `x^2 + x + 1` produced `1, 3, 7, 13, 21, ...`.
- All 10,000 pairs of two-digit BCD operands passed.

## Milestone 2 — Generalised seventh-order binary engine

**Status:** COMPLETE

Deliverables:

- [x] Eight-register state table.
- [x] Initialiser accepting coefficients `A7` through `A0` and `X0`.
- [x] Automatic construction of the complete forward-difference table.
- [x] Configurable binary word width.
- [x] Parallel, previous-state crank operation.
- [x] Comments connecting each SQL operation to the proposed electronics.

Acceptance criteria:

- Quadratic coefficients still work when higher coefficients are zero.
- A known seventh-order polynomial matches direct evaluation before overflow.
- Limited-width results match direct evaluation modulo `2^word_bits`.
- Reinitialisation and invalid-parameter paths behave predictably.

## Milestone 3 — Cubic four-digit BCD bridge

**Status:** COMPLETE

Purpose: introduce the wider BCD word and one additional difference slice before
constructing all eight columns.

Deliverables:

- [x] Four-digit packed-BCD adder and formatter.
- [x] Four-register cubic state model.
- [x] Distributed test covering 10,000 four-digit operand pairs.
- [x] Component count for one four-digit difference slice.

Acceptance criteria:

- Cubic output matches direct evaluation modulo 10,000.
- Invalid BCD nibbles are detected.

## Milestone 4 — Seventh-order four-digit BCD engine

**Status:** COMPLETE

Deliverables:

- [x] Eight four-digit BCD registers.
- [x] Seven parallel BCD additions per crank.
- [x] Coefficient-driven difference initialisation.
- [x] Overflow/carry behaviour explicitly documented.
- [x] Direct-polynomial verification queries.

Acceptance criteria:

- Results match direct evaluation modulo 10,000 for tested polynomials.
- Initial negative or out-of-range differences are rejected clearly.
- Each stored register contains valid packed BCD.

## Milestone 5 — Theoretical electronic architecture and logic signals

**Status:** COMPLETE

The electronics are a conceptual architecture for the SQL model. A physical
build is not a project requirement.

Deliverables:

- [x] Reusable difference-slice definition.
- [x] Preliminary component implications and scaling limits.
- [x] Per-digit BCD adder signal trace.
- [x] Seven-adder combinational signal inspection.
- [x] Explicit clock-edge and old-state/new-state trace.
- [x] Conceptual register-transfer block diagram.
- [x] Error, overflow, and carry signalling model.

Acceptance criteria:

- Every SQL register and operation maps to a named theoretical hardware block.
- BCD correction signals agree with the arithmetic functions for tested inputs.
- The design uses simultaneous register updates or documented shadow storage.
- Electrical effects that SQL does not model are stated explicitly.

## Milestone 6 — Publication package

**Status:** IN PROGRESS

Deliverables:

- [ ] Single-command repeatable installation script.
- [x] Compact repeatable publication demonstration script.
- [x] Expected result tables for quadratic, cubic, and seventh-order examples.
- [x] Article-ready explanation of finite-difference initialisation.
- [x] Clear distinction between Babbage's mechanism and the electronic thought experiment.
- [ ] Register-transfer diagrams independently reviewed before publication.

## Milestone 7 — Interactive Streamlit model

**Status:** IN PROGRESS

Deliverables:

- [x] Project-local Python dependency set.
- [x] Run-isolated SQL tables and procedures using `RunID`.
- [x] Coefficient, degree, and starting-point form.
- [x] Single, ten, and configurable crank controls.
- [x] Eight-register display and result history.
- [x] Polynomial output chart.
- [x] Per-clock, per-adder logic inspector.
- [x] Saved experiment selection and deletion.
- [x] Python/SQL integration smoke test.
- [x] Streamlit application render test.
- [x] Difference-triangle visualisation.
- [x] Exact mathematical result versus configured-width electronic comparison.
- [x] Persistent, width-aware per-register overflow warnings.
- [x] Built-in example presets.
- [x] Configurable four- and eight-digit packed-BCD register widths.
- [x] Width-aware overflow, formatting, comparison, and logic traces.
- [ ] Automated Streamlit interaction tests.

## Progress log

| Date | Milestone | Progress |
|---|---|---|
| 2026-11-19 | 1 | Quadratic binary and BCD scripts corrected and verified on SQL Server 2025. |
| 2026-11-19 | 2 | Eight-register binary engine implemented; `x^7`, quadratic compatibility, and word-width overflow tests passed. |
| 2026-11-19 | 3 | Four-digit BCD functions and cubic bridge implemented; `x^3` and 10,000 BCD additions passed. |
| 2026-11-19 | 4 | Eight-register BCD engine implemented; seventh-order falling-factorial test passed modulo 10,000. |
| 2026-11-19 | 5 | Reframed as a theoretical electronic design. Preliminary package implications documented; signal-level SQL model started. |
| 2026-11-19 | 5 | Digit-level correction gates, seven-adder traces, carry signals, and atomic clock edges implemented and verified. |
| 2026-11-19 | 6 | Reader run order and publication demonstration preparation started. |
| 2026-11-19 | 6 | Compact demo verified: x^7, x^3, seventh-order BCD overflow, and internal BCD correction trace. |
| 2026-11-19 | 7 | Streamlit MVP and isolated-run SQL layer implemented; connection, crank, trace, deletion, and render smoke tests passed. |
| 2026-11-19 | 7 | Added persistent overflow banners, register indicators, and an event history that works with or without detailed signal capture. |
| 2026-11-19 | 7 | Added exact-versus-hardware comparison, first-divergence reporting, the initial difference triangle, and six example presets. |
| 2026-11-19 | 7 | Generalised Streamlit runs to four or eight BCD digits; verified legacy 28-row and expanded 56-row logic traces plus natural k^7 evaluation. |
