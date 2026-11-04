/// Setup of LabTriage in the current namespace, after the classes are compiled.
/// Called by iris.script (Docker build) and by the IPM module (module.xml, Invoke after Activate).
/// Every step is idempotent: running it again changes nothing.
Include EnsConstants

Class LabTriage.Installer
{

    /// Folder the production reads and writes (Production.cls and AgentOperation use these paths).
    Parameter DEVROOT = "/home/irisowner/dev/";

    /// Production started by IRIS on every start (SetAutoStart).
    Parameter PRODUCTION = "LabTriage.Production";

    /// Workflow role: same name as the Workflow Operation host.
    Parameter ROLE = "LabReviewer";

    /// Sets up the app. pRoot is the root of the source tree (with or without the final "/"):
    /// config/FlagCategory.xml is read from it and, when it is not DEVROOT, the replay
    /// recordings and the samples are copied from it into DEVROOT/data (existing files are kept).
    /// pStartProduction = 1 (IPM) also starts the production now, if no production is running in the
    /// namespace; iris.script leaves it at 0, since AutoStart starts it when the container starts.
    ClassMethod Setup(pRoot As %String, pStartProduction As %Boolean = 0) As %Status
    {
        Set tSC = $$$OK
        Try
        {
            Set tRoot = ##class(%File).NormalizeDirectory(pRoot)
            Set tDev = ##class(%File).NormalizeDirectory(..#DEVROOT)

            // Data folders. In the Docker build they come from the repo (read-only bind mount),
            // so they are only created when missing.
            For tName = "in", "out", "error", "archive", "replay"
            {
                Set tDir = ##class(%File).NormalizeDirectory(tDev _ "data/" _ tName)
                If ('##class(%File).DirectoryExists(tDir)) && ('##class(%File).CreateDirectoryChain(tDir, .tReturn))
                {
                    $$$ThrowStatus($$$ERROR($$$GeneralError, "Cannot create " _ tDir _ " (" _ tReturn _ ")"))
                }
            }
            If (tRoot '= tDev)
            {
                $$$ThrowOnError(..CopyMissing(tRoot _ "data/replay/", tDev _ "data/replay/", "*.json"))
                $$$ThrowOnError(..CopyMissing(tRoot _ "data/samples/", tDev _ "data/samples/", "*.hl7"))
            }

            // Lookup Table with the default flag categories.
            $$$ThrowOnError(##class(Ens.Util.LookupTable).%Import(tRoot _ "config/FlagCategory.xml", "LabTriage.FlagCategory"))

            // Workflow: a role with no users fails every task (EnsWfErrNoUsersFound).
            For tUser = "SuperUser", "_SYSTEM"
            {
                If ('##class(EnsLib.Workflow.UserDefinition).%ExistsId(tUser))
                {
                    $$$ThrowOnError(##class(EnsLib.Workflow.UserDefinition).CreateUser(tUser))
                }
            }
            If ('##class(EnsLib.Workflow.RoleDefinition).%ExistsId(..#ROLE))
            {
                $$$ThrowOnError(##class(EnsLib.Workflow.RoleDefinition).CreateRole(..#ROLE))
            }
            For tUser = "SuperUser", "_SYSTEM"
            {
                If ('##class(EnsLib.Workflow.RoleMembership).%ExistsId(..#ROLE _ "||" _ tUser))
                {
                    $$$ThrowOnError(##class(EnsLib.Workflow.RoleDefinition).AddUserToRole(..#ROLE, tUser))
                }
            }

            // Starts the production every time IRIS starts, not only now.
            $$$ThrowOnError(##class(Ens.Director).SetAutoStart(..#PRODUCTION))

            If (pStartProduction)
            {
                $$$ThrowOnError(..StartIfIdle())
            }
        }
        Catch tEx
        {
            Set tSC = tEx.AsStatus()
        }
        Return tSC
    }

    /// Starts PRODUCTION when no production is running in the namespace. Running, suspended and troubled
    /// all hold the namespace (GetProductionStatus returns their name); another production is never
    /// stopped, only reported.
    /// Inside a transaction the start is left to a job that runs after the commit: IPM load/install run
    /// Compile and Activate in one transaction, which keeps the lock on the production configuration
    /// saved by the compile (^Ens.Config.ItemD) until TCOMMIT, so a start from here would time out.
    ClassMethod StartIfIdle() As %Status
    {
        $$$QuitOnError(##class(Ens.Director).GetProductionStatus(.tName, .tState))
        If $LISTFIND($LISTBUILD($$$eProductionStateRunning, $$$eProductionStateSuspended, $$$eProductionStateTroubled), tState)
        {
            If (tName '= ..#PRODUCTION)
            {
                Write !, "WARNING: production ", tName, " is running in ", $NAMESPACE, ", so ", ..#PRODUCTION, " was not started.", !
                Write "Stop ", tName, ", then run: Do ##class(Ens.Director).StartProduction(""", ..#PRODUCTION, """)", !
            }
            Return $$$OK
        }
        If ($TLEVEL = 0)
        {
            Return ##class(Ens.Director).StartProduction(..#PRODUCTION)
        }

        // Inside a transaction an unlock takes effect at TCOMMIT or TROLLBACK, so the job below gets
        // this lock only when the transaction is over.
        Lock +^LabTriage.Installer("Start"):5
        If ('$TEST)
        {
            Return $$$ERROR($$$GeneralError, "Cannot lock ^LabTriage.Installer(""Start"")")
        }
        Job ##class(LabTriage.Installer).StartAfterCommit()::5
        Set tJobbed = $TEST
        Lock -^LabTriage.Installer("Start")
        If ('tJobbed)
        {
            Return $$$ERROR($$$GeneralError, "Cannot start the job that starts " _ ..#PRODUCTION)
        }
        Write !, ..#PRODUCTION, " starts when the install transaction commits (job ", $ZCHILD, ").", !
        Return $$$OK
    }

    /// Job started by StartIfIdle: waits for the end of the install transaction, then starts PRODUCTION
    /// if the install was committed (after a rollback, AutoStart is no longer PRODUCTION).
    /// Outcomes go to messages.log.
    ClassMethod StartAfterCommit()
    {
        Lock +^LabTriage.Installer("Start"):600
        If ('$TEST)
        {
            Do ##class(%SYS.System).WriteToConsoleLog("LabTriage.Installer: install still running after 600 s, " _ ..#PRODUCTION _ " not started", 0, 1)
            Quit
        }
        Lock -^LabTriage.Installer("Start")
        Quit:($GET(^Ens.AutoStart) '= ..#PRODUCTION)
        Set tSC = ..StartIfIdle()
        Do ##class(%SYS.System).WriteToConsoleLog("LabTriage.Installer: start of " _ ..#PRODUCTION _ ": " _ $SELECT($$$ISOK(tSC): "OK", 1: $SYSTEM.Status.GetErrorText(tSC)), 0, $SELECT($$$ISOK(tSC): 0, 1: 1))
    }

    /// Copies the files of pFrom that match pWildcards into pTo, skipping the ones pTo already has.
    /// A missing pFrom copies nothing.
    ClassMethod CopyMissing(pFrom As %String, pTo As %String, pWildcards As %String) As %Status
    {
        If ('##class(%File).DirectoryExists(pFrom))
        {
            Return $$$OK
        }
        If ('##class(%File).DirectoryExists(pTo)) && ('##class(%File).CreateDirectoryChain(pTo, .tReturn))
        {
            Return $$$ERROR($$$GeneralError, "Cannot create " _ pTo _ " (" _ tReturn _ ")")
        }
        Set tRS = ##class(%ResultSet).%New("%File:FileSet")
        Set tSC = tRS.Execute(pFrom, pWildcards)
        If $$$ISERR(tSC)
        {
            Return tSC
        }
        While tRS.Next()
        {
            // FileSet also returns folders; only files are copied.
            Continue:(tRS.Get("Type") '= "F")
            Set tTarget = pTo _ tRS.Get("ItemName")
            Continue:##class(%File).Exists(tTarget)
            If ('##class(%File).CopyFile(tRS.Get("Name"), tTarget, 0, .tReturn))
            {
                Return $$$ERROR($$$GeneralError, "Cannot copy " _ tRS.Get("Name") _ " to " _ tTarget _ " (" _ tReturn _ ")")
            }
        }
        Return $$$OK
    }

}
