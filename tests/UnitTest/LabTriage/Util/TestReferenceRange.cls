/// Unit tests for LabTriage.Util.ReferenceRange.Classify.
/// a-b includes the bounds; in <x and >x the value x itself is abnormal.
/// Flags H, L and A make the exam abnormal even inside the range.
/// Exams are built in memory and never saved.
Class LabTriage.Util.TestReferenceRange Extends %UnitTest.TestCase
{

    /// Builds an in-memory valid exam with the given reference range, value and flag.
    Method NewExam(pRange As %String, pValue, pFlag As %String = "N") As LabTriage.Msg.ExamResult
    {
        Set tExam = ##class(LabTriage.Msg.ExamResult).%New()
        Set tExam.LoincCode = "2823-3"
        Set tExam.RawValue = pValue
        Set tExam.NumericValue = +pValue
        Set tExam.Unit = "mmol/L"
        Set tExam.ReferenceRange = pRange
        Set tExam.AbnormalFlag = pFlag
        Set tExam.ResultStatus = "F"
        Return tExam
    }

    /// Runs Classify and asserts the return.
    Method AssertClassify(pExam As LabTriage.Msg.ExamResult, pExpected As %String)
    {
        Set tCase = "range='"_pExam.ReferenceRange_"' value="_pExam.NumericValue_" flag="_pExam.AbnormalFlag
        Set tReturn = ##class(LabTriage.Util.ReferenceRange).Classify(pExam)
        Do $$$AssertEquals(tReturn, pExpected, tCase_": return is "_pExpected)
    }

    // ---- a-b: 3.5-5.1, bounds are normal ----

    Method TestRangeBelowLowerBound()
    {
        Do ..AssertClassify(..NewExam("3.5-5.1", 3.49), "ABNORMAL")
    }

    Method TestRangeAtLowerBound()
    {
        Do ..AssertClassify(..NewExam("3.5-5.1", 3.5), "NORMAL")
    }

    Method TestRangeInside()
    {
        Do ..AssertClassify(..NewExam("3.5-5.1", 4.2), "NORMAL")
    }

    Method TestRangeAtUpperBound()
    {
        Do ..AssertClassify(..NewExam("3.5-5.1", 5.1), "NORMAL")
    }

    Method TestRangeAboveUpperBound()
    {
        Do ..AssertClassify(..NewExam("3.5-5.1", 5.11), "ABNORMAL")
    }

    // ---- <x: <200, normal below 200 ----

    Method TestLessThanBelow()
    {
        Do ..AssertClassify(..NewExam("<200", 199.99), "NORMAL")
    }

    /// The value equal to x is abnormal.
    Method TestLessThanAtLimit()
    {
        Do ..AssertClassify(..NewExam("<200", 200), "ABNORMAL")
    }

    Method TestLessThanAbove()
    {
        Do ..AssertClassify(..NewExam("<200", 200.01), "ABNORMAL")
    }

    // ---- >x: >60, normal above 60 ----

    Method TestGreaterThanBelow()
    {
        Do ..AssertClassify(..NewExam(">60", 59.99), "ABNORMAL")
    }

    /// The value equal to x is abnormal.
    Method TestGreaterThanAtLimit()
    {
        Do ..AssertClassify(..NewExam(">60", 60), "ABNORMAL")
    }

    Method TestGreaterThanAbove()
    {
        Do ..AssertClassify(..NewExam(">60", 60.01), "NORMAL")
    }

    // ---- Flags H, L and A: abnormal even inside the range ----

    Method TestFlagHInsideRange()
    {
        Do ..AssertClassify(..NewExam("3.5-5.1", 4.2, "H"), "ABNORMAL")
    }

    Method TestFlagLInsideRange()
    {
        Do ..AssertClassify(..NewExam("3.5-5.1", 4.2, "L"), "ABNORMAL")
    }

    Method TestFlagAInsideRange()
    {
        Do ..AssertClassify(..NewExam("3.5-5.1", 4.2, "A"), "ABNORMAL")
    }

    // ---- Formats other than a-b, <x and >x: UNPARSEABLE ----

    Method TestTextRange()
    {
        Do ..AssertClassify(..NewExam("negativo", 4.2), "UNPARSEABLE")
    }

    Method TestEmptyRange()
    {
        Do ..AssertClassify(..NewExam("", 4.2), "UNPARSEABLE")
    }

    Method TestRangeWithThreeParts()
    {
        Do ..AssertClassify(..NewExam("1-2-3", 4.2), "UNPARSEABLE")
    }

    Method TestRangeWithSpaces()
    {
        Do ..AssertClassify(..NewExam("3.5 - 5.1", 4.2), "UNPARSEABLE")
    }

    Method TestLessThanText()
    {
        Do ..AssertClassify(..NewExam("<abc", 4.2), "UNPARSEABLE")
    }

}
