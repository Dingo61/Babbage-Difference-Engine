/*
    Milestone 3: four-digit BCD components and a four-register cubic bridge.

    An INT holds four packed BCD nibbles, for example decimal 1234 is 0x1234.
    The arithmetic below deliberately performs correction one digit at a time,
    mirroring four cascaded corrected-BCD stages rather than using decimal +.
*/
USE difference_engine;
GO

CREATE OR ALTER FUNCTION dbo.Decimal_To_BCD4 (@DecimalValue INT)
RETURNS INT
AS
BEGIN
    IF @DecimalValue NOT BETWEEN 0 AND 9999 RETURN NULL;

    DECLARE @Remaining INT = @DecimalValue;
    DECLARE @Packed INT = 0;
    DECLARE @Place INT = 1;
    DECLARE @Digit TINYINT;
    DECLARE @Count TINYINT = 0;

    WHILE @Count < 4
    BEGIN
        SET @Digit = @Remaining % 10;
        SET @Packed += @Digit * @Place;
        SET @Remaining /= 10;
        SET @Place *= 16;
        SET @Count += 1;
    END;

    RETURN @Packed;
END;
GO

CREATE OR ALTER FUNCTION dbo.Add_BCD_4Digit (@A INT, @B INT)
RETURNS INT
AS
BEGIN
    IF @A IS NULL OR @B IS NULL RETURN NULL;

    DECLARE @Result INT = 0;
    DECLARE @Place INT = 1;
    DECLARE @Carry TINYINT = 0;
    DECLARE @Digit TINYINT = 0;

    WHILE @Digit < 4
    BEGIN
        DECLARE @ADigit TINYINT = (@A / @Place) & 15;
        DECLARE @BDigit TINYINT = (@B / @Place) & 15;
        IF @ADigit > 9 OR @BDigit > 9 RETURN NULL;

        DECLARE @Sum TINYINT = @ADigit + @BDigit + @Carry;
        SET @Carry = 0;
        IF @Sum > 9
        BEGIN
            -- A physical correction stage adds binary 0110. Masking retains
            -- the corrected four-bit digit and Carry represents decimal Cout.
            SET @Sum = (@Sum + 6) & 15;
            SET @Carry = 1;
        END;

        SET @Result += @Sum * @Place;
        SET @Place *= 16;
        SET @Digit += 1;
    END;

    -- Carry out of the fourth digit is intentionally discarded: 9999 + 1
    -- therefore becomes 0000 in this fixed-width model.
    RETURN @Result;
END;
GO

CREATE OR ALTER FUNCTION dbo.Format_BCD4 (@BCD INT)
RETURNS CHAR(4)
AS
BEGIN
    IF @BCD IS NULL RETURN NULL;

    DECLARE @Text VARCHAR(4) = '';
    DECLARE @Place INT = 4096; -- 16^3, the most-significant nibble
    DECLARE @Digit TINYINT;
    DECLARE @Count TINYINT = 0;

    WHILE @Count < 4
    BEGIN
        SET @Digit = (@BCD / @Place) & 15;
        IF @Digit > 9 RETURN '????';
        SET @Text += CHAR(ASCII('0') + @Digit);
        SET @Place /= 16;
        SET @Count += 1;
    END;

    RETURN CONVERT(CHAR(4), @Text);
END;
GO

IF OBJECT_ID(N'dbo.DifferenceEngine3BCD4', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DifferenceEngine3BCD4
    (
        StepID  INT IDENTITY(1, 1) NOT NULL
            CONSTRAINT PK_DifferenceEngine3BCD4 PRIMARY KEY,
        X_Value BIGINT NOT NULL,
        R0 INT NOT NULL,
        R1 INT NOT NULL,
        R2 INT NOT NULL,
        R3 INT NOT NULL
    );
END;
GO

CREATE OR ALTER PROCEDURE dbo.InitialiseDifferenceEngine3BCD4
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

    WHILE @Position <= 3
    BEGIN
        DECLARE @X DECIMAL(38, 0) = @X0 + @Position;
        DECLARE @Fx DECIMAL(38, 0) = ((@A3 * @X + @A2) * @X + @A1) * @X + @A0;
        INSERT @Samples VALUES (@Position, @Fx);
        SET @Position += 1;
    END;

    DECLARE @Order TINYINT = 0;
    WHILE @Order <= 3
    BEGIN
        INSERT @Differences
        SELECT @Order, Value FROM @Samples WHERE Position = 0;

        UPDATE CurrentSample
        SET Value = NextSample.Value - CurrentSample.Value
        FROM @Samples AS CurrentSample
        INNER JOIN @Samples AS NextSample
            ON NextSample.Position = CurrentSample.Position + 1
        WHERE CurrentSample.Position < 3 - @Order;
        SET @Order += 1;
    END;

    IF EXISTS (SELECT 1 FROM @Differences WHERE Value NOT BETWEEN 0 AND 9999)
        THROW 50200,
            'Initial cubic differences must each be 0..9999 for unsigned four-digit BCD.',
            1;

    DECLARE @R0 INT, @R1 INT, @R2 INT, @R3 INT;
    SELECT @R0 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder = 0;
    SELECT @R1 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder = 1;
    SELECT @R2 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder = 2;
    SELECT @R3 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder = 3;

    BEGIN TRANSACTION;
        TRUNCATE TABLE dbo.DifferenceEngine3BCD4;
        INSERT dbo.DifferenceEngine3BCD4 (X_Value, R0, R1, R2, R3)
        VALUES (@X0, @R0, @R1, @R2, @R3);
    COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE dbo.StepDifferenceEngine3BCD4 @Cranks INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @Cranks < 1 THROW 50201, 'Cranks must be at least 1.', 1;

    DECLARE @X BIGINT, @R0 INT, @R1 INT, @R2 INT, @R3 INT;
    DECLARE @N0 INT, @N1 INT, @N2 INT, @Crank INT = 0;

    BEGIN TRANSACTION;
        SELECT TOP (1) @X = X_Value, @R0 = R0, @R1 = R1, @R2 = R2, @R3 = R3
        FROM dbo.DifferenceEngine3BCD4 WITH (UPDLOCK, HOLDLOCK)
        ORDER BY StepID DESC;
        IF @R0 IS NULL THROW 50202, 'Initialise the cubic BCD engine first.', 1;

        WHILE @Crank < @Cranks
        BEGIN
            -- Three adders calculate from the same old Q outputs.
            SET @N0 = dbo.Add_BCD_4Digit(@R0, @R1);
            SET @N1 = dbo.Add_BCD_4Digit(@R1, @R2);
            SET @N2 = dbo.Add_BCD_4Digit(@R2, @R3);
            IF @N0 IS NULL OR @N1 IS NULL OR @N2 IS NULL
                THROW 50203, 'A cubic register contains invalid packed BCD.', 1;

            SELECT @R0 = @N0, @R1 = @N1, @R2 = @N2;
            SET @X += 1;
            INSERT dbo.DifferenceEngine3BCD4 (X_Value, R0, R1, R2, R3)
            VALUES (@X, @R0, @R1, @R2, @R3);
            SET @Crank += 1;
        END;
    COMMIT TRANSACTION;
END;
GO

-- Bridge demonstration: f(x) = x^3.
EXEC dbo.InitialiseDifferenceEngine3BCD4 @A3 = 1, @X0 = 0;
EXEC dbo.StepDifferenceEngine3BCD4 @Cranks = 10;

SELECT StepID, X_Value,
       dbo.Format_BCD4(R0) AS R0,
       dbo.Format_BCD4(R1) AS R1,
       dbo.Format_BCD4(R2) AS R2,
       dbo.Format_BCD4(R3) AS R3
FROM dbo.DifferenceEngine3BCD4
ORDER BY StepID;
GO
