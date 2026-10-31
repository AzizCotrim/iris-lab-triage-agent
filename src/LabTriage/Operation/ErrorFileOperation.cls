/// Writes each RejectedFile to ErrorPath: a copy of the input file as received and
/// <file>.error.json with the reason. Both go to a temporary file first and are renamed,
/// so nobody reads a half-written file.
Class LabTriage.Operation.ErrorFileOperation Extends Ens.BusinessOperation
{

    Parameter INVOCATION = "Queue";

    Parameter SETTINGS = "ErrorPath:Basic";

    /// Folder for rejected files, as seen inside the container. Must end with "/": paths are built by plain concatenation.
    Property ErrorPath As %String(MAXLEN = 255);

    Method OnMessage(pRequest As LabTriage.Msg.RejectedFile, Output pResponse As %Library.Persistent) As %Status
    {
        If '##class(%File).DirectoryExists(..ErrorPath)
        {
            If '##class(%File).CreateDirectoryChain(..ErrorPath)
            {
                Return $$$ERROR($$$GeneralError, "Could not create folder "_..ErrorPath)
            }
        }

        // 1. Copy of the input file, as received.
        Do pRequest.Content.Rewind()
        Set tSC = ..WriteFile(..ErrorPath_pRequest.SourceFileName, pRequest.Content)
        If $$$ISERR(tSC)
        {
            Return tSC
        }

        // 2. Reason. Missing MSH-10 or PID-3 are written as null.
        Set tJson = {}
        Do tJson.%Set("sourceFileName", pRequest.SourceFileName)
        Do tJson.%Set("reason", pRequest.Reason)
        Do tJson.%Set("messageControlId", pRequest.MessageControlId, $SELECT(pRequest.MessageControlId = "": "null", 1: "string"))
        Do tJson.%Set("patientId", pRequest.PatientId, $SELECT(pRequest.PatientId = "": "null", 1: "string"))
        // ReceivedAt is stored in UTC as "YYYY-MM-DD hh:mm:ss"; written as ISO 8601 with "T" and "Z".
        Do tJson.%Set("receivedAt", $TRANSLATE(pRequest.ReceivedAt, " ", "T")_"Z")

        Set tSC = ..WriteFile(..ErrorPath_pRequest.SourceFileName_".error.json", tJson.%ToJSON())
        If $$$ISERR(tSC)
        {
            Return tSC
        }

        $$$LOGINFO("Wrote rejected file "_pRequest.SourceFileName_" and its .error.json")
        Return $$$OK
    }

    /// Writes pContent (a string or a stream) to pFileName through a temporary file.
    /// A file with the same name is replaced.
    ClassMethod WriteFile(pFileName As %String, pContent) As %Status
    {
        Set tTmpFileName = pFileName_".tmp"
        Set tStream = ##class(%Stream.FileCharacter).%New()
        Set tStream.TranslateTable = "UTF8"
        Set tSC = tStream.LinkToFile(tTmpFileName)
        If $$$ISERR(tSC)
        {
            Return tSC
        }

        If $ISOBJECT(pContent)
        {
            Set tSC = tStream.CopyFrom(pContent)
        } Else
        {
            Set tSC = tStream.Write(pContent)
        }
        If $$$ISERR(tSC)
        {
            Return tSC
        }

        Set tSC = tStream.%Save()
        If $$$ISERR(tSC)
        {
            Return tSC
        }
        // Close the file before renaming it.
        Kill tStream

        // Same file name rejected again: the new copy replaces the old one.
        If ##class(%File).Exists(pFileName)
        {
            Do ##class(%File).Delete(pFileName)
        }
        If '##class(%File).Rename(tTmpFileName, pFileName)
        {
            Return $$$ERROR($$$GeneralError, "Could not rename "_tTmpFileName_" to "_pFileName)
        }
        Return $$$OK
    }

}