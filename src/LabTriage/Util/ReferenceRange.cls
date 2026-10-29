/// Decides whether a valid, non-critical exam is normal or abnormal, from the
/// laboratory flag and the reference range (OBX-7). Abnormal exams go to the agent.
Class LabTriage.Util.ReferenceRange
{
    /// Classifies a valid, non-critical exam against its reference range and flag.
    /// Returns "NORMAL", "ABNORMAL" or "UNPARSEABLE".
    ClassMethod Classify(pExam As LabTriage.Msg.ExamResult) As %String
    {
        Set tAbnormalFlag = pExam.AbnormalFlag
        Set tReferenceRange = pExam.ReferenceRange
        Set tNumericValue = pExam.NumericValue

        // The laboratory flag wins: H, L and A are the abnormal category.
        // TODO (Fri 10-30): read abnormal flags (H, L, A) from the Lookup Table.
        If ((tAbnormalFlag = "H") || (tAbnormalFlag = "L") || (tAbnormalFlag = "A"))
        {
            Return "ABNORMAL"
        }

        // Only a-b, <x and >x are read; anything else (including spaces) is UNPARSEABLE and goes to review.
        Set tFirstChar = $EXTRACT(tReferenceRange, 1)

        // <x: normal below x. >x: normal above x. A value equal to x is abnormal.
        If ((tFirstChar = "<") || (tFirstChar = ">"))
        {
            Set tValueReference = $EXTRACT(tReferenceRange, 2, *)

            If ('$ISVALIDNUM(tValueReference))
            {
                Return "UNPARSEABLE"
            }

            // '< means "not less than" (greater or equal); '> means "not greater than" (less or equal).
            If (((tFirstChar = "<") && (tNumericValue '< tValueReference)) || ((tFirstChar = ">") && (tNumericValue '> tValueReference)))
            {
                Return "ABNORMAL"
            }

            Return "NORMAL"
        }

        // a-b: normal from a to b, bounds included (as in HL7).
        Set tPartsCount = $LENGTH(tReferenceRange, "-")

        If (tPartsCount = 2)
        {
            Set tValue1 = $PIECE(tReferenceRange, "-", 1)
            Set tValue2 = $PIECE(tReferenceRange, "-", 2)

            If (('$ISVALIDNUM(tValue1)) || ('$ISVALIDNUM(tValue2)))
            {
                Return "UNPARSEABLE"
            }

            If ((tNumericValue < tValue1) || (tNumericValue > tValue2))
            {
                Return "ABNORMAL"
            }

            Return "NORMAL"
        }

        Return "UNPARSEABLE"
    }
}