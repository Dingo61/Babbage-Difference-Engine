/*
    Stage 2: a two-decimal-digit packed-BCD adder.

    Bits 7..4 hold tens and bits 3..0 hold ones. A physical corrected BCD
    digit normally uses two 74LS283 adders; a two-digit adder therefore uses
    four 74LS283 packages, plus correction gates.
*/
USE difference_engine;
GO

CREATE OR ALTER FUNCTION dbo.Add_BCD_2Digit (@A TINYINT, @B TINYINT)
RETURNS TINYINT
AS
BEGIN
    IF @A IS NULL OR @B IS NULL RETURN NULL;

    -- Split each packed byte into its decimal digit nibbles.
    DECLARE @A_Ones TINYINT = @A & 15;
    DECLARE @B_Ones TINYINT = @B & 15;
    DECLARE @A_Tens TINYINT = (@A / 16) & 15;
    DECLARE @B_Tens TINYINT = (@B / 16) & 15;

    -- Nibbles A..F are not valid decimal digits. A function cannot THROW,
    -- so NULL is used to expose malformed BCD to its caller.
    IF @A_Ones > 9 OR @B_Ones > 9 OR @A_Tens > 9 OR @B_Tens > 9
        RETURN NULL;

    -- Add the ones digit and apply the classic add-six correction.
    DECLARE @Sum_Ones TINYINT = @A_Ones + @B_Ones;
    DECLARE @Carry_Ones TINYINT = 0;
    IF @Sum_Ones > 9
    BEGIN
        SET @Sum_Ones = (@Sum_Ones + 6) & 15;
        SET @Carry_Ones = 1;
    END;

    -- Carry from ones becomes carry-in to the tens digit.
    DECLARE @Sum_Tens TINYINT = @A_Tens + @B_Tens + @Carry_Ones;
    IF @Sum_Tens > 9
    BEGIN
        -- Discarding carry here models a two-digit register wrapping at 100.
        SET @Sum_Tens = (@Sum_Tens + 6) & 15;
    END;

    RETURN (@Sum_Tens * 16) | @Sum_Ones;
END;
GO

-- Display the packed bytes in hexadecimal so their BCD digits are visible.
-- Expected outputs are 0x42, 0x00, and NULL respectively.
SELECT CONVERT(BINARY(1), dbo.Add_BCD_2Digit(0x15, 0x27)) AS [15_plus_27],
       CONVERT(BINARY(1), dbo.Add_BCD_2Digit(0x99, 0x01)) AS [99_plus_01_wraps],
       CONVERT(BINARY(1), dbo.Add_BCD_2Digit(0x1A, 0x01)) AS [Invalid_BCD_returns_NULL];
GO
