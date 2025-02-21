# Define parameters for testing
$parameters = @{
    EmpId = "testuser"
    CatalogName = "GITHUB ENT -Mavericks"
    RequestType = "github access"
    EjectionGroup = "TestEjectionGroup"
    Url = "https://example.com/api"
    WorkNotes = "Test work notes"
}

# Function to log entries
function LogEntry {
    param (
        $LogFile,
        $Message
    )
    Write-Output "Log: $Message"
}

# Function to schedule a task (simplified for testing)
function Schedule-Task {
    param (
        [string]$TaskName,
        [string]$Action,
        [datetime]$TriggerTime
    )
    Write-Output "Scheduled Task: $TaskName at $TriggerTime"
}

# Function to send email notification (mocked for testing)
function Send-Notification {
    param (
        [string]$EmailTo,
        [string]$Body,
        [string]$Subject
    )
    Write-Output "Email sent to $EmailTo with subject: $Subject"
}

# Main script logic
try {
    $groupName = ""

    if ($parameters.CatalogName -eq "GITHUB ENT -Mavericks") {
        if ($parameters.RequestType -eq "github access") {
            $groupName = "githubaccess_hexavarsity"
        }
    } elseif ($parameters.CatalogName -eq "GITHUB ENT -Repository") {
        if ($parameters.RequestType -eq "github access") {
            $groupName = "Github_access_users"
        }
    }

    $errormessage = ""
    $isError = $false

    Write-Output "Starting access process for user $($parameters.EmpId)"

    if ($parameters.EmpId -ne "") {
        try {
            # Mock AD group check
            $group = @{ SamAccountName = $groupName }
            if ($group) {
                LogEntry -LogFile "testlog.txt" -Message "Group $groupName Exists"
                # Mock group membership check
                $isMember = $false
                if ($isMember) {
                    LogEntry -LogFile "testlog.txt" -Message "$($parameters.EmpId) already a member of $groupName group"
                    Write-Output "$($parameters.EmpId) is already a member of the group $groupName."
                    $isError = $false
                } else {
                    if ($parameters.RequestType -eq "github access") {
                        LogEntry -LogFile "testlog.txt" -Message "Adding $($parameters.EmpId) to $groupName group"
                        Write-Output "Adding $($parameters.EmpId) to $groupName group"
                        # Mock adding to group
                        Write-Output "$($parameters.EmpId) added to the group $groupName."

                        # Mock scheduling tasks
                        $daysToRemove = if ($groupName -eq "githubaccess_hexavarsity") { 45 } else { 90 }
                        $notificationDays = 15
                        $removalDate = (Get-Date).AddDays($daysToRemove)
                        $notificationDate = $removalDate.AddDays(-$notificationDays)

                        $removalTaskName = "Remove_$($parameters.EmpId)_From_$groupName"
                        $notificationTaskName = "Notify_$($parameters.EmpId)_About_$groupName_Removal"

                        $removalAction = "Mock removal action"
                        $notificationBody = "Mock notification body"
                        $notificationAction = "Mock notification action"

                        Schedule-Task -TaskName $removalTaskName -Action $removalAction -TriggerTime $removalDate
                        Schedule-Task -TaskName $notificationTaskName -Action $notificationAction -TriggerTime $notificationDate

                        # Mock email sending
                        $Body = "Mock email body"
                        Write-Output "Sending email to $($parameters.EmpId)@example.com"
                        Send-Notification -EmailTo "$($parameters.EmpId)@example.com" -Body $Body -Subject "Access request completed"
                        Write-Output "Email sent to $($parameters.EmpId)@example.com successfully"
                    }
                }
            } else {
                LogEntry -LogFile "testlog.txt" -Message "$groupName group not found in AD"
                Write-Output "Group $groupName not found in AD."
                $isError = $true
                $errormessage += "Automation couldn't find the group $groupName in AD,"
            }
        } catch {
            $message = $_.Exception.Message
            $isError = $true
            $errormessage += (", $($parameters.EmpId) not added because $message ,")
        }
    }

    if ($isError) {
        LogEntry -LogFile "testlog.txt" -Message "Task execution failed with error message: $errormessage, ticket is ejected."
        Write-Output ("Task execution failed with error message: $errormessage, ticket is ejected.")
    } else {
        LogEntry -LogFile "testlog.txt" -Message "Task execution success, ticket is closed."
        Write-Output ("Task execution success, ticket is closed.")
    }
} catch {
    LogEntry -LogFile "testlog.txt" -Message "Task execution failed"
    Write-Output ("Task execution failed, putting the ticket to WIP with reason: $($_.Exception.Message).")
}
