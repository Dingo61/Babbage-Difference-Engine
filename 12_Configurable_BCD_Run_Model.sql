/*
    Add configurable four- or eight-digit packed-BCD words to Streamlit runs.

    Existing four-digit experiments remain valid. BIGINT safely stores eight
    packed BCD nibbles such as 0x99999999, which exceeds a signed SQL INT.
*/
USE difference_engine;
GO

CREATE OR ALTER FUNCTION dbo.Decimal_To_PackedBCD
(
    @DecimalValue BIGINT,
    @Digits TINYINT
)
RETURNS BIGINT
AS
BEGIN
    IF @Digits NOT IN (4, 8) RETURN NULL;
    DECLARE @Limit BIGINT = CASE @Digits WHEN 4 THEN 10000 ELSE 100000000 END;
    IF @DecimalValue < 0 OR @DecimalValue >= @Limit RETURN NULL;

    DECLARE @Remaining BIGINT = @DecimalValue;
    DECLARE @Packed BIGINT = 0;
    DECLARE @Place BIGINT = 1;
    DECLARE @Index TINYINT = 0;
    WHILE @Index < @Digits
    BEGIN
        SET @Packed += (@Remaining % 10) * @Place;
        SET @Remaining /= 10;
        SET @Place *= 16;
        SET @Index += 1;
    END;
    RETURN @Packed;
END;
GO

CREATE OR ALTER FUNCTION dbo.Add_PackedBCD
(
    @A BIGINT,
    @B BIGINT,
    @Digits TINYINT
)
RETURNS BIGINT
AS
BEGIN
    IF @A IS NULL OR @B IS NULL OR @Digits NOT IN (4, 8) RETURN NULL;

    DECLARE @Result BIGINT = 0;
    DECLARE @Place BIGINT = 1;
    DECLARE @Carry TINYINT = 0;
    DECLARE @Index TINYINT = 0;
    WHILE @Index < @Digits
    BEGIN
        DECLARE @ADigit TINYINT = (@A / @Place) & 15;
        DECLARE @BDigit TINYINT = (@B / @Place) & 15;
        IF @ADigit > 9 OR @BDigit > 9 RETURN NULL;

        DECLARE @Sum TINYINT = @ADigit + @BDigit + @Carry;
        SET @Carry = 0;
        IF @Sum > 9
        BEGIN
            SET @Sum = (@Sum + 6) & 15;
            SET @Carry = 1;
        END;
        SET @Result += CONVERT(BIGINT, @Sum) * @Place;
        SET @Place *= 16;
        SET @Index += 1;
    END;
    -- Carry beyond the configured most-significant digit is discarded.
    RETURN @Result;
END;
GO

CREATE OR ALTER FUNCTION dbo.Format_PackedBCD
(
    @BCD BIGINT,
    @Digits TINYINT
)
RETURNS VARCHAR(8)
AS
BEGIN
    IF @BCD IS NULL OR @Digits NOT IN (4, 8) RETURN NULL;
    DECLARE @Text VARCHAR(8) = '';
    DECLARE @Place BIGINT = CASE @Digits WHEN 4 THEN 4096 ELSE 268435456 END;
    DECLARE @Index TINYINT = 0;
    WHILE @Index < @Digits
    BEGIN
        DECLARE @Digit TINYINT = (@BCD / @Place) & 15;
        IF @Digit > 9 RETURN REPLICATE('?', @Digits);
        SET @Text += CHAR(ASCII('0') + @Digit);
        SET @Place /= 16;
        SET @Index += 1;
    END;
    RETURN @Text;
END;
GO

CREATE OR ALTER FUNCTION dbo.Trace_PackedBCD_Add
(
    @A BIGINT,
    @B BIGINT,
    @Digits TINYINT
)
RETURNS @Signals TABLE
(
    DigitIndex TINYINT NOT NULL,
    A_Digit TINYINT NULL, B_Digit TINYINT NULL, CarryIn TINYINT NULL,
    RawBinarySum TINYINT NULL, C4 TINYINT NULL,
    S3 TINYINT NULL, S2 TINYINT NULL, S1 TINYINT NULL, S0 TINYINT NULL,
    Gate_S3_AND_S2 TINYINT NULL, Gate_S3_AND_S1 TINYINT NULL,
    CorrectionK TINYINT NULL, CorrectionAddend TINYINT NULL,
    CorrectedDigit TINYINT NULL, CarryOut TINYINT NULL,
    IsValidBCD BIT NOT NULL
)
AS
BEGIN
    IF @A IS NULL OR @B IS NULL OR @Digits NOT IN (4, 8) RETURN;
    DECLARE @Place BIGINT = 1;
    DECLARE @Index TINYINT = 0;
    DECLARE @Carry TINYINT = 0;
    WHILE @Index < @Digits
    BEGIN
        DECLARE @ADigit TINYINT = (@A / @Place) & 15;
        DECLARE @BDigit TINYINT = (@B / @Place) & 15;
        IF @ADigit > 9 OR @BDigit > 9
        BEGIN
            INSERT @Signals (DigitIndex,A_Digit,B_Digit,CarryIn,IsValidBCD)
            VALUES (@Index,@ADigit,@BDigit,@Carry,0);
            RETURN;
        END;

        DECLARE @Raw TINYINT = @ADigit + @BDigit + @Carry;
        DECLARE @C4 TINYINT = @Raw / 16;
        DECLARE @S TINYINT = @Raw & 15;
        DECLARE @S3 TINYINT = (@S / 8) & 1;
        DECLARE @S2 TINYINT = (@S / 4) & 1;
        DECLARE @S1 TINYINT = (@S / 2) & 1;
        DECLARE @S0 TINYINT = @S & 1;
        DECLARE @Gate32 TINYINT = @S3 & @S2;
        DECLARE @Gate31 TINYINT = @S3 & @S1;
        DECLARE @K TINYINT = CASE
            WHEN @C4=1 OR @Gate32=1 OR @Gate31=1 THEN 1 ELSE 0 END;
        DECLARE @Corrected TINYINT = (@S + @K * 6) & 15;

        INSERT @Signals VALUES
            (@Index,@ADigit,@BDigit,@Carry,@Raw,@C4,@S3,@S2,@S1,@S0,
             @Gate32,@Gate31,@K,@K*6,@Corrected,@K,1);
        SET @Carry=@K; SET @Place*=16; SET @Index+=1;
    END;
    RETURN;
END;
GO

-- Widen existing packed registers before an eight-digit value is stored.
DECLARE @ColumnName SYSNAME;
DECLARE RegisterColumns CURSOR LOCAL FAST_FORWARD FOR
    SELECT name FROM sys.columns
    WHERE object_id=OBJECT_ID(N'dbo.DifferenceEngineRunState')
      AND name IN ('R0','R1','R2','R3','R4','R5','R6','R7')
      AND system_type_id=TYPE_ID(N'int');
OPEN RegisterColumns;
FETCH NEXT FROM RegisterColumns INTO @ColumnName;
WHILE @@FETCH_STATUS=0
BEGIN
    DECLARE @AlterSql NVARCHAR(400) =
        N'ALTER TABLE dbo.DifferenceEngineRunState ALTER COLUMN '
        + QUOTENAME(@ColumnName) + N' BIGINT NOT NULL;';
    EXEC sys.sp_executesql @AlterSql;
    FETCH NEXT FROM RegisterColumns INTO @ColumnName;
END;
CLOSE RegisterColumns;
DEALLOCATE RegisterColumns;
GO

IF COL_LENGTH('dbo.DifferenceEngineRun','RegisterDigits') IS NULL
BEGIN
    ALTER TABLE dbo.DifferenceEngineRun ADD RegisterDigits TINYINT NOT NULL
        CONSTRAINT DF_DifferenceEngineRun_RegisterDigits DEFAULT (4);
END;
GO

IF OBJECT_ID(N'dbo.CK_DifferenceEngineRun_RegisterDigits', N'C') IS NULL
BEGIN
    ALTER TABLE dbo.DifferenceEngineRun ADD CONSTRAINT
        CK_DifferenceEngineRun_RegisterDigits CHECK (RegisterDigits IN (4,8));
END;
GO

CREATE OR ALTER PROCEDURE dbo.CreateDifferenceEngineRun
    @RunID UNIQUEIDENTIFIER,
    @RunName NVARCHAR(100),
    @Degree TINYINT,
    @A7 DECIMAL(18,0)=0, @A6 DECIMAL(18,0)=0,
    @A5 DECIMAL(18,0)=0, @A4 DECIMAL(18,0)=0,
    @A3 DECIMAL(18,0)=0, @A2 DECIMAL(18,0)=0,
    @A1 DECIMAL(18,0)=0, @A0 DECIMAL(18,0)=0,
    @X0 BIGINT=0,
    @RegisterDigits TINYINT=4
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @RunID IS NULL THROW 50700,'RunID is required.',1;
    IF NULLIF(LTRIM(RTRIM(@RunName)),N'') IS NULL THROW 50701,'RunName is required.',1;
    IF @Degree NOT BETWEEN 0 AND 7 THROW 50702,'Degree must be between 0 and 7.',1;
    IF @RegisterDigits NOT IN (4,8) THROW 50707,'RegisterDigits must be 4 or 8.',1;
    IF EXISTS(SELECT 1 FROM dbo.DifferenceEngineRun WHERE RunID=@RunID)
        THROW 50703,'RunID already exists.',1;
    IF (@Degree<7 AND @A7<>0) OR (@Degree<6 AND @A6<>0)
       OR (@Degree<5 AND @A5<>0) OR (@Degree<4 AND @A4<>0)
       OR (@Degree<3 AND @A3<>0) OR (@Degree<2 AND @A2<>0)
       OR (@Degree<1 AND @A1<>0)
        THROW 50704,'Coefficients above the selected degree must be zero.',1;
    IF (@Degree=7 AND @A7=0) OR (@Degree=6 AND @A6=0)
       OR (@Degree=5 AND @A5=0) OR (@Degree=4 AND @A4=0)
       OR (@Degree=3 AND @A3=0) OR (@Degree=2 AND @A2=0)
       OR (@Degree=1 AND @A1=0)
        THROW 50705,'The coefficient at the selected degree must be nonzero.',1;

    DECLARE @Samples TABLE(Position TINYINT PRIMARY KEY,Value DECIMAL(38,0));
    DECLARE @Differences TABLE(DifferenceOrder TINYINT PRIMARY KEY,Value DECIMAL(38,0));
    DECLARE @Position TINYINT=0;
    WHILE @Position<=7
    BEGIN
        DECLARE @X DECIMAL(38,0)=@X0+@Position;
        DECLARE @Fx DECIMAL(38,0)=@A7;
        SET @Fx=@Fx*@X+@A6; SET @Fx=@Fx*@X+@A5;
        SET @Fx=@Fx*@X+@A4; SET @Fx=@Fx*@X+@A3;
        SET @Fx=@Fx*@X+@A2; SET @Fx=@Fx*@X+@A1;
        SET @Fx=@Fx*@X+@A0;
        INSERT @Samples VALUES(@Position,@Fx); SET @Position+=1;
    END;
    DECLARE @Order TINYINT=0;
    WHILE @Order<=7
    BEGIN
        INSERT @Differences SELECT @Order,Value FROM @Samples WHERE Position=0;
        UPDATE C SET Value=N.Value-C.Value
        FROM @Samples C JOIN @Samples N ON N.Position=C.Position+1
        WHERE C.Position<7-@Order;
        SET @Order+=1;
    END;
    DECLARE @Limit BIGINT=CASE @RegisterDigits WHEN 4 THEN 10000 ELSE 100000000 END;
    IF EXISTS(SELECT 1 FROM @Differences WHERE Value<0 OR Value>=@Limit)
        THROW 50706,'Initial differences do not fit the selected unsigned BCD width.',1;

    DECLARE @R0 BIGINT,@R1 BIGINT,@R2 BIGINT,@R3 BIGINT;
    DECLARE @R4 BIGINT,@R5 BIGINT,@R6 BIGINT,@R7 BIGINT;
    SELECT @R0=dbo.Decimal_To_PackedBCD(CONVERT(BIGINT,Value),@RegisterDigits) FROM @Differences WHERE DifferenceOrder=0;
    SELECT @R1=dbo.Decimal_To_PackedBCD(CONVERT(BIGINT,Value),@RegisterDigits) FROM @Differences WHERE DifferenceOrder=1;
    SELECT @R2=dbo.Decimal_To_PackedBCD(CONVERT(BIGINT,Value),@RegisterDigits) FROM @Differences WHERE DifferenceOrder=2;
    SELECT @R3=dbo.Decimal_To_PackedBCD(CONVERT(BIGINT,Value),@RegisterDigits) FROM @Differences WHERE DifferenceOrder=3;
    SELECT @R4=dbo.Decimal_To_PackedBCD(CONVERT(BIGINT,Value),@RegisterDigits) FROM @Differences WHERE DifferenceOrder=4;
    SELECT @R5=dbo.Decimal_To_PackedBCD(CONVERT(BIGINT,Value),@RegisterDigits) FROM @Differences WHERE DifferenceOrder=5;
    SELECT @R6=dbo.Decimal_To_PackedBCD(CONVERT(BIGINT,Value),@RegisterDigits) FROM @Differences WHERE DifferenceOrder=6;
    SELECT @R7=dbo.Decimal_To_PackedBCD(CONVERT(BIGINT,Value),@RegisterDigits) FROM @Differences WHERE DifferenceOrder=7;

    BEGIN TRANSACTION;
      INSERT dbo.DifferenceEngineRun
        (RunID,RunName,Degree,X0,A7,A6,A5,A4,A3,A2,A1,A0,RegisterDigits)
      VALUES(@RunID,LTRIM(RTRIM(@RunName)),@Degree,@X0,
        @A7,@A6,@A5,@A4,@A3,@A2,@A1,@A0,@RegisterDigits);
      INSERT dbo.DifferenceEngineRunState
        (RunID,StepNo,X_Value,R0,R1,R2,R3,R4,R5,R6,R7)
      VALUES(@RunID,0,@X0,@R0,@R1,@R2,@R3,@R4,@R5,@R6,@R7);
    COMMIT;
END;
GO

CREATE OR ALTER PROCEDURE dbo.StepDifferenceEngineRun
    @RunID UNIQUEIDENTIFIER,@Cranks INT=1,@CaptureLogic BIT=1
AS
BEGIN
    SET NOCOUNT ON; SET XACT_ABORT ON;
    IF @Cranks NOT BETWEEN 1 AND 1000 THROW 50710,'Cranks must be between 1 and 1000.',1;
    DECLARE @Digits TINYINT;
    SELECT @Digits=RegisterDigits FROM dbo.DifferenceEngineRun WHERE RunID=@RunID;
    IF @Digits IS NULL THROW 50711,'RunID was not found.',1;

    DECLARE @StepNo INT,@X BIGINT,@Iteration INT=0;
    DECLARE @R0 BIGINT,@R1 BIGINT,@R2 BIGINT,@R3 BIGINT;
    DECLARE @R4 BIGINT,@R5 BIGINT,@R6 BIGINT,@R7 BIGINT;
    DECLARE @N0 BIGINT,@N1 BIGINT,@N2 BIGINT,@N3 BIGINT;
    DECLARE @N4 BIGINT,@N5 BIGINT,@N6 BIGINT;
    BEGIN TRANSACTION;
      SELECT TOP(1) @StepNo=StepNo,@X=X_Value,
        @R0=R0,@R1=R1,@R2=R2,@R3=R3,@R4=R4,@R5=R5,@R6=R6,@R7=R7
      FROM dbo.DifferenceEngineRunState WITH(UPDLOCK,HOLDLOCK)
      WHERE RunID=@RunID ORDER BY StepNo DESC;
      IF @StepNo IS NULL THROW 50711,'RunID has no state.',1;

      WHILE @Iteration<@Cranks
      BEGIN
        IF @CaptureLogic=1
        BEGIN
          INSERT dbo.DifferenceEngineRunLogicTrace
          (RunID,SourceStepNo,X_Before,AdderIndex,DestinationRegister,
           DigitIndex,A_Digit,B_Digit,CarryIn,RawBinarySum,C4,S3,S2,S1,S0,
           Gate_S3_AND_S2,Gate_S3_AND_S1,CorrectionK,CorrectionAddend,
           CorrectedDigit,CarryOut)
          SELECT @RunID,@StepNo,@X,P.AdderIndex,P.DestinationRegister,
           S.DigitIndex,S.A_Digit,S.B_Digit,S.CarryIn,S.RawBinarySum,S.C4,
           S.S3,S.S2,S.S1,S.S0,S.Gate_S3_AND_S2,S.Gate_S3_AND_S1,
           S.CorrectionK,S.CorrectionAddend,S.CorrectedDigit,S.CarryOut
          FROM(VALUES
           (CONVERT(TINYINT,0),'R0',@R0,@R1),(CONVERT(TINYINT,1),'R1',@R1,@R2),
           (CONVERT(TINYINT,2),'R2',@R2,@R3),(CONVERT(TINYINT,3),'R3',@R3,@R4),
           (CONVERT(TINYINT,4),'R4',@R4,@R5),(CONVERT(TINYINT,5),'R5',@R5,@R6),
           (CONVERT(TINYINT,6),'R6',@R6,@R7)
          )P(AdderIndex,DestinationRegister,OperandA,OperandB)
          CROSS APPLY dbo.Trace_PackedBCD_Add(P.OperandA,P.OperandB,@Digits)S;
          DECLARE @TraceRows INT=@@ROWCOUNT;
          IF @TraceRows<>7*@Digits THROW 50712,'Incomplete packed-BCD logic trace.',1;
        END;
        SET @N0=dbo.Add_PackedBCD(@R0,@R1,@Digits);
        SET @N1=dbo.Add_PackedBCD(@R1,@R2,@Digits);
        SET @N2=dbo.Add_PackedBCD(@R2,@R3,@Digits);
        SET @N3=dbo.Add_PackedBCD(@R3,@R4,@Digits);
        SET @N4=dbo.Add_PackedBCD(@R4,@R5,@Digits);
        SET @N5=dbo.Add_PackedBCD(@R5,@R6,@Digits);
        SET @N6=dbo.Add_PackedBCD(@R6,@R7,@Digits);
        IF @N0 IS NULL OR @N1 IS NULL OR @N2 IS NULL OR @N3 IS NULL
           OR @N4 IS NULL OR @N5 IS NULL OR @N6 IS NULL
          THROW 50713,'A run register contains invalid packed BCD.',1;
        SELECT @R0=@N0,@R1=@N1,@R2=@N2,@R3=@N3,@R4=@N4,@R5=@N5,@R6=@N6;
        SET @StepNo+=1; SET @X+=1;
        INSERT dbo.DifferenceEngineRunState
          (RunID,StepNo,X_Value,R0,R1,R2,R3,R4,R5,R6,R7)
        VALUES(@RunID,@StepNo,@X,@R0,@R1,@R2,@R3,@R4,@R5,@R6,@R7);
        SET @Iteration+=1;
      END;
    COMMIT;
END;
GO
