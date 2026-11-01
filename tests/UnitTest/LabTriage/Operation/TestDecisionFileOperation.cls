/// Unit tests for LabTriage.Operation.DecisionFileOperation.WriteReview and WriteJsonFile:
/// REVIEWED/<MSH-10>.review.json, its fields, ISO UTC timestamps, safe file names and the
/// timestamp suffix of a repeated MSH-10.
/// The operation runs outside the production: %New with a config name that is not in the
/// production gives a shadow instance (Ens.Host.initConfig: no settings, no OnInit), and
/// OutputPath points to a temporary folder created before and removed after each test.
/// ReviewResult messages are built in memory and never saved.
Class LabTriage.Operation.TestDecisionFileOperation Extends %UnitTest.TestCase
{

    /// Temporary OutputPath of the current test, ends with "/".
    Property OutputPath As %String(MAXLEN = 1024);

    Method OnBeforeOneTest(testname As %String) As %Status
    {
        Set tName = "labtriage-ut-"_$JOB_"-"_$TRANSLATE($ZTIMESTAMP, ",.")
        Set ..OutputPath = ##class(%File).NormalizeDirectory(##class(%File).NormalizeDirectory(##class(%SYS.System).TempDirectory())_tName)
        If '##class(%File).CreateDirectoryChain(..OutputPath)
        {
            Return $$$ERROR($$$GeneralError, "Could not create "_..OutputPath)
        }
        Return $$$OK
    }

    Method OnAfterOneTest(testname As %String) As %Status
    {
        If (..OutputPath '= "")
        {
            Do ##class(%File).RemoveDirectoryTree(..OutputPath)
        }
        Return $$$OK
    }

    /// Operation outside the production, writing under the temporary OutputPath.
    Method NewOperation() As LabTriage.Operation.DecisionFileOperation
    {
        Set tOperation = ##class(LabTriage.Operation.DecisionFileOperation).%New("UnitTest.DecisionFileOperation")
        Set tOperation.OutputPath = ..OutputPath
        Return tOperation
    }

    /// In-memory review of sample 06, released by SuperUser.
    Method NewReview(pMessageControlId As %String = "SYN-ORU-0006", pAction As %String = "Release") As LabTriage.Msg.ReviewResult
    {
        Set tReview = ##class(LabTriage.Msg.ReviewResult).%New()
        Set tReview.MessageControlId = pMessageControlId
        Set tReview.OrderId = "ORD-1006"
        Set tReview.PatientId = "SYN-000106"
        Set tReview.Action = pAction
        Set tReview.Reviewer = "SuperUser"
        Set tReview.Role = "LabReviewer"
        Set tReview.TaskCreatedAt = "2026-11-01 12:49:42.685"
        Set tReview.TaskCompletedAt = "2026-11-01 12:55:10.120"
        Set tReview.EmittedAt = "2026-11-01 12:55:10.131"
        Return tReview
    }

    /// Runs WriteReview and asserts the status.
    Method WriteReview(pReview As LabTriage.Msg.ReviewResult)
    {
        Set tSC = ..NewOperation().WriteReview(pReview, .tResponse)
        Do $$$AssertStatusOK(tSC, "WriteReview MSH-10='"_pReview.MessageControlId_"' returns OK")
    }

    /// Names of the files in pDir (no folders), sorted, as a $LIST.
    Method ListFiles(pDir As %String) As %List
    {
        Set tList = ""
        Set tStatement = ##class(%SQL.Statement).%New()
        If $$$ISERR(tStatement.%PrepareClassQuery("%Library.File", "FileSet"))
        {
            Return tList
        }
        Set tResult = tStatement.%Execute(pDir, "*", "Name", 0)
        While tResult.%Next()
        {
            // FileSet also returns folders (Type "D"), whatever includedirs says.
            Continue:(tResult.%Get("Type") '= "F")
            Set tNames(##class(%File).GetFilename(tResult.%Get("Name"))) = ""
        }
        Set tName = ""
        For
        {
            Set tName = $ORDER(tNames(tName))
            Quit:(tName = "")
            Set tList = tList_$LISTBUILD(tName)
        }
        Return tList
    }

    /// Parses a JSON file written by the operation. Returns "" when it cannot be read.
    Method ReadJson(pPath As %String) As %DynamicObject
    {
        Try
        {
            Set tStream = ##class(%Stream.FileCharacter).%New()
            Set tStream.TranslateTable = "UTF8"
            $$$ThrowOnError(tStream.LinkToFile(pPath))
            Set tJson = ##class(%DynamicObject).%FromJSON(tStream)
        } Catch
        {
            Set tJson = ""
        }
        Return tJson
    }

    /// Asserts that REVIEWED has exactly the files in pExpected ($LIST, sorted).
    Method AssertReviewedFiles(pExpected As %List)
    {
        Set tFiles = ..ListFiles(..OutputPath_"REVIEWED/")
        Do $$$AssertEquals($LISTTOSTRING(tFiles), $LISTTOSTRING(pExpected), "REVIEWED has only "_$LISTTOSTRING(pExpected))
    }

    // ---- path and fields ----

    Method TestWritesReviewedFile()
    {
        Do $$$AssertNotTrue(##class(%File).DirectoryExists(..OutputPath_"REVIEWED/"), "REVIEWED does not exist before the first review")
        Do ..WriteReview(..NewReview())
        Do $$$AssertTrue(##class(%File).Exists(..OutputPath_"REVIEWED/SYN-ORU-0006.review.json"), "file is <OutputPath>/REVIEWED/SYN-ORU-0006.review.json")
        // No .tmp left behind: the temporary file is renamed.
        Do ..AssertReviewedFiles($LISTBUILD("SYN-ORU-0006.review.json"))
        // Nothing else under OutputPath.
        Do $$$AssertEquals($LISTTOSTRING(..ListFiles(..OutputPath)), "", "no file directly under OutputPath")
    }

    Method TestReviewFields()
    {
        Do ..WriteReview(..NewReview())
        Set tJson = ..ReadJson(..OutputPath_"REVIEWED/SYN-ORU-0006.review.json")
        If '$$$AssertTrue($ISOBJECT(tJson), "file is valid JSON")
        {
            Return
        }

        Do $$$AssertEquals(tJson.messageControlId, "SYN-ORU-0006", "messageControlId")
        Do $$$AssertEquals(tJson.outputType, "REVIEW", "outputType is REVIEW")
        Do $$$AssertEquals(tJson.orderId, "ORD-1006", "orderId")
        Do $$$AssertEquals(tJson.patientId, "SYN-000106", "patientId")
        Do $$$AssertEquals(tJson.action, "Release", "action")
        Do $$$AssertEquals(tJson.reviewer, "SuperUser", "reviewer")
        Do $$$AssertEquals(tJson.role, "LabReviewer", "role")
        Do $$$AssertEquals(tJson.taskCreatedAt, "2026-11-01T12:49:42.685Z", "taskCreatedAt in ISO UTC")
        Do $$$AssertEquals(tJson.taskCompletedAt, "2026-11-01T12:55:10.120Z", "taskCompletedAt in ISO UTC")
        Do $$$AssertEquals(tJson.emittedAt, "2026-11-01T12:55:10.131Z", "emittedAt in ISO UTC")

        // Exactly these keys, in this order.
        Set tKeys = ""
        Set tIterator = tJson.%GetIterator()
        While tIterator.%GetNext(.tKey, .tValue)
        {
            Set tKeys = tKeys_$LISTBUILD(tKey)
        }
        Do $$$AssertEquals($LISTTOSTRING(tKeys), "messageControlId,outputType,orderId,patientId,action,reviewer,role,taskCreatedAt,taskCompletedAt,emittedAt", "keys of the review JSON")
    }

    Method TestEmptyTimestampStaysEmpty()
    {
        Set tReview = ..NewReview()
        Set tReview.TaskCompletedAt = ""
        Do ..WriteReview(tReview)
        Set tJson = ..ReadJson(..OutputPath_"REVIEWED/SYN-ORU-0006.review.json")
        If '$$$AssertTrue($ISOBJECT(tJson), "file is valid JSON")
        {
            Return
        }
        Do $$$AssertEquals(tJson.%GetTypeOf("taskCompletedAt"), "string", "empty taskCompletedAt is still a string")
        Do $$$AssertEquals(tJson.taskCompletedAt, "", "empty taskCompletedAt stays empty (no lone T or Z)")
        Do $$$AssertEquals(tJson.taskCreatedAt, "2026-11-01T12:49:42.685Z", "the other timestamps are still converted")
    }

    Method TestToIsoUtc()
    {
        Do $$$AssertEquals(##class(LabTriage.Operation.DecisionFileOperation).ToIsoUtc("2026-11-01 12:49:42.685"), "2026-11-01T12:49:42.685Z", "timestamp with milliseconds")
        Do $$$AssertEquals(##class(LabTriage.Operation.DecisionFileOperation).ToIsoUtc("2026-11-01 12:49:42"), "2026-11-01T12:49:42Z", "timestamp without milliseconds")
        Do $$$AssertEquals(##class(LabTriage.Operation.DecisionFileOperation).ToIsoUtc(""), "", "empty stays empty")
    }

    // ---- file names ----

    Method TestUnsafeMsh10()
    {
        // "..", "/", space, "?" and "*" are dropped; the leading dots go too.
        Do ..WriteReview(..NewReview("../SYN/ORU 0006?*"))
        Do ..AssertReviewedFiles($LISTBUILD("SYNORU0006.review.json"))
        Do $$$AssertEquals($LISTTOSTRING(..ListFiles(..OutputPath)), "", "nothing written outside REVIEWED")
        Set tJson = ..ReadJson(..OutputPath_"REVIEWED/SYNORU0006.review.json")
        If $$$AssertTrue($ISOBJECT(tJson), "file is valid JSON")
        {
            Do $$$AssertEquals(tJson.messageControlId, "../SYN/ORU 0006?*", "JSON keeps the original MSH-10")
        }
    }

    Method TestEmptyMsh10()
    {
        Do ..WriteReview(..NewReview(""))
        Do ..AssertReviewedFiles($LISTBUILD("NO-MSH10.review.json"))
        Set tJson = ..ReadJson(..OutputPath_"REVIEWED/NO-MSH10.review.json")
        If $$$AssertTrue($ISOBJECT(tJson), "file is valid JSON")
        {
            Do $$$AssertEquals(tJson.messageControlId, "", "JSON keeps the empty MSH-10")
        }
    }

    Method TestRepeatedMsh10()
    {
        Do ..WriteReview(..NewReview("SYN-ORU-0006", "Release"))
        Do ..WriteReview(..NewReview("SYN-ORU-0006", "KeepOnHold"))

        Set tFiles = ..ListFiles(..OutputPath_"REVIEWED/")
        If '$$$AssertEquals($LISTLENGTH(tFiles), 2, "two files for the same MSH-10: "_$LISTTOSTRING(tFiles))
        {
            Return
        }
        // Sorted by name: "." (46) comes before "_" (95), so the plain name is first.
        Set tFirst = $LISTGET(tFiles, 1)
        Set tSecond = $LISTGET(tFiles, 2)
        Do $$$AssertEquals(tFirst, "SYN-ORU-0006.review.json", "first review keeps the plain name")
        // UTC suffix: $ZDATETIME(,8,1,3) without " :." = yyyymmddhhmmssfff (17 digits).
        Do $$$AssertTrue(tSecond?1"SYN-ORU-0006_"17N1".review.json", "second review gets a timestamp suffix: "_tSecond)

        Set tJson = ..ReadJson(..OutputPath_"REVIEWED/"_tFirst)
        If $$$AssertTrue($ISOBJECT(tJson), "first file is valid JSON")
        {
            Do $$$AssertEquals(tJson.action, "Release", "first file is intact (action Release)")
        }
        Set tJson = ..ReadJson(..OutputPath_"REVIEWED/"_tSecond)
        If $$$AssertTrue($ISOBJECT(tJson), "second file is valid JSON")
        {
            Do $$$AssertEquals(tJson.action, "KeepOnHold", "second file has the second review (action KeepOnHold)")
        }
    }

}
