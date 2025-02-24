# Import the Active Directory module
Import-Module ActiveDirectory

# Define parameters
$parameters = @{
    EmpId = "testuser"          # Replace with the actual username
    CatalogName = "GITHUB ENT -Mavericks"  # Replace with the actual catalog name
    RequestType = "github access"  # Replace with the actual request type
}

# Log file path
$logDirectory = "C:\Scripts\Youcom\accesslogs"
$date = Get-Date -UFormat %d-%b-%Y
$dateformat = [string](Get-Date).Hour + 'hours' + [string](Get-Date).Minute + 'mins' + [string](Get-Date).Second + 'seconds'
$newlogfilename = "Git_access_log_" + $date + "_" + $dateformat + ".txt"
$LogFile = "$logDirectory\$newlogfilename"

# Ensure the log directory exists
if (-not (Test-Path -Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory
}

# Function to log entries
function LogEntry {
    param (
        $LogFile,
        $Message
    )
    Add-Content -Path $LogFile -Value $Message
}

try {
    $member = $parameters.EmpId
    $catalogName = $parameters.CatalogName
    $requestType = $parameters.RequestType
    $groupName = ""

    Write-Output "Starting access process for user $member"

    if ($catalogName -eq "GITHUB ENT -Mavericks") {
        if ($requestType -eq "github access") {
            $groupName = "githubaccess_hexavarsity"
        }
    } elseif ($catalogName -eq "GITHUB ENT -Repository") {
        if ($requestType -eq "github access") {
            $groupName = "Github_access_users"
        }
    }

    if ($groupName -eq "") {
        Write-Output "No valid group name found for the given catalog name and request type."
        exit
    }

    if ($member -ne "") {
        try {
            $group = Get-ADGroup -Filter { SamAccountName -eq $groupName } -ErrorAction Stop
            if ($group) {
                LogEntry -LogFile $LogFile -Message "Group $groupName Exists"
                $isMember = Get-ADGroupMember -Identity $group.DistinguishedName | Where-Object { $_.SamAccountName -eq $member }
                if ($isMember) {
                    LogEntry -LogFile $LogFile -Message "$($member) already a member of $groupName group"
                    Write-Output "$member is already a member of the group $groupName."
                } else {
                    LogEntry -LogFile $LogFile -Message "Adding $($member) to $groupName group"
                    Write-Output "Adding $($member) to $groupName group"
                    Add-ADGroupMember -Identity $group.DistinguishedName -Members $member -ErrorAction Stop
                    Write-Output "$member added to the group $groupName."

                    # Verify the addition
                    $verification = Get-ADGroupMember -Identity $group.DistinguishedName | Where-Object { $_.SamAccountName -eq $member }
                    if ($verification) {
                        Write-Output "$member successfully added to the group $groupName."
                    } else {
                        Write-Output "$member was not added to the group $groupName."
                    }
                }
            } else {
                LogEntry -LogFile $LogFile -Message "$groupName group not found in AD"
                Write-Output "Group $groupName not found in AD."
            }
        } catch {
            $message = $_.Exception.Message
            LogEntry -LogFile $LogFile -Message "Error: $message"
            Write-Output "Error: $message"
        }
    } else {
        Write-Output "Member parameter is empty."
    }
} catch {
    $message = $_.Exception.Message
    LogEntry -LogFile $LogFile -Message "Task execution failed with error: $message"
    Write-Output "Task execution failed with error: $message"
}
