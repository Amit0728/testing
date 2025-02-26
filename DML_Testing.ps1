Param
(
    [Parameter (Mandatory = $true)]
    [object] $parameters
)

Import-Module Orchestrator.AssetManagement.Cmdlets -ErrorAction SilentlyContinue
$gitCredential = Get-AutomationPSCredential -Name 'GitHubProdCredentials'
$sqlCredential = ""
$fullLocation = $parameters.Location
$locationUrl = @()
$locationUrl = $fullLocation.Split(',')
$errormessage = ""
$isError = $false
$count = 0

$servername = $parameters.FirstName
$RITM = $parameters.RITM
$empName = $parameters.Name
$GITPath = $parameters.Location
$appName = $parameters.ApplicationName
$eventType = ""
$status = ""
$QueryText = ""

if ($servername.ToLower() -eq "cch1wdsthstg") {
    $Cred = "EmailDBCredCCHWPSQLREP"
    $sqlCredential = Get-AutomationPSCredential -Name 'EmailDBCredCCHWPSQLREP'
} else {
    $Cred = "DMLSQLServerCred"
    $sqlCredential = Get-AutomationPSCredential -Name 'DMLSQLServerCred'
}

Write-Output $Cred

foreach ($url in $locationUrl) {
    if (($url -ne " ") -and ($url -ne "")) {
        $url = $url.Trim()
        Write-Output "URL"
        Write-Output $url

        $parent = Split-Path $url -Parent
        $parent = $parent.Replace("\", "/")

        $after = $parent.Replace(" ", "%20")
        $url = $url.Replace($parent, $after)

        $cmd = "cd C:\Temp && git clone `"$url`" --config user.name=$($gitCredential.UserName) --config user.password=$($gitCredential.GetNetworkCredential().Password)"
        Invoke-Expression $cmd

        $fileName = Split-Path $url -Leaf
        $fileName = $fileName.Replace("%5B", "[").Replace("%5D", "]").Replace("%20", " ")
        $serverFilePath = "C:\Temp\$fileName"
        Write-Output $serverFilePath

        if (Test-Path -LiteralPath $serverFilePath) {
            Write-Output "before query result"
            Write-Output $serverFilePath

            $queryResult = sqlcmd -S $parameters.FirstName -d $parameters.LastName -U $sqlCredential.UserName -P $sqlCredential.GetNetworkCredential().Password -i $serverFilePath

            Write-Output "query result : "
            Write-Output $queryResult
            Write-Output "query result ends"

            $fname = $parameters.RITM
            if ($count -ne 0) {
                $fname = $fname + "_" + $count
            }
            $filepath = "D:\SQLQueryOutput\$fname.txt"
            New-Item $filepath
            Set-Content $filepath $queryResult

            $affectedRows = ""
            foreach ($query in $queryResult) {
                if ($query.Contains("Changed") -or $query.Contains("rows") -or $query.Contains("Msg") -or $query.Contains("Incorrect") -or $query.Contains("error") -or $query.Contains("failed") -or $query.Contains("Could not") -or $query.Contains("deadlock") -or $query.Contains("Rerun") -or $query.Contains("Cannot get the column information")) {
                    $affectedRows += "`n" + $query
                }
            }
            Write-Output $affectedRows
            if ($affectedRows.Contains("Incorrect") -or $queryResult.Contains("error") -or $queryResult.Contains("failed") -or $queryResult.Contains("Could not") -or $queryResult.Contains("Invalid") -or $queryResult.Contains("Cannot get the column information")) {
                $isError = $true
                $status = "Failure"
            } else {
                $isError = $false
                $status = "Success"
            }

            $QueryText = Get-Content $serverFilePath

            foreach ($d in $QueryText) {
                if (($d.ToLower().Contains("insert")) -and (!$eventType.Contains("insert"))) {
                    $eventType += " insert"
                }
                if (($d.ToLower().Contains("update")) -and (!$eventType.Contains("update"))) {
                    $eventType += " update"
                }
                if (($d.ToLower().Contains("delete")) -and (!$eventType.Contains("delete"))) {
                    $eventType += " delete"
                }
                if (($d.ToLower().Contains("select")) -and (!$eventType.Contains("select"))) {
                    $eventType += " select"
                }
            }
            Write-Output $eventType
            $datet = Get-Date
            $databasename = $parameters.LastName
            $DMLExecUserName = "AzureAutomation"
            $DMLExcelFile = $parameters.DMLExcelFile
            $QueryText = $QueryText.Replace("'", "''")

            if ($DMLExcelFile) {
                $query = "insert into [dbo].[DML_LOG] values ('$RITM','$empName','$QueryText','$appName','$serverName','$databaseName','$GITPath','$eventType', '$datet' ,'$status','$DMLExecUserName','$DMLExcelFile')"
            } else {
                $query = "insert into [dbo].[DML_LOG] values ('$RITM','$empName','$QueryText','$appName','$serverName','$databaseName','$GITPath','$eventType', '$datet' ,'$status')"
            }
            Write-Output "Query"
            Write-Output $query

            $params = @{
                'Database' = "GithubTest"
                'ServerInstance' = "$servername"
                'Username' = $sqlCredential.UserName
                'Password' = $sqlCredential.GetNetworkCredential().Password
                'OutputSqlErrors' = $true
                'Query' = "$query"
                'GitRepoUrl' = $url  # Add the Git repository URL to the params
            }

            $tb = Invoke-Sqlcmd @params

            Remove-Item $serverFilePath -Recurse -Force -Confirm:$false
            Write-Output ("Task execution success for $url")
            $errormessage += ("Given file {0} is executed on the SQL server with the result : {1} .`n" -f $url, $affectedRows)
        } else {
            Write-Output ("Task execution failed, GIT File not found: $url")
            $isError = $true
            Remove-Item $serverFilePath -Recurse -Force -Confirm:$false
            $errormessage += ("Task execution failed for {0}, GIT File not found." -f $url)
        }
    }
    $count = $count + 1
}

if ($isError) {
    Write-Output ("Task execution failed with error message: $errormessage")
} else {
    Write-Output ("Task execution success")
}
