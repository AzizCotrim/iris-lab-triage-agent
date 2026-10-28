/// Reads HL7 v2 ORU^R01 files from the adapter FilePath, builds a TriageRequest and sends it to TargetConfigName.
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

        Set tFirstSegmentName = tMsg.GetSegmentAt(1).Name
        If (tFirstSegmentName '= "MSH")
        {
            Return $$$ERROR($$$GeneralError, "First segment is "_tFirstSegmentName_", expected MSH: "_tFileName)
        }

        Set tMessageCode = tMsg.GetValueAt("1:9.1")
        Set tTriggerEvent = tMsg.GetValueAt("1:9.2")
        If ((tMessageCode '= "ORU") || (tTriggerEvent '= "R01"))
        {
            Return $$$ERROR($$$GeneralError, "Message type is "_tMessageCode_"^"_tTriggerEvent_", expected ORU^R01: "_tFileName)
        }

        Set tTriageRequest = ##class(LabTriage.Msg.TriageRequest).%New()
        Set tTriageRequest.MessageControlId = tMsg.GetValueAt("1:10")
        Set tTriageRequest.SourceFileName = tFileName
        
        Set tSegmentCount = tMsg.SegCount
        Set tObxCount = 0

        For tSegIndex = 1:1:tSegmentCount
        {
            Set tSegName = tMsg.GetSegmentAt(tSegIndex).Name

            If (tSegName = "PID") {
                Set tTriageRequest.PatientId = tMsg.GetValueAt(tSegIndex_":3.1")
            } ElseIf (tSegName = "OBR") {
                Set tTriageRequest.OrderId = tMsg.GetValueAt(tSegIndex_":2")
            } ElseIf (tSegName = "OBX") {
                Set tObxCount = tObxCount + 1

                Set tExamResult = ##class(LabTriage.Msg.ExamResult).%New()
                Set tExamResult.LoincCode = tMsg.GetValueAt(tSegIndex_":3.1")
                Set tExamResult.RawValue = tMsg.GetValueAt(tSegIndex_":5")
                Set tExamResult.Unit = tMsg.GetValueAt(tSegIndex_":6")
                Set tExamResult.ReferenceRange = tMsg.GetValueAt(tSegIndex_":7")

                Set tExamResult.AbnormalFlag = tMsg.GetValueAt(tSegIndex_":8")
                If (tExamResult.AbnormalFlag = "")
                {
                    Set tExamResult.AbnormalFlag = "N"
                }

                Set tExamResult.ResultStatus = tMsg.GetValueAt(tSegIndex_":11")
                Set tExamResult.ObsDateTime = tMsg.GetValueAt(tSegIndex_":14")

                Set tEntry = ##class(LabTriage.ExamCatalog).Lookup(tExamResult.LoincCode)
                If '$ISOBJECT(tEntry)
                {
                    // Not in the exam catalog: kept so it shows up for review, never evaluated.
                    Set tExamResult.ReasonCode = "UNSUPPORTED_EXAM"
                    $$$LOGWARNING("Unsupported exam LOINC "_tExamResult.LoincCode_" in MSH-10="_tTriageRequest.MessageControlId_"; add it to the exam catalog to evaluate it")
                } Else
                {
                    Set tExamResult.ExamName = tEntry.name
                    If ($ISVALIDNUM(tExamResult.RawValue))
                    {
                        Set tExamResult.NumericValue = tExamResult.RawValue
                    } Else
                    {
                        Set tExamResult.ReasonCode = "INVALID_VALUE"
                    }
                }

                Do tTriageRequest.Exams.Insert(tExamResult)
                $$$LOGINFO("OBX "_tSegIndex_" LOINC="_tExamResult.LoincCode_" raw value="_tExamResult.RawValue_" reasonCode="_tExamResult.ReasonCode)
            }
        }

        If (tObxCount = 0)
        {
            Return $$$ERROR($$$GeneralError, "No OBX segment: "_tFileName)
        }

        $$$LOGINFO("Parsed "_tFileName_": MSH-10="_tTriageRequest.MessageControlId_" patient="_tTriageRequest.PatientId_" order="_tTriageRequest.OrderId_ " OBX="_tObxCount_" exams kept="_tTriageRequest.Exams.Count())

        Return ..SendRequestAsync(..TargetConfigName, tTriageRequest)
    }

}