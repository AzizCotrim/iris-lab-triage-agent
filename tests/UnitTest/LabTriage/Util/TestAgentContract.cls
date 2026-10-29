/// Unit tests for LabTriage.Util.AgentContract.Validate.
/// Cases come from spec section 2: the validation table, the answers the Process must
/// reject and the valid examples. Unless a test says otherwise, the codes sent to the
/// agent are those of the spec input example: potassium, creatinine and hemoglobin.
Class LabTriage.Util.TestAgentContract Extends %UnitTest.TestCase
{

    /// Codes of the spec input example: 2823-3 potassium, 2160-0 creatinine, 718-7 hemoglobin.
    Method SentCodes() As %DynamicArray
    {
        Return ["2823-3", "2160-0", "718-7"]
    }

    /// Runs Validate and asserts the answer is rejected: return 0, pViolation not empty
    /// (and containing pViolationHas, when given), and the other outputs left cleared.
    Method AssertRejected(pRawText As %String, pSentCodes As %DynamicArray, pViolationHas As %String = "")
    {
        Set tReturn = ##class(LabTriage.Util.AgentContract).Validate(pRawText, pSentCodes, .tDecision, .tReason, .tFlagged, .tViolation)
        Do $$$AssertEquals(tReturn, 0, "return is 0")
        Do $$$AssertNotEquals(tViolation, "", "pViolation is not empty: "_tViolation)
        If (pViolationHas '= "")
        {
            Do $$$AssertTrue(tViolation [ pViolationHas, "pViolation contains '"_pViolationHas_"': "_tViolation)
        }
        Do $$$AssertEquals(tDecision, "", "pDecision is empty")
        Do $$$AssertEquals(tReason, "", "pReason is empty")
        Do $$$AssertEquals(tFlagged.%ToJSON(), "[]", "pFlagged is an empty list")
    }

    /// Runs Validate and asserts the answer is accepted: return 1, empty pViolation and
    /// the expected pDecision, pReason and pFlagged (compared as JSON text).
    Method AssertAccepted(pRawText As %String, pSentCodes As %DynamicArray, pDecision As %String, pReason As %String, pFlaggedJSON As %String)
    {
        Set tReturn = ##class(LabTriage.Util.AgentContract).Validate(pRawText, pSentCodes, .tDecision, .tReason, .tFlagged, .tViolation)
        Do $$$AssertEquals(tReturn, 1, "return is 1")
        Do $$$AssertEquals(tViolation, "", "pViolation is empty")
        Do $$$AssertEquals(tDecision, pDecision, "pDecision is "_pDecision)
        Do $$$AssertEquals(tReason, pReason, "pReason is as answered")
        Do $$$AssertEquals(tFlagged.%ToJSON(), pFlaggedJSON, "pFlagged is "_pFlaggedJSON)
    }

    // ---- Validation table, spec section 2: one row per test ----

    /// Not JSON.
    Method TestRowNotJson()
    {
        Do ..AssertRejected("The results look fine and can be released.", ..SentCodes(), "not valid JSON")
    }

    /// Text outside the object: after it (text before it is in TestRejectTextBeforeObject).
    Method TestRowTextAfterObject()
    {
        Set tText = "{""decision"": ""HOLD_FOR_REVIEW"", ""reason"": ""Potassium is high."", ""flaggedExams"": [""2823-3""]} Let me know if you need more."
        Do ..AssertRejected(tText, ..SentCodes(), "not valid JSON")
    }

    /// Fences are removed and the content still goes through every rule.
    Method TestRowFencedContentIsValidated()
    {
        Set tText = "```json"_$CHAR(10)_"{""decision"": ""HOLD_FOR_REVIEW"", ""reason"": ""Sodium is low."", ""flaggedExams"": [""2951-2""]}"_$CHAR(10)_"```"
        Do ..AssertRejected(tText, ..SentCodes(), "2951-2")
    }

    Method TestRowMissingDecision()
    {
        Set tText = "{""reason"": ""Potassium is high."", ""flaggedExams"": [""2823-3""]}"
        Do ..AssertRejected(tText, ..SentCodes(), "Missing field: decision")
    }

    Method TestRowMissingReason()
    {
        Set tText = "{""decision"": ""HOLD_FOR_REVIEW"", ""flaggedExams"": [""2823-3""]}"
        Do ..AssertRejected(tText, ..SentCodes(), "Missing field: reason")
    }

    Method TestRowMissingFlaggedExams()
    {
        Set tText = "{""decision"": ""HOLD_FOR_REVIEW"", ""reason"": ""Potassium is high.""}"
        Do ..AssertRejected(tText, ..SentCodes(), "Missing field: flaggedExams")
    }

    /// A synonym (CRITICAL and lowercase are in the rejected answers of the spec).
    Method TestRowDecisionSynonym()
    {
        Set tText = "{""decision"": ""APPROVE"", ""reason"": ""All results are acceptable."", ""flaggedExams"": []}"
        Do ..AssertRejected(tText, ..SentCodes(), "decision must be")
    }

    Method TestRowReasonEmpty()
    {
        Set tText = "{""decision"": ""HOLD_FOR_REVIEW"", ""reason"": """", ""flaggedExams"": [""2823-3""]}"
        Do ..AssertRejected(tText, ..SentCodes(), "reason must be")
    }

    /// Only spaces counts as empty.
    Method TestRowReasonBlank()
    {
        Set tText = "{""decision"": ""HOLD_FOR_REVIEW"", ""reason"": ""   "", ""flaggedExams"": [""2823-3""]}"
        Do ..AssertRejected(tText, ..SentCodes(), "reason must be")
    }

    /// One code that was sent and one that was not.
    Method TestRowFlaggedCodeNotInInput()
    {
        Set tText = "{""decision"": ""HOLD_FOR_REVIEW"", ""reason"": ""Potassium and glucose are high."", ""flaggedExams"": [""2823-3"", ""2345-7""]}"
        Do ..AssertRejected(tText, ..SentCodes(), "2345-7")
    }

    Method TestRowReleaseWithFlaggedExams()
    {
        Set tText = "{""decision"": ""RELEASE"", ""reason"": ""Potassium is marginally high."", ""flaggedExams"": [""2823-3""]}"
        Do ..AssertRejected(tText, ..SentCodes(), "For RELEASE")
    }

    Method TestRowHoldWithEmptyFlaggedExams()
    {
        Set tText = "{""decision"": ""HOLD_FOR_REVIEW"", ""reason"": ""Potassium and creatinine are high."", ""flaggedExams"": []}"
        Do ..AssertRejected(tText, ..SentCodes(), "For HOLD_FOR_REVIEW")
    }

    /// Extra fields are ignored: the answer is accepted.
    Method TestRowExtraFieldsIgnored()
    {
        Set tText = "{""decision"": ""HOLD_FOR_REVIEW"", ""reason"": ""Potassium is high."", ""flaggedExams"": [""2823-3""], ""severity"": ""moderate""}"
        Do ..AssertAccepted(tText, ..SentCodes(), "HOLD_FOR_REVIEW", "Potassium is high.", "[""2823-3""]")
    }

    /// Empty answer from the provider.
    Method TestRowEmptyAnswer()
    {
        Do ..AssertRejected("", ..SentCodes())
    }

    // ---- Answers the Process must reject, spec section 2 ----

    Method TestRejectTextBeforeObject()
    {
        Set tText = "Sure! Here is my decision: {""decision"": ""RELEASE"", ""reason"": ""All normal."", ""flaggedExams"": []}"
        Do ..AssertRejected(tText, ..SentCodes(), "not valid JSON")
    }

    Method TestRejectDecisionCritical()
    {
        Set tText = "{""decision"": ""CRITICAL"", ""reason"": ""Potassium is dangerously high."", ""flaggedExams"": [""2823-3""]}"
        Do ..AssertRejected(tText, ..SentCodes(), "got CRITICAL")
    }

    Method TestRejectDecisionLowercase()
    {
        Set tText = "{""decision"": ""release"", ""reason"": ""All normal."", ""flaggedExams"": []}"
        Do ..AssertRejected(tText, ..SentCodes(), "got release")
    }

    Method TestRejectMissingFlaggedExams()
    {
        Set tText = "{""decision"": ""RELEASE"", ""reason"": ""Looks fine.""}"
        Do ..AssertRejected(tText, ..SentCodes(), "Missing field: flaggedExams")
    }

    /// Glucose was sent, so the answer breaks only the RELEASE rule.
    Method TestRejectReleaseWithFlaggedExam()
    {
        Set tText = "{""decision"": ""RELEASE"", ""reason"": ""Looks fine."", ""flaggedExams"": [""2345-7""]}"
        Do ..AssertRejected(tText, ["2345-7"], "For RELEASE")
    }

    Method TestRejectHoldWithEmptyFlaggedExams()
    {
        Set tText = "{""decision"": ""HOLD_FOR_REVIEW"", ""reason"": ""Needs review."", ""flaggedExams"": []}"
        Do ..AssertRejected(tText, ..SentCodes(), "For HOLD_FOR_REVIEW")
    }

    /// The message had no sodium.
    Method TestRejectFlaggedSodiumNotInInput()
    {
        Set tText = "{""decision"": ""HOLD_FOR_REVIEW"", ""reason"": ""Sodium is low."", ""flaggedExams"": [""2951-2""]}"
        Do ..AssertRejected(tText, ..SentCodes(), "flaggedExams contained 2951-2, which was not in the input.")
    }

    // ---- Valid examples, spec section 2 ----

    /// Isolated, mild abnormal: glucose 104 mg/dL (70-99, H).
    Method TestAcceptIsolatedMildAbnormal()
    {
        Set tText = "{""decision"": ""RELEASE"", ""reason"": ""Glucose is marginally above the reference range with no other abnormal results."", ""flaggedExams"": []}"
        Do ..AssertAccepted(tText, ["2345-7"], "RELEASE", "Glucose is marginally above the reference range with no other abnormal results.", "[]")
    }

    /// Concerning combination: potassium 5.6 mmol/L (H) and creatinine 2.1 mg/dL (H).
    Method TestAcceptConcerningCombination()
    {
        Set tText = "{""decision"": ""HOLD_FOR_REVIEW"", ""reason"": ""Elevated potassium together with elevated creatinine should be reviewed by a person."", ""flaggedExams"": [""2823-3"", ""2160-0""]}"
        Do ..AssertAccepted(tText, ["2823-3", "2160-0"], "HOLD_FOR_REVIEW", "Elevated potassium together with elevated creatinine should be reviewed by a person.", "[""2823-3"",""2160-0""]")
    }

    /// Drop from the previous result: hemoglobin 12.4 g/dL (N), 15.8 g/dL 6 days ago.
    Method TestAcceptDropFromPrevious()
    {
        Set tText = "{""decision"": ""HOLD_FOR_REVIEW"", ""reason"": ""Hemoglobin dropped from 15.8 to 12.4 g/dL in 6 days, although it is inside the reference range."", ""flaggedExams"": [""718-7""]}"
        Do ..AssertAccepted(tText, ["718-7"], "HOLD_FOR_REVIEW", "Hemoglobin dropped from 15.8 to 12.4 g/dL in 6 days, although it is inside the reference range.", "[""718-7""]")
    }

    // ---- Fences, extra fields, reason length and JSON shape ----

    /// The whole answer is fence + JSON + fence.
    Method TestFencedJsonAccepted()
    {
        Set tText = "```json"_$CHAR(10)_"{""decision"": ""HOLD_FOR_REVIEW"", ""reason"": ""Potassium is high."", ""flaggedExams"": [""2823-3""]}"_$CHAR(10)_"```"
        Do ..AssertAccepted(tText, ..SentCodes(), "HOLD_FOR_REVIEW", "Potassium is high.", "[""2823-3""]")
    }

    /// Strict removal: with text before the fence, nothing is removed.
    Method TestFencedJsonWithTextBeforeRejected()
    {
        Set tText = "Here is my answer:"_$CHAR(10)_"```json"_$CHAR(10)_"{""decision"": ""HOLD_FOR_REVIEW"", ""reason"": ""Potassium is high."", ""flaggedExams"": [""2823-3""]}"_$CHAR(10)_"```"
        Do ..AssertRejected(tText, ..SentCodes(), "not valid JSON")
    }

    Method TestExtraFieldAccepted()
    {
        Set tText = "{""decision"": ""RELEASE"", ""reason"": ""Glucose is marginally high."", ""flaggedExams"": [], ""confidence"": 0.9}"
        Do ..AssertAccepted(tText, ["2345-7"], "RELEASE", "Glucose is marginally high.", "[]")
    }

    Method TestReason501Rejected()
    {
        Set tReason = $TRANSLATE($JUSTIFY("", 501), " ", "x")
        Do $$$AssertEquals($LENGTH(tReason), 501, "reason has 501 characters")
        Set tAnswer = {"decision": "HOLD_FOR_REVIEW", "reason": (tReason), "flaggedExams": ["2823-3"]}
        Do ..AssertRejected(tAnswer.%ToJSON(), ..SentCodes(), "longer than 500")
    }

    Method TestReason500Accepted()
    {
        Set tReason = $TRANSLATE($JUSTIFY("", 500), " ", "x")
        Do $$$AssertEquals($LENGTH(tReason), 500, "reason has 500 characters")
        Set tAnswer = {"decision": "HOLD_FOR_REVIEW", "reason": (tReason), "flaggedExams": ["2823-3"]}
        Do ..AssertAccepted(tAnswer.%ToJSON(), ..SentCodes(), "HOLD_FOR_REVIEW", tReason, "[""2823-3""]")
    }

    Method TestFlaggedExamsNotListRejected()
    {
        Set tText = "{""decision"": ""HOLD_FOR_REVIEW"", ""reason"": ""Potassium is high."", ""flaggedExams"": ""2823-3""}"
        Do ..AssertRejected(tText, ..SentCodes(), "flaggedExams must be a list")
    }

    /// A valid answer wrapped in an array is not one JSON object.
    Method TestJsonArrayRejected()
    {
        Set tText = "[{""decision"": ""HOLD_FOR_REVIEW"", ""reason"": ""Potassium is high."", ""flaggedExams"": [""2823-3""]}]"
        Do ..AssertRejected(tText, ..SentCodes(), "one JSON object")
    }

}
