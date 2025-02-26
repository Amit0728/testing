# Manually input parameters
$parameters = @{
    FirstName     = "CCH1WDSTHSTG"  # Replace with your SQL Server name
    LastName      = "GithubTest"  # Replace with your Database name
    Location      = "https://github.com/Hexaware-Repo/AppopsDBA"  # Replace with your GitHub URL
    RITM          = "INC123456"  # Replace with a test RITM value
    Name          = "TestUser"  # Replace with a test user name
    ApplicationName = "TestApp"  # Replace with a test application name
    EjectionGroup = "TestGroup"  # Replace with a test ejection group
    #Url           = "https://your-servicenow-instance.service-now.com/api/now/table/incident/INC123456"  # Replace with your ServiceNow URL
    DMLExcelFile  = $null  # Set to a path if you have an Excel file to log
}

# Manually input credentials
#$snowCredential = Get-Credential -Message "Enter ServiceNow credentials"
$gitCredential = Get-Credential -Message "Enter GitHub credentials"
$sqlCredential = Get-Credential -Message "Enter SQL Server credentials"

# Base64 encode ServiceNow credentials
#$pair = "$($snowCredential.UserName):$($snowCredential.GetNetworkCredential().Password)"
#$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
#$basicAuthValue = "Basic $encodedCreds"
#$Headers = @{Authorization = $basicAuthValue}

# Trust all certificates for SSL/TLS (not recommended for production)
Add-Type @"
using System.Net;
using System.Security.Cryptography.X509Certificates;
public class TrustAllCertsPolicy : ICertificatePolicy {
    public bool CheckValidationResult(
        ServicePoint srvPoint, X509Certificate certificate,
        WebRequest request, int certificateProblem) {
        return true;
    }
}
"@
[System.Net.ServicePointManager]::CertificatePolicy = [TrustAllCertsPolicy]::new()
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Main script logic
try {
    $locationUrl = $parameters.Location -split ','
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

    Write-Output "Using SQL credentials: $($sqlCredential.UserName)"

    foreach ($url in $locationUrl) {
        if (-not [string]::IsNullOrWhiteSpace($url)) {
            $url = $url.Trim()
            Write-Output "URL: $url"

            $parent = Split-Path $url -Parent -Replace '\\', '/' -Replace ' ', '%20'
            $url = $url -Replace [regex]::Escape($parent), $parent

            $cmd = "cd C:\Temp && git clone `"$url`" --config user.name=$($gitCredential.UserName) --config user.password=$($gitCredential.GetNetworkCredential().Password)"
            Invoke-Expression $cmd

            $fileName = Split-Path $url -Leaf -Replace '%5B', '[' -Replace '%5D', ']' -Replace '%20', ' '
            $serverFilePath = "C:\Temp\$fileName"

            if (Test-Path -LiteralPath $serverFilePath) {
                $queryResult = sqlcmd -S $parameters.FirstName -d $parameters.LastName -U $sqlCredential.UserName -P $sqlCredential.GetNetworkCredential().Password -i $serverFilePath
                $affectedRows = $queryResult -match 'Changed|rows|Msg|Incorrect|error|failed|Could not|deadlock|Rerun|Cannot get the column information'

                if ($affectedRows -match 'Incorrect|error|failed|Could not|Invalid|Cannot get the column information') {
                    $isError = $true
                    $status = "Failure"
                } else {
                    $status = "Success"
                }

                $QueryText = Get-Content $serverFilePath -Raw
                $eventType = ($QueryText -split '\r?\n' | ForEach-Object {
                    if ($_ -match 'insert') { 'insert' }
                    if ($_ -match 'update') { 'update' }
                    if ($_ -match 'delete') { 'delete' }
                    if ($_ -match 'select') { 'select' }
                } | Select-Object -Unique) -join ' '

                $datet = Get-Date
                $databaseName = $parameters.LastName
                $DMLExecUserName = "AzureAutomation"
                $QueryText = $QueryText -Replace "'", "''"

                $query = "INSERT INTO [dbo].[DML_LOG] VALUES ('$($parameters.RITM)','$($parameters.Name)','$QueryText','$($parameters.ApplicationName)','$($parameters.FirstName)','$databaseName','$($parameters.Location)','$eventType', '$datet', '$status', '$DMLExecUserName', '$($parameters.DMLExcelFile)')"

                Invoke-Sqlcmd -Database "GithubTest" -ServerInstance $parameters.FirstName -Username $sqlCredential.UserName -Password $sqlCredential.GetNetworkCredential().Password -Query $query

                Remove-Item $serverFilePath -Recurse -Force
                Write-Output "Task execution success for $url"
                $errormessage += "Given file $url is executed on the SQL server with the result: $affectedRows.`n"
            } else {
                Write-Output "Task execution failed, putting the ticket to WIP with reason: $url GIT File not found."
                $isError = $true
                Remove-Item $serverFilePath -Recurse -Force -ErrorAction Ignore
                $errormessage += "Task execution failed for $url, putting the ticket to WIP: GIT File not found.`n"
                $params = @{"state" = 1; "assigned_to" = ""; "assignment_group" = $parameters.EjectionGroup; "work_notes" = "GIT path file not found."}
                Invoke-WebRequest -Uri $parameters.Url -Headers $Headers -Method PATCH -Body ($params | ConvertTo-Json) -ContentType "application/json" -UseBasicParsing
            }
        }
        $count++
    }

    if ($isError) {
        Write-Output "Task execution failed with error message: $errormessage, ticket is ejected."
        $params = @{"state" = 1; "assigned_to" = ""; "assignment_group" = $parameters.EjectionGroup; "work_notes" = $errormessage; "u_automation_ejected_comments" = $errormessage}
        Invoke-WebRequest -Uri $parameters.Url -Headers $Headers -Method PATCH -Body ($params | ConvertTo-Json) -ContentType "application/json" -UseBasicParsing

        # Send email (uncomment and configure if needed)
        # $psMailCred = Get-Credential -Message "Enter email credentials"
        # $emailTo = @('APPOPS_DBA@hexaware.com')
        # $emailCC = "RamkumarS@hexaware.com"
        # $body = "Dear Team, `n `n This is regarding the request $($parameters.RITM). There seems to be an error - $errormessage, while executing the request. Hence assigning the ticket to APPOPS queue.`n `n This is an automated message, please do not respond. `n `n Thanks & Regards, `n STG automation team"
        # Send-MailMessage -To $emailTo -Cc $emailCC -From $psMailCred.UserName -UseSsl -Subject "DML Ticket - $($parameters.RITM)" -Body $body -Credential $psMailCred -SmtpServer "hexaware-com.mail.protection.outlook.com" -Port 25 -Encoding ([System.Text.Encoding]::UTF8) -ErrorAction Stop
    } else {
        Write-Output "Task execution success, ticket is closed."
        $message = $errormessage
        $params = @{"state" = 3; "u_resolution_notes" = $message; "u_resolution_code" = "Resolved Successfully"; "u_automation_ejected_comments" = ""; "work_end" = (Get-Date)}
        Invoke-WebRequest -Uri $parameters.Url -Headers $Headers -Method PATCH -Body ($params | ConvertTo-Json) -ContentType "application/json" -UseBasicParsing
    }
} catch {
    Write-Output "Task execution failed, putting the ticket to WIP with reason: $_.Exception.Message."
    $exception = $_.Exception.Message
    if (-not $parameters.FirstName) {
        $exception = "Automation unable to connect the Database Server, due to Database Server Name display value is empty."
        $params = @{"state" = 1; "assigned_to" = ""; "assignment_group" = $parameters.EjectionGroup; "work_notes" = $exception; "u_automation_ejected_comments" = $exception}
        Invoke-WebRequest -Uri $parameters.Url -Headers $Headers -Method PATCH -Body ($params | ConvertTo-Json) -ContentType "application/json" -UseBasicParsing
    } else {
        if ($errormessage) {
            $exception = "$errormessage, Task execution failed for the next query with the reason: $_.Exception.Message"
        }
        $params = @{"state" = 1; "assigned_to" = ""; "assignment_group" = $parameters.EjectionGroup; "work_notes" = $exception; "u_automation_ejected_comments" = $exception}
        Invoke-WebRequest -Uri $parameters.Url -Headers $Headers -Method PATCH -Body ($params | ConvertTo-Json) -ContentType "application/json" -UseBasicParsing

        # Send email (uncomment and configure if needed)
        # $psMailCred = Get-Credential -Message "Enter email credentials"
        # $emailTo = @('APPOPS_DBA@hexaware.com')
        # $emailCC = "RamkumarS@hexaware.com"
        # $body = "Dear Team, `n `n This is regarding the request $($parameters.RITM). There seems to be an error - $exception, while executing the request. Hence assigning the ticket to APPOPS queue.`n `n This is an automated message, please do not respond. `n `n Thanks & Regards, `n STG automation team"
        # Send-MailMessage -To $emailTo -Cc $emailCC -From $psMailCred.UserName -UseSsl -Subject "DML Ticket - $($parameters.RITM)" -Body $body -Credential $psMailCred -SmtpServer "hexaware-com.mail.protection.outlook.com" -Port 25 -Encoding ([System.Text.Encoding]::UTF8) -ErrorAction Stop
    }
}
