"""Database boundary for the interactive Difference Engine.

The module deliberately contains no finite-difference arithmetic. SQL Server
remains the model; Python sends commands and converts result sets to DataFrames.
"""

from __future__ import annotations

import os
import uuid
from contextlib import contextmanager
from typing import Iterator, Sequence

import pandas as pd
import pyodbc


DEFAULT_CONNECTION_STRING = (
    "DRIVER={ODBC Driver 17 for SQL Server};"
    "SERVER=localhost;"
    "DATABASE=difference_engine;"
    "Trusted_Connection=yes;"
    "Encrypt=no;"
    "TrustServerCertificate=yes;"
    "Connection Timeout=5;"
)


def connection_string() -> str:
    """Read an override without putting credentials in source control."""
    return os.getenv("DIFFERENCE_ENGINE_CONNECTION_STRING", DEFAULT_CONNECTION_STRING)


@contextmanager
def connect() -> Iterator[pyodbc.Connection]:
    connection = pyodbc.connect(connection_string(), autocommit=False)
    try:
        yield connection
    finally:
        connection.close()


def _frame(cursor: pyodbc.Cursor) -> pd.DataFrame:
    columns = [column[0] for column in cursor.description]
    return pd.DataFrame.from_records(cursor.fetchall(), columns=columns)


def check_connection() -> tuple[str, str]:
    with connect() as connection:
        cursor = connection.cursor()
        row = cursor.execute(
            "SELECT @@SERVERNAME, CAST(SERVERPROPERTY('ProductVersion') AS varchar(30))"
        ).fetchone()
    return str(row[0]), str(row[1])


def configurable_width_schema_ready() -> bool:
    """Confirm that script 12's procedure upgrade is currently deployed."""
    query = """
        SELECT CASE WHEN
            COL_LENGTH('dbo.DifferenceEngineRun','RegisterDigits') IS NOT NULL
            AND EXISTS
            (
                SELECT 1 FROM sys.parameters
                WHERE object_id=OBJECT_ID('dbo.CreateDifferenceEngineRun')
                  AND name='@RegisterDigits'
            )
            THEN 1 ELSE 0 END;
    """
    with connect() as connection:
        return bool(connection.cursor().execute(query).fetchval())


def create_run(
    name: str,
    degree: int,
    coefficients: Sequence[int],
    x0: int = 0,
    register_digits: int = 4,
) -> uuid.UUID:
    """Create an isolated BCD run and return its generated identifier."""
    if len(coefficients) != 8:
        raise ValueError("coefficients must contain A0 through A7")
    if register_digits not in (4, 8):
        raise ValueError("register_digits must be 4 or 8")

    run_id = uuid.uuid4()
    # The procedure accepts A7 down to A0; the UI stores the natural A0..A7 order.
    parameters = [str(run_id), name, degree, *reversed(coefficients), x0, register_digits]
    placeholders = ", ".join("?" for _ in parameters)
    with connect() as connection:
        connection.cursor().execute(
            f"EXEC dbo.CreateDifferenceEngineRun {placeholders}", *parameters
        )
        connection.commit()
    return run_id


def step_run(run_id: str | uuid.UUID, cranks: int, capture_logic: bool = True) -> None:
    with connect() as connection:
        connection.cursor().execute(
            "EXEC dbo.StepDifferenceEngineRun @RunID=?, @Cranks=?, @CaptureLogic=?",
            str(run_id),
            cranks,
            int(capture_logic),
        )
        connection.commit()


def delete_run(run_id: str | uuid.UUID) -> None:
    with connect() as connection:
        connection.cursor().execute(
            "EXEC dbo.DeleteDifferenceEngineRun @RunID=?", str(run_id)
        )
        connection.commit()


def list_runs() -> pd.DataFrame:
    query = """
        SELECT r.RunID, r.RunName, r.Degree, r.RegisterDigits, r.X0, r.CreatedAt,
               COALESCE(MAX(s.StepNo), 0) AS LastStep,
               COALESCE(MAX(s.X_Value), r.X0) AS LastX
        FROM dbo.DifferenceEngineRun AS r
        LEFT JOIN dbo.DifferenceEngineRunState AS s ON s.RunID = r.RunID
        GROUP BY r.RunID, r.RunName, r.Degree, r.RegisterDigits, r.X0, r.CreatedAt
        ORDER BY r.CreatedAt DESC, r.RunName;
    """
    with connect() as connection:
        return _frame(connection.cursor().execute(query))


def get_run(run_id: str | uuid.UUID) -> dict[str, object] | None:
    query = """
        SELECT RunID, RunName, Degree, RegisterDigits, X0, CreatedAt,
               A7, A6, A5, A4, A3, A2, A1, A0
        FROM dbo.DifferenceEngineRun WHERE RunID=?;
    """
    with connect() as connection:
        cursor = connection.cursor().execute(query, str(run_id))
        row = cursor.fetchone()
        if row is None:
            return None
        return dict(zip((column[0] for column in cursor.description), row, strict=True))


def get_history(run_id: str | uuid.UUID) -> pd.DataFrame:
    query = """
        SELECT s.StepNo, s.X_Value,
               dbo.Format_PackedBCD(s.R0,r.RegisterDigits) AS R0,
               dbo.Format_PackedBCD(s.R1,r.RegisterDigits) AS R1,
               dbo.Format_PackedBCD(s.R2,r.RegisterDigits) AS R2,
               dbo.Format_PackedBCD(s.R3,r.RegisterDigits) AS R3,
               dbo.Format_PackedBCD(s.R4,r.RegisterDigits) AS R4,
               dbo.Format_PackedBCD(s.R5,r.RegisterDigits) AS R5,
               dbo.Format_PackedBCD(s.R6,r.RegisterDigits) AS R6,
               dbo.Format_PackedBCD(s.R7,r.RegisterDigits) AS R7
        FROM dbo.DifferenceEngineRunState AS s
        INNER JOIN dbo.DifferenceEngineRun AS r ON r.RunID=s.RunID
        WHERE s.RunID=? ORDER BY s.StepNo;
    """
    with connect() as connection:
        return _frame(connection.cursor().execute(query, str(run_id)))


def get_logic_trace(run_id: str | uuid.UUID, step_no: int) -> pd.DataFrame:
    query = """
        SELECT DestinationRegister, DigitIndex, A_Digit, B_Digit, CarryIn,
               RawBinarySum, C4, S3, S2, S1, S0,
               Gate_S3_AND_S2, Gate_S3_AND_S1,
               CorrectionK, CorrectionAddend, CorrectedDigit, CarryOut
        FROM dbo.DifferenceEngineRunLogicTrace
        WHERE RunID=? AND SourceStepNo=?
        ORDER BY AdderIndex, DigitIndex;
    """
    with connect() as connection:
        return _frame(connection.cursor().execute(query, str(run_id), step_no))


def get_overflow_events(run_id: str | uuid.UUID) -> pd.DataFrame:
    """Return additions whose carry exceeded the configured register width.

    This is derived from saved states, so warnings remain available even when
    the user disables the more verbose digit-level logic trace.
    """
    query = """
        SELECT NextState.StepNo, NextState.X_Value,
               Pair.DestinationRegister,
               Pair.LeftValue, Pair.RightValue,
               Pair.LeftValue + Pair.RightValue AS AdderSum,
               (Pair.LeftValue + Pair.RightValue) % RunInfo.Modulus AS StoredValue
        FROM dbo.DifferenceEngineRunState AS PreviousState
        INNER JOIN dbo.DifferenceEngineRunState AS NextState
            ON NextState.RunID = PreviousState.RunID
           AND NextState.StepNo = PreviousState.StepNo + 1
        INNER JOIN
        (
            SELECT RunID,RegisterDigits,
                   CASE RegisterDigits WHEN 4 THEN 10000 ELSE 100000000 END AS Modulus
            FROM dbo.DifferenceEngineRun
        ) AS RunInfo ON RunInfo.RunID=PreviousState.RunID
        CROSS APPLY (VALUES
            ('R0', CONVERT(BIGINT,dbo.Format_PackedBCD(PreviousState.R0,RunInfo.RegisterDigits)), CONVERT(BIGINT,dbo.Format_PackedBCD(PreviousState.R1,RunInfo.RegisterDigits))),
            ('R1', CONVERT(BIGINT,dbo.Format_PackedBCD(PreviousState.R1,RunInfo.RegisterDigits)), CONVERT(BIGINT,dbo.Format_PackedBCD(PreviousState.R2,RunInfo.RegisterDigits))),
            ('R2', CONVERT(BIGINT,dbo.Format_PackedBCD(PreviousState.R2,RunInfo.RegisterDigits)), CONVERT(BIGINT,dbo.Format_PackedBCD(PreviousState.R3,RunInfo.RegisterDigits))),
            ('R3', CONVERT(BIGINT,dbo.Format_PackedBCD(PreviousState.R3,RunInfo.RegisterDigits)), CONVERT(BIGINT,dbo.Format_PackedBCD(PreviousState.R4,RunInfo.RegisterDigits))),
            ('R4', CONVERT(BIGINT,dbo.Format_PackedBCD(PreviousState.R4,RunInfo.RegisterDigits)), CONVERT(BIGINT,dbo.Format_PackedBCD(PreviousState.R5,RunInfo.RegisterDigits))),
            ('R5', CONVERT(BIGINT,dbo.Format_PackedBCD(PreviousState.R5,RunInfo.RegisterDigits)), CONVERT(BIGINT,dbo.Format_PackedBCD(PreviousState.R6,RunInfo.RegisterDigits))),
            ('R6', CONVERT(BIGINT,dbo.Format_PackedBCD(PreviousState.R6,RunInfo.RegisterDigits)), CONVERT(BIGINT,dbo.Format_PackedBCD(PreviousState.R7,RunInfo.RegisterDigits)))
        ) AS Pair(DestinationRegister, LeftValue, RightValue)
        WHERE PreviousState.RunID = ?
          AND Pair.LeftValue + Pair.RightValue >= RunInfo.Modulus
        ORDER BY NextState.StepNo, Pair.DestinationRegister;
    """
    with connect() as connection:
        return _frame(connection.cursor().execute(query, str(run_id)))


def _evaluate_polynomial(coefficients: Sequence[int], x_value: int) -> int:
    """Evaluate A0..A7 exactly using Python's arbitrary-precision integers."""
    result = 0
    for coefficient in reversed(coefficients):
        result = result * x_value + int(coefficient)
    return result


def get_reference_comparison(run_id: str | uuid.UUID) -> pd.DataFrame:
    """Compare unlimited mathematical values with the four-digit R0 register."""
    run = get_run(run_id)
    if run is None:
        return pd.DataFrame()

    coefficients = [int(run[f"A{power}"]) for power in range(8)]
    history = get_history(run_id)
    rows: list[dict[str, object]] = []
    for state in history.itertuples(index=False):
        exact = _evaluate_polynomial(coefficients, int(state.X_Value))
        hardware = int(state.R0)
        rows.append(
            {
                "StepNo": int(state.StepNo),
                "X_Value": int(state.X_Value),
                "ExactValue": exact,
                "HardwareValue": hardware,
                "Difference": exact - hardware,
                "Status": "matches" if exact == hardware else "diverged",
            }
        )
    return pd.DataFrame(rows)


def get_difference_triangle(run_id: str | uuid.UUID) -> pd.DataFrame:
    """Build the exact forward-difference triangle used during initialisation."""
    run = get_run(run_id)
    if run is None:
        return pd.DataFrame()

    x0 = int(run["X0"])
    coefficients = [int(run[f"A{power}"]) for power in range(8)]
    levels: list[list[int]] = [
        [_evaluate_polynomial(coefficients, x0 + offset) for offset in range(8)]
    ]
    for _ in range(1, 8):
        previous = levels[-1]
        levels.append(
            [previous[index + 1] - previous[index] for index in range(len(previous) - 1)]
        )

    rows: list[dict[str, object]] = []
    for sample_index in range(8):
        row: dict[str, object] = {"x": x0 + sample_index}
        for order in range(8):
            row[f"Δ{order}"] = (
                levels[order][sample_index]
                if sample_index < len(levels[order])
                else None
            )
        rows.append(row)
    return pd.DataFrame(rows)
