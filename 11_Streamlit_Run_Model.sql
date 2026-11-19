/*
    Run-isolated storage for the Streamlit interface.

    Each browser experiment receives its own RunID. Nothing is truncated, so
    multiple sessions and saved demonstrations can coexist without interference.

    Prerequisites: scripts 5, 6, and 8 (BCD functions and signal trace function).
*/
USE difference_engine;
GO

IF OBJECT_ID(N'dbo.DifferenceEngineRun', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DifferenceEngineRun
    (
        RunID UNIQUEIDENTIFIER NOT NULL
            CONSTRAINT PK_DifferenceEngineRun PRIMARY KEY,
        RunName NVARCHAR(100) NOT NULL,
        CreatedAt DATETIME2(0) NOT NULL
            CONSTRAINT DF_DifferenceEngineRun_CreatedAt DEFAULT SYSUTCDATETIME(),
        CreatedBy SYSNAME NOT NULL
            CONSTRAINT DF_DifferenceEngineRun_CreatedBy DEFAULT SUSER_SNAME(),
        Degree TINYINT NOT NULL,
        X0 BIGINT NOT NULL,
        A7 DECIMAL(18, 0) NOT NULL,
        A6 DECIMAL(18, 0) NOT NULL,
        A5 DECIMAL(18, 0) NOT NULL,
        A4 DECIMAL(18, 0) NOT NULL,
        A3 DECIMAL(18, 0) NOT NULL,
        A2 DECIMAL(18, 0) NOT NULL,
        A1 DECIMAL(18, 0) NOT NULL,
        A0 DECIMAL(18, 0) NOT NULL,
        CONSTRAINT CK_DifferenceEngineRun_Degree CHECK (Degree BETWEEN 0 AND 7)
    );
END;
GO

IF OBJECT_ID(N'dbo.DifferenceEngineRunState', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DifferenceEngineRunState
    (
        RunID UNIQUEIDENTIFIER NOT NULL,
        StepNo INT NOT NULL,
        X_Value BIGINT NOT NULL,
        R0 INT NOT NULL, R1 INT NOT NULL, R2 INT NOT NULL, R3 INT NOT NULL,
        R4 INT NOT NULL, R5 INT NOT NULL, R6 INT NOT NULL, R7 INT NOT NULL,
        CONSTRAINT PK_DifferenceEngineRunState PRIMARY KEY (RunID, StepNo),
        CONSTRAINT FK_DifferenceEngineRunState_Run FOREIGN KEY (RunID)
            REFERENCES dbo.DifferenceEngineRun(RunID) ON DELETE CASCADE
    );
END;
GO

IF OBJECT_ID(N'dbo.DifferenceEngineRunLogicTrace', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DifferenceEngineRunLogicTrace
    (
        RunID UNIQUEIDENTIFIER NOT NULL,
        SourceStepNo INT NOT NULL,
        X_Before BIGINT NOT NULL,
        AdderIndex TINYINT NOT NULL,
        DestinationRegister VARCHAR(2) NOT NULL,
        DigitIndex TINYINT NOT NULL,
        A_Digit TINYINT NOT NULL,
        B_Digit TINYINT NOT NULL,
        CarryIn TINYINT NOT NULL,
        RawBinarySum TINYINT NOT NULL,
        C4 TINYINT NOT NULL,
        S3 TINYINT NOT NULL, S2 TINYINT NOT NULL,
        S1 TINYINT NOT NULL, S0 TINYINT NOT NULL,
        Gate_S3_AND_S2 TINYINT NOT NULL,
        Gate_S3_AND_S1 TINYINT NOT NULL,
        CorrectionK TINYINT NOT NULL,
        CorrectionAddend TINYINT NOT NULL,
        CorrectedDigit TINYINT NOT NULL,
        CarryOut TINYINT NOT NULL,
        CONSTRAINT PK_DifferenceEngineRunLogicTrace
            PRIMARY KEY (RunID, SourceStepNo, AdderIndex, DigitIndex),
        CONSTRAINT FK_DifferenceEngineRunLogicTrace_Run FOREIGN KEY (RunID)
            REFERENCES dbo.DifferenceEngineRun(RunID) ON DELETE CASCADE
    );
END;
GO

CREATE OR ALTER PROCEDURE dbo.CreateDifferenceEngineRun
    @RunID UNIQUEIDENTIFIER,
    @RunName NVARCHAR(100),
    @Degree TINYINT,
    @A7 DECIMAL(18, 0) = 0, @A6 DECIMAL(18, 0) = 0,
    @A5 DECIMAL(18, 0) = 0, @A4 DECIMAL(18, 0) = 0,
    @A3 DECIMAL(18, 0) = 0, @A2 DECIMAL(18, 0) = 0,
    @A1 DECIMAL(18, 0) = 0, @A0 DECIMAL(18, 0) = 0,
    @X0 BIGINT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @RunID IS NULL THROW 50700, 'RunID is required.', 1;
    IF NULLIF(LTRIM(RTRIM(@RunName)), N'') IS NULL
        THROW 50701, 'RunName is required.', 1;
    IF @Degree NOT BETWEEN 0 AND 7
        THROW 50702, 'Degree must be between 0 and 7.', 1;
    IF EXISTS (SELECT 1 FROM dbo.DifferenceEngineRun WHERE RunID = @RunID)
        THROW 50703, 'RunID already exists.', 1;

    -- Coefficients above the selected degree would make the label misleading.
    IF (@Degree < 7 AND @A7 <> 0) OR (@Degree < 6 AND @A6 <> 0)
       OR (@Degree < 5 AND @A5 <> 0) OR (@Degree < 4 AND @A4 <> 0)
       OR (@Degree < 3 AND @A3 <> 0) OR (@Degree < 2 AND @A2 <> 0)
       OR (@Degree < 1 AND @A1 <> 0)
        THROW 50704, 'Coefficients above the selected degree must be zero.', 1;

    IF (@Degree = 7 AND @A7 = 0) OR (@Degree = 6 AND @A6 = 0)
       OR (@Degree = 5 AND @A5 = 0) OR (@Degree = 4 AND @A4 = 0)
       OR (@Degree = 3 AND @A3 = 0) OR (@Degree = 2 AND @A2 = 0)
       OR (@Degree = 1 AND @A1 = 0)
        THROW 50705, 'The coefficient at the selected degree must be nonzero.', 1;

    DECLARE @Samples TABLE
        (Position TINYINT PRIMARY KEY, Value DECIMAL(38, 0) NOT NULL);
    DECLARE @Differences TABLE
        (DifferenceOrder TINYINT PRIMARY KEY, Value DECIMAL(38, 0) NOT NULL);
    DECLARE @Position TINYINT = 0;

    WHILE @Position <= 7
    BEGIN
        DECLARE @X DECIMAL(38, 0) = @X0 + @Position;
        DECLARE @Fx DECIMAL(38, 0) = @A7;
        SET @Fx = @Fx * @X + @A6; SET @Fx = @Fx * @X + @A5;
        SET @Fx = @Fx * @X + @A4; SET @Fx = @Fx * @X + @A3;
        SET @Fx = @Fx * @X + @A2; SET @Fx = @Fx * @X + @A1;
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

    IF EXISTS (SELECT 1 FROM @Differences WHERE Value NOT BETWEEN 0 AND 9999)
        THROW 50706,
            'All initial differences must be 0..9999 for unsigned four-digit BCD.',
            1;

    DECLARE @R0 INT, @R1 INT, @R2 INT, @R3 INT;
    DECLARE @R4 INT, @R5 INT, @R6 INT, @R7 INT;
    SELECT @R0 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder=0;
    SELECT @R1 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder=1;
    SELECT @R2 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder=2;
    SELECT @R3 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder=3;
    SELECT @R4 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder=4;
    SELECT @R5 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder=5;
    SELECT @R6 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder=6;
    SELECT @R7 = dbo.Decimal_To_BCD4(CONVERT(INT, Value)) FROM @Differences WHERE DifferenceOrder=7;

    BEGIN TRANSACTION;
        INSERT dbo.DifferenceEngineRun
            (RunID, RunName, Degree, X0, A7, A6, A5, A4, A3, A2, A1, A0)
        VALUES
            (@RunID, LTRIM(RTRIM(@RunName)), @Degree, @X0,
             @A7, @A6, @A5, @A4, @A3, @A2, @A1, @A0);
        INSERT dbo.DifferenceEngineRunState
            (RunID, StepNo, X_Value, R0, R1, R2, R3, R4, R5, R6, R7)
        VALUES
            (@RunID, 0, @X0, @R0, @R1, @R2, @R3, @R4, @R5, @R6, @R7);
    COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE dbo.StepDifferenceEngineRun
    @RunID UNIQUEIDENTIFIER,
    @Cranks INT = 1,
    @CaptureLogic BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @Cranks NOT BETWEEN 1 AND 1000
        THROW 50710, 'Cranks must be between 1 and 1000.', 1;

    DECLARE @StepNo INT, @X BIGINT;
    DECLARE @R0 INT, @R1 INT, @R2 INT, @R3 INT;
    DECLARE @R4 INT, @R5 INT, @R6 INT, @R7 INT;
    DECLARE @N0 INT, @N1 INT, @N2 INT, @N3 INT;
    DECLARE @N4 INT, @N5 INT, @N6 INT;
    DECLARE @Iteration INT = 0;

    BEGIN TRANSACTION;
        SELECT TOP (1)
            @StepNo=StepNo, @X=X_Value,
            @R0=R0, @R1=R1, @R2=R2, @R3=R3,
            @R4=R4, @R5=R5, @R6=R6, @R7=R7
        FROM dbo.DifferenceEngineRunState WITH (UPDLOCK, HOLDLOCK)
        WHERE RunID=@RunID ORDER BY StepNo DESC;
        IF @StepNo IS NULL THROW 50711, 'RunID was not found or has no state.', 1;

        WHILE @Iteration < @Cranks
        BEGIN
            IF @CaptureLogic = 1
            BEGIN
                INSERT dbo.DifferenceEngineRunLogicTrace
                (
                    RunID, SourceStepNo, X_Before, AdderIndex,
                    DestinationRegister, DigitIndex, A_Digit, B_Digit,
                    CarryIn, RawBinarySum, C4, S3, S2, S1, S0,
                    Gate_S3_AND_S2, Gate_S3_AND_S1, CorrectionK,
                    CorrectionAddend, CorrectedDigit, CarryOut
                )
                SELECT @RunID, @StepNo, @X, Pair.AdderIndex,
                       Pair.DestinationRegister, Signal.DigitIndex,
                       Signal.A_Digit, Signal.B_Digit, Signal.CarryIn,
                       Signal.RawBinarySum, Signal.C4,
                       Signal.S3, Signal.S2, Signal.S1, Signal.S0,
                       Signal.Gate_S3_AND_S2, Signal.Gate_S3_AND_S1,
                       Signal.CorrectionK, Signal.CorrectionAddend,
                       Signal.CorrectedDigit, Signal.CarryOut
                FROM (VALUES
                    (CONVERT(TINYINT,0),'R0',@R0,@R1),
                    (CONVERT(TINYINT,1),'R1',@R1,@R2),
                    (CONVERT(TINYINT,2),'R2',@R2,@R3),
                    (CONVERT(TINYINT,3),'R3',@R3,@R4),
                    (CONVERT(TINYINT,4),'R4',@R4,@R5),
                    (CONVERT(TINYINT,5),'R5',@R5,@R6),
                    (CONVERT(TINYINT,6),'R6',@R6,@R7)
                ) AS Pair(AdderIndex,DestinationRegister,OperandA,OperandB)
                CROSS APPLY dbo.Trace_BCD4_Add(Pair.OperandA,Pair.OperandB) AS Signal;
                IF @@ROWCOUNT <> 28
                    THROW 50712, 'Invalid BCD prevented a complete logic trace.', 1;
            END;

            SET @N0=dbo.Add_BCD_4Digit(@R0,@R1);
            SET @N1=dbo.Add_BCD_4Digit(@R1,@R2);
            SET @N2=dbo.Add_BCD_4Digit(@R2,@R3);
            SET @N3=dbo.Add_BCD_4Digit(@R3,@R4);
            SET @N4=dbo.Add_BCD_4Digit(@R4,@R5);
            SET @N5=dbo.Add_BCD_4Digit(@R5,@R6);
            SET @N6=dbo.Add_BCD_4Digit(@R6,@R7);
            IF @N0 IS NULL OR @N1 IS NULL OR @N2 IS NULL OR @N3 IS NULL
               OR @N4 IS NULL OR @N5 IS NULL OR @N6 IS NULL
                THROW 50713, 'A run register contains invalid packed BCD.', 1;

            SELECT @R0=@N0,@R1=@N1,@R2=@N2,@R3=@N3,
                   @R4=@N4,@R5=@N5,@R6=@N6;
            SET @StepNo += 1; SET @X += 1;
            INSERT dbo.DifferenceEngineRunState
                (RunID,StepNo,X_Value,R0,R1,R2,R3,R4,R5,R6,R7)
            VALUES
                (@RunID,@StepNo,@X,@R0,@R1,@R2,@R3,@R4,@R5,@R6,@R7);
            SET @Iteration += 1;
        END;
    COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE dbo.DeleteDifferenceEngineRun
    @RunID UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DELETE dbo.DifferenceEngineRun WHERE RunID=@RunID;
    IF @@ROWCOUNT=0 THROW 50720, 'RunID was not found.', 1;
END;
GO
