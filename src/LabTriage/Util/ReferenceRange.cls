/// Decides whether a valid, non-critical exam is normal or abnormal, from the
/// reference range (OBX-7) and the laboratory flag. Abnormal exams go to the agent.
Class LabTriage.Util.ReferenceRange
{
    /// Classifies a valid, non-critical exam against its reference range and flag.
    /// Returns "NORMAL", "ABNORMAL" or "UNPARSEABLE".
    /// An unreadable range always wins: the exam goes to review, even with an abnormal flag.
    ClassMethod Classify(pExam As LabTriage.Msg.ExamResult) As %String
    {
        Set tRangeResult = ..ClassifyRange(pExam.ReferenceRange, pExam.NumericValue)
        If (tRangeResult = "UNPARSEABLE")
        {
            Return "UNPARSEABLE"
        }

        // The laboratory flag wins over a readable range: H, L and A are the abnormal category.
        // TODO (Fri 10-30): read abnormal flags (H, L, A) from the Lookup Table.
        Set tAbnormalFlag = pExam.AbnormalFlag
        If ((tAbnormalFlag = "H") || (tAbnormalFlag = "L") || (tAbnormalFlag = "A"))
        {
            Return "ABNORMAL"
        }

        Return tRangeResult
    }

    /// Reads a reference range and compares a value with it. Returns "NORMAL", "ABNORMAL" or "UNPARSEABLE".
    /// Only a-b, <x and >x are read; anything else (including spaces) is UNPARSEABLE.
    /// Known limitation: a negative lower bound (e.g. -1-5) is not read.
    ClassMethod ClassifyRange(pReferenceRange As %String, pNumericValue As %Decimal) As %String
    {
        Set tFirstChar = $EXTRACT(pReferenceRange, 1)

        // <x: normal below x. >x: normal above x. A value equal to x is abnormal.
        If ((tFirstChar = "<") || (tFirstChar = ">"))
        {
            Set tValueReference = $EXTRACT(pReferenceRange, 2, *)

            If ('$ISVALIDNUM(tValueReference))
            {
                Return "UNPARSEABLE"
            }

            // '< means "not less than" (greater or equal); '> means "not greater than" (less or equal).
            If (((tFirstChar = "<") && (pNumericValue '< tValueReference)) || ((tFirstChar = ">") && (pNumericValue '> tValueReference)))
            {
                Return "ABNORMAL"
            }

            Return "NORMAL"
        }

        // a-b: normal from a to b, bounds included (as in HL7).
        If ($LENGTH(pReferenceRange, "-") = 2)
        {
            Set tValue1 = $PIECE(pReferenceRange, "-", 1)
            Set tValue2 = $PIECE(pReferenceRange, "-", 2)

            If (('$ISVALIDNUM(tValue1)) || ('$ISVALIDNUM(tValue2)))
            {
                Return "UNPARSEABLE"
            }

            If ((pNumericValue < tValue1) || (pNumericValue > tValue2))
            {
                Return "ABNORMAL"
            }

            Return "NORMAL"
        }

        Return "UNPARSEABLE"
    }
}