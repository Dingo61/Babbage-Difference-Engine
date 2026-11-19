/*
    Compact demonstrations intended for screenshots or article result tables.
    Prerequisite: run scripts 1 through 9 first.
*/
USE difference_engine;
GO
SET NOCOUNT ON;

PRINT 'DEMO 1: Eight-register binary engine evaluating f(x) = x^7';
EXEC dbo.InitialiseDifferenceEngine7Binary @A7 = 1, @X0 = 0, @WordBits = 32;
EXEC dbo.StepDifferenceEngine7Binary @Cranks = 8;

SELECT X_Value AS x, R0 AS [f(x)], R7 AS [constant seventh difference]
FROM dbo.DifferenceEngine7Binary
ORDER BY X_Value;

PRINT 'DEMO 2: Four-register BCD bridge evaluating f(x) = x^3';
EXEC dbo.InitialiseDifferenceEngine3BCD4 @A3 = 1, @X0 = 0;
EXEC dbo.StepDifferenceEngine3BCD4 @Cranks = 10;

SELECT X_Value AS x,
       dbo.Format_BCD4(R0) AS [f(x)],
       dbo.Format_BCD4(R3) AS [constant third difference]
FROM dbo.DifferenceEngine3BCD4
ORDER BY X_Value;

PRINT 'DEMO 3: Seventh-order BCD falling factorial';
EXEC dbo.InitialiseDifferenceEngine7BCD4
    @A7 = 1, @A6 = -21, @A5 = 175, @A4 = -735,
    @A3 = 1624, @A2 = -1764, @A1 = 720, @A0 = 0, @X0 = 0;
TRUNCATE TABLE dbo.DifferenceEngine7BCD4LogicTrace;
EXEC dbo.StepDifferenceEngine7BCD4_WithLogicTrace @Cranks = 10;

SELECT X_Value AS x,
       dbo.Format_BCD4(R0) AS [four-digit f(x)],
       dbo.Format_BCD4(R7) AS [constant seventh difference]
FROM dbo.DifferenceEngine7BCD4
ORDER BY X_Value;

PRINT 'DEMO 4: A carry-correction event inside one theoretical BCD adder';
-- Trace 0099 + 0001. Ones produces 10, is corrected to 0, and carries into tens.
SELECT DigitName, A_Digit, B_Digit, CarryIn, RawBinarySum,
       C4, S3, S2, S1, S0,
       Gate_S3_AND_S2, Gate_S3_AND_S1,
       CorrectionK, CorrectionAddend, CorrectedDigit, CarryOut
FROM dbo.Trace_BCD4_Add(0x0099, 0x0001)
ORDER BY DigitIndex;
GO
