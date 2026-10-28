/// Single place for the supported exams: LOINC, canonical name, expected unit
/// and critical limits (fictional, exclusive). Adding an exam means editing only this class.
Class LabTriage.ExamCatalog
{

    /// Returns the catalog entry for a LOINC code, or "" if the exam is not supported.
    ClassMethod Lookup(pLoinc As %String) As %DynamicObject
    {
        Set tCatalog = {
            "718-7":  {"name": "Hemoglobin", "unit": "g/dL",   "criticalLow": 7.0, "criticalHigh": 20.0},
            "2345-7": {"name": "Glucose",    "unit": "mg/dL",  "criticalLow": 50,  "criticalHigh": 400},
            "2823-3": {"name": "Potassium",  "unit": "mmol/L", "criticalLow": 2.8, "criticalHigh": 6.2},
            "2160-0": {"name": "Creatinine", "unit": "mg/dL",  "criticalLow": null, "criticalHigh": 4.0},
            "2951-2": {"name": "Sodium",     "unit": "mmol/L", "criticalLow": 120, "criticalHigh": 160}
        }
        Return tCatalog.%Get(pLoinc)
    }

}