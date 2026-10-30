/// Category of a laboratory flag (OBX-8), from the Lookup Table LabTriage.FlagCategory,
/// editable in the Management Portal (Interoperability > Configure > Data Lookup Tables).
/// Default values: config/FlagCategory.xml, loaded by iris.script.
Class LabTriage.Util.FlagTable
{

    /// Lookup Table that maps a flag to NORMAL, ABNORMAL or CRITICAL.
    Parameter TABLE = "LabTriage.FlagCategory";

    /// Returns NORMAL, ABNORMAL or CRITICAL, or "" when the flag is not in the table.
    /// A missing table makes every flag unknown, so every exam goes to review (fail-safe).
    ClassMethod Category(pFlag As %String) As %String
    {
        // An empty key is not allowed in a Lookup Table; the Service already turns an empty flag into N.
        If (pFlag = "")
        {
            Return ""
        }
        Set tCategory = ##class(Ens.Util.LookupTable).%GetValue(..#TABLE, pFlag, .tExists)
        Return $SELECT(tExists: tCategory, 1: "")
    }

}