/*
    Milestone 4: eight-register, four-digit BCD Difference Engine.

    Prerequisite: run 5_Cubic_BCD_4Digit.sql to create Decimal_To_BCD4,
    Add_BCD_4Digit, and Format_BCD4.
*/
USE difference_engine;
GO

IF OBJECT_ID(N'dbo.DifferenceEngine7BCD4', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DifferenceEngine7BCD4
    (
        StepID  INT IDENTITY(1, 1) NOT NULL
            CONSTRAINT PK_DifferenceEngine7BCD4 PRIMARY KEY,
        X_Value BIGINT NOT NULL,
        R0 INT NOT NULL,
        R1 INT NOT NULL,
        R2 INT NOT NULL,
        R3 INT NOT NULL,
        R4 INT NOT NULL,
        R5 INT NOT NULL,
        R6 INT NOT NULL,
        R7 INT NOT NULL
    );
END;
GO

CREATE OR ALTER PROCEDURE dbo.InitialiseDifferenceEngine7BCD4
    @A7 DECIMAL(18, 0) = 0,
    @A6 DECIMAL(18, 0) = 0,
    @A5 DECIMAL(18, 0) = 0,
    @A4 DECIMAL(18, 0) = 0,
    @A3 DECIMAL(18, 0) = 0,
    @A2 DECIMAL(18, 0) = 0,
    @A1 DECIMAL(18, 0) = 0,
    @A0 DECIMAL(18, 0) = 0,
    @X0 BIGINT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Samples TABLE
        (Position TINYINT PRIMARY KEY, Value DECIMAL(38, 0) NOT NULL);
    DECLARE @Differences TABLE
        (DifferenceOrder TINYINT PRIMARY KEY, Value DECIMAL(38, 0) NOT NULL);
    DECLARE @Position TINYINT = 0;

    WHILE @Position <= 7
    BEGIN
        DECLARE @X DECIMAL(38, 0) = @X0 + @Position;
        DECLARE @Fx DECIMAL(38, 0) = @A7;
        SET @Fx = @Fx * @X + @A6;
        SET @Fx = @Fx * @X + @A5;
        SET @Fx = @Fx * @X + @A4;
        SET @Fx = @Fx * @X + @A3;
        SET @Fx = @Fx * @X + @A2;
        SET @Fx = @Fx * @X + @A1;
        SET @Fx = @Fx * @X + @A0;
        INSERT @Samples VALUES (@Position, @Fx);
        SET @Position += 1;
    END;

    DECLARE @Order TINYINT = 0;
    WHILE @Order <= 7
    BEGIN
        INSERT @Differences
        SELECT @Order, Value FROM @Samples WHERE Position = 0;

        UPDATE CurrentSample
        SET Value = NextSample.Value - CurrentSample.Value
        FROM @Samples AS CurrentSample
        INNER JOIN @Samples AS NextSample
            ON NextSample.Position = CurrentSample.Position + 1
        WHERE CurrentSample.Position < 7 - @Order;
        SET @Order += 1;
    END;

    -- This stage uses unsigned BCD. Rejecting unsupported initial states is
    -- preferable to silently choosing an undocumented signed representation.
    IF EXISTS (SELECT 1 FROM @Differences WHERE Value NOT BETWEEN 0 AND 9999)
        THROW 50300,
            'All eight initial differences must be 0..9999 for unsigned four-digit BCD.',
            1;

    DECLARE @R0 INT, @R1 INT, @R2 INT, @R3 INT;
    DECLARE @R4 INT, @R5 INT, @R6 INT, @R7 INT;
    SELECT @R0 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder = 0;
    SELECT @R1 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder = 1;
    SELECT @R2 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder = 2;
    SELECT @R3 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder = 3;
    SELECT @R4 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder = 4;
    SELECT @R5 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder = 5;
    SELECT @R6 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder = 6;
    SELECT @R7 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder = 7;

    BEGIN TRANSACTION;
        TRUNCATE TABLE dbo.DifferenceEngine7BCD4;
        INSERT dbo.DifferenceEngine7BCD4
            (X_Value, R0, R1, R2, R3, R4, R5, R6, R7)
        VALUES
            (@X0, @R0, @R1, @R2, @R3, @R4, @R5, @R6, @R7);
    COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE dbo.StepDifferenceEngine7BCD4 @Cranks INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @Cranks < 1 THROW 50301, 'Cranks must be at least 1.', 1;

    DECLARE @X BIGINT;
    DECLARE @R0 INT, @R1 INT, @R2 INT, @R3 INT;
    DECLARE @R4 INT, @R5 INT, @R6 INT, @R7 INT;
    DECLARE @N0 INT, @N1 INT, @N2 INT, @N3 INT;
    DECLARE @N4 INT, @N5 INT, @N6 INT;
    DECLARE @Crank INT = 0;

    BEGIN TRANSACTION;
        SELECT TOP (1)
            @X = X_Value,
            @R0 = R0, @R1 = R1, @R2 = R2, @R3 = R3,
            @R4 = R4, @R5 = R5, @R6 = R6, @R7 = R7
        FROM dbo.DifferenceEngine7BCD4 WITH (UPDLOCK, HOLDLOCK)
        ORDER BY StepID DESC;
        IF @R0 IS NULL
            THROW 50302, 'Initialise the seventh-order BCD engine first.', 1;

        WHILE @Crank < @Cranks
        BEGIN
            -- Seven corrected-BCD adders operate from the old register outputs.
            SET @N0 = dbo.Add_BCD_4Digit(@R0, @R1);
            SET @N1 = dbo.Add_BCD_4Digit(@R1, @R2);
            SET @N2 = dbo.Add_BCD_4Digit(@R2, @R3);
            SET @N3 = dbo.Add_BCD_4Digit(@R3, @R4);
            SET @N4 = dbo.Add_BCD_4Digit(@R4, @R5);
            SET @N5 = dbo.Add_BCD_4Digit(@R5, @R6);
            SET @N6 = dbo.Add_BCD_4Digit(@R6, @R7);

            IF @N0 IS NULL OR @N1 IS NULL OR @N2 IS NULL OR @N3 IS NULL
               OR @N4 IS NULL OR @N5 IS NULL OR @N6 IS NULL
                THROW 50303, 'A seventh-order register contains invalid packed BCD.', 1;

            SELECT @R0 = @N0, @R1 = @N1, @R2 = @N2, @R3 = @N3,
                   @R4 = @N4, @R5 = @N5, @R6 = @N6;
            SET @X += 1;

            INSERT dbo.DifferenceEngine7BCD4
                (X_Value, R0, R1, R2, R3, R4, R5, R6, R7)
            VALUES
                (@X, @R0, @R1, @R2, @R3, @R4, @R5, @R6, @R7);
            SET @Crank += 1;
        END;
    COMMIT TRANSACTION;
END;
GO

/*
    Seventh-order demonstration using the falling-factorial polynomial:

      f(x) = x(x-1)(x-2)(x-3)(x-4)(x-5)(x-6)
           = x^7 - 21x^6 + 175x^5 - 735x^4
             + 1624x^3 - 1764x^2 + 720x

    At x=0 its initial differences are zero except R7=5040. This fits four
    unsigned BCD digits and gives an especially clear view of the highest
    difference propagating down through the register chain.
*/
EXEC dbo.InitialiseDifferenceEngine7BCD4
    @A7 = 1, @A6 = -21, @A5 = 175, @A4 = -735,
    @A3 = 1624, @A2 = -1764, @A1 = 720, @A0 = 0,
    @X0 = 0;
EXEC dbo.StepDifferenceEngine7BCD4 @Cranks = 10;

SELECT StepID, X_Value,
       dbo.Format_BCD4(R0) AS R0, dbo.Format_BCD4(R1) AS R1,
       dbo.Format_BCD4(R2) AS R2, dbo.Format_BCD4(R3) AS R3,
       dbo.Format_BCD4(R4) AS R4, dbo.Format_BCD4(R5) AS R5,
       dbo.Format_BCD4(R6) AS R6, dbo.Format_BCD4(R7) AS R7
FROM dbo.DifferenceEngine7BCD4
ORDER BY StepID;
GO
