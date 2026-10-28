/// Unit tests for LabTriage.Rules.CriticalLimits.Check.
/// Limits come from LabTriage.ExamCatalog (fictional, exclusive: a value equal to the
/// limit is not critical). Exams are built in memory and never saved.
Class LabTriage.Rules.TestCriticalLimits Extends %UnitTest.TestCase
{

    /// Builds an in-memory exam. The unit defaults to the catalog unit.
    Method NewExam(pLoinc As %String, pValue, pFlag As %String = "N", pUnit As %String = "") As LabTriage.Msg.ExamResult
    {
        Set tExam = ##class(LabTriage.Msg.ExamResult).%New()
        Set tExam.LoincCode = pLoinc
        Set tExam.RawValue = pValue
        Set tExam.NumericValue = pValue
        Set tExam.AbnormalFlag = pFlag
        If (pUnit = "")
        {
            Set tEntry = ##class(LabTriage.ExamCatalog).Lookup(pLoinc)
            If $ISOBJECT(tEntry)
            {
                Set pUnit = tEntry.unit
            }
        }
        Set tExam.Unit = pUnit
        Set tExam.ResultStatus = "F"
        Return tExam
    }

    /// Runs Check and asserts the return and pReasonCode. When the result is not
    /// CRITICAL, pReason must be empty.
    Method AssertCheck(pExam As LabTriage.Msg.ExamResult, pExpected As %String, pExpectedCode As %String, Output pReason As %String)
    {
        Set tCase = pExam.LoincCode_" value="_pExam.NumericValue_" flag="_pExam.AbnormalFlag
        Set tReturn = ##class(LabTriage.Rules.CriticalLimits).Check(pExam, .tReasonCode, .pReason)
        Do $$$AssertEquals(tReturn, pExpected, tCase_": return is "_pExpected)
        Do $$$AssertEquals(tReasonCode, pExpectedCode, tCase_": pReasonCode is '"_pExpectedCode_"'")
        If (pExpected '= "CRITICAL")
        {
            Do $$$AssertEquals(pReason, "", tCase_": pReason is empty")
        }
    }

    /// Asserts that pReason contains pText.
    Method AssertReasonHas(pReason As %String, pText As %String)
    {
        Do $$$AssertTrue(pReason [ pText, "pReason contains '"_pText_"': "_pReason)
    }

    // ---- Hemoglobin 718-7: low 7.0, high 20.0 ----

    Method TestHemoglobinBelowLowLimit()
    {
        Do ..AssertCheck(..NewExam("718-7", 6.99, "N"), "CRITICAL", "CRITICAL_LOW", .tReason)
        Do ..AssertReasonHas(tReason, "6.99 g/dL")
        Do ..AssertReasonHas(tReason, "limit of 7 g/dL")
    }

    Method TestHemoglobinAtLowLimit()
    {
        Do ..AssertCheck(..NewExam("718-7", 7.0, "N"), "OK", "")
    }

    Method TestHemoglobinAtHighLimit()
    {
        Do ..AssertCheck(..NewExam("718-7", 20.0, "N"), "OK", "")
    }

    Method TestHemoglobinAboveHighLimit()
    {
        Do ..AssertCheck(..NewExam("718-7", 20.01, "N"), "CRITICAL", "CRITICAL_HIGH", .tReason)
        Do ..AssertReasonHas(tReason, "20.01 g/dL")
        Do ..AssertReasonHas(tReason, "limit of 20 g/dL")
    }

    Method TestHemoglobinWithinLimitsFlagLL()
    {
        Do ..AssertCheck(..NewExam("718-7", 13.0, "LL"), "CRITICAL", "CRITICAL_LAB_FLAG", .tReason)
        Do ..AssertReasonHas(tReason, "13 g/dL")
        Do ..AssertReasonHas(tReason, "flagged it as LL")
    }

    Method TestHemoglobinWithinLimitsFlagAA()
    {
        Do ..AssertCheck(..NewExam("718-7", 13.0, "AA"), "CRITICAL", "CRITICAL_LAB_FLAG", .tReason)
        Do ..AssertReasonHas(tReason, "flagged it as AA")
    }

    Method TestHemoglobinNegativeValue()
    {
        Do ..AssertCheck(..NewExam("718-7", -1, "N"), "CRITICAL", "CRITICAL_LOW", .tReason)
        Do ..AssertReasonHas(tReason, "-1 g/dL")
        Do ..AssertReasonHas(tReason, "limit of 7 g/dL")
    }

    // ---- Potassium 2823-3: low 2.8, high 6.2 ----

    Method TestPotassiumBelowLowLimit()
    {
        Do ..AssertCheck(..NewExam("2823-3", 2.79, "L"), "CRITICAL", "CRITICAL_LOW", .tReason)
        Do ..AssertReasonHas(tReason, "2.79 mmol/L")
        Do ..AssertReasonHas(tReason, "limit of 2.8 mmol/L")
    }

    Method TestPotassiumAtLowLimit()
    {
        Do ..AssertCheck(..NewExam("2823-3", 2.8, "L"), "OK", "")
    }

    Method TestPotassiumAtHighLimitFlagH()
    {
        Do ..AssertCheck(..NewExam("2823-3", 6.2, "H"), "OK", "")
    }

    Method TestPotassiumAboveHighLimitFlagH()
    {
        Do ..AssertCheck(..NewExam("2823-3", 6.21, "H"), "CRITICAL", "CRITICAL_HIGH", .tReason)
        Do ..AssertReasonHas(tReason, "6.21 mmol/L")
        Do ..AssertReasonHas(tReason, "limit of 6.2 mmol/L")
    }

    /// Five decimal places (NumericValue SCALE) just above the limit.
    Method TestPotassiumJustAboveHighLimitDecimals()
    {
        Do ..AssertCheck(..NewExam("2823-3", 6.20001, "H"), "CRITICAL", "CRITICAL_HIGH", .tReason)
        Do ..AssertReasonHas(tReason, "6.20001 mmol/L")
        Do ..AssertReasonHas(tReason, "limit of 6.2 mmol/L")
    }

    /// The limit wins over the flag: the reason is CRITICAL_HIGH, not CRITICAL_LAB_FLAG.
    Method TestPotassiumAboveHighLimitFlagHH()
    {
        Do ..AssertCheck(..NewExam("2823-3", 6.8, "HH"), "CRITICAL", "CRITICAL_HIGH", .tReason)
        Do ..AssertReasonHas(tReason, "6.8 mmol/L")
        Do ..AssertReasonHas(tReason, "limit of 6.2 mmol/L")
    }

    Method TestPotassiumWithinLimitsFlagHH()
    {
        Do ..AssertCheck(..NewExam("2823-3", 6.0, "HH"), "CRITICAL", "CRITICAL_LAB_FLAG", .tReason)
        Do ..AssertReasonHas(tReason, "6 mmol/L")
        Do ..AssertReasonHas(tReason, "flagged it as HH")
    }

    /// H is abnormal, not critical.
    Method TestPotassiumWithinLimitsFlagH()
    {
        Do ..AssertCheck(..NewExam("2823-3", 5.6, "H"), "OK", "")
    }

    // ---- Creatinine 2160-0: no low limit, high 4.0 ----

    /// Values below 1 are passed as strings, as FileInbound sets them (NumericValue = RawValue):
    /// the numeric literal 0.1 is canonical .1 and the reason would read ".1 mg/dL".
    Method TestCreatinineNoLowLimit()
    {
        Do ..AssertCheck(..NewExam("2160-0", "0.1", "N"), "OK", "")
    }

    Method TestCreatinineNoLowLimitFlagLL()
    {
        Do ..AssertCheck(..NewExam("2160-0", "0.1", "LL"), "CRITICAL", "CRITICAL_LAB_FLAG", .tReason)
        Do ..AssertReasonHas(tReason, "0.1 mg/dL")
        Do ..AssertReasonHas(tReason, "flagged it as LL")
    }

    Method TestCreatinineAtHighLimit()
    {
        Do ..AssertCheck(..NewExam("2160-0", 4.0, "H"), "OK", "")
    }

    Method TestCreatinineAboveHighLimit()
    {
        Do ..AssertCheck(..NewExam("2160-0", 4.01, "H"), "CRITICAL", "CRITICAL_HIGH", .tReason)
        Do ..AssertReasonHas(tReason, "4.01 mg/dL")
        Do ..AssertReasonHas(tReason, "limit of 4 mg/dL")
    }

    // ---- Glucose 2345-7: low 50, high 400 ----

    Method TestGlucoseBelowLowLimit()
    {
        Do ..AssertCheck(..NewExam("2345-7", 49.9, "L"), "CRITICAL", "CRITICAL_LOW", .tReason)
        Do ..AssertReasonHas(tReason, "49.9 mg/dL")
        Do ..AssertReasonHas(tReason, "limit of 50 mg/dL")
    }

    Method TestGlucoseAtLowLimit()
    {
        Do ..AssertCheck(..NewExam("2345-7", 50, "L"), "OK", "")
    }

    Method TestGlucoseAtHighLimit()
    {
        Do ..AssertCheck(..NewExam("2345-7", 400, "H"), "OK", "")
    }

    Method TestGlucoseAboveHighLimit()
    {
        Do ..AssertCheck(..NewExam("2345-7", 400.1, "H"), "CRITICAL", "CRITICAL_HIGH", .tReason)
        Do ..AssertReasonHas(tReason, "400.1 mg/dL")
        Do ..AssertReasonHas(tReason, "limit of 400 mg/dL")
    }

    // ---- Sodium 2951-2: low 120, high 160 ----

    Method TestSodiumBelowLowLimit()
    {
        Do ..AssertCheck(..NewExam("2951-2", 119.9, "L"), "CRITICAL", "CRITICAL_LOW", .tReason)
        Do ..AssertReasonHas(tReason, "119.9 mmol/L")
        Do ..AssertReasonHas(tReason, "limit of 120 mmol/L")
    }

    Method TestSodiumAtLowLimit()
    {
        Do ..AssertCheck(..NewExam("2951-2", 120, "L"), "OK", "")
    }

    Method TestSodiumAtHighLimit()
    {
        Do ..AssertCheck(..NewExam("2951-2", 160, "H"), "OK", "")
    }

    Method TestSodiumAboveHighLimit()
    {
        Do ..AssertCheck(..NewExam("2951-2", 160.1, "H"), "CRITICAL", "CRITICAL_HIGH", .tReason)
        Do ..AssertReasonHas(tReason, "160.1 mmol/L")
        Do ..AssertReasonHas(tReason, "limit of 160 mmol/L")
    }

    // ---- Not evaluable and determinism ----

    /// TSH is not in the exam catalog: NOT_EVALUABLE, never OK.
    Method TestUnsupportedExam()
    {
        Do ..AssertCheck(..NewExam("3016-3", 2.1, "N", "mIU/L"), "NOT_EVALUABLE", "")
    }

    /// Same input, same output: the same object twice and an equal second object.
    Method TestSameInputSameOutput()
    {
        Set tExam = ..NewExam("2823-3", 6.8, "HH")
        Set tFirst = ##class(LabTriage.Rules.CriticalLimits).Check(tExam, .tFirstCode, .tFirstReason)
        Set tSecond = ##class(LabTriage.Rules.CriticalLimits).Check(tExam, .tSecondCode, .tSecondReason)
        Set tThird = ##class(LabTriage.Rules.CriticalLimits).Check(..NewExam("2823-3", 6.8, "HH"), .tThirdCode, .tThirdReason)

        Do $$$AssertEquals(tFirst, "CRITICAL", "first call is CRITICAL")
        Do $$$AssertEquals(tSecond, tFirst, "second call: same return")
        Do $$$AssertEquals(tSecondCode, tFirstCode, "second call: same pReasonCode")
        Do $$$AssertEquals(tSecondReason, tFirstReason, "second call: same pReason")
        Do $$$AssertEquals(tThird, tFirst, "equal object: same return")
        Do $$$AssertEquals(tThirdCode, tFirstCode, "equal object: same pReasonCode")
        Do $$$AssertEquals(tThirdReason, tFirstReason, "equal object: same pReason")
    }

}
