/*
    Stage 1: an 8-bit binary model of a three-column Difference Engine

    The example models a quadratic polynomial: f(x) = a*x^2 + b*x + c.
    Registers are TINYINT values, so results wrap modulo 256 just as an
    eight-bit register does when its carry-out is ignored.
*/
USE difference_engine;
GO

-- Each row records the register outputs after one clock phase.
IF OBJECT_ID(N'dbo.DifferenceEngineState', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DifferenceEngineState
    (
        StepID     INT IDENTITY(1, 1) NOT NULL
            CONSTRAINT PK_DifferenceEngineState PRIMARY KEY,
        CrankPhase VARCHAR(15) NOT NULL,
        R0_Value   TINYINT NOT NULL, -- Current output, f(x)
        R1_Delta1  TINYINT NOT NULL, -- First forward difference
        R2_Delta2  TINYINT NOT NULL  -- Constant second difference
    );
END;
GO

/*
    Load the registers from coefficients. At starting point x0:
      R0 = f(x0)                     = a*x0^2 + b*x0 + c
      R1 = f(x0 + 1) - f(x0)         = 2*a*x0 + a + b
      R2 = second forward difference = 2*a

    The modulo expression handles negative values too: -1 is stored as 255,
    its eight-bit two's-complement bit pattern.
*/
CREATE OR ALTER PROCEDURE dbo.InitialiseDifferenceEngineBinary
    @A INT = 1, @B INT = 1, @C INT = 1, @X0 INT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- DECIMAL(38,0) avoids ordinary INT multiplication overflow.
    DECLARE @R0_Math DECIMAL(38, 0) =
        CONVERT(DECIMAL(38, 0), @A) * @X0 * @X0
        + CONVERT(DECIMAL(38, 0), @B) * @X0 + @C;
    DECLARE @R1_Math DECIMAL(38, 0) =
        CONVERT(DECIMAL(38, 0), 2) * @A * @X0 + @A + @B;
    DECLARE @R2_Math DECIMAL(38, 0) = CONVERT(DECIMAL(38, 0), 2) * @A;

    DECLARE @R0 TINYINT = CONVERT(TINYINT, ((@R0_Math % 256) + 256) % 256);
    DECLARE @R1 TINYINT = CONVERT(TINYINT, ((@R1_Math % 256) + 256) % 256);
    DECLARE @R2 TINYINT = CONVERT(TINYINT, ((@R2_Math % 256) + 256) % 256);

    BEGIN TRANSACTION;
        -- Reinitialising corresponds to clearing and reloading the registers.
        DELETE FROM dbo.DifferenceEngineState;
        DBCC CHECKIDENT ('dbo.DifferenceEngineState', RESEED, 0) WITH NO_INFOMSGS;
        INSERT dbo.DifferenceEngineState
            (CrankPhase, R0_Value, R1_Delta1, R2_Delta2)
        VALUES ('INIT (Load)', @R0, @R1, @R2);
    COMMIT TRANSACTION;
END;
GO

-- Turn the simulated crank one or more complete two-phase cycles.
CREATE OR ALTER PROCEDURE dbo.StepDifferenceEngine @Cranks INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Cranks < 1
        THROW 50001, 'The number of crank cycles must be at least 1.', 1;

    DECLARE @R0 TINYINT, @R1 TINYINT, @R2 TINYINT;
    DECLARE @Crank INT = 0;

    BEGIN TRANSACTION;
        -- Prevent two sessions from advancing the same state concurrently.
        SELECT TOP (1)
            @R0 = R0_Value, @R1 = R1_Delta1, @R2 = R2_Delta2
        FROM dbo.DifferenceEngineState WITH (UPDLOCK, HOLDLOCK)
        ORDER BY StepID DESC;

        IF @R0 IS NULL
            THROW 50002, 'Initialise the engine before turning the crank.', 1;

        WHILE @Crank < @Cranks
        BEGIN
            -- Phase 1 uses the old R1 and latches the adder output into R0.
            SET @R0 = CONVERT(TINYINT, (CONVERT(INT, @R0) + @R1) % 256);
            INSERT dbo.DifferenceEngineState
                (CrankPhase, R0_Value, R1_Delta1, R2_Delta2)
            VALUES ('Phase 1 (Even)', @R0, @R1, @R2);

            -- Phase 2 advances R1 only after R0 has latched its value.
            SET @R1 = CONVERT(TINYINT, (CONVERT(INT, @R1) + @R2) % 256);
            INSERT dbo.DifferenceEngineState
                (CrankPhase, R0_Value, R1_Delta1, R2_Delta2)
            VALUES ('Phase 2 (Odd)', @R0, @R1, @R2);

            SET @Crank += 1;
        END;
    COMMIT TRANSACTION;
END;
GO

-- Tutorial example: f(x) = x^2 + x + 1, starting at x = 0.
EXEC dbo.InitialiseDifferenceEngineBinary @A = 1, @B = 1, @C = 1, @X0 = 0;
EXEC dbo.StepDifferenceEngine @Cranks = 5;

SELECT StepID, CrankPhase, R0_Value, R1_Delta1, R2_Delta2
FROM dbo.DifferenceEngineState
ORDER BY StepID;
GO
