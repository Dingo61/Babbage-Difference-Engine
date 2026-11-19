/*
    Acceptance tests for milestones 2 through 4.

    This script stops with an error if any engine output differs from direct
    polynomial evaluation or if a documented validation rule is not enforced.
*/
USE difference_engine;
GO

SET NOCOUNT ON;
DECLARE @Failures TABLE
(
    TestName VARCHAR(80) NOT NULL,
    Details VARCHAR(300) NOT NULL
);

-- Test 10,000 distributed operand pairs, exercising every possible A value.
;WITH Numbers AS
(
    SELECT 0 AS N
    UNION ALL
    SELECT N + 1 FROM Numbers WHERE N < 9999
), BCDPairs AS
(
    SELECT N AS A, (N * 7919 + 123) % 10000 AS B
    FROM Numbers
)
INSERT @Failures (TestName, Details)
SELECT TOP (1)
    'Four-digit BCD addition',
    CONCAT(A, ' + ', B, ' returned ', Actual, '; expected ', Expected)
FROM BCDPairs
CROSS APPLY
(
    SELECT
        CONVERT(INT, dbo.Format_BCD4(dbo.Add_BCD_4Digit(
            dbo.Decimal_To_BCD4(A), dbo.Decimal_To_BCD4(B)))) AS Actual,
        (A + B) % 10000 AS Expected
) AS CheckValue
WHERE Actual <> Expected
OPTION (MAXRECURSION 0);

-- Higher coefficients set to zero must reproduce the familiar quadratic.
EXEC dbo.InitialiseDifferenceEngine7Binary
    @A2 = 1, @A1 = 1, @A0 = 1, @X0 = 0, @WordBits = 16;
EXEC dbo.StepDifferenceEngine7Binary @Cranks = 20;

INSERT @Failures (TestName, Details)
SELECT TOP (1)
    'Binary quadratic compatibility',
    CONCAT('x=', X_Value, ' returned ', R0,
           '; expected ', (X_Value * X_Value + X_Value + 1) % 65536)
FROM dbo.DifferenceEngine7Binary
WHERE R0 <> (X_Value * X_Value + X_Value + 1) % 65536
ORDER BY X_Value;

-- A genuine degree-seven polynomial verifies all eight registers are useful.
EXEC dbo.InitialiseDifferenceEngine7Binary @A7 = 1, @X0 = 0, @WordBits = 32;
EXEC dbo.StepDifferenceEngine7Binary @Cranks = 12;

INSERT @Failures (TestName, Details)
SELECT TOP (1)
    'Binary seventh order',
    CONCAT('x=', X_Value, ' returned ', R0,
           '; expected ', CONVERT(BIGINT, POWER(CONVERT(DECIMAL(38, 0), X_Value), 7)))
FROM dbo.DifferenceEngine7Binary
WHERE R0 <> CONVERT(BIGINT, POWER(CONVERT(DECIMAL(38, 0), X_Value), 7))
ORDER BY X_Value;

-- Repeat at eight bits to verify hardware-style overflow rather than only the
-- unbounded mathematical sequence.
EXEC dbo.InitialiseDifferenceEngine7Binary @A7 = 1, @X0 = 0, @WordBits = 8;
EXEC dbo.StepDifferenceEngine7Binary @Cranks = 20;

INSERT @Failures (TestName, Details)
SELECT TOP (1)
    'Binary modulo overflow',
    CONCAT('x=', X_Value, ' returned ', R0, '; expected ',
           CONVERT(BIGINT, POWER(CONVERT(DECIMAL(38, 0), X_Value), 7)) % 256)
FROM dbo.DifferenceEngine7Binary
WHERE R0 <> CONVERT(BIGINT,
    POWER(CONVERT(DECIMAL(38, 0), X_Value), 7)) % 256
ORDER BY X_Value;

-- The intermediate cubic model verifies all four packed-BCD registers.
EXEC dbo.InitialiseDifferenceEngine3BCD4 @A3 = 1, @X0 = 0;
EXEC dbo.StepDifferenceEngine3BCD4 @Cranks = 20;

INSERT @Failures (TestName, Details)
SELECT TOP (1)
    'Four-digit BCD cubic',
    CONCAT('x=', X_Value, ' returned ', dbo.Format_BCD4(R0),
           '; expected ', (X_Value * X_Value * X_Value) % 10000)
FROM dbo.DifferenceEngine3BCD4
WHERE CONVERT(INT, dbo.Format_BCD4(R0)) <>
      (X_Value * X_Value * X_Value) % 10000
ORDER BY X_Value;

-- Test the seventh-order falling factorial used by the tutorial demonstration.
EXEC dbo.InitialiseDifferenceEngine7BCD4
    @A7 = 1, @A6 = -21, @A5 = 175, @A4 = -735,
    @A3 = 1624, @A2 = -1764, @A1 = 720, @A0 = 0,
    @X0 = 0;
EXEC dbo.StepDifferenceEngine7BCD4 @Cranks = 20;

INSERT @Failures (TestName, Details)
SELECT TOP (1)
    'Four-digit BCD seventh order',
    CONCAT('x=', X_Value, ' returned ', dbo.Format_BCD4(R0),
           '; expected ',
           (X_Value * (X_Value-1) * (X_Value-2) * (X_Value-3) *
            (X_Value-4) * (X_Value-5) * (X_Value-6)) % 10000)
FROM dbo.DifferenceEngine7BCD4
WHERE CONVERT(INT, dbo.Format_BCD4(R0)) <>
      (X_Value * (X_Value-1) * (X_Value-2) * (X_Value-3) *
       (X_Value-4) * (X_Value-5) * (X_Value-6)) % 10000
ORDER BY X_Value;

-- Validation tests must fail for the documented reasons.
BEGIN TRY
    EXEC dbo.InitialiseDifferenceEngine7Binary @A0 = 0, @WordBits = 3;
    INSERT @Failures VALUES
        ('Binary width validation', 'WordBits=3 was accepted unexpectedly.');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 50100
        INSERT @Failures VALUES
            ('Binary width validation', CONCAT('Unexpected error ', ERROR_NUMBER(), ': ', ERROR_MESSAGE()));
END CATCH;

BEGIN TRY
    EXEC dbo.InitialiseDifferenceEngine7BCD4 @A7 = -1, @X0 = 0;
    INSERT @Failures VALUES
        ('Unsigned BCD validation', 'Negative initial differences were accepted unexpectedly.');
END TRY
BEGIN CATCH
    IF ERROR_NUMBER() <> 50300
        INSERT @Failures VALUES
            ('Unsigned BCD validation', CONCAT('Unexpected error ', ERROR_NUMBER(), ': ', ERROR_MESSAGE()));
END CATCH;

IF EXISTS (SELECT 1 FROM @Failures)
BEGIN
    SELECT TestName, Details FROM @Failures;
    THROW 50400, 'One or more Difference Engine acceptance tests failed.', 1;
END;

SELECT TestName, Result
FROM (VALUES
    ('Four-digit BCD addition (10,000 operand pairs)', 'PASS'),
    ('Binary quadratic compatibility', 'PASS'),
    ('Binary seventh-order evaluation', 'PASS'),
    ('Binary limited-width overflow', 'PASS'),
    ('Four-digit BCD cubic evaluation', 'PASS'),
    ('Four-digit BCD seventh-order evaluation', 'PASS'),
    ('Parameter validation', 'PASS')
) AS Results(TestName, Result);

-- Restore the principal demonstration states after destructive test initialisers.
EXEC dbo.InitialiseDifferenceEngine7Binary @A7 = 1, @X0 = 0, @WordBits = 32;
EXEC dbo.StepDifferenceEngine7Binary @Cranks = 8;
EXEC dbo.InitialiseDifferenceEngine3BCD4 @A3 = 1, @X0 = 0;
EXEC dbo.StepDifferenceEngine3BCD4 @Cranks = 10;
EXEC dbo.InitialiseDifferenceEngine7BCD4
    @A7 = 1, @A6 = -21, @A5 = 175, @A4 = -735,
    @A3 = 1624, @A2 = -1764, @A1 = 720, @A0 = 0,
    @X0 = 0;
EXEC dbo.StepDifferenceEngine7BCD4 @Cranks = 10;
GO
