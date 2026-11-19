/*
    Stage 3: connect the packed-BCD adder to three simulated registers.
    Run 2_BCD_2Digit.sql first because this script calls Add_BCD_2Digit.
*/
USE difference_engine;
GO

-- Format a packed byte as the two characters a pair of displays would show.
CREATE OR ALTER FUNCTION dbo.Format_BCD (@BCD TINYINT)
RETURNS CHAR(2)
AS
BEGIN
    IF @BCD IS NULL RETURN NULL;
    DECLARE @Ones TINYINT = @BCD & 15;
    DECLARE @Tens TINYINT = (@BCD / 16) & 15;
    IF @Ones > 9 OR @Tens > 9 RETURN '??';
    RETURN CHAR(ASCII('0') + @Tens) + CHAR(ASCII('0') + @Ones);
END;
GO

IF OBJECT_ID(N'dbo.DifferenceEngineBCD', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DifferenceEngineBCD
    (
        StepID       INT IDENTITY(1, 1) NOT NULL
            CONSTRAINT PK_DifferenceEngineBCD PRIMARY KEY,
        CrankPhase   VARCHAR(15) NOT NULL,
        R0_PackedBCD TINYINT NOT NULL, -- Current f(x)
        R1_PackedBCD TINYINT NOT NULL, -- First forward difference
        R2_PackedBCD TINYINT NOT NULL  -- Constant second difference
    );
END;
GO

/*
    Load a quadratic f(x) = a*x^2 + b*x + c at x0. This tutorial accepts
    only initial values 0..99. Negative BCD needs a separate sign convention.
*/
CREATE OR ALTER PROCEDURE dbo.InitialiseDifferenceEngineBCD
    @A INT = 1, @B INT = 1, @C INT = 1, @X0 INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @R0_Math DECIMAL(38, 0) =
        CONVERT(DECIMAL(38, 0), @A) * @X0 * @X0
        + CONVERT(DECIMAL(38, 0), @B) * @X0 + @C;
    DECLARE @R1_Math DECIMAL(38, 0) =
        CONVERT(DECIMAL(38, 0), 2) * @A * @X0 + @A + @B;
    DECLARE @R2_Math DECIMAL(38, 0) = CONVERT(DECIMAL(38, 0), 2) * @A;

    IF @R0_Math NOT BETWEEN 0 AND 99
       OR @R1_Math NOT BETWEEN 0 AND 99
       OR @R2_Math NOT BETWEEN 0 AND 99
        THROW 50010,
            'Initial R0, R1, and R2 must each be 0..99 for unsigned two-digit BCD.',
            1;

    -- Convert ordinary decimal to packed BCD: for example, 42 becomes 0x42.
    -- FLOOR is important because these source values are DECIMAL, so division
    -- by 10 would otherwise retain a fractional part rather than truncate it.
    DECLARE @R0 TINYINT = CONVERT(TINYINT,
        FLOOR(@R0_Math / 10) * 16 + @R0_Math % 10);
    DECLARE @R1 TINYINT = CONVERT(TINYINT,
        FLOOR(@R1_Math / 10) * 16 + @R1_Math % 10);
    DECLARE @R2 TINYINT = CONVERT(TINYINT,
        FLOOR(@R2_Math / 10) * 16 + @R2_Math % 10);

    BEGIN TRANSACTION;
        DELETE FROM dbo.DifferenceEngineBCD;
        DBCC CHECKIDENT ('dbo.DifferenceEngineBCD', RESEED, 0) WITH NO_INFOMSGS;
        INSERT dbo.DifferenceEngineBCD
            (CrankPhase, R0_PackedBCD, R1_PackedBCD, R2_PackedBCD)
        VALUES ('INIT (Load)', @R0, @R1, @R2);
    COMMIT TRANSACTION;
END;
GO

-- Advance the engine by one or more complete two-phase crank cycles.
CREATE OR ALTER PROCEDURE dbo.StepDifferenceEngine_BCD @Cranks INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Cranks < 1
        THROW 50011, 'The number of crank cycles must be at least 1.', 1;

    DECLARE @R0 TINYINT, @R1 TINYINT, @R2 TINYINT;
    DECLARE @Crank INT = 0;

    BEGIN TRANSACTION;
        SELECT TOP (1)
            @R0 = R0_PackedBCD, @R1 = R1_PackedBCD, @R2 = R2_PackedBCD
        FROM dbo.DifferenceEngineBCD WITH (UPDLOCK, HOLDLOCK)
        ORDER BY StepID DESC;

        IF @R0 IS NULL
            THROW 50012, 'Initialise the BCD engine before turning the crank.', 1;

        WHILE @Crank < @Cranks
        BEGIN
            -- Phase 1 uses the old first difference.
            SET @R0 = dbo.Add_BCD_2Digit(@R0, @R1);
            IF @R0 IS NULL
                THROW 50013, 'The BCD adder received invalid packed BCD.', 1;
            INSERT dbo.DifferenceEngineBCD
                (CrankPhase, R0_PackedBCD, R1_PackedBCD, R2_PackedBCD)
            VALUES ('Phase 1 (Even)', @R0, @R1, @R2);

            -- Phase 2 prepares the first difference for the next cycle.
            SET @R1 = dbo.Add_BCD_2Digit(@R1, @R2);
            IF @R1 IS NULL
                THROW 50014, 'The BCD adder received invalid packed BCD.', 1;
            INSERT dbo.DifferenceEngineBCD
                (CrankPhase, R0_PackedBCD, R1_PackedBCD, R2_PackedBCD)
            VALUES ('Phase 2 (Odd)', @R0, @R1, @R2);

            SET @Crank += 1;
        END;
    COMMIT TRANSACTION;
END;
GO

-- Tutorial example. Change any coefficient or the starting x value here.
EXEC dbo.InitialiseDifferenceEngineBCD @A = 1, @B = 1, @C = 1, @X0 = 0;
EXEC dbo.StepDifferenceEngine_BCD @Cranks = 10;

SELECT
    StepID, CrankPhase,
    dbo.Format_BCD(R0_PackedBCD) AS [R0_Display (f(x))],
    dbo.Format_BCD(R1_PackedBCD) AS [R1_Display (Delta1)],
    dbo.Format_BCD(R2_PackedBCD) AS [R2_Display (Delta2)]
FROM dbo.DifferenceEngineBCD
ORDER BY StepID;
GO
