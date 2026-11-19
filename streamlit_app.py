"""Interactive front end for the SQL Server Difference Engine model."""

from __future__ import annotations

import uuid

import pandas as pd
import pyodbc
import streamlit as st

import data_access as db


PRESETS: dict[str, dict[str, object] | None] = {
    "Custom": None,
    "Squares · k²": {
        "name": "Squares",
        "degree": 2,
        "x0": 0,
        "coefficients": [0, 0, 1, 0, 0, 0, 0, 0],
    },
    "Cubes · k³": {
        "name": "Cubes",
        "degree": 3,
        "x0": 0,
        "coefficients": [0, 0, 0, 1, 0, 0, 0, 0],
    },
    "Fourth powers · k⁴": {
        "name": "Fourth powers",
        "degree": 4,
        "x0": 0,
        "coefficients": [0, 0, 0, 0, 1, 0, 0, 0],
    },
    "Decimal carry · 99k + 1": {
        "name": "Decimal carry test",
        "degree": 1,
        "x0": 0,
        "coefficients": [1, 99, 0, 0, 0, 0, 0, 0],
    },
    "Euler primes · k² − k + 41": {
        "name": "Euler primes",
        "degree": 2,
        "x0": 1,
        "coefficients": [41, -1, 1, 0, 0, 0, 0, 0],
    },
    "Seventh-order falling factorial": {
        "name": "Seventh-order falling factorial",
        "degree": 7,
        "x0": 0,
        "coefficients": [0, 720, -1764, 1624, -735, 175, -21, 1],
    },
    "Seventh powers · k⁷ (eight digits)": {
        "name": "Seventh powers",
        "degree": 7,
        "x0": 0,
        "digits": 8,
        "coefficients": [0, 0, 0, 0, 0, 0, 0, 1],
    },
}


st.set_page_config(
    page_title="Electronic Difference Engine",
    page_icon="⚙️",
    layout="wide",
)


def friendly_database_error(error: pyodbc.Error) -> str:
    text = " ".join(str(part) for part in error.args)
    # SQL Server messages follow the driver prefix; keep the useful final text.
    return text.rsplit("]", maxsplit=1)[-1].strip() or text


@st.cache_data(ttl=3)
def cached_runs() -> pd.DataFrame:
    return db.list_runs()


def select_run(run_id: uuid.UUID | str) -> None:
    st.session_state.active_run_id = str(run_id)
    cached_runs.clear()


def load_selected_preset() -> None:
    preset = PRESETS.get(st.session_state.preset_name)
    if preset is None:
        return
    st.session_state.form_run_name = preset["name"]
    st.session_state.form_degree = preset["degree"]
    st.session_state.form_x0 = preset["x0"]
    st.session_state.form_register_digits = preset.get("digits", 4)
    for power, coefficient in enumerate(preset["coefficients"]):
        st.session_state[f"form_a{power}"] = coefficient


if "form_degree" not in st.session_state:
    st.session_state.preset_name = "Euler primes · k² − k + 41"
    load_selected_preset()


st.title("Babbage's Electronic Difference Engine")
st.caption(
    "An eight-register, seventh-order packed-BCD logic model running in SQL Server."
)

try:
    server_name, server_version = db.check_connection()
except pyodbc.Error as error:
    st.error(f"SQL Server is unavailable: {friendly_database_error(error)}")
    st.stop()

if not db.configurable_width_schema_ready():
    st.error(
        "The database has an older CreateDifferenceEngineRun procedure. "
        "Run 12_Configurable_BCD_Run_Model.sql, then refresh this page."
    )
    st.stop()

with st.sidebar:
    st.success(f"Connected to {server_name}")
    st.caption(f"SQL Server {server_version}")
    st.header("Saved experiments")
    runs = cached_runs()
    if runs.empty:
        st.info("Create the first experiment below.")
    else:
        labels = {
            str(row.RunID): f"{row.RunName} · degree {row.Degree} · step {row.LastStep}"
            for row in runs.itertuples()
        }
        known_ids = list(labels)
        current = st.session_state.get("active_run_id")
        index = known_ids.index(current) if current in known_ids else 0
        chosen = st.selectbox(
            "Experiment", known_ids, index=index, format_func=labels.get
        )
        if chosen != current:
            select_run(chosen)


with st.expander(
    "Create an experiment", expanded=not bool(st.session_state.get("active_run_id"))
):
    st.selectbox(
        "Example preset",
        options=list(PRESETS),
        key="preset_name",
        on_change=load_selected_preset,
        help="Choose Custom to retain values while editing your own polynomial.",
    )
    degree = st.selectbox(
        "Polynomial degree",
        range(8),
        key="form_degree",
        help="Changing the degree enables the corresponding coefficient fields.",
    )
    register_digits = st.radio(
        "Register width",
        options=[4, 8],
        format_func=lambda digits: f"{digits} digits",
        horizontal=True,
        key="form_register_digits",
        help="Eight digits model two cascaded four-digit BCD display modules.",
    )
    with st.form("create_run"):
        name_col, x_col = st.columns([2, 1])
        run_name = name_col.text_input("Experiment name", key="form_run_name")
        x0 = x_col.number_input("Starting x", step=1, key="form_x0")

        st.markdown("#### Coefficients")
        coefficient_columns = st.columns(4)
        coefficients: list[int] = []
        for power in range(8):
            disabled = power > degree
            coefficient = coefficient_columns[power % 4].number_input(
                f"A{power} · x^{power}",
                step=1,
                disabled=disabled,
                key=f"form_a{power}",
            )
            coefficients.append(0 if disabled else int(coefficient))

        submitted = st.form_submit_button("Initialise new run", type="primary")
        if submitted:
            try:
                new_run_id = db.create_run(
                    run_name, degree, coefficients, int(x0), register_digits
                )
            except (pyodbc.Error, ValueError) as error:
                message = (
                    friendly_database_error(error)
                    if isinstance(error, pyodbc.Error)
                    else str(error)
                )
                st.error(message)
            else:
                select_run(new_run_id)
                st.rerun()


active_run_id = st.session_state.get("active_run_id")
if not active_run_id:
    st.info("Create an experiment to load the eight difference registers.")
    st.stop()

run = db.get_run(active_run_id)
if run is None:
    st.session_state.pop("active_run_id", None)
    cached_runs.clear()
    st.warning("The selected experiment no longer exists.")
    st.rerun()

st.subheader(str(run["RunName"]))
coefficient_text = " + ".join(
    f"{int(run[f'A{power}'])}x^{power}" for power in range(int(run["Degree"]), -1, -1)
)
st.caption(
    f"f(x) = {coefficient_text} · starting at x = {run['X0']} · "
    f"{run['RegisterDigits']}-digit packed BCD"
)

control_1, control_10, control_custom, logic_col, delete_col = st.columns(
    [1, 1, 2, 2, 1]
)
capture_logic = logic_col.toggle("Capture logic signals", value=True)
custom_cranks = control_custom.number_input("Cranks", 1, 1000, 25)

try:
    if control_1.button("One crank", type="primary", width="stretch"):
        db.step_run(active_run_id, 1, capture_logic)
        cached_runs.clear()
        st.rerun()
    if control_10.button("Ten cranks", width="stretch"):
        db.step_run(active_run_id, 10, capture_logic)
        cached_runs.clear()
        st.rerun()
    if control_custom.button("Run selected", width="stretch"):
        db.step_run(active_run_id, int(custom_cranks), capture_logic)
        cached_runs.clear()
        st.rerun()
except pyodbc.Error as error:
    st.error(friendly_database_error(error))

if delete_col.button("Delete", type="secondary", width="stretch"):
    db.delete_run(active_run_id)
    st.session_state.pop("active_run_id", None)
    cached_runs.clear()
    st.rerun()

history = db.get_history(active_run_id)
latest = history.iloc[-1]
overflow_events = db.get_overflow_events(active_run_id)
comparison = db.get_reference_comparison(active_run_id)
triangle = db.get_difference_triangle(active_run_id)
latest_overflows = (
    overflow_events[overflow_events["StepNo"] == int(latest["StepNo"])]
    if not overflow_events.empty
    else overflow_events
)

if not latest_overflows.empty:
    affected = ", ".join(latest_overflows["DestinationRegister"].astype(str))
    st.warning(
        f"{run['RegisterDigits']}-digit overflow on the latest crank in {affected}. "
        "The carry beyond the most-significant digit was discarded."
    )

divergent = comparison[comparison["Status"] == "diverged"]
if divergent.empty:
    st.success(
        f"The four-digit engine matches the exact polynomial through "
        f"x = {int(latest['X_Value'])}."
    )
else:
    first_divergence = divergent.iloc[0]
    current_comparison = comparison.iloc[-1]
    st.warning(
        f"The limited-width engine first diverged at x = "
        f"{int(first_divergence['X_Value'])}. At the current step the exact "
        f"value is {current_comparison['ExactValue']:,}, while R0 stores "
        f"{int(current_comparison['HardwareValue']):0{int(run['RegisterDigits'])}d}."
    )

with st.expander("Initial forward-difference triangle"):
    st.caption(
        "The first row contains the exact values loaded into R0 through R7. "
        "Blank cells lie outside the triangular difference table."
    )
    st.dataframe(triangle, width="stretch", hide_index=True)

st.markdown("### Register bank")
for group_start in (0, 4):
    register_columns = st.columns(4)
    for offset, column in enumerate(register_columns):
        register = group_start + offset
        label = "f(x)" if register == 0 else f"Δ{register}"
        register_name = f"R{register}"
        overflowed = (
            not latest_overflows.empty
            and register_name in latest_overflows["DestinationRegister"].values
        )
        column.metric(
            f"{register_name} · {label}",
            latest[register_name],
            delta="overflow" if overflowed else None,
            delta_color="inverse" if overflowed else "normal",
        )

if not overflow_events.empty:
    with st.expander(
        f"Overflow history · {len(overflow_events)} event(s)",
        expanded=not latest_overflows.empty,
    ):
        st.caption(
            f"BCD adder sums beyond {10 ** int(run['RegisterDigits']) - 1:,} "
            f"wrap modulo {10 ** int(run['RegisterDigits']):,}. Earlier "
            "register overflow may already have separated "
            "this value from the unbounded polynomial result."
        )
        st.dataframe(overflow_events, width="stretch", hide_index=True)

st.markdown("### Generated table")
chart_data = comparison[["X_Value", "ExactValue", "HardwareValue"]].copy()
largest_magnitude = max(abs(int(value)) for value in chart_data["ExactValue"])
if largest_magnitude <= 10**15:
    chart_data["Exact polynomial"] = chart_data["ExactValue"].astype(float)
    chart_data[f"{run['RegisterDigits']}-digit R0"] = chart_data[
        "HardwareValue"
    ].astype(float)
    st.line_chart(
        chart_data.set_index("X_Value")[
            ["Exact polynomial", f"{run['RegisterDigits']}-digit R0"]
        ]
    )
else:
    st.info("Exact values are too large for a useful floating-point chart.")

comparison_display = comparison.copy()
comparison_display["ExactValue"] = comparison_display["ExactValue"].map(
    lambda value: f"{int(value):,}"
)
comparison_display["HardwareValue"] = comparison_display["HardwareValue"].map(
    lambda value: f"{int(value):0{int(run['RegisterDigits'])}d}"
)
comparison_display["Difference"] = comparison_display["Difference"].map(
    lambda value: f"{int(value):,}"
)
st.dataframe(comparison_display, width="stretch", hide_index=True)

with st.expander("All difference registers"):
    st.dataframe(history, width="stretch", hide_index=True)

st.markdown("### Logic inspector")
trace_steps = list(range(max(0, int(latest["StepNo"]))))
if not trace_steps:
    st.info("Turn the crank with logic capture enabled to inspect adder signals.")
else:
    selected_step = st.select_slider(
        "State before clock edge", options=trace_steps, value=trace_steps[-1]
    )
    trace = db.get_logic_trace(active_run_id, selected_step)
    if trace.empty:
        st.info("No logic signals were captured for this clock edge.")
    else:
        destination = st.selectbox(
            "Adder destination", trace["DestinationRegister"].unique()
        )
        st.dataframe(
            trace[trace["DestinationRegister"] == destination],
            width="stretch",
            hide_index=True,
        )
