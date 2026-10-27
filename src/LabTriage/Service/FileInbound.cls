Class LabTriage.Service.FileInbound Extends Ens.BusinessService
{

    Parameter ADAPTER = "EnsLib.File.InboundAdapter";

    Parameter SETTINGS = "TargetConfigName:Basic";

    /// Production item that receives the TriageRequest (the TriageProcess).
    Property TargetConfigName As Ens.DataType.ConfigName;

    /// DReads ORU^R01 files from data/in and sends a TriageRequest to the Process.
    Method OnProcessInput(pInput As %Stream.Object, Output pOutput As %RegisteredObject, ByRef pHint As %String) As %Status
    {
        $$$LOGINFO($CLASSNAME(pInput))
        $$$LOGINFO(pInput.Attributes("Filename"))

        Return $$$OK
    }

}
