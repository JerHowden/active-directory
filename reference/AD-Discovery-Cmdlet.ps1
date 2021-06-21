#Requires -modules ActiveDirectory


# AD Users/Groups
$GetUsersStatistics = { Function Get-UsersStatistics {

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
            HelpMessage='Cutoffs in days for inactive users and computers. (90, 180, 360)')]
        [ValidateScript({ ($_.count -gt 0) -and ($_.count -le 12) })]
        [int[]]$InactiveThresholds = (90, 180, 360)
    )

    $Date = [DateTime]::ParseExact($DateString, 'yyyy-MM-dd HH:mm:ss', $null)

    Write-Progress -Id 10 -ParentId 1 -Activity 'User Statistics' -Status " --- Scanning User Objects" -PercentComplete 1

    # Totals
    $Users = Get-ADUser -Filter * -Properties name,lastlogondate,enabled,admincount -Server $Server
    $EnabledUsers = $Users | Where-Object {$_.enabled}
    $AdminUsers = $Users | Where-Object {$_.admincount -eq 1}
    $TotalStatistics = [ordered]@{
        'Total User Objects:' = ($Users).count
        'Enabled User Objects:' = ($EnabledUsers).count
        'Admin User Objects:' = ($AdminUsers).count
        'Total Groups:' = (Get-ADGroup -Filter * -Server $Server).count
        'Empty Groups:' = (Get-ADGroup -Filter * -Server $Server -Properties Members | Where-Object {-not $_.members}).count
    }

    Write-Progress -Id 10 -ParentId 1 -Activity 'User Statistics' -Status " --- Scanning Inactive Users" -PercentComplete 50

    # Inactive Users
    $InactiveStatistics = [ordered]@{}
    $ThresholdDates = $InactiveThresholds | ForEach-Object { $Date.AddDays(-1 * $_) }
    for($i=0; $i -lt $InactiveThresholds.Count; $i++) {
        $ThresholdCount = ($EnabledUsers | Where-Object {$_.lastlogondate -lt $ThresholdDates[$i]}).count
        if(!$ThresholdCount) {
            $ThresholdCount = 0
        }
        $InactiveStatistics['Users ' + $InactiveThresholds[$i] + ' Days Inactive:'] = $ThresholdCount
    }

    Write-Progress -Id 10 -ParentId 1 -Activity 'User Statistics' -Status " --- All Users Scanned" -PercentComplete 100

    return ($TotalStatistics + $InactiveStatistics)

} }

#AD Endpoints
$GetEndpointStatistics = { Function Get-EndpointStatistics {

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
            HelpMessage='Cutoffs in days for inactive users and computers. (90, 180, 360)')]
        [ValidateScript({ ($_.count -gt 0) -and ($_.count -le 12) })]
        [int[]]$InactiveThresholds = (90, 180, 360)
    )

    $Date = [DateTime]::ParseExact($DateString, 'yyyy-MM-dd HH:mm:ss', $null)

    Write-Progress -Id 20 -ParentId 2 -Activity 'Endpoint Statistics' -Status " --- Scanning Computers" -PercentComplete 1

    # Totals
    $Computers = Get-ADComputer -Filter * -Properties name,operatingsystem,lastlogondate,passwordlastset -Server $Server
    $ComputersEnabled = ($Computers | Where-Object {$_.enabled})
    $ComputersDisabled = ($Computers | Where-Object {!$_.enabled})
    $ComputerStatistics = [ordered]@{
        'Total Computer Objects:' = ($Computers).count
        'Enabled Computer Objects:' = ($ComputersEnabled).count
        'Disabled Computer Objects:' = ($ComputersDisabled).count
    }

    Write-Progress -Id 20 -ParentId 2 -Activity 'Endpoint Statistics' -Status " --- Scanning Inactive Computers" -PercentComplete 33

    # Inactive Computers
    $ComputersInactiveStatistics = [ordered]@{}
    $ThresholdDates = $InactiveThresholds | ForEach-Object { $Date.AddDays(-1 * $_) }
    for($i=0; $i -lt $InactiveThresholds.Count; $i++) {
        $ThresholdCount = ($ComputersEnabled | Where-Object {$_.lastlogondate -lt $ThresholdDates[$i]}).count
        if(!$ThresholdCount) {
            $ThresholdCount = 0
        }
        $ComputersInactiveStatistics['Computers ' + $InactiveThresholds[$i] + ' Days Inactive:'] = $ThresholdCount
    }
    for($i=0; $i -lt $InactiveThresholds.Count; $i++) {
        $ThresholdCount = ($ComputersEnabled | Where-Object {$_.passwordlastset -lt $ThresholdDates[$i]}).count
        if(!$ThresholdCount) {
            $ThresholdCount = 0
        }
        $ComputersInactiveStatistics['Computers ' + $InactiveThresholds[$i] + ' Days Since Password Set:'] = $ThresholdCount
    }

    Write-Progress -Id 20 -ParentId 2 -Activity 'Endpoint Statistics' -Status " --- Scanning Operating Systems" -PercentComplete 66

    # Operating Systems
    $ComputerOSCount = [ordered]@{
        'Windows XP Computers:' = 0
        'Windows 7 Computers:' = 0
        'Windows 8 Computers:' = 0
        'Windows 10 Computers:' = 0
        'Windows 2000 Servers:' = 0
        'Windows 2003 Servers:' = 0
        'Windows 2008 Servers:' = 0
        'Windows 2012 Servers:' = 0
        'Windows 2016 Servers:' = 0
        'Windows 2019 Servers:' = 0
    }
    foreach ($C in $Computers) {
        Switch -Regex ($C.OperatingSystem) {
            'XP' {$ComputerOSCount['Windows XP Computers:']++; break}
            'Windows 7' {$ComputerOSCount['Windows 7 Computers:']++; break}
            'Windows 8' {$ComputerOSCount['Windows 8 Computers:']++; break}
            'Windows 10' {$ComputerOSCount['Windows 10 Computers:']++; break}
            'Server 2000' {$ComputerOSCount['Windows 2000 Servers:']++; break}
            'Server 2003' {$ComputerOSCount['Windows 2003 Servers:']++; break}
            'Server 2008' {$ComputerOSCount['Windows 2008 Servers:']++; break}
            'Server 2012' {$ComputerOSCount['Windows 2012 Servers:']++; break}
            'Server 2016' {$ComputerOSCount['Windows 2016 Servers:']++; break}
            'Server 2019' {$ComputerOSCount['Windows 2019 Servers:']++; break}
            Default {$ComputerOSCount['? - ' + $C.OperatingSystem + ':']++}
        }
    }

    Write-Progress -Id 20 -ParentId 2 -Activity 'Endpoint Statistics' -Status " --- All Computers Scanned" -PercentComplete 100
    
    return ($ComputerStatistics + $ComputersInactiveStatistics + $ComputerOSCount)

} }

# OUs with Blocked Inheritance
$GetOUsWithBlockedInheritanceCount = { Function Get-OUsWithBlockedInheritanceCount {
    
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory,
            HelpMessage='Active Directory Server. (DC01.prod.demo.com)')]
        [string]$Server,

        [Parameter(Mandatory,
            HelpMessage='Active Directory root DSE default naming context.')]
        [string]$DefaultNamingContext
    )

    $OUs = Get-ADOrganizationalUnit -SearchBase $DefaultNamingContext -Filter * -Server $Server
    $BlockedCount = 0

    $Index = 0
    $Total = $OUs.Count

    $OUs | ForEach-Object {
        If ((Get-GPInheritance $_.DistinguishedName).GpoInheritanceBlocked -eq 'Yes') {
            $BlockedCount++
        }
        $Index++
        Write-Progress -Id 30 -ParentId 3 -Activity 'Blocked OUs' -Status " --- OUs Scanned: $Index" -PercentComplete (100 * $Index / $Total)
    }
  
    return [ordered]@{ 'OUs with Blocked Inheritance:' = $BlockedCount }
    
} }

# Empty OUs
$GetEmptyOUsCount = { Function Get-EmptyOUsCount {

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory,
            HelpMessage='Active Directory Server. (DC01.prod.demo.com)')]
        [string]$Server,

        [Parameter(Mandatory,
            HelpMessage='Active Directory root DSE default naming context.')]
        [string]$DefaultNamingContext
    )

    $OUs = Get-ADOrganizationalUnit -SearchBase $DefaultNamingContext -Filter * -Server $Server
    $EmptyCount = 0

    $Index = 0
    $Total = $OUs.Count
    
    $OUs | ForEach-Object { 
        If (!(Get-ADObject -Filter * -SearchBase $_ -SearchScope OneLevel -Server $Server)) {
            $EmptyCount++
        } 
        $Index++
        Write-Progress -Id 40 -ParentId 4 -Activity 'Empty OUs' -Status " --- OUs Scanned: $Index" -PercentComplete (100 * $Index / $Total)
    }
    
    return [ordered]@{ 'Empty OUs:' = $EmptyCount }

} }
    
# Unlinked GPOs
$GetUnlinkedGPOsCount = { Function Get-UnlinkedGPOsCount {

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory,
            HelpMessage='Active Directory Domain. (prod.demo.com)')]
        [string]$Domain
    )

    $GPOs = Get-GPO -All -Domain $Domain
    $UnlinkedCount = 0

    $Index = 0
    $Total = $GPOs.Count

    $GPOs | ForEach-Object {
        If ($_ | Get-GPOReport -ReportType XML -Domain $Domain | Select-String -NotMatch '<LinksTo>') {
            # Write-Host $_.DisplayName
            $UnlinkedCount++
        }
        Write-Progress -Id 50 -ParentId 5 -Activity 'Unlinked GPOs' -Status " --- GPOs Scanned: $Index" -PercentComplete (100 * $Index / $Total)
    }
    
    return [ordered]@{
        'Total GPOs:' = $GPOs.Count
        'Unlinked GPOs:' = $UnlinkedCount
    }

} }

# Duplicate SPNs
$GetDuplicateSPNsCount = { Function Get-DuplicateSPNsCount {
    
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory,
            HelpMessage='Active Directory Server. (DC01.prod.demo.com)')]
        [string]$Server
    )

    $AllSPNsObjects = Get-ADObject -Server $Server -Filter "(objectClass -eq 'user') -and (objectClass -eq 'computer')" -Properties sAMAccountName, servicePrincipalName | Where-Object servicePrincipalName -ne $null
    $SPNArray = @()
    $DuplicateCount = 0

    $Index = 0
    $Total = $AllSPNsObjects.Count

    foreach ($SPNObject in $AllSPNsObjects) {
        $SamAccountName = $SPNObject.SamAccountName
        $ServicePrincipalNames = $SPNObject.ServicePrincipalName
        foreach ($ServicePrincipalName in $ServicePrincipalNames) {
            $MatchedSPNs = $SPNArray.ServicePrincipalName -like "$ServicePrincipalName"
            if ($MatchedSPNs) {
                foreach ($MatchSPN in $MatchedSPNs) {
                    $MatchSamAccountName = $MatchSPN.SamAccountName
                    if ($MatchSamAccountName -ne $SamAccountName) {
                       $DuplicateCount++
                    }
                }
            } else {
                $SPNArray += [PSCustomObject]@{
                    "SamAccountName" = $SamAccountName
                    "ServicePrincipalName" = $ServicePrincipalName
                }
            }
        }
        $Index++
        Write-Progress -Id 60 -ParentId 6 -Activity 'SPN Duplicates' -Status " --- SPNs Scanned: $Index" -PercentComplete (100 * $Index / $Total)
    }

    return [ordered]@{
        'Duplicate SPNs:' = $DuplicateCount
    }

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
    .Synopsis
    The Invoke-ADDiscovery returns basic active directory statistics on a domain.

    .Description
    Returns a list of information on the following:
     - Domain
     - Forest
     - FSMO Holders
     - Schema Version
     - Tombstone Lifetime
     - Domain Password Policy
     - AD Backups
     - AD Recycle Bin
     - AD Replication Links

     - AD Sites and Subnets
     - AD Trusts
     - AD Users and Groups
         - Totals
         - Inactive
     - AD Endpoints
         - Totals
         - Inactive
         - Operating Systems
     - OUs with Blocked Inheritance
     - Empty OUs
     - Unlinked GPOs
     - Duplicate SPNs

     .Example
     Invoke-ADDiscovery -Domain prod.ncidemo.com -DomainController DC01 -InactiveThresholds 30,60,90

     .Example
     'prod.ncidemo.com', 'priv.redforest.com' | Invoke-ADDiscovery -DomainController DC01 -Export


#>
Function Invoke-ADDiscovery {
    [CmdletBinding()]
    Param (
        [Parameter(ValueFromPipeline,
            HelpMessage='Active Directory Domain. (prod.demo.com)')]
        [string]$Domain,

        [Parameter(Mandatory,
            HelpMessage='Active Directory Server. (DC01)')]
        [string]$DomainController,

        [Parameter(
            HelpMessage='Cutoffs in days for inactive users and computers.')]
        [ValidateScript({ ($_.count -gt 0) -and ($_.count -le 12) })]
        [int[]]$InactiveThresholds = (90,180,360),

        [Parameter(
            HelpMessage='Maximum number of AD Objects to return.')]
        [int]$Limit,

        [Parameter(
            HelpMessage='Export to CSV.')]
        [switch]$Export,

        [Parameter(
            HelpMessage='Running cmdlet in production.')]
        [switch]$Prod
    )

    Begin {

        $RootPath = Split-Path $PSScriptRoot
        $Date = Get-Date
        $DiscoveryArray = @()

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
        Write-Progress -Id 0 -Activity 'Discovery' -Status "Initiating Jobs:" -PercentComplete 0
        $UsersStatisticsJob = Start-Job -InitializationScript $GetUsersStatistics -ScriptBlock {
            param($Server, $Date, $InactiveThresholds)
            Get-UsersStatistics -Server $Server -DateString ($Date).ToString('yyyy-MM-dd HH:mm:ss') -InactiveThresholds $InactiveThresholds 
        } -ArgumentList $Server,$Date,$InactiveThresholds
        $EndpointStatisticsJob = Start-Job -InitializationScript $GetEndpointStatistics -ScriptBlock { 
            param($Server, $Date, $InactiveThresholds)
            Get-EndpointStatistics -Server $Server -DateString ($Date).ToString('yyyy-MM-dd HH:mm:ss') -InactiveThresholds $InactiveThresholds 
        } -ArgumentList $Server,$Date,$InactiveThresholds
        $OUsWithBlockedInheritanceCountJob = Start-Job -InitializationScript $GetOUsWithBlockedInheritanceCount -ScriptBlock { 
            param($Server, $DefaultNamingContext)
            Get-OUsWithBlockedInheritanceCount -Server $Server -DefaultNamingContext $DefaultNamingContext 
        } -ArgumentList $Server,$RootDSE.defaultNamingContext
        $EmptyOUsCountJob = Start-Job -InitializationScript $GetEmptyOUsCount -ScriptBlock { 
            param($Server, $DefaultNamingContext)
            Get-EmptyOUsCount -Server $Server -DefaultNamingContext $DefaultNamingContext 
        } -ArgumentList $Server,$RootDSE.defaultNamingContext
        $UnlinkedGPOsCountJob = Start-Job -InitializationScript $GetUnlinkedGPOsCount -ScriptBlock { 
            param($Domain)
            Get-UnlinkedGPOsCount -Domain $Domain 
        } -ArgumentList $Domain
        $DuplicateSPNsCountJob = Start-Job -InitializationScript $GetDuplicateSPNsCount -ScriptBlock { 
            param($Server)
            Get-DuplicateSPNsCount -Server $Server 
        } -ArgumentList $Server

        $Jobs = Get-Job | ? { $_.state -eq 'Running' }
        $TotalJobs = $Jobs.Count
        $RunningJobs = $Jobs.Count
        while($RunningJobs -gt 0) {
            $Jobs = Get-Job | ? { $_.state -eq 'Running' }
            $RunningJobs = $Jobs.Count
            Write-Progress -Id 0 -Activity 'Discovery' -Status "$RunningJobs Jobs Left:" -PercentComplete ((100 * ($TotalJobs-$RunningJobs)) / $TotalJobs)

            WriteJobProgress -Job $UsersStatisticsJob -Id 1
            WriteJobProgress -Job $EndpointStatisticsJob -Id 2
            WriteJobProgress -Job $OUsWithBlockedInheritanceCountJob -Id 3
            WriteJobProgress -Job $EmptyOUsCountJob -Id 4
            WriteJobProgress -Job $UnlinkedGPOsCountJob -Id 5
            WriteJobProgress -Job $DuplicateSPNsCountJob -Id 6

            Start-Sleep -Seconds 1
        }

        # Wait for all Discovery Jobs
        # Wait-Job -Job $UsersStatisticsJob,$EndpointStatisticsJob,$OUsWithBlockedInheritanceCountJob,$EmptyOUsCountJob,$UnlinkedGPOsCountJob,$DuplicateSPNsCountJob

        # Receive Discovery Jobs
        $Discovery += Receive-Job -Job $UsersStatisticsJob
        $Discovery += Receive-Job -Job $EndpointStatisticsJob
        $Discovery += Receive-Job -Job $OUsWithBlockedInheritanceCountJob
        $Discovery += Receive-Job -Job $EmptyOUsCountJob
        $Discovery += Receive-Job -Job $UnlinkedGPOsCountJob
        $Discovery += Receive-Job -Job $DuplicateSPNsCountJob
        
        # $Discovery | Format-Table -AutoSize
        $DiscoveryArray += [pscustomobject]$Discovery

    }

    End {
        # Write-Host $DiscoveryArray
        If($Export) {
            If($Prod) {
                $DiscoveryArray | Export-Csv -Path ($PSScriptRoot + '\AD-Discovery_' + ($Date).ToString('yyyy-MM-dd_HH-mm-ss') + '.csv') -NoTypeInformation
            } Else {
                $DiscoveryArray | Export-Csv -Path ($RootPath + '\results\Discovery_' + ($Date).ToString('yyyy-MM-dd_HH-mm-ss') + '.csv') -NoTypeInformation
            }
        }
        return $DiscoveryArray
    }
}

# Test
'prod.ncidemo.com' | Invoke-ADDiscovery -DomainController 'DC01' -Export

# Prod
# 'novelis.biz', 'aleris.biz' | Invoke-ADDiscovery -DomainController 'DC01' -Export -Prod
