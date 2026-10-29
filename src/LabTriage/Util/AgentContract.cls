/// Checks the LLM answer against the output contract of the agent (spec, section 2).
/// It does not judge the clinical decision: it decides whether the answer can be used.
/// An answer that breaks any rule is never turned into a decision.
Class LabTriage.Util.AgentContract
{
    /// Validates the LLM answer against the contract.
    /// Returns 1 when valid; then pDecision, pReason and pFlagged are set.
    /// Returns 0 when invalid; then pViolation says, in one English sentence, which rule was broken.
    ClassMethod Validate(pRawText As %String, pSentCodes As %DynamicArray, Output pDecision As %String, Output pReason As %String, Output pFlagged As %DynamicArray, Output pViolation As %String) As %Boolean
    {
        // 0. Clear the outputs.
        Set pDecision = ""
        Set pReason = ""
        Set pFlagged = []
        Set pViolation = ""

        // 1. Markdown fences, strict removal: only when the whole answer is fence + JSON + fence.
        Set tText = $ZSTRIP(pRawText, "<>WC")
        If (($EXTRACT(tText, 1, 3) = "```") && ($EXTRACT(tText, *-2, *) = "```"))
        {
            // Drop the opening fence line (it may be ```json) and the closing fence.
            Set tText = $PIECE(tText, $CHAR(10), 2, *)
            Set tText = $EXTRACT(tText, 1, *-3)
            Set tText = $ZSTRIP(tText, "<>WC")
        }

        // 2. Must be JSON. Only %FromJSON can throw, so only it stays inside the Try.
        Try
        {
            Set tAnswer = ##class(%DynamicAbstractObject).%FromJSON(tText)
        } Catch
        {
            Set pViolation = "The answer is not valid JSON."
            Return 0
        }
        If (('$ISOBJECT(tAnswer)) || ($CLASSNAME(tAnswer) '= "%Library.DynamicObject"))
        {
            Set pViolation = "The answer must be one JSON object."
            Return 0
        }

        // 3. Required fields.
        For tField = "decision", "reason", "flaggedExams"
        {
            If ('tAnswer.%IsDefined(tField))
            {
                Set pViolation = "Missing field: "_tField_"."
                Return 0
            }
        }

        // 4. decision: exactly RELEASE or HOLD_FOR_REVIEW (catches CRITICAL, lowercase and synonyms).
        Set tDecision = tAnswer.%Get("decision")
        If ((tAnswer.%GetTypeOf("decision") '= "string") || ((tDecision '= "RELEASE") && (tDecision '= "HOLD_FOR_REVIEW")))
        {
            Set pViolation = "decision must be RELEASE or HOLD_FOR_REVIEW, got "_tDecision_"."
            Return 0
        }

        // 5. reason: not empty, at most 500 characters.
        Set tReason = tAnswer.%Get("reason")
        If ((tAnswer.%GetTypeOf("reason") '= "string") || ($ZSTRIP(tReason, "<>WC") = ""))
        {
            Set pViolation = "reason must be a non-empty text."
            Return 0
        }
        If ($LENGTH(tReason) > 500)
        {
            Set pViolation = "reason is longer than 500 characters."
            Return 0
        }

        // 6. flaggedExams: a list, and only codes that were sent.
        If (tAnswer.%GetTypeOf("flaggedExams") '= "array")
        {
            Set pViolation = "flaggedExams must be a list."
            Return 0
        }
        Set tFlagged = tAnswer.%Get("flaggedExams")

        // JSON arrays start at index 0.
        Set tSentList = ""
        For tIndex = 0:1:(pSentCodes.%Size() - 1)
        {
            Set tSentList = tSentList_$LISTBUILD(pSentCodes.%Get(tIndex))
        }
        For tIndex = 0:1:(tFlagged.%Size() - 1)
        {
            Set tCode = tFlagged.%Get(tIndex)
            If ('$LISTFIND(tSentList, tCode))
            {
                Set pViolation = "flaggedExams contained "_tCode_", which was not in the input."
                Return 0
            }
        }

        // 7. decision and flaggedExams must agree.
        If ((tDecision = "RELEASE") && (tFlagged.%Size() > 0))
        {
            Set pViolation = "For RELEASE, flaggedExams must be an empty list."
            Return 0
        }
        If ((tDecision = "HOLD_FOR_REVIEW") && (tFlagged.%Size() = 0))
        {
            Set pViolation = "For HOLD_FOR_REVIEW, flaggedExams must contain at least one code."
            Return 0
        }

        // 8. Extra fields are ignored on purpose.

        // 9. Valid.
        Set pDecision = tDecision
        Set pReason = tReason
        Set pFlagged = tFlagged
        Return 1
    }
}