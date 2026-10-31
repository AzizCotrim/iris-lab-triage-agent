/// Reads HL7 v2 ORU^R01 files from the adapter FilePath, builds a TriageRequest and sends it to TargetConfigName.
/// A file that is not a valid ORU^R01 goes to ErrorTargetConfigName as a RejectedFile, so the adapter
/// archives it instead of leaving it in FilePath.
Class LabTriage.Service.FileInbound Extends Ens.BusinessService
{

    Parameter ADAPTER = "EnsLib.File.InboundAdapter";

    Parameter SETTINGS = "TargetConfigName:Basic,ErrorTargetConfigName:Basic";

    /// Production item that receives the TriageRequest (the TriageProcess).
    Property TargetConfigName As Ens.DataType.ConfigName;

    /// Production item that receives the RejectedFile (the ErrorFileOperation).
    Property ErrorTargetConfigName As Ens.DataType.ConfigName;

    Method OnProcessInput(pInput As %Stream.Object, Output pOutput As %RegisteredObject, ByRef pHint As %String) As %Status
    {
        Set tFileName = ##class(%File).GetFilename(pInput.Attributes("Filename"))
        $$$LOGINFO("Received "_tFileName)

        Set tMsg = ##class(EnsLib.HL7.Message).ImportFromLibraryStream(pInput, .tSC)

        If $$$ISERR(tSC)
        {
            Return ..Reject(pInput, tFileName, "The file could not be parsed as HL7 ("_$SYSTEM.Status.GetErrorText(tSC)_").")
        }

        If '$ISOBJECT(tMsg)
        {
            Return ..Reject(pInput, tFileName, "The file does not contain an HL7 message.")
        }

        Set tFirstSegment = tMsg.GetSegmentAt(1)
        If '$ISOBJECT(tFirstSegment)
        {
            Return ..Reject(pInput, tFileName, "The HL7 message has no segments.")
        }
        If (tFirstSegment.Name '= "MSH")
        {
            Return ..Reject(pInput, tFileName, "The first segment is "_tFirstSegment.Name_", expected MSH.", "", ..FindPatientId(tMsg))
        }

        Set tMessageCode = tMsg.GetValueAt("1:9.1")
        Set tTriggerEvent = tMsg.GetValueAt("1:9.2")
        If ((tMessageCode '= "ORU") || (tTriggerEvent '= "R01"))
        {
            Return ..Reject(pInput, tFileName, "The message type is "_tMessageCode_"^"_tTriggerEvent_", expected ORU^R01.", tMsg.GetValueAt("1:10"), ..FindPatientId(tMsg))
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

                    // First problem found wins: the exam has a single ReasonCode.
                    // C (corrected) is triaged as final.
                    If ((tExamResult.ResultStatus '= "F") && (tExamResult.ResultStatus '= "C"))
                    {
                        Set tExamResult.ReasonCode = "NOT_FINAL"
                    } ElseIf (tExamResult.Unit '= tEntry.unit)
                    {
                        // Case-sensitive on purpose: "mmol/l" is not "mmol/L" (fail-safe).
                        Set tExamResult.ReasonCode = "UNEXPECTED_UNIT"
                    } ElseIf ('$ISVALIDNUM(tExamResult.RawValue))
                    {
                        Set tExamResult.ReasonCode = "INVALID_VALUE"
                    } ElseIf (##class(LabTriage.Util.FlagTable).Category(tExamResult.AbnormalFlag) = "")
                    {
                        // Not in the Lookup Table LabTriage.FlagCategory.
                        Set tExamResult.ReasonCode = "UNKNOWN_FLAG"
                    } Else
                    {
                        Set tExamResult.NumericValue = tExamResult.RawValue
                    }
                }

                Do tTriageRequest.Exams.Insert(tExamResult)
                $$$LOGINFO("OBX "_tSegIndex_" LOINC="_tExamResult.LoincCode_" raw value="_tExamResult.RawValue_" reasonCode="_tExamResult.ReasonCode)
            }
        }

        If (tObxCount = 0)
        {
            Return ..Reject(pInput, tFileName, "The message has no OBX segment.", tTriageRequest.MessageControlId, tTriageRequest.PatientId)
        }

        $$$LOGINFO("Parsed "_tFileName_": MSH-10="_tTriageRequest.MessageControlId_" patient="_tTriageRequest.PatientId_" order="_tTriageRequest.OrderId_" OBX="_tObxCount_" exams kept="_tTriageRequest.Exams.Count())

        Return ..SendRequestAsync(..TargetConfigName, tTriageRequest)
    }

    /// Sends the file to ErrorTargetConfigName as a RejectedFile and returns the send status.
    /// An OK status lets the adapter archive the file instead of leaving it in FilePath.
    Method Reject(pInput As %Stream.Object, pFileName As %String, pReason As %String, pMessageControlId As %String = "", pPatientId As %String = "") As %Status
    {
        $$$LOGWARNING("Rejected "_pFileName_": "_pReason)

        Set tRejected = ##class(LabTriage.Msg.RejectedFile).%New()
        Set tRejected.SourceFileName = pFileName
        Set tRejected.Reason = $EXTRACT(pReason, 1, 500)
        Set tRejected.MessageControlId = $EXTRACT(pMessageControlId, 1, 255)
        Set tRejected.PatientId = $EXTRACT(pPatientId, 1, 255)

        // ImportFromLibraryStream already read the stream: rewind before copying it.
        Do pInput.Rewind()
        Set tSC = tRejected.Content.CopyFrom(pInput)
        If $$$ISERR(tSC)
        {
            Return tSC
        }

        Return ..SendRequestAsync(..ErrorTargetConfigName, tRejected)
    }

    /// PID-3.1 of the first PID segment, or "" when there is none. Used only for rejected files.
    ClassMethod FindPatientId(pMsg As EnsLib.HL7.Message) As %String
    {
        For tSegIndex = 1:1:pMsg.SegCount
        {
            Set tSegment = pMsg.GetSegmentAt(tSegIndex)
            If (($ISOBJECT(tSegment)) && (tSegment.Name = "PID"))
            {
                Return pMsg.GetValueAt(tSegIndex_":3.1")
            }
        }
        Return ""
    }

}