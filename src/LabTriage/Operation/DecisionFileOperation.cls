/// Writes each TriageResponse as a JSON file under OutputPath:
/// CRITICAL_ALERT goes to ALERTS/<MSH-10>.critical.json,
/// FINAL goes to <DECISION>/<MSH-10>.final.json.
Class LabTriage.Operation.DecisionFileOperation Extends Ens.BusinessOperation
{

    Parameter INVOCATION = "Queue";

    Parameter SETTINGS = "OutputPath:Basic";

    /// Root folder for output files, as seen inside the container. Must end with "/": paths are built by plain concatenation.
    Property OutputPath As %String(MAXLEN = 255);

    Method OnMessage(pRequest As LabTriage.Msg.TriageResponse, Output pResponse As %Library.Persistent) As %Status
    {
        // 1. Folder and file name
        If (pRequest.OutputType = "CRITICAL_ALERT")
        {
            Set tSubdir = "ALERTS"
            Set tFileName = pRequest.MessageControlId_".critical.json"
        } Else
        {
            Set tSubdir = pRequest.Decision
            Set tFileName = pRequest.MessageControlId_".final.json"
        }

        // 2. JSON content
        Set tJson = {}
        Do tJson.%Set("messageControlId", pRequest.MessageControlId)
        Do tJson.%Set("outputType", pRequest.OutputType)
        Do tJson.%Set("orderId", pRequest.OrderId)
        Do tJson.%Set("patientId", pRequest.PatientId)
        Do tJson.%Set("decision", pRequest.Decision)
        Do tJson.%Set("released", ..DecisionsToJsonArray(pRequest.Released))
        Do tJson.%Set("review", ..DecisionsToJsonArray(pRequest.Review))
        Do tJson.%Set("critical", ..DecisionsToJsonArray(pRequest.Critical))

        Set tAgent = {}
        Do tAgent.%Set("called", pRequest.AgentCalled, "boolean")
        If (pRequest.AgentCalled)
        {
            Do tAgent.%Set("attempts", pRequest.AgentAttempts, "number")
            Do tAgent.%Set("status", pRequest.AgentStatus)
            Do tAgent.%Set("latencyMs", pRequest.AgentLatencyMs, "number")
            Do tAgent.%Set("provider", pRequest.AgentProvider)
            Do tAgent.%Set("model", pRequest.AgentModel)
        }
        Do tJson.%Set("agent", tAgent)

        // EmittedAt is stored in UTC as "YYYY-MM-DD hh:mm:ss.fff"; written as ISO 8601 with "T" and "Z".
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

        Set tTmpFileName = tDir_tFileName_".tmp"
        Set tStream = ##class(%Stream.FileCharacter).%New()
        Set tStream.TranslateTable = "UTF8"
        Set tSC = tStream.LinkToFile(tTmpFileName)
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
        // Close the file before renaming it.
        Kill tStream

        If '##class(%File).Rename(tTmpFileName, tDir_tFileName)
        {
            Return $$$ERROR($$$GeneralError, "Could not rename "_tTmpFileName_" to "_tDir_tFileName)
        }

        $$$LOGINFO("Wrote "_tSubdir_"/"_tFileName)
        Return $$$OK
    }

    /// Converts a list of ExamDecision objects into a JSON array, one JSON object per exam.
    ClassMethod DecisionsToJsonArray(pDecisions As %Collection.ListOfObj) As %DynamicArray
    {
        Set tArray = []
        For tIndex = 1:1:pDecisions.Count()
        {
            Set tDecision = pDecisions.GetAt(tIndex)
            Do tArray.%Push({"code": (tDecision.LoincCode), "name": (tDecision.ExamName), "decidedBy": (tDecision.DecidedBy), "reasonCode": (tDecision.ReasonCode), "reason": (tDecision.Reason)})
        }
        Return tArray
    }

}