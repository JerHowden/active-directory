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
        [int[]]$InactiveThreshold,
    )

    $Date = [DateTime]::ParseExact($DateString, 'yyyy-MM-dd HH:mm:ss', $null)
    If(!$InactiveThreshold) { $InactiveThreshold = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge.Days }

    Write-Progress -Id 10 -ParentId 1 -Activity 'User/Group Scoping' -Status " --- Initializating User/Group Scoping" -PercentComplete 1

    # Users
    $Users = Get-ADUser -Filter * -Properties name,distinguishedname,lastlogondate,enabled,admincount -Server $Server
    $InactiveUserDate = $Date.AddDays(-1 * $InactiveThreshold)

    Write-Progress -Id 10 -ParentId 1 -Activity 'User/Group Scoping' -Status " --- Scoping User Objects" -PercentComplete 25
    $GreenUsers = $Users | Where-Object {$_.enabled -and $_.lastlogondate -le $InactiveUserDate}
    $YellowUsers = $Users | Where-Object {$_.enabled -and $_.lastlogondate -gt $InactiveUserDate -and $_.lastlogondate -le ($Date.AddDays(-365))}
    $RedUsers = $Users | Where-Object {!$_.enabled -or $_.lastlogondate -gt ($Date.AddDays(-365))}

    Write-Progress -Id 10 -ParentId 1 -Activity 'User/Group Scoping' -Status " --- Scoped User Objects!" -PercentComplete 50
    $SetsTotal = ($GreenUsers.count + $YellowUsers.count + $RedUsers.count)
    If($SetsTotal -lt $Users.count) {
        Write-Host " --- ERROR: Scoped user sets not including all users."
        Return
    } ElseIf ($SetsTotal -gt $Users.count) {
        Write-Host " --- ERROR: Scoped user sets double counting certain users."
        Return
    }

    Write-Host "In-Scope Users" -ForegroundColor DarkGreen
    $GreenUsers | Format-Table -AutoSize
    Write-Host "Questionable Users" -ForegroundColor Yellow
    $YellowUsers | Format-Table -AutoSize
    Write-Host "Out-of-Scope Users" -ForegroundColor Red
    $RedUsers | Format-Table -AutoSize

    Write-Progress -Id 10 -ParentId 1 -Activity 'User/Group Scoping' -Status " --- " -PercentComplete 50

    #Groups
    $GroupsWithGreen = $GreenUsers | ForEach-Object {
        Get-WinADGroupMemberOf $_.DistinguishedName
    } | Select -ExpandProperty Name -Unique | % { Get-ADGroup $_ }
    $GroupsWithYellow = $YellowUsers | ForEach-Object {
        Get-WinADGroupMemberOf $_.DistinguishedName
    } | Select -ExpandProperty Name -Unique | % { Get-ADGroup $_ }
    $GroupsWithRed = $RedUsers | ForEach-Object {
        Get-WinADGroupMemberOf $_.DistinguishedName
    } | Select -ExpandProperty Name -Unique | % { Get-ADGroup $_ }

    # Categorizing by Type
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
    }

    For($i = 0; $i -lt $GroupsWithRed.count; $i++) {
        If(!$GroupsWithRed[$i].CustomGroupType) {
            $GroupsWithRed[$i].CustomGroupType = 3
        }
    }

    $GreenUsers | Export-Csv
    $YellowUsers | Export-Csv
    $RedUsers | Export-Csv
    $GroupsWithGreen | Export-Csv
    $GroupsWithYellow | Export-Csv
    $GroupsWithRed | Export-Csv

} }



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
            param($Server, $Date)
            Get-UsersStatistics -Server $Server -DateString ($Date).ToString('yyyy-MM-dd HH:mm:ss') -InactiveThreshold 90
        } -ArgumentList $Server,$Date

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
