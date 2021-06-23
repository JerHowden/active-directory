# AD Users/Groups
$ExportScopedUsersAndGroups = { Function Export-ScopedUsersAndGroups {

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory,
            HelpMessage='Active Directory Server. (DC01.prod.demo.com)')]
        [string]$Server,

        [Parameter(Mandatory,
            HelpMessage='Date string in the form of yyyy-MM-dd HH:mm:ss')]
        [ValidateScript({ 
            [System.DateTime]$ParsedDate = Get-Date
            [DateTime]::TryParseExact($_, 'yyyy-MM-dd HH:mm:ss', $null, [System.Globalization.DateTimeStyles]::None, [ref]$ParsedDate)
            $ParsedDate
        })]
        [string]$DateString,

        [Parameter(
            HelpMessage='Cutoff in days for inactive users. (90), (180), (360)')]
        [ValidateScript({ ($_.count -gt 0) -and ($_.count -le 12) })]
        [int]$InactiveThreshold,

        [Parameter(Mandatory,
            HelpMessage='Folder to send the export files to.')]
        [string]$Directory
    )

    $Date = [DateTime]::ParseExact($DateString, 'yyyy-MM-dd HH:mm:ss', $null)
    If(!$InactiveThreshold) { $InactiveThreshold = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge.Days }

    Write-Progress -Id 10 -ParentId 1 -Activity '(1/10) User Scoping' -Status " --- Initializating User Scoping" -PercentComplete 0


    # Users
    $Users = Get-ADUser -Filter * -Properties name,distinguishedname,lastlogondate,enabled,admincount -Server $Server
    $InactiveUserDate = $Date.AddDays(-1 * $InactiveThreshold)

    Write-Progress -Id 10 -ParentId 1 -Activity '(2/10) User Scoping' -Status " --- Scoping User Objects" -PercentComplete 40
    $GreenUsers = $Users | Where-Object {$_.enabled -and $_.lastlogondate -and $_.lastlogondate -gt $InactiveUserDate}
    $YellowUsers = $Users | Where-Object {$_.enabled -and $_.lastlogondate -and $_.lastlogondate -le $InactiveUserDate -and $_.lastlogondate -gt ($Date.AddDays(-365))}
    $RedUsers = $Users | Where-Object {(!$_.enabled) -or (!$_.lastlogondate) -or ($_.enabled -and $_.lastlogondate -le ($Date.AddDays(-365)))}

    Write-Progress -Id 10 -ParentId 1 -Activity '(3/10) User Scoping' -Status " --- Scoped User Objects!" -PercentComplete 100

    Write-Host "In-Scope Users" -ForegroundColor DarkGreen
    $GreenUsers | Select-Object -Property name,enabled,lastlogondate | Format-Table -AutoSize
    Write-Host "Questionable Users" -ForegroundColor Yellow
    $YellowUsers | Select-Object -Property name,enabled,lastlogondate | Format-Table -AutoSize
    Write-Host "Out-of-Scope Users" -ForegroundColor Red
    $RedUsers | Select-Object -Property name,enabled,lastlogondate | Format-Table -AutoSize


    # Groups
    Write-Progress -Id 10 -ParentId 1 -Activity '(4/10) User-Group Scoping' -Status " --- Getting Groups with Green Users" -PercentComplete 0
    $GroupsWithGreen = $GreenUsers | ForEach-Object {
        Get-WinADGroupMemberOf $_.DistinguishedName
    } | Select -ExpandProperty Name -Unique | % { Get-ADGroup $_ }
    Write-Progress -Id 10 -ParentId 1 -Activity '(5/10) User-Group Scoping' -Status " --- Getting Groups with Yellow Users" -PercentComplete 33
    $GroupsWithYellow = $YellowUsers | ForEach-Object {
        Get-WinADGroupMemberOf $_.DistinguishedName
    } | Select -ExpandProperty Name -Unique | % { Get-ADGroup $_ }
    Write-Progress -Id 10 -ParentId 1 -Activity '(6/10) User-Group Scoping' -Status " --- Getting Groups with Red Users" -PercentComplete 67
    $GroupsWithRed = $RedUsers | ForEach-Object {
        Get-WinADGroupMemberOf $_.DistinguishedName
    } | Select -ExpandProperty Name -Unique | % { Get-ADGroup $_ }
    Write-Progress -Id 10 -ParentId 1 -Activity '(7/10) User-Group Scoping' -Status " --- All Groups Received" -PercentComplete 100

    $GroupsCount = $GroupsWithGreen.count + $GroupsWithYellow.count + $GroupsWithRed.count #(includes duplicates)
    Write-Host "$($GroupsCount) Groups, $($GroupsWithGreen.count) Green Groups, $($GroupsWithYellow.count) Yellow Groups, $($GroupsWithRed.count) Red Groups"

    # Categorizing Groups by Type
    For($i = 0; $i -lt $GroupsWithGreen.count; $i++) {
        $yellowIndex
        For($j = 0; $j -lt $GroupsWithYellow.count; $j++) {
            If($GroupsWithGreen[$i].DistinguishedName -match $GroupsWithYellow[$j].DistinguishedName) {
                $GroupsWithGreen[$i].CustomGroupType = 4
                $GroupsWithYellow[$j].CustomGroupType = 4
                $yellowIndex = $j
                Break
            }
        }
        For($j = 0; $j -lt $GroupsWithRed.count; $j++) {
            If($GroupsWithGreen[$i].DistinguishedName -match $GroupsWithRed[$j].DistinguishedName) {
                If($GroupsWithGreen[$i].CustomGroupType -eq 4) {
                    $GroupsWithGreen[$i].CustomGroupType = 7
                    $GroupsWithRed[$j].CustomGroupType = 7
                    $GroupsWithYellow[$yellowIndex].CustomGroupType = 7
                } Else {
                    $GroupsWithGreen[$i].CustomGroupType = 6
                    $GroupsWithRed[$j].CustomGroupType = 6
                }
                Break
            }
        }
        If(!$GroupsWithGreen[$i].CustomGroupType) {
            $GroupsWithGreen[$i].CustomGroupType = 1
        }
        Write-Progress -Id 10 -ParentId 1 -Activity '(8/10) Green User-Group Scoping' -Status " --- Added User-Group Type $($GroupsWithGreen[$i].CustomGroupType)" -PercentComplete (100 * $i / $GroupsWithGreen.count)
    }

    For($i = 0; $i -lt $GroupsWithYellow.count; $i++) {
        For($j = 0; $j -lt $GroupsWithRed.count; $j++) {
            If($GroupsWithYellow[$i].DistinguishedName -match $GroupsWithRed[$j].DistinguishedName) {
                If($GroupsWithYellow[$i].CustomGroupType -ne 7) {
                    $GroupsWithYellow[$i].CustomGroupType = 5
                    $GroupsWithRed[$j].CustomGroupType = 5
                }
                Break
            }
        }
        If(!$GroupsWithYellow[$i].CustomGroupType) {
            $GroupsWithYellow[$i].CustomGroupType = 2
        }
        Write-Progress -Id 10 -ParentId 1 -Activity '(9/10) Yellow User-Group Scoping' -Status " --- Added User-Group Type $($GroupsWithYellow[$i].CustomGroupType)" -PercentComplete (100 * $i / $GroupsWithYellow.count)
    }

    For($i = 0; $i -lt $GroupsWithRed.count; $i++) {
        If(!$GroupsWithRed[$i].CustomGroupType) {
            $GroupsWithRed[$i].CustomGroupType = 3
        }
        Write-Progress -Id 10 -ParentId 1 -Activity '(10/10) Red User-Group Scoping' -Status " --- Added User-Group Type $($GroupsWithRed[$i].CustomGroupType)" -PercentComplete (100 * $i / $GroupsWithRed.count)
    }

    # Export
    New-Item -Path "$($Directory)" -Name "ScopeReport $($Date.ToString('yyyy-MM-dd HH-mm-ss'))" -ItemType "directory"
    $GreenUsers | Export-Csv -NoTypeInformation -Path "$($Directory)\ScopeReport $($Date.ToString('yyyy-MM-dd HH-mm-ss'))\GreenUsers.csv"
    $YellowUsers | Export-Csv -NoTypeInformation -Path "$($Directory)\ScopeReport $($Date.ToString('yyyy-MM-dd HH-mm-ss'))\YellowUsers.csv"
    $RedUsers | Export-Csv -NoTypeInformation -Path "$($Directory)\ScopeReport $($Date.ToString('yyyy-MM-dd HH-mm-ss'))\RedUsers.csv"
    $GroupsWithGreen | Export-Csv -NoTypeInformation -Path "$($Directory)\ScopeReport $($Date.ToString('yyyy-MM-dd HH-mm-ss'))\GroupsWithGreen.csv"
    $GroupsWithYellow | Export-Csv -NoTypeInformation -Path "$($Directory)\ScopeReport $($Date.ToString('yyyy-MM-dd HH-mm-ss'))\GroupsWithYellow.csv"
    $GroupsWithRed | Export-Csv -NoTypeInformation -Path "$($Directory)\ScopeReport $($Date.ToString('yyyy-MM-dd HH-mm-ss'))\GroupsWithRed.csv"

} }


#Accepts a Job as a parameter and writes the latest progress of it
function WriteJobProgress {

    param($Job, $Id)
 
    #Make sure the first child job exists
    if($Job.ChildJobs[0].Progress -ne $null)
    {
        #Extracts the latest progress of the job and writes the progress
        $jobProgressHistory = $Job.ChildJobs[0].Progress;
        $latestProgress = $jobProgressHistory[$jobProgressHistory.Count - 1];
        $latestPercentComplete = $latestProgress | Select -expand PercentComplete;
        $latestActivity = $latestProgress | Select -expand Activity;
        $latestStatus = $latestProgress | Select -expand StatusDescription;
    
        #When adding multiple progress bars, a unique ID must be provided. Here I am providing the JobID as this
        Write-Progress -Id $Id -ParentId 0 -Activity $latestActivity -Status $latestStatus -PercentComplete $latestPercentComplete;
    }
}


<#
    .Notes
    Get stale users (91 days)
     -> Get all groups that stale users are a part of
         -> Get all groups that are 100% stale?
    Get stale computers (31 days)
     -> Get all groups that computers are a part of
     -> Get all fireshares these computers have access to?
#>
Function Invoke-ADScopeReport {
    [CmdletBinding()]
    Param (
        [Parameter(ValueFromPipeline,
            HelpMessage='Active Directory Domain. (prod.demo.com)')]
        [string]$Domain,

        [Parameter(Mandatory,
            HelpMessage='Active Directory Server. (DC01)')]
        [string]$DomainController
    )

    Begin {

        $Date = Get-Date
        $ScopeArray = @()

    }

    # Pipeline should always be domain name (prod.ncidemo.com)
    Process {
    
        # Domain Variables
        $Server = $DomainController + '.' + $Domain
        $RootDSE = Get-ADRootDSE -Server $Server
        $Discovery = [ordered]@{
            'Domain:' = $Domain
            'Date:' = ($Date).ToString('yyyy-MM-dd HH:mm:ss')
        }

        # Start Discovery Jobs
        Write-Progress -Id 0 -Activity 'Scope Report' -Status "Initiating Jobs:" -PercentComplete 0
        $UserScopingJob = Start-Job -InitializationScript $ExportScopedUsersAndGroups -ScriptBlock {
            param($Server, $Date, $Directory)
            Export-ScopedUsersAndGroups -Server $Server -DateString ($Date).ToString('yyyy-MM-dd HH:mm:ss') -InactiveThreshold 90 -Directory $Directory
        } -ArgumentList $Server,$Date,$PSScriptRoot

        $Jobs = Get-Job | ? { $_.state -eq 'Running' }
        $TotalJobs = $Jobs.Count
        $RunningJobs = $Jobs.Count
        while($RunningJobs -gt 0) {
            $Jobs = Get-Job | ? { $_.state -eq 'Running' }
            $RunningJobs = $Jobs.Count
            Write-Progress -Id 0 -Activity 'Scope Report' -Status "$RunningJobs Jobs Left:" -PercentComplete ((100 * ($TotalJobs-$RunningJobs)) / $TotalJobs)

            WriteJobProgress -Job $UserScopingJob -Id 1

            Start-Sleep -Seconds 1
        }
        # Receive Discovery Jobs
        Receive-Job -Job $UserScopingJob
        


    }

    End {}
}

# Test
Invoke-ADScopeReport -Domain 'prod.ncidemo.com' -DomainController 'DC01'

# Prod
# Invoke-ADScopeReport -Domain '' -DomainController ''
