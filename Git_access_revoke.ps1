Param 
( 
    [Parameter (Mandatory = $true)] 
    [object] $parameters 
) 

function LogEntry { 
    param ( 
        $LogFile, 
        $Message 
    ) 
    # Log entry logic here 
} 

$date = Get-Date -UFormat %d-%b-%Y 
$dateformat = [string](Get-Date).Hour + 'hours' + [string](Get-Date).Minute + 'mins' + [string](Get-Date).Second + 'seconds' 
$newlogfilename = "Git_access_log_" + $date + "_" + $dateformat 
$LogFile = "u{202a}C: ScriptsYoucomaccesslogs$newlogfilename.txt" 

Import-Module Orchestrator.AssetManagement.Cmdlets -ErrorAction SilentlyContinue 
$myCredential = Get- AutomationPSCredential -Name 'ServiceNow' 
$user = $myCredential.UserName 
$pass = $myCredential.GetNetworkCredential().Password 
$pair = "$($user):$($pass)" 
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair)) 
$basicAuthValue = "Basic $encodedCreds" 
$Headers = @{ Authorization = $basicAuthValue } 
$member = $parameters.EmpId 
$catalogName = $parameters.CatalogName 
$requestType = $parameters.RequestType 

$date = Get-Date 
$psMailCred = Get- AutomationPSCredential -Name 'EmailAccount' 
$emailTo = $member + "@hexaware.com" 
$smtpServer = "hexaware-com.mail.protection.outlook.com" 
$From = " GDC@hexaware.com" 
$Subject = "Access Revocation Notice" 
[System.Net.ServicePointManager]::SecurityProtocol = 'Tls,TLS11,TLS12' 

try 
{ 
    $groupName = "" 

    if ($catalogName -eq "GITHUB ENT -Mavericks") { 
        if ($requestType -eq "revoke") { 
            $groupName = "githubaccess_hexavarsity" 
        } 
    } elseif ($catalogName -eq "GITHUB ENT -Repository") { 
        if ($requestType -eq "revoke") { 
            $groupName = "Github_access_users" 
        } 
    } 

    $errormessage = "" 
    $isError = $false 

    Write-Output "Starting access revocation process for user $member" 

    if ($member -ne "") { 
        try { 
            $group = Get-ADGroup -Filter { SamAccountName -eq $groupName } -ErrorAction Stop 
            if ($group) { 
                LogEntry -LogFile $LogFile -Message "Group $groupName Exists" 
                $isMember = Get-ADGroupMember -Identity $group.DistinguishedName | Where-Object { $_.SamAccountName -eq $member } 
                if ($isMember) { 
                    LogEntry -LogFile $LogFile -Message "Removing $($member) from $groupName group" 
                    Write-Output "Removing $($member) from $groupName group" 
                    Remove-ADGroupMember -Identity $group.DistinguishedName -Members $member -Confirm:$false -ErrorAction Stop 
                    Write-Output "$member removed from the group $groupName." 

                    # Send email notification after revocation
                    $Body = @" 
Dear user,

Your access to $groupName has been revoked as per your request.

Best regards,
STG Automation Team
"@

                    Write-Output "Sending revocation email to $emailTo" 
                    Send-MailMessage -From $psMailCred.UserName -To $emailTo -UseSsl -Subject $Subject -Body $Body -Credential $psMailCred -SmtpServer $smtpServer -Port Port 587 -Encoding ([System.Text.Encoding]::UTF8) -ErrorAction Stop 
                    Write-Output "Revocation email sent to $emailTo successfully" 
                } else { 
                    LogEntry -LogFile $LogFile -Message "$($member) is not a member of $groupName group" 
                    Write-Output "$member is not a member of the group $groupName." 
                } 
            } else { 
                LogEntry -LogFile $LogFile -Message "$groupName group not found in AD" 
                Write-Output "Group $groupName not found in AD." 
                $isError = $true 
                $errormessage += "Automation couldn't find the group $groupName in AD," 
            } 
        } catch { 
            $message = $_.Exception.Message 
            $isError = $true 
            $errormessage += (", {0} not removed because {1} ," -f $member, $message) 
        } 
    } 

    if ($isError) { 
        LogEntry -LogFile $LogFile -Message "Task execution failed with error message: $errormessage, ticket is ejected." 
        Write-Output ("Task execution failed with error message: $errormessage, ticket is ejected.") 
        $params = @{ 
            "state" = 1; 
            "assigned_to" = ""; 
            "assignment_group" = $parameters.EjectionGroup; 
            "work_notes" = $errormessage; 
            "u_automation_ejected_comments" = $errormessage 
        } 
        Invoke-WebRequest -Uri $parameters.Url -Headers $Headers -Method PATCH -Body ($params | ConvertTo-Json) -ContentType "application/json" -UseBasicParsing 
    } else { 
        LogEntry -LogFile $LogFile -Message "Task execution success, ticket is closed." 
        Write-Output ("Task execution success, ticket is closed.") 
        $params = @{ 
            "state" = 3; 
            "u_resolution_notes" = $parameters.WorkNotes; 
            "u_resolution_code" = "Resolved Successfully"; 
            "work_end" = $date 
        } 
        Invoke-WebRequest -Uri $parameters.Url -Headers $Headers -Method PATCH -Body ($params | ConvertTo-Json) -ContentType "application/json" -UseBasicParsing 
    } 
} 
catch 
{ 
    if ($_.Exception.Message -like '*Cannot bind parameter ''Identity''. Cannot convert value "" to*') { 
        LogEntry -LogFile $LogFile -Message "Task execution failed, putting the ticket to WIP with reason: Group name value is empty in the request" 
        $message = "Group name value is empty in the request" 
        Write-Output ("Task execution failed, putting the ticket to WIP with reason: {0}." -f $message) 
        $params = @{ 
            "state" = 1; 
            "assigned_to" = ""; 
            "assignment_group" = $parameters.EjectionGroup; 
            "work_notes" = $message; 
            "u_automation_ejected_comments" = $message 
        } 
        Invoke-WebRequest -Uri $parameters.Url -Headers $Headers -Method PATCH -Body ($params | ConvertTo-Json) -ContentType "application/json" -UseBasicParsing 
    } else { 
        LogEntry -LogFile $LogFile -Message "Task execution failed" 
        Write-Output ("Task execution failed, putting the ticket to WIP with reason: {0}." -f $_.Exception.Message) 
        $params = @{ 
            "state" = 1; 
            "assigned_to" = ""; 
            "assignment_group" = $parameters.EjectionGroup; 
            "work_notes" = $_.Exception.Message; 
            "u_automation_ejected_comments" = $_.Exception.Message 
        } 
        Invoke-WebRequest -Uri $parameters.Url -Headers $Headers -Method PATCH -Body ($params | ConvertTo-Json) -ContentType "application/json" -UseBasicParsing 
    } 
} 
