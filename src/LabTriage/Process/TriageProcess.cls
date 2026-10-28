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

        Set tQtExams = pRequest.Exams.Count()
        For i = 1:1:tQtExams
        {
            Set tExam = pRequest.Exams.GetAt(i)

            Set tExamDecision = ##class(LabTriage.Msg.ExamDecision).%New()
            Set tExamDecision.LoincCode = tExam.LoincCode
            Set tExamDecision.ExamName = tExam.ExamName
            Set tExamDecision.DecidedBy = "RULE"

            If (tExam.ReasonCode '= "")
            {
                Set tExamDecision.ReasonCode = tExam.ReasonCode
                Set tExamDecision.Reason = "Exam cannot be evaluated: "_tExam.ReasonCode_"."
                Do tTriageResponse.Review.Insert(tExamDecision)
            } Else
            {
                // TODO (agent day): abnormal exams go to the agent instead of being released.
                Set tExamDecision.ReasonCode = "NORMAL"
                Set tExamDecision.Reason = "Within reference range."
                Do tTriageResponse.Released.Insert(tExamDecision)
            }
        }
        Set tTriageResponse.Decision = $SELECT(tTriageResponse.Review.Count() > 0: "HOLD_FOR_REVIEW", 1: "RELEASE")

        Set tTriageResponse.EmittedAt = $ZDATETIME($ZTIMESTAMP, 3, 1, 3)

        Return ..SendRequestAsync("DecisionFileOperation", tTriageResponse, 0)
    }

Storage Default
{
<Type>%Storage.Persistent</Type>
}

}
