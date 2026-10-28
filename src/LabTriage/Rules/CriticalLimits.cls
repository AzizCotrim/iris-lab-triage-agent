/// Decides whether a valid exam is critical, from the exam catalog limits
/// and the laboratory flag. Limits are fictional and exclusive: a value equal
/// to the limit is not critical.
Class LabTriage.Rules.CriticalLimits
{
    /// Deterministic critical-value rule. Returns "CRITICAL", "OK" or "NOT_EVALUABLE".
    /// When CRITICAL, pReasonCode is CRITICAL_LOW, CRITICAL_HIGH or CRITICAL_LAB_FLAG
    /// and pReason explains it.
    ClassMethod Check(pExam As LabTriage.Msg.ExamResult, Output pReasonCode As %String, Output pReason As %String) As %String
    {
        Set pReasonCode = ""
        Set pReason = ""
        Set tReturn = "OK"

        Set tEntry = ##class(LabTriage.ExamCatalog).Lookup(pExam.LoincCode)
        If '$ISOBJECT(tEntry)
        {
            Set tReturn = "NOT_EVALUABLE"
            Return tReturn
        }
        Set tNumericValue = pExam.NumericValue
        Set tName = tEntry.name
        Set tUnit = tEntry.unit
        Set tCriticalLow = tEntry.criticalLow
        Set tCriticalHigh = tEntry.criticalHigh

        // Limits are exclusive (< and >). An empty limit means the exam has no limit on that side.
        If ((tCriticalLow '= "") && (tNumericValue < tCriticalLow))
        {
            Set pReasonCode = "CRITICAL_LOW"
            Set pReason = tName_" "_tNumericValue_" "_tUnit_" is below the critical low limit of "_tCriticalLow_" "_tUnit_" (fictional limit)."
            Set tReturn = "CRITICAL"
        } 
        ElseIf ((tCriticalHigh '= "") && (tNumericValue > tCriticalHigh))
        {
            Set pReasonCode = "CRITICAL_HIGH"
            Set pReason = tName_" "_tNumericValue_" "_tUnit_" is above the critical high limit of "_tCriticalHigh_" "_tUnit_" (fictional limit)."
            Set tReturn = "CRITICAL"
        }

        // A value beyond a limit wins over the flag; the flag only counts when no limit was crossed.
        // TODO (Fri 10-30): read critical flags (HH, LL, AA) from the Lookup Table.
        If ((tReturn = "OK") && ((pExam.AbnormalFlag = "HH") || (pExam.AbnormalFlag = "LL") || (pExam.AbnormalFlag = "AA")))
        {
            Set pReasonCode = "CRITICAL_LAB_FLAG"
            Set pReason = tName_" "_tNumericValue_" "_tUnit_" is within the critical limits, but the laboratory flagged it as "_pExam.AbnormalFlag_"."
            Set tReturn = "CRITICAL"
        }

        Return tReturn
    }
}
