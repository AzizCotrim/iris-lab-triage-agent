/// Triages each exam of a TriageRequest and sends the TriageResponse to the DecisionFileOperation.
/// If any exam is critical, a CRITICAL_ALERT is sent first, before the final output.
Class LabTriage.Process.TriageProcess Extends Ens.BusinessProcess
{

    Method OnRequest(pRequest As LabTriage.Msg.TriageRequest, Output pResponse As %Library.Persistent) As %Status
    {
        Set tTriageResponse = ##class(LabTriage.Msg.TriageResponse).%New()

        Set tTriageResponse.MessageControlId = pRequest.MessageControlId
        Set tTriageResponse.OrderId = pRequest.OrderId
        Set tTriageResponse.PatientId = pRequest.PatientId
        Set tTriageResponse.OutputType = "FINAL"

        Set tExamCount = pRequest.Exams.Count()
        For tExamIndex = 1:1:tExamCount
        {
            Set tExamResult = pRequest.Exams.GetAt(tExamIndex)

            Set tExamDecision = ##class(LabTriage.Msg.ExamDecision).%New()
            Set tExamDecision.LoincCode = tExamResult.LoincCode
            Set tExamDecision.ExamName = tExamResult.ExamName
            Set tExamDecision.DecidedBy = "RULE"

            If (tExamResult.ReasonCode '= "")
            {
                Set tExamDecision.ReasonCode = tExamResult.ReasonCode
                Set tExamDecision.Reason = "Exam cannot be evaluated: "_tExamResult.ReasonCode_"."
                Do tTriageResponse.Review.Insert(tExamDecision)
            } Else
            {
                // B3: every valid exam goes through the critical rule first.
                Set tRuleResult = ##class(LabTriage.Rules.CriticalLimits).Check(tExamResult, .tCode, .tReason)

                If (tRuleResult = "CRITICAL")
                {
                    Set tExamDecision.ReasonCode = tCode
                    Set tExamDecision.Reason = tReason
                    Do tTriageResponse.Critical.Insert(tExamDecision)
                } ElseIf (tRuleResult = "NOT_EVALUABLE")
                {
                    // The Service already marks unsupported exams and invalid values, so here
                    // the rule can only refuse because of a unit mismatch.
                    // TODO (Fri 10-30): the Service marks UNEXPECTED_UNIT before the Process.
                    Set tExamDecision.ReasonCode = "UNEXPECTED_UNIT"
                    Set tExamDecision.Reason = "Unit "_tExamResult.Unit_" is not the unit expected by the exam catalog."
                    Do tTriageResponse.Review.Insert(tExamDecision)
                } Else
                {
                    // TODO (agent day): abnormal exams go to the agent instead of being released.
                    Set tExamDecision.ReasonCode = "NORMAL"
                    Set tExamDecision.Reason = "Valid value; reference range not checked yet."
                    Do tTriageResponse.Released.Insert(tExamDecision)
                }
            }
        }

        // B3: critical results do not wait. The alert goes out before the final output.
        If (tTriageResponse.Critical.Count() > 0)
        {
            Set tAlert = ##class(LabTriage.Msg.TriageResponse).%New()
            Set tAlert.MessageControlId = pRequest.MessageControlId
            Set tAlert.OrderId = pRequest.OrderId
            Set tAlert.PatientId = pRequest.PatientId
            Set tAlert.OutputType = "CRITICAL_ALERT"
            Set tAlert.Decision = "CRITICAL"

            // The alert carries only the critical list.
            For tCriticalIndex = 1:1:tTriageResponse.Critical.Count()
            {
                Do tAlert.Critical.Insert(tTriageResponse.Critical.GetAt(tCriticalIndex))
            }

            Set tAlert.EmittedAt = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)
            Set tSC = ..SendRequestAsync("DecisionFileOperation", tAlert, 0) // 0 = no response expected.
            If $$$ISERR(tSC)
            {
                Return tSC
            }
        }

        // B3: the message decision is the most severe one among the lists.
        Set tTriageResponse.Decision = $SELECT(tTriageResponse.Critical.Count() > 0: "CRITICAL", tTriageResponse.Review.Count() > 0: "HOLD_FOR_REVIEW", 1: "RELEASE")

        // Overwrites the InitialExpression with the time right before sending, in milliseconds.
        // Set after the alert, so the final output is always later than the alert.
        Set tTriageResponse.EmittedAt = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)

        Return ..SendRequestAsync("DecisionFileOperation", tTriageResponse, 0) // 0 = no response expected.
    }
    
Storage Default
{
<Type>%Storage.Persistent</Type>
}

}