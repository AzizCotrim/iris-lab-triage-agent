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

        If $$$ISERR(tSC) {
            Return tSC
        }

        If '$ISOBJECT(tMsg){
            Return $$$ERROR($$$GeneralError, "Not an HL7 message: "_tFileName)
        }

        $$$LOGINFO("MSH-10: "_tMsg.GetValueAt("1:10"))
        Return $$$OK
    }

}