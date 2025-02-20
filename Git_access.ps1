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
$Subject = "Access request completed"  
[System.Net.ServicePointManager]::SecurityProtocol = 'Tls,TLS11,TLS12'  

# Define a function to schedule a task  
function Schedule-Task {  
    param (  
        [string]$TaskName,  
        [string]$Action,  
        [datetime]$TriggerTime  
    )  
    $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoProfile -WindowStyle Hidden -Command $Action"  
    $trigger = New- ScheduledTaskTrigger -Once -At $TriggerTime  
    Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $TaskName -Force  
}  

# Define a function to send email notification  
function Send-Notification {  
    param (  
        [string]$EmailTo,  
        [string]$Body,  
        [string]$Subject  
    )  
    Send-MailMessage -From $psMailCred.UserName -To $EmailTo -UseSsl -Subject $Subject -Body $Body -Credential $psMailCred -SmtpServer $smtpServer -Port Port 587 -Encoding ([System.Text.Encoding]::UTF8) -ErrorAction Stop  
}  

try  
{  
    $groupName = ""  

    if ($catalogName -eq "GITHUB ENT -Mavericks") {  
        if ($requestType -eq "github access") {  
            $groupName = "githubaccess_hexavarsity"  
        }  
    } elseif ($catalogName -eq "GITHUB ENT -Repository") {  
        if ($requestType -eq "github access") {  
            $groupName = "Github_access_users"  
        }  
    }  

    $errormessage = ""  
    $isError = $false  

    Write-Output "Starting access process for user $member"  

    if ($member -ne "") {  
        try {  
            $group = Get-ADGroup -Filter { SamAccountName -eq $groupName } -ErrorAction Stop  
            if ($group) {  
                LogEntry -LogFile $LogFile -Message "Group $groupName Exists"  
                $isMember = Get-ADGroupMember -Identity $group.DistinguishedName | Where-Object { $_.SamAccountName -eq $member }  
                if ($isMember) {  
                    LogEntry -LogFile $LogFile -Message "$($member) already a member of $groupName group"  
                    Write-Output "$member is already a member of the group $groupName."  
                    $isError = $false  
                } else {  
                    if ($requestType -eq "github access") {  
                        LogEntry -LogFile $LogFile -Message "Adding $($member) to $groupName group"  
                        Write-Output "Adding $($member) to $groupName group"  
                        Add-ADGroupMember -Identity $group.DistinguishedName -Members $member -ErrorAction Stop  
                        Write-Output "$member added to the group $groupName."  

                        # Schedule removal and notification  
                        $daysToRemove = if ($groupName -eq "githubaccess_hexavarsity") { 45 } else { 90 }  
                        $notificationDays = 15  
                        $removalDate = (Get-Date).AddDays($daysToRemove)  
                        $notificationDate = $removalDate.AddDays(-$notificationDays)  

                        $removalTaskName = "Remove_$member_From_$groupName"  
                        $notificationTaskName = "Notify_$member_About_$groupName_Removal"  

                        $removalAction = "Remove-ADGroupMember -Identity '$($group.DistinguishedName)' -Members '$member' -Confirm:$false; Send-Notification -EmailTo '$emailTo' -Body 'Dear user, Your access to $groupName has been revoked as your subscription has expired.' -Subject 'Access Revoked'"  
                        $notificationBody = "Dear user, Your access to $groupName will end in $notificationDays days. Please take necessary actions."  
                        $notificationAction = "Send-Notification -EmailTo '$emailTo' -Body '$notificationBody' -Subject 'Access Ending Soon'"  

                        Schedule-Task -TaskName $removalTaskName -Action $removalAction -TriggerTime $removalDate  
                        Schedule-Task -TaskName $notificationTaskName -Action $notificationAction -TriggerTime $notificationDate  

                        # Define the body with the ServiceNow KB article link  
                        $Body = @"  
Dear user,  

Your access has been granted. To understand how to access, please follow the instructions in the following KB article:  
[Access Instructions](https://askgenie.hexaware.com/kb_view.do?sys_kb_id=3cc7f16d479fd2905b7aeee4116d43a9&preview_article=true)  

Best regards,  
STG Automation Team  
"@  

                        # Send the email  
                        Write-Output "Sending email to $emailTo"  
                        Send-MailMessage -From $psMailCred.UserName -To $emailTo -UseSsl -Subject $Subject -Body $Body -Credential $psMailCred -SmtpServer $smtpServer -Port Port 587 -Encoding ([System.Text.Encoding]::UTF8) -ErrorAction Stop  
                        Write-Output "Email sent to $emailTo successfully"  
                    }  
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
            $errormessage += (", {0} not added because {1} ," -f $member, $message)  
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
