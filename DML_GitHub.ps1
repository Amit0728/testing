Param
(
    [Parameter (Mandatory = $true)]
    [object] $parameters
)

Import-Module Orchestrator.AssetManagement.Cmdlets -ErrorAction SilentlyContinue
$snowCredential = Get-AutomationPSCredential -Name 'ServiceNow'
$user = $snowCredential.UserName
$pass = $snowCredential.GetNetworkCredential().Password
$pair = "$($user):$($pass)"
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$basicAuthValue = "Basic $encodedCreds"
$Headers = @{Authorization = $basicAuthValue}
$date = get-date

try
{
        add-type @"
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

$AllProtocols = [System.Net.SecurityProtocolType]'Ssl3,Tls,Tls11,Tls12'
[System.Net.ServicePointManager]::SecurityProtocol = $AllProtocols
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy


    $gitCredential = Get-AutomationPSCredential -Name 'GitHubProdCredentials'
    $sqlCredential = ""
    $fullLocation = $parameters.Location
    $locationUrl = @()
    $locationUrl = $fullLocation.Split(',')
    #$locationUrl = $fullLocation
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
    #Existing servername - cch1wpsqlrep
    #testing servername - CCH1WDSTHSTG
    if($servername.ToLower() -eq "cch1wdsthstg"){
        $Cred = "EmailDBCredCCHWPSQLREP"
         $sqlCredential = Get-AutomationPSCredential -Name 'EmailDBCredCCHWPSQLREP'
    }
    else{
        $Cred = "DMLSQLServerCred"
         $sqlCredential = Get-AutomationPSCredential -Name 'DMLSQLServerCred'
    }
    
    Write-Output $Cred

    foreach ($url in $locationUrl)
    {
        if(($url -ne " ") -and ($url -ne ""))
        {
            $url = $url.Trim()
            Write-Output "URL"
            Write-Output $url

            $parent = Split-Path $url -Parent
            $parent = $parent.Replace("\","/")

            $after = $parent.Replace(" ","%20")
            $url = $url.Replace($parent,$after)

            #$cmd = ("cd C:\Users\AzureAutomaation\Desktop && svn export ""{0}"" --username {1} --password ""{2}""" -f $url,$svnCredential.UserName,$svnCredential.GetNetworkCredential().Password)
            $cmd = ("cd C:\Temp && git clone ""{0}"" --config user.name={1} --config user.password=""{2}""" -f $url, $gitCredential.UserName, $gitCredential.Password)            

            #$cmd = "cd C:\Temp && git clone `"$url`" --config user.name=$($gitCredential.UserName) --config user.password=$($gitCredential.GetNetworkCredential().Password)"
            Invoke-Expression $cmd
            $git = cmd /c $cmd
            $queryResult = ""
            $fileName = Split-Path $url -leaf
            $fileName = $fileName.Replace("%5B","[").Replace("%5D","]").Replace("%20"," ")
            #$serverFilePath = "C:\Users\AzureAutomaation\Desktop\$fileName"
            $serverFilePath = "C:\Temp\$fileName"
            Write-Output $serverFilePath
            if(Test-Path -LiteralPath $serverFilePath)
            {
                Write-Output "before query result"
                 Write-Output $serverFilePath
                #$queryResult = sqlcmd -S $parameters.FirstName -d $parameters.LastName -U $sqlCredential.UserName -P $sqlCredential.GetNetworkCredential().Password -i $serverFilePath
                $queryResult = sqlcmd -S $parameters.FirstName -d $parameters.LastName -U $sqlCredential.UserName -P $sqlCredential.GetNetworkCredential().Password -i $serverFilePath
                
                Write-Output "query result : "
                Write-Output $queryResult
                Write-Output "query result ends"
                # To store result
                $fname = $parameters.RITM
                if($count -ne 0)
                {
                    $fname = $fname + "_" + $count
                }
                $filepath = "D:\SQLQueryOutput\$fname.txt"
                New-Item $filepath
                Set-Content $filepath $queryResult
                #ends
                
                $affectedRows = ""
                foreach($query in $queryResult)
                {
                    if($query.Contains("Changed") -or $query.Contains("rows") -or $query.Contains("Msg") -or $query.Contains("Incorrect") -or $query.Contains("error") -or $query.Contains("failed") -or $query.Contains("Could not") -or $query.Contains("deadlock") -or $query.Contains("Rerun") -or $query.Contains("Cannot get the column information"))
                    {
                            $affectedRows+= "`n" + $query 
                    }
                }
                Write-Output $affectedRows
                if($affectedRows.Contains("Incorrect") -or $queryResult.Contains("error") -or $queryResult.Contains("failed") -or $queryResult.Contains("Could not") -or $queryResult.Contains("Invalid") -or $queryResult.Contains("Cannot get the column information"))
                {
                    $isError = $true
                    $status = "Failure"
                }
                else{
                    $isError = $false
                    $status = "Success"
                }
                #$fileName = "INCT0094901_V3.sql"
                #$serverFilePath = "C:\Users\AzureAutomaation\Desktop\$fileName"
                #$serverFilePath
                $QueryText = Get-Content $serverFilePath

                
                foreach($d in $QueryText)
                {
                    if(($d.ToLower().Contains("insert")) -and (!$eventType.Contains("insert")))
                    {
                        $eventType += " insert"
                    }
                    if(($d.ToLower().Contains("update")) -and (!$eventType.Contains("update")))
                    {
                        $eventType += " update"
                    }
                    if(($d.ToLower().Contains("delete")) -and (!$eventType.Contains("delete")))
                    {
                        $eventType += " delete"
                    }
                    if(($d.ToLower().Contains("select")) -and (!$eventType.Contains("select")))
                    {
                        $eventType += " select"
                    }
                }
                Write-Output $eventType
                $datet = get-date
                #$databasename = "AdminDB"
                $databasename = $parameters.LastName 
                $DMLExecUserName = "AzureAutomaation" 
                $DMLExcelFile = $parameters.DMLExcelFile
                $QueryText =  $QueryText.Replace("'","''")
                if($DMLExcelFile)
                {
                    $query = "insert into [dbo].[DML_LOG] values ('$RITM','$empName','$QueryText','$appName','$serverName','$databaseName','$GITPath','$eventType', '$datet' ,'$status','$DMLExecUserName','$DMLExcelFile')"
                }
                else{
                    $query = "insert into [dbo].[DML_LOG] values ('$RITM','$empName','$QueryText','$appName','$serverName','$databaseName','$GITPath','$eventType', '$datet' ,'$status')"
                }
                Write-Output "Query"
                Write-Output $query

                $params = @{
                    'Database' = "GithubTest"
                    'ServerInstance' =  "$servername"
                    'Username' = $sqlCredential.UserName
                    'Password' = $sqlCredential.GetNetworkCredential().Password
                    'OutputSqlErrors' = $true
                    #'TrustServerCertificate' = $true
                    'Query' = "$query"
                }

                #Write-Output "params"
                #Write-Output $params

                $tb =  Invoke-Sqlcmd  @params    
            
                Remove-Item $serverFilePath -Recurse –Force -confirm:$false
                Write-Output ("Task execution success for $url")
                $errormessage += ("Given file {0} is executed on the SQL server with the result : {1} .`n" -f $url, $affectedRows)               
            }
            else{
                Write-Output ("Task execution failed, putting the ticket to WIP with reason: $url  GIT File not found.")
                $isError = $true
                Remove-Item $serverFilePath -Recurse –Force -confirm:$false
                $errormessage += ("Task execution failed for {0}, putting the ticket to WIP : GIT File not found." -f $url) 
                $params = @{"state" = 1; "assigned_to" = ""; "assignment_group" = $parameters.EjectionGroup; "work_notes" = "GIT path file not found."}
                Invoke-WebRequest -Uri $parameters.Url -Headers $Headers -Method PATCH -Body ($params|ConvertTo-Json) -ContentType "application/json" -UseBasicParsing
            }
        }
        $count = $count + 1
    }  
    if($isError )
    {
        Write-Output ("Task execution failed with error message: $errormessage, ticket is ejected.")
        $params = @{"state" = 1; "assigned_to" = ""; "assignment_group" = $parameters.EjectionGroup; "work_notes" = $errormessage; "u_automation_ejected_comments" = $errormessage}
        
        Invoke-WebRequest -Uri $parameters.Url -Headers $Headers -Method PATCH -Body ($params|ConvertTo-Json) -ContentType "application/json" -UseBasicParsing

        #Sending mail to team
        $psMailCred = Get-AutomationPSCredential -Name 'EmailAccount'

        $emailTo = @('APPOPS_DBA@hexaware.com')
        $emailCC = "RamkumarS@hexaware.com"
        $body = ("Dear Team, `n `n This is regarding the request {0}. There seems to be an error - {1}, while executing the request. Hence assigning the ticket to APPOPS queue.`n `n This is automated message, please do not respond. `n `n Thanks & Regards, `n STG automation team" -f $parameters.RITM, $errormessage)

        [System.Net.ServicePointManager]::SecurityProtocol = 'Tls,TLS11,TLS12'
        #Send-MailMessage -To $emailTo -Cc $emailCC -From $psMailCred.UserName -UseSsl -Subject ("DML Ticket - {0}" -f $parameters.RITM) -Body $body -Credential $psMailCred -SmtpServer "hexaware-com.mail.protection.outlook.com" -Port 25 -Encoding ([System.Text.Encoding]::UTF8) -ErrorAction Stop

    }
    else{
        Write-Output ("Task execution success, ticket is closed.")
        $message = $errormessage
        $params = @{"state" = 3; "u_resolution_notes" = $message; "u_resolution_code" = "Resolved Successfully";"u_automation_ejected_comments" = ""; "work_end" = $date}
        Invoke-WebRequest -Uri $parameters.Url -Headers $Headers -Method PATCH -Body ($params|ConvertTo-Json) -ContentType "application/json" -UseBasicParsing
    }
}
catch{
   Write-Output ("Task execution failed, putting the ticket to WIP with reason: {0}." -f $_.Exception.Message)
   $exception = $_.Exception.Message
   Write-Output "FirstName"
   Write-Output $parameters.FirstName
   if($parameters.FirstName -eq '')
   {
        $exception = "Automation unable to connect the Database Server, due to Database Server Name display value is empty."
        $params = @{"state" = 1; "assigned_to" = ""; "assignment_group" = $parameters.EjectionGroup; "work_notes" = $exception; "u_automation_ejected_comments" = $exception}
        Invoke-WebRequest -Uri $parameters.Url -Headers $Headers -Method PATCH -Body ($params|ConvertTo-Json) -ContentType "application/json" -UseBasicParsing
   }
   else{
        if ($errormessage -ne '')
        {
            $exception = $errormessage + ", Task execution failed for the next query with the reason :" + $_.Exception.Message
        }
        $params = @{"state" = 1; "assigned_to" = ""; "assignment_group" = $parameters.EjectionGroup; "work_notes" = $exception; "u_automation_ejected_comments" = $exception}
        Invoke-WebRequest -Uri $parameters.Url -Headers $Headers -Method PATCH -Body ($params|ConvertTo-Json) -ContentType "application/json" -UseBasicParsing

            #Sending mail to team
            $psMailCred = Get-AutomationPSCredential -Name 'EmailAccount'

            $emailTo = @('APPOPS_DBA@hexaware.com')
            $emailCC = "RamkumarS@hexaware.com"
            $body = ("Dear Team, `n `n This is regarding the request {0}. There seems to be an error - {1}, while executing the request. Hence assigning the ticket to APPOPS queue.`n `n This is automated message, please do not respond. `n `n Thanks & Regards, `n STG automation team" -f $parameters.RITM, $exception)

            [System.Net.ServicePointManager]::SecurityProtocol = 'Tls,TLS11,TLS12'
            Send-MailMessage -To $emailTo -Cc $emailCC -From $psMailCred.UserName -UseSsl -Subject ("DML Ticket - {0}" -f $parameters.RITM) -Body $body -Credential $psMailCred -SmtpServer "hexaware-com.mail.protection.outlook.com" -Port 25 -Encoding ([System.Text.Encoding]::UTF8) -ErrorAction Stop

       # Remove-Item "C:\Users\AzureAutomaation\Desktop\$fileName" -Recurse –Force -confirm:$false -ErrorAction Ignore
        Remove-Item "C:\Temp\$fileName" -Recurse –Force -confirm:$false -ErrorAction Ignore
   }
}
#Get-AutomationPSCredential -Name 'GitHubProdCredentials'Get-AutomationPSCredential -Name 'GitHubProdCredentials'