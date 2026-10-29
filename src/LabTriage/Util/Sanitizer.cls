/// Builds the only text sent to the LLM. Allowlist of exam fields: nothing about the
/// patient, the order or the file is copied, so it cannot reach the model.
Class LabTriage.Util.Sanitizer
{
    /// Builds the minimal payload sent to the LLM. Allowlist: only the fields below are copied;
    /// patient identity, order IDs, dates and free text never enter the payload.
    ClassMethod BuildPayload(pExams As %ListOfObjects) As %String
    {
        Set tExams = []

        Set tExamsCount = pExams.Count()

        For tExamIndex = 1:1:tExamsCount
        {
            Set tExam = pExams.GetAt(tExamIndex)
            Set tItem = {}
            Do tItem.%Set("code", tExam.LoincCode)
            Do tItem.%Set("name", tExam.ExamName)
            Do tItem.%Set("value", tExam.NumericValue, "number")
            Do tItem.%Set("unit", tExam.Unit)
            Do tItem.%Set("referenceRange", tExam.ReferenceRange)
            Do tItem.%Set("flag", tExam.AbnormalFlag)
            Do tItem.%Set("status", tExam.ResultStatus)

            Do tExams.%Push(tItem)
        }
        Return {"exams": (tExams)}.%ToJSON()
    }

}
