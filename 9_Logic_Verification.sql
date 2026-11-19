/* Acceptance tests for the digit-level theoretical logic model. */
USE difference_engine;
GO

SET NOCOUNT ON;
DECLARE @Failures TABLE
    (TestName VARCHAR(80) NOT NULL, Details VARCHAR(300) NOT NULL);

-- Reconstruct the packed result from four corrected output digits for 10,000
-- distributed input pairs, then compare it with the established BCD function.
;WITH Numbers AS
(
    SELECT 0 AS N
    UNION ALL SELECT N + 1 FROM Numbers WHERE N < 9999
), Pairs AS
(
    SELECT N AS A, (N * 7919 + 123) % 10000 AS B FROM Numbers
), Traced AS
(
    SELECT Pair.A, Pair.B,
           COUNT(*) AS SignalRows,
           SUM(CONVERT(INT, Signal.IsValidBCD)) AS ValidRows,
           SUM(CONVERT(INT, Signal.CorrectedDigit) *
               CASE Signal.DigitIndex
                   WHEN 0 THEN 1 WHEN 1 THEN 16
                   WHEN 2 THEN 256 ELSE 4096 END) AS PackedResult
    FROM Pairs AS Pair
    CROSS APPLY dbo.Trace_BCD4_Add(
        dbo.Decimal_To_BCD4(Pair.A), dbo.Decimal_To_BCD4(Pair.B)) AS Signal
    GROUP BY Pair.A, Pair.B
)
INSERT @Failures
SELECT TOP (1) 'Digit-level signal reconstruction',
       CONCAT(A, ' + ', B, ' produced ', PackedResult,
              ' from ', SignalRows, ' rows; expected packed ',
              dbo.Add_BCD_4Digit(dbo.Decimal_To_BCD4(A), dbo.Decimal_To_BCD4(B)))
FROM Traced
WHERE SignalRows <> 4 OR ValidRows <> 4
   OR PackedResult <> dbo.Add_BCD_4Digit(
        dbo.Decimal_To_BCD4(A), dbo.Decimal_To_BCD4(B))
OPTION (MAXRECURSION 0);

-- Capture eight complete clock edges through the seventh-order demonstration.
EXEC dbo.InitialiseDifferenceEngine7BCD4
    @A7 = 1, @A6 = -21, @A5 = 175, @A4 = -735,
    @A3 = 1624, @A2 = -1764, @A1 = 720, @A0 = 0, @X0 = 0;
TRUNCATE TABLE dbo.DifferenceEngine7BCD4LogicTrace;
EXEC dbo.StepDifferenceEngine7BCD4_WithLogicTrace @Cranks = 8;

IF (SELECT COUNT(*) FROM dbo.DifferenceEngine7BCD4LogicTrace) <> 224
    INSERT @Failures VALUES
        ('Seven-adder trace size', 'Eight clocks did not produce 8 x 7 x 4 = 224 signal rows.');

IF EXISTS
(
    SELECT SourceStepID
    FROM dbo.DifferenceEngine7BCD4LogicTrace
    GROUP BY SourceStepID
    HAVING COUNT(*) <> 28
)
    INSERT @Failures VALUES
        ('Per-clock trace size', 'At least one clock did not contain 28 digit paths.');

-- Rebuild every adder output from its traced corrected digits and compare it
-- with the same source state's established arithmetic function.
;WITH Rebuilt AS
(
    SELECT SourceStepID, AdderIndex,
           SUM(CONVERT(INT, CorrectedDigit) *
               CASE DigitIndex WHEN 0 THEN 1 WHEN 1 THEN 16
                               WHEN 2 THEN 256 ELSE 4096 END) AS PackedResult
    FROM dbo.DifferenceEngine7BCD4LogicTrace
    GROUP BY SourceStepID, AdderIndex
), Expected AS
(
    SELECT Rebuilt.SourceStepID, Rebuilt.AdderIndex, Rebuilt.PackedResult,
           dbo.Add_BCD_4Digit(
               CASE Rebuilt.AdderIndex
                   WHEN 0 THEN State.R0 WHEN 1 THEN State.R1
                   WHEN 2 THEN State.R2 WHEN 3 THEN State.R3
                   WHEN 4 THEN State.R4 WHEN 5 THEN State.R5 ELSE State.R6 END,
               CASE Rebuilt.AdderIndex
                   WHEN 0 THEN State.R1 WHEN 1 THEN State.R2
                   WHEN 2 THEN State.R3 WHEN 3 THEN State.R4
                   WHEN 4 THEN State.R5 WHEN 5 THEN State.R6 ELSE State.R7 END
           ) AS ExpectedResult
    FROM Rebuilt
    INNER JOIN dbo.DifferenceEngine7BCD4 AS State
        ON State.StepID = Rebuilt.SourceStepID
)
INSERT @Failures
SELECT TOP (1) 'Seven-adder signal agreement',
       CONCAT('Step ', SourceStepID, ', adder ', AdderIndex,
              ' rebuilt ', PackedResult, '; expected ', ExpectedResult)
FROM Expected
WHERE PackedResult <> ExpectedResult;

IF NOT EXISTS
(
    SELECT 1 FROM dbo.DifferenceEngine7BCD4
    WHERE X_Value = 8 AND dbo.Format_BCD4(R0) = '0320'
)
    INSERT @Failures VALUES
        ('Traced clock state', 'Expected R0=0320 at x=8 was not recorded.');

IF EXISTS (SELECT 1 FROM @Failures)
BEGIN
    SELECT TestName, Details FROM @Failures;
    THROW 50600, 'One or more logic-signal acceptance tests failed.', 1;
END;

SELECT TestName, Result
FROM (VALUES
    ('Digit-level signal reconstruction (10,000 pairs)', 'PASS'),
    ('Seven adders x four digits per clock', 'PASS'),
    ('Traced signals agree with packed-BCD arithmetic', 'PASS'),
    ('Clock-edge state agrees with seventh-order sequence', 'PASS')
) AS Results(TestName, Result);

-- Extend the restored demonstration to the same x=10 endpoint as other scripts.
EXEC dbo.StepDifferenceEngine7BCD4_WithLogicTrace @Cranks = 2;
GO
