/*
    Milestone 5: observable logic signals inside the four-digit BCD adders.

    This is a logical model of settled signals. It does not assign real gate
    delays or attempt to predict analogue glitches, voltage, current, or heat.
*/
USE difference_engine;
GO

CREATE OR ALTER FUNCTION dbo.Trace_BCD4_Add (@A INT, @B INT)
RETURNS @Signals TABLE
(
    DigitIndex TINYINT NOT NULL,       -- 0=ones, 1=tens, 2=hundreds, 3=thousands
    DigitName VARCHAR(10) NOT NULL,
    A_Digit TINYINT NULL,
    B_Digit TINYINT NULL,
    CarryIn TINYINT NULL,
    RawBinarySum TINYINT NULL,
    C4 TINYINT NULL,
    S3 TINYINT NULL,
    S2 TINYINT NULL,
    S1 TINYINT NULL,
    S0 TINYINT NULL,
    Gate_S3_AND_S2 TINYINT NULL,
    Gate_S3_AND_S1 TINYINT NULL,
    CorrectionK TINYINT NULL,
    CorrectionAddend TINYINT NULL,
    CorrectedDigit TINYINT NULL,
    CarryOut TINYINT NULL,
    IsValidBCD BIT NOT NULL
)
AS
BEGIN
    IF @A IS NULL OR @B IS NULL RETURN;

    DECLARE @Place INT = 1;
    DECLARE @DigitIndex TINYINT = 0;
    DECLARE @Carry TINYINT = 0;

    WHILE @DigitIndex < 4
    BEGIN
        DECLARE @ADigit TINYINT = (@A / @Place) & 15;
        DECLARE @BDigit TINYINT = (@B / @Place) & 15;
        DECLARE @Name VARCHAR(10) = CASE @DigitIndex
            WHEN 0 THEN 'ones' WHEN 1 THEN 'tens'
            WHEN 2 THEN 'hundreds' ELSE 'thousands' END;

        IF @ADigit > 9 OR @BDigit > 9
        BEGIN
            INSERT @Signals
                (DigitIndex, DigitName, A_Digit, B_Digit, CarryIn, IsValidBCD)
            VALUES
                (@DigitIndex, @Name, @ADigit, @BDigit, @Carry, 0);
            RETURN;
        END;

        -- First 74LS283: A digit + B digit + decimal carry-in.
        DECLARE @Raw TINYINT = @ADigit + @BDigit + @Carry;
        DECLARE @C4 TINYINT = @Raw / 16;
        DECLARE @S TINYINT = @Raw & 15;
        DECLARE @S3 TINYINT = (@S / 8) & 1;
        DECLARE @S2 TINYINT = (@S / 4) & 1;
        DECLARE @S1 TINYINT = (@S / 2) & 1;
        DECLARE @S0 TINYINT = @S & 1;
        DECLARE @Gate32 TINYINT = @S3 & @S2;
        DECLARE @Gate31 TINYINT = @S3 & @S1;

        -- Correction network: K = C4 OR (S3 AND S2) OR (S3 AND S1).
        DECLARE @K TINYINT = CASE
            WHEN @C4 = 1 OR @Gate32 = 1 OR @Gate31 = 1 THEN 1 ELSE 0 END;

        -- Second 74LS283 adds either 0000 or 0110.
        DECLARE @Addend TINYINT = @K * 6;
        DECLARE @Corrected TINYINT = (@S + @Addend) & 15;

        INSERT @Signals
        (
            DigitIndex, DigitName, A_Digit, B_Digit, CarryIn,
            RawBinarySum, C4, S3, S2, S1, S0,
            Gate_S3_AND_S2, Gate_S3_AND_S1, CorrectionK,
            CorrectionAddend, CorrectedDigit, CarryOut, IsValidBCD
        )
        VALUES
        (
            @DigitIndex, @Name, @ADigit, @BDigit, @Carry,
            @Raw, @C4, @S3, @S2, @S1, @S0,
            @Gate32, @Gate31, @K, @Addend, @Corrected, @K, 1
        );

        SET @Carry = @K;
        SET @Place *= 16;
        SET @DigitIndex += 1;
    END;

    RETURN;
END;
GO

IF OBJECT_ID(N'dbo.DifferenceEngine7BCD4LogicTrace', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DifferenceEngine7BCD4LogicTrace
    (
        TraceID BIGINT IDENTITY(1, 1) NOT NULL
            CONSTRAINT PK_DifferenceEngine7BCD4LogicTrace PRIMARY KEY,
        SourceStepID INT NOT NULL,
        X_Before BIGINT NOT NULL,
        AdderIndex TINYINT NOT NULL,
        DestinationRegister VARCHAR(2) NOT NULL,
        DigitIndex TINYINT NOT NULL,
        A_Digit TINYINT NOT NULL,
        B_Digit TINYINT NOT NULL,
        CarryIn TINYINT NOT NULL,
        RawBinarySum TINYINT NOT NULL,
        C4 TINYINT NOT NULL,
        S3 TINYINT NOT NULL,
        S2 TINYINT NOT NULL,
        S1 TINYINT NOT NULL,
        S0 TINYINT NOT NULL,
        Gate_S3_AND_S2 TINYINT NOT NULL,
        Gate_S3_AND_S1 TINYINT NOT NULL,
        CorrectionK TINYINT NOT NULL,
        CorrectionAddend TINYINT NOT NULL,
        CorrectedDigit TINYINT NOT NULL,
        CarryOut TINYINT NOT NULL
    );
END;
GO

/*
    Capture the 28 digit-level adder traces for each crank, then latch the next
    eight-register state using the already-tested register-transfer procedure.
*/
CREATE OR ALTER PROCEDURE dbo.StepDifferenceEngine7BCD4_WithLogicTrace
    @Cranks INT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @Cranks < 1 THROW 50500, 'Cranks must be at least 1.', 1;

    DECLARE @Iteration INT = 0;
    WHILE @Iteration < @Cranks
    BEGIN
        DECLARE @StepID INT, @X BIGINT;
        DECLARE @R0 INT, @R1 INT, @R2 INT, @R3 INT;
        DECLARE @R4 INT, @R5 INT, @R6 INT, @R7 INT;

        BEGIN TRANSACTION;
            SELECT TOP (1)
                @StepID = StepID, @X = X_Value,
                @R0 = R0, @R1 = R1, @R2 = R2, @R3 = R3,
                @R4 = R4, @R5 = R5, @R6 = R6, @R7 = R7
            FROM dbo.DifferenceEngine7BCD4 WITH (UPDLOCK, HOLDLOCK)
            ORDER BY StepID DESC;

            IF @StepID IS NULL
                THROW 50501, 'Initialise the seventh-order BCD engine first.', 1;

            INSERT dbo.DifferenceEngine7BCD4LogicTrace
            (
                SourceStepID, X_Before, AdderIndex, DestinationRegister,
                DigitIndex, A_Digit, B_Digit, CarryIn, RawBinarySum,
                C4, S3, S2, S1, S0, Gate_S3_AND_S2, Gate_S3_AND_S1,
                CorrectionK, CorrectionAddend, CorrectedDigit, CarryOut
            )
            SELECT
                @StepID, @X, Pair.AdderIndex, Pair.DestinationRegister,
                Signal.DigitIndex, Signal.A_Digit, Signal.B_Digit,
                Signal.CarryIn, Signal.RawBinarySum, Signal.C4,
                Signal.S3, Signal.S2, Signal.S1, Signal.S0,
                Signal.Gate_S3_AND_S2, Signal.Gate_S3_AND_S1,
                Signal.CorrectionK, Signal.CorrectionAddend,
                Signal.CorrectedDigit, Signal.CarryOut
            FROM (VALUES
                (CONVERT(TINYINT, 0), 'R0', @R0, @R1),
                (CONVERT(TINYINT, 1), 'R1', @R1, @R2),
                (CONVERT(TINYINT, 2), 'R2', @R2, @R3),
                (CONVERT(TINYINT, 3), 'R3', @R3, @R4),
                (CONVERT(TINYINT, 4), 'R4', @R4, @R5),
                (CONVERT(TINYINT, 5), 'R5', @R5, @R6),
                (CONVERT(TINYINT, 6), 'R6', @R6, @R7)
            ) AS Pair(AdderIndex, DestinationRegister, OperandA, OperandB)
            CROSS APPLY dbo.Trace_BCD4_Add(Pair.OperandA, Pair.OperandB) AS Signal;

            IF @@ROWCOUNT <> 28
                THROW 50502, 'Logic tracing found invalid BCD or incomplete adder signals.', 1;

            -- Nested transaction semantics keep the trace and state edge atomic.
            EXEC dbo.StepDifferenceEngine7BCD4 @Cranks = 1;
        COMMIT TRANSACTION;

        SET @Iteration += 1;
    END;
END;
GO

-- Demonstrate eight traced clocks from the seventh-order falling factorial.
EXEC dbo.InitialiseDifferenceEngine7BCD4
    @A7 = 1, @A6 = -21, @A5 = 175, @A4 = -735,
    @A3 = 1624, @A2 = -1764, @A1 = 720, @A0 = 0, @X0 = 0;
TRUNCATE TABLE dbo.DifferenceEngine7BCD4LogicTrace;
EXEC dbo.StepDifferenceEngine7BCD4_WithLogicTrace @Cranks = 8;

-- Show the 28 settled digit paths immediately before the first clock edge.
SELECT SourceStepID, X_Before, DestinationRegister, DigitIndex,
       A_Digit, B_Digit, CarryIn, RawBinarySum, C4,
       S3, S2, S1, S0, Gate_S3_AND_S2, Gate_S3_AND_S1,
       CorrectionK, CorrectionAddend, CorrectedDigit, CarryOut
FROM dbo.DifferenceEngine7BCD4LogicTrace
WHERE SourceStepID = 1
ORDER BY AdderIndex, DigitIndex;

-- Confirm that each crank captured seven adders times four decimal digits.
SELECT SourceStepID, X_Before, COUNT(*) AS SignalRows
FROM dbo.DifferenceEngine7BCD4LogicTrace
GROUP BY SourceStepID, X_Before
ORDER BY SourceStepID;
GO
