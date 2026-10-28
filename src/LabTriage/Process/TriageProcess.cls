/// Triages each exam of a TriageRequest and sends the TriageResponse to the DecisionFileOperation.
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
                // TODO (agent day): abnormal exams go to the agent instead of being released.
                Set tExamDecision.ReasonCode = "NORMAL"
                Set tExamDecision.Reason = "Valid value; reference range not checked yet."
                Do tTriageResponse.Released.Insert(tExamDecision)
            }
        }
        // A single exam under review holds the whole message; otherwise it is released.
        Set tTriageResponse.Decision = $SELECT(tTriageResponse.Review.Count() > 0: "HOLD_FOR_REVIEW", 1: "RELEASE")

        // Overwrites the InitialExpression with the time right before sending, in milliseconds.
        Set tTriageResponse.EmittedAt = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)

        Return ..SendRequestAsync("DecisionFileOperation", tTriageResponse, 0) // 0 = no response expected.
    }

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
