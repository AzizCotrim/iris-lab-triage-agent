/// Writes each TriageResponse as a JSON file under OutputPath:
/// CRITICAL_ALERT goes to ALERTS/<MSH-10>.critical.json,
/// FINAL goes to <DECISION>/<MSH-10>.final.json.
Class LabTriage.Operation.DecisionFileOperation Extends Ens.BusinessOperation
{

    Parameter INVOCATION = "Queue";

    Parameter SETTINGS = "OutputPath:Basic";

    /// Root folder for output files, as seen inside the container (ends with /).
    Property OutputPath As %String(MAXLEN = 255);

    Method OnMessage(pRequest As LabTriage.Msg.TriageResponse, Output pResponse As %Library.Persistent) As %Status
    {
        // 1. Folder and file name
        If (pRequest.OutputType = "CRITICAL_ALERT")
        {
            Set tSubdir = "ALERTS"
            Set tName = pRequest.MessageControlId_".critical.json"
        } Else
        {
            Set tSubdir = pRequest.Decision
            Set tName = pRequest.MessageControlId_".final.json"
        }

        // 2. JSON content
        Set tJson = {}
        Do tJson.%Set("messageControlId", pRequest.MessageControlId)
        Do tJson.%Set("outputType", pRequest.OutputType)
        Do tJson.%Set("orderId", pRequest.OrderId)
        Do tJson.%Set("patientId", pRequest.PatientId)
        Do tJson.%Set("decision", pRequest.Decision)
        Do tJson.%Set("released", ..ItemsToArray(pRequest.Released))
        Do tJson.%Set("review", ..ItemsToArray(pRequest.Review))
        Do tJson.%Set("critical", ..ItemsToArray(pRequest.Critical))

        Set tAgent = {}
        Do tAgent.%Set("called", pRequest.AgentCalled, "boolean")
        Do tJson.%Set("agent", tAgent)

        // Stored in UTC; written in ISO 8601 with Z
        Do tJson.%Set("emittedAt", $TRANSLATE(pRequest.EmittedAt, " ", "T")_"Z")

        // 3. Write to a temporary file, then rename, so nobody reads a half-written file
        Set tDir = ..OutputPath_tSubdir_"/"
        If '##class(%File).DirectoryExists(tDir)
        {
            If '##class(%File).CreateDirectoryChain(tDir)
            {
                Return $$$ERROR($$$GeneralError, "Could not create folder "_tDir)
            }
        }

        Set tTmp = tDir_tName_".tmp"
        Set tStream = ##class(%Stream.FileCharacter).%New()
        Set tStream.TranslateTable = "UTF8"
        Set tSC = tStream.LinkToFile(tTmp)
        If $$$ISERR(tSC)
        {
            Return tSC
        }
        Do tStream.Write(tJson.%ToJSON())
        Set tSC = tStream.%Save()
        If $$$ISERR(tSC)
        {
            Return tSC
        }
        Kill tStream

        If '##class(%File).Rename(tTmp, tDir_tName)
        {
            Return $$$ERROR($$$GeneralError, "Could not write "_tDir_tName)
        }

        $$$LOGINFO("Wrote "_tSubdir_"/"_tName)
        Return $$$OK
    }

    /// Converts a list of ExamDecision into a JSON array of output items.
    ClassMethod ItemsToArray(pList As %Collection.ListOfObj) As %DynamicArray
    {
        Set tArray = []
        For i = 1:1:pList.Count()
        {
            Set tItem = pList.GetAt(i)
            Do tArray.%Push({"code": (tItem.LoincCode), "name": (tItem.ExamName), "decidedBy": (tItem.DecidedBy), "reasonCode": (tItem.ReasonCode), "reason": (tItem.Reason)})
        }
        Return tArray
    }

}