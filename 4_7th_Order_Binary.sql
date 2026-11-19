/*
    Milestone 2: configurable binary model for polynomials up to degree seven.

    Eight registers hold the value and seven forward differences:
      R0 = f(x), R1 = first difference, ... R7 = seventh difference.

    In a parallel electronic implementation, seven combinational adders feed
    R0..R6. All eight edge-triggered registers share one clock, so every adder
    sees the old register outputs and all new values latch simultaneously.
*/
USE difference_engine;
GO

IF OBJECT_ID(N'dbo.DifferenceEngine7Binary', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DifferenceEngine7Binary
    (
        StepID   INT IDENTITY(1, 1) NOT NULL
            CONSTRAINT PK_DifferenceEngine7Binary PRIMARY KEY,
        X_Value  BIGINT NOT NULL,
        WordBits TINYINT NOT NULL,
        R0 BIGINT NOT NULL,
        R1 BIGINT NOT NULL,
        R2 BIGINT NOT NULL,
        R3 BIGINT NOT NULL,
        R4 BIGINT NOT NULL,
        R5 BIGINT NOT NULL,
        R6 BIGINT NOT NULL,
        R7 BIGINT NOT NULL
    );
END;
GO

/*
    Evaluate f(x0), f(x0+1), ... f(x0+7), then repeatedly subtract adjacent
    entries to construct the first row of the forward-difference table.

    Coefficients are named by power: A7*x^7 + A6*x^6 + ... + A1*x + A0.
    Horner's method evaluates the polynomial without calling POWER repeatedly.
*/
CREATE OR ALTER PROCEDURE dbo.InitialiseDifferenceEngine7Binary
    @A7 DECIMAL(18, 0) = 0,
    @A6 DECIMAL(18, 0) = 0,
    @A5 DECIMAL(18, 0) = 0,
    @A4 DECIMAL(18, 0) = 0,
    @A3 DECIMAL(18, 0) = 0,
    @A2 DECIMAL(18, 0) = 0,
    @A1 DECIMAL(18, 0) = 0,
    @A0 DECIMAL(18, 0) = 0,
    @X0 BIGINT = 0,
    @WordBits TINYINT = 16
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    -- BIGINT registers safely support unsigned words up to 62 bits. Keeping
    -- one spare bit allows two maximum register values to be added safely.
    IF @WordBits NOT BETWEEN 4 AND 62
        THROW 50100, 'WordBits must be between 4 and 62.', 1;

    DECLARE @Modulus BIGINT = CONVERT(BIGINT,
        POWER(CONVERT(DECIMAL(38, 0), 2), @WordBits));
    DECLARE @Samples TABLE
    (
        Position TINYINT NOT NULL PRIMARY KEY,
        Value DECIMAL(38, 0) NOT NULL
    );
    DECLARE @InitialDifferences TABLE
    (
        DifferenceOrder TINYINT NOT NULL PRIMARY KEY,
        Value DECIMAL(38, 0) NOT NULL
    );

    DECLARE @Position TINYINT = 0;
    WHILE @Position <= 7
    BEGIN
        DECLARE @X DECIMAL(38, 0) = @X0 + @Position;
        DECLARE @Fx DECIMAL(38, 0);

        -- Horner evaluation: start at A7 and fold in one coefficient at a time.
        SET @Fx = @A7;
        SET @Fx = @Fx * @X + @A6;
        SET @Fx = @Fx * @X + @A5;
        SET @Fx = @Fx * @X + @A4;
        SET @Fx = @Fx * @X + @A3;
        SET @Fx = @Fx * @X + @A2;
        SET @Fx = @Fx * @X + @A1;
        SET @Fx = @Fx * @X + @A0;

        INSERT @Samples (Position, Value) VALUES (@Position, @Fx);
        SET @Position += 1;
    END;

    DECLARE @Order TINYINT = 0;
    WHILE @Order <= 7
    BEGIN
        INSERT @InitialDifferences (DifferenceOrder, Value)
        SELECT @Order, Value FROM @Samples WHERE Position = 0;

        -- Replace each entry with the entry to its right minus itself. The
        -- simultaneous UPDATE reads the old table state for both operands.
        UPDATE CurrentSample
        SET Value = NextSample.Value - CurrentSample.Value
        FROM @Samples AS CurrentSample
        INNER JOIN @Samples AS NextSample
            ON NextSample.Position = CurrentSample.Position + 1
        WHERE CurrentSample.Position < 7 - @Order;

        SET @Order += 1;
    END;

    DECLARE @D0 DECIMAL(38, 0), @D1 DECIMAL(38, 0);
    DECLARE @D2 DECIMAL(38, 0), @D3 DECIMAL(38, 0);
    DECLARE @D4 DECIMAL(38, 0), @D5 DECIMAL(38, 0);
    DECLARE @D6 DECIMAL(38, 0), @D7 DECIMAL(38, 0);

    -- Separate scalar lookups avoid the "null eliminated by aggregate" warning
    -- that conditional MAX expressions would otherwise print for students.
    SELECT @D0 = Value FROM @InitialDifferences WHERE DifferenceOrder = 0;
    SELECT @D1 = Value FROM @InitialDifferences WHERE DifferenceOrder = 1;
    SELECT @D2 = Value FROM @InitialDifferences WHERE DifferenceOrder = 2;
    SELECT @D3 = Value FROM @InitialDifferences WHERE DifferenceOrder = 3;
    SELECT @D4 = Value FROM @InitialDifferences WHERE DifferenceOrder = 4;
    SELECT @D5 = Value FROM @InitialDifferences WHERE DifferenceOrder = 5;
    SELECT @D6 = Value FROM @InitialDifferences WHERE DifferenceOrder = 6;
    SELECT @D7 = Value FROM @InitialDifferences WHERE DifferenceOrder = 7;

    BEGIN TRANSACTION;
        -- TRUNCATE clears the old run and reliably restarts StepID at 1.
        TRUNCATE TABLE dbo.DifferenceEngine7Binary;

        -- Normalising twice after modulo maps negative differences into their
        -- unsigned word patterns, just as the quadratic binary model does.
        INSERT dbo.DifferenceEngine7Binary
            (X_Value, WordBits, R0, R1, R2, R3, R4, R5, R6, R7)
        VALUES
        (
            @X0, @WordBits,
            CONVERT(BIGINT, ((@D0 % @Modulus) + @Modulus) % @Modulus),
            CONVERT(BIGINT, ((@D1 % @Modulus) + @Modulus) % @Modulus),
            CONVERT(BIGINT, ((@D2 % @Modulus) + @Modulus) % @Modulus),
            CONVERT(BIGINT, ((@D3 % @Modulus) + @Modulus) % @Modulus),
            CONVERT(BIGINT, ((@D4 % @Modulus) + @Modulus) % @Modulus),
            CONVERT(BIGINT, ((@D5 % @Modulus) + @Modulus) % @Modulus),
            CONVERT(BIGINT, ((@D6 % @Modulus) + @Modulus) % @Modulus),
            CONVERT(BIGINT, ((@D7 % @Modulus) + @Modulus) % @Modulus)
        );
    COMMIT TRANSACTION;
END;
GO

-- Advance all seven adder/register stages atomically for each crank.
CREATE OR ALTER PROCEDURE dbo.StepDifferenceEngine7Binary @Cranks INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Cranks < 1
        THROW 50101, 'The number of crank cycles must be at least 1.', 1;

    DECLARE @X BIGINT, @WordBits TINYINT;
    DECLARE @R0 BIGINT, @R1 BIGINT, @R2 BIGINT, @R3 BIGINT;
    DECLARE @R4 BIGINT, @R5 BIGINT, @R6 BIGINT, @R7 BIGINT;
    DECLARE @N0 BIGINT, @N1 BIGINT, @N2 BIGINT, @N3 BIGINT;
    DECLARE @N4 BIGINT, @N5 BIGINT, @N6 BIGINT;
    DECLARE @Crank INT = 0;

    BEGIN TRANSACTION;
        SELECT TOP (1)
            @X = X_Value, @WordBits = WordBits,
            @R0 = R0, @R1 = R1, @R2 = R2, @R3 = R3,
            @R4 = R4, @R5 = R5, @R6 = R6, @R7 = R7
        FROM dbo.DifferenceEngine7Binary WITH (UPDLOCK, HOLDLOCK)
        ORDER BY StepID DESC;

        IF @R0 IS NULL
            THROW 50102, 'Initialise the seventh-order binary engine first.', 1;

        DECLARE @Modulus BIGINT = CONVERT(BIGINT,
            POWER(CONVERT(DECIMAL(38, 0), 2), @WordBits));

        WHILE @Crank < @Cranks
        BEGIN
            -- Calculate every D input before changing any Q value. This is the
            -- SQL equivalent of seven adders operating in parallel.
            SET @N0 = (@R0 + @R1) % @Modulus;
            SET @N1 = (@R1 + @R2) % @Modulus;
            SET @N2 = (@R2 + @R3) % @Modulus;
            SET @N3 = (@R3 + @R4) % @Modulus;
            SET @N4 = (@R4 + @R5) % @Modulus;
            SET @N5 = (@R5 + @R6) % @Modulus;
            SET @N6 = (@R6 + @R7) % @Modulus;

            SELECT @R0 = @N0, @R1 = @N1, @R2 = @N2, @R3 = @N3,
                   @R4 = @N4, @R5 = @N5, @R6 = @N6;
            SET @X += 1;

            INSERT dbo.DifferenceEngine7Binary
                (X_Value, WordBits, R0, R1, R2, R3, R4, R5, R6, R7)
            VALUES
                (@X, @WordBits, @R0, @R1, @R2, @R3, @R4, @R5, @R6, @R7);

            SET @Crank += 1;
        END;
    COMMIT TRANSACTION;
END;
GO

-- Demonstration: f(x) = x^7 using a 32-bit simulated register word.
EXEC dbo.InitialiseDifferenceEngine7Binary
    @A7 = 1, @A6 = 0, @A5 = 0, @A4 = 0,
    @A3 = 0, @A2 = 0, @A1 = 0, @A0 = 0,
    @X0 = 0, @WordBits = 32;
EXEC dbo.StepDifferenceEngine7Binary @Cranks = 8;

SELECT StepID, X_Value, WordBits, R0, R1, R2, R3, R4, R5, R6, R7
FROM dbo.DifferenceEngine7Binary
ORDER BY StepID;
GO
