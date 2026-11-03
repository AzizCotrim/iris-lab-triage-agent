/// Unit tests for the trace metadata of LabTriage.Operation.AgentOperation: PromptVersion,
/// InputTokens, OutputTokens and LatencyMs on the AgentResponse in REPLAY and SIMULATION, and the
/// Record -> Replay round trip that carries them from a REAL call to a replayed one.
/// The operation runs outside the production (shadow instance, see TestDecisionFileOperation),
/// and ReplayPath points to a temporary folder created before and removed after each test.
Class LabTriage.Operation.TestAgentOperation Extends %UnitTest.TestCase
{

    /// Temporary ReplayPath of the current test, ends with "/".
    Property ReplayPath As %String(MAXLEN = 1024);

    Method OnBeforeOneTest(testname As %String) As %Status
    {
        Set tName = "labtriage-ut-replay-"_$JOB_"-"_$TRANSLATE($ZTIMESTAMP, ",.")
        Set ..ReplayPath = ##class(%File).NormalizeDirectory(##class(%File).NormalizeDirectory(##class(%SYS.System).TempDirectory())_tName)
        If '##class(%File).CreateDirectoryChain(..ReplayPath)
        {
            Return $$$ERROR($$$GeneralError, "Could not create "_..ReplayPath)
        }
        Return $$$OK
    }

    Method OnAfterOneTest(testname As %String) As %Status
    {
        If (..ReplayPath '= "")
        {
            Do ##class(%File).RemoveDirectoryTree(..ReplayPath)
        }
        Return $$$OK
    }

    /// Operation outside the production, reading and writing recordings under the temporary ReplayPath.
    Method NewOperation() As LabTriage.Operation.AgentOperation
    {
        Set tOperation = ##class(LabTriage.Operation.AgentOperation).%New("UnitTest.AgentOperation")
        Set tOperation.ReplayPath = ..ReplayPath
        Return tOperation
    }

    /// Sanitized payload with one abnormal exam (same shape as the Sanitizer output).
    ClassMethod Payload() As %String
    {
        Return {"exams": [{"code": "2823-3", "name": "Potassium", "value": 6.2, "unit": "mmol/L", "referenceRange": "3.5-5.1", "flag": "H", "status": "F"}]}.%ToJSON()
    }

    /// A REAL answer recorded with its token counts comes back from REPLAY with the same
    /// prompt version and token counts.
    Method TestRecordThenReplayKeepsPromptAndTokens()
    {
        Set tOperation = ..NewOperation()
        Set tInput = ..Payload()

        Set tReal = ##class(LabTriage.Msg.AgentResponse).%New()
        Set tReal.Status = "OK"
        Set tReal.Provider = "gemini"
        Set tReal.Model = "gemini-test"
        Set tReal.PromptVersion = ##class(LabTriage.Agent.TriageAgent).#PROMPTVERSION
        Set tReal.InputTokens = 812
        Set tReal.OutputTokens = 47
        Set tReal.LatencyMs = 1234
        Set tReal.RawText = {"decision": "HOLD_FOR_REVIEW", "reason": "Potassium is high.", "flaggedExams": ["2823-3"]}.%ToJSON()
        Do tOperation.Record(tInput, tReal)

        Set tReplayed = ##class(LabTriage.Msg.AgentResponse).%New()
        Do tOperation.Replay(tInput, tReplayed)

        Do $$$AssertEquals(tReplayed.Status, "OK", "Replay finds the recording")
        Do $$$AssertEquals(tReplayed.Provider, "replay", "Provider is replay")
        Do $$$AssertEquals(tReplayed.RawText, tReal.RawText, "RawText comes from the recording")
        Do $$$AssertEquals(tReplayed.Model, "gemini-test", "Model comes from the recording")
        Do $$$AssertEquals(tReplayed.PromptVersion, ##class(LabTriage.Agent.TriageAgent).#PROMPTVERSION, "PromptVersion comes from the recording")
        Do $$$AssertEquals(tReplayed.InputTokens, 812, "InputTokens comes from the recording")
        Do $$$AssertEquals(tReplayed.OutputTokens, 47, "OutputTokens comes from the recording")
        Do $$$AssertEquals(tReplayed.LatencyMs, 1234, "LatencyMs comes from the recording")
    }

    /// A recording made before tokens and latency were recorded still replays: prompt version
    /// from the file, token counts empty (not 0), LatencyMs 0 as before.
    Method TestReplayOldRecordingWithoutTokens()
    {
        Set tOperation = ..NewOperation()
        Set tInput = ..Payload()

        Set tRecord = {"promptVersion": (##class(LabTriage.Agent.TriageAgent).#PROMPTVERSION), "model": "gemini-old", "recordedAt": "2026-10-30T17:13:56.683Z", "input": (tInput), "rawText": "{}"}
        Set tStream = ##class(%Stream.FileCharacter).%New()
        Set tStream.TranslateTable = "UTF8"
        Do $$$AssertStatusOK(tStream.LinkToFile(tOperation.ReplayFileName(tInput)), "Old-format recording file opens")
        Do tStream.Write(tRecord.%ToJSON())
        Do $$$AssertStatusOK(tStream.%Save(), "Old-format recording is written")

        Set tReplayed = ##class(LabTriage.Msg.AgentResponse).%New()
        Do tOperation.Replay(tInput, tReplayed)

        Do $$$AssertEquals(tReplayed.Status, "OK", "Old recording replays")
        Do $$$AssertEquals(tReplayed.PromptVersion, ##class(LabTriage.Agent.TriageAgent).#PROMPTVERSION, "PromptVersion comes from the old recording")
        Do $$$AssertEquals(tReplayed.InputTokens, "", "InputTokens is empty when the recording has none")
        Do $$$AssertEquals(tReplayed.OutputTokens, "", "OutputTokens is empty when the recording has none")
        Do $$$AssertEquals(tReplayed.LatencyMs, 0, "LatencyMs stays 0 when the recording has none")
    }

    /// No recording for the input: NO_KEY, and no prompt version or tokens are claimed.
    Method TestReplayWithoutRecordingLeavesMetadataEmpty()
    {
        Set tReplayed = ##class(LabTriage.Msg.AgentResponse).%New()
        Do ..NewOperation().Replay(..Payload(), tReplayed)

        Do $$$AssertEquals(tReplayed.Status, "NO_KEY", "Missing recording gives NO_KEY")
        Do $$$AssertEquals(tReplayed.PromptVersion, "", "No PromptVersion without a recording")
        Do $$$AssertEquals(tReplayed.InputTokens, "", "No InputTokens without a recording")
        Do $$$AssertEquals(tReplayed.OutputTokens, "", "No OutputTokens without a recording")
    }

    /// SIMULATION never uses the prompt or the provider: prompt version and tokens stay empty.
    Method TestSimulationLeavesMetadataEmpty()
    {
        Set tRequest = ##class(LabTriage.Msg.AgentRequest).%New()
        Set tRequest.Payload = ..Payload()

        Set tSimulated = ##class(LabTriage.Msg.AgentResponse).%New()
        Do ..NewOperation().Simulate(tRequest, tSimulated)

        Do $$$AssertEquals(tSimulated.Status, "OK", "Simulated HOLD_ALL answer")
        Do $$$AssertEquals(tSimulated.PromptVersion, "", "No PromptVersion in SIMULATION")
        Do $$$AssertEquals(tSimulated.InputTokens, "", "No InputTokens in SIMULATION")
        Do $$$AssertEquals(tSimulated.OutputTokens, "", "No OutputTokens in SIMULATION")
    }

}
