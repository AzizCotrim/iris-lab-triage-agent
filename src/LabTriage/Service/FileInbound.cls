/// Reads ORU^R01 files from data/in and sends a TriageRequest to the Process.
Class LabTriage.Service.FileInbound Extends Ens.BusinessService
{

    Parameter ADAPTER = "EnsLib.File.InboundAdapter";

    Parameter SETTINGS = "TargetConfigName:Basic";

    /// Production item that receives the TriageRequest (the TriageProcess).
    Property TargetConfigName As Ens.DataType.ConfigName;

    Method OnProcessInput(pInput As %Stream.Object, Output pOutput As %RegisteredObject, ByRef pHint As %String) As %Status
    {
        Set tFileName = ##class(%File).GetFilename(pInput.Attributes("Filename"))
        $$$LOGINFO("Received "_tFileName)

        Set tMsg = ##class(EnsLib.HL7.Message).ImportFromLibraryStream(pInput, .tSC)

        If $$$ISERR(tSC)
        {
            Return tSC
        }

        If '$ISOBJECT(tMsg)
        {
            Return $$$ERROR($$$GeneralError, "Not an HL7 message: "_tFileName)
        }

        Set tMsh = tMsg.GetSegmentAt(1).Name
        If (tMsh '= "MSH")
        {
            Return $$$ERROR($$$GeneralError, "First segment is not MSH")
        }

        Set tMsh91 = tMsg.GetValueAt("1:9.1")
        Set tMsh92 = tMsg.GetValueAt("1:9.2")
        If ((tMsh91 '= "ORU") || (tMsh92 '= "R01"))
        {
            Return $$$ERROR($$$GeneralError, "Message type is not ORU^R01")
        }

        Set tTriageRequest = ##class(LabTriage.Msg.TriageRequest).%New()
        Set tTriageRequest.MessageControlId = tMsg.GetValueAt("1:10")
        Set tTriageRequest.SourceFileName = tFileName
        
        Set tQtSegments = tMsg.SegCount
        Set tQtObx = 0

        For i = 1:1:tQtSegments
        {
            Set tSegName = tMsg.GetSegmentAt(i).Name

            If (tSegName = "PID") {
                Set tTriageRequest.PatientId = tMsg.GetValueAt(i_":3.1")
            } ElseIf (tSegName = "OBR") {
                Set tTriageRequest.OrderId = tMsg.GetValueAt(i_":2")
            } ElseIf (tSegName = "OBX") {
                Set tQtObx = tQtObx + 1

                // MVP step 1: only hemoglobin; the other exams come with the exam catalog.
                If (tMsg.GetValueAt(i_":3.1") = "718-7")
                {
                    Set tExamResult = ##class(LabTriage.Msg.ExamResult).%New()
                    Set tExamResult.LoincCode = tMsg.GetValueAt(i_":3.1")
                    Set tExamResult.RawValue = tMsg.GetValueAt(i_":5")
                    If ($ISVALIDNUM(tExamResult.RawValue))
                    {
                        Set tExamResult.NumericValue = tExamResult.RawValue
                    } Else
                    {
                        Set tExamResult.ReasonCode = "INVALID_VALUE"
                    }

                    Set tExamResult.Unit = tMsg.GetValueAt(i_":6")
                    Set tExamResult.ReferenceRange = tMsg.GetValueAt(i_":7")

                    Set tExamResult.AbnormalFlag = tMsg.GetValueAt(i_":8")
                    If (tExamResult.AbnormalFlag = "")
                    {
                        Set tExamResult.AbnormalFlag = "N"
                    }

                    Set tExamResult.ResultStatus = tMsg.GetValueAt(i_":11")
                    Set tExamResult.ObsDateTime = tMsg.GetValueAt(i_":14")

                    Do tTriageRequest.Exams.Insert(tExamResult)
                    $$$LOGINFO("Hemoglobin raw value: "_tExamResult.RawValue)
                }
            }
        }

        If (tQtObx = 0)
        {
            Return $$$ERROR($$$GeneralError, "Message has no OBX segment")
        }

        $$$LOGINFO("MSH-10="_tTriageRequest.MessageControlId_" patient="_tTriageRequest.PatientId_" order="_tTriageRequest.OrderId_" exams="_tTriageRequest.Exams.Count())
        
        Return ..SendRequestAsync(..TargetConfigName, tTriageRequest)
    }

}