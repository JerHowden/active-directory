

# Query Settings
    Clear-Host
    #Requires -modules ActiveDirectory
    $dDomain = 'prod.ncidemo.com' #change domain name
    $dServer = 'DC01' + '.' + $dDomain #change server name
    Write-Host ''
    Write-Host ''
    Write-Host('Querying Server: ' + $dServer) -ForegroundColor Cyan

# Global Variables
    $date = Get-Date
    $fDate = Get-Date -UFormat '%m%d%Y-%H%M'
    $rDSE = Get-ADRootDSE -Server $dServer
    $dInfo = Get-ADDomain -Server $dServer
    $fInfo = Get-ADForest -Server $dServer
    $directory = '..\results'

# Handle Output
    If( !(Test-Path $directory) ) {
        New-Item -Path $directory -ItemType Directory
    }
    Start-Transcript -path ($directory + '\AD-Discovery_' + $dDomain + '_' + $($fDate) + '.txt')
    Write-Host ''
    Write-Host 'Date: ' $date
    Write-Host ''

# Forest/Domain

    # Information
    Write-Host 'Domain Information:' -ForegroundColor Cyan
    Write-Host 'Domain Name: ' $dInfo.dnsroot
    Write-Host 'NetBIOS Name: ' $dInfo.netbiosname

    # Functional Levels
    $ffl = ($fInfo).forestmode
    $dfl = ($fInfo).domainmode
    $dAge = Get-ADObject ($rDSE).rootDomainNamingContext -Property whencreated -Server $dServer
    Write-Host 'Forest Functional Level: ' $ffl
    Write-Host 'Domain Functional Level: ' $dfl
    Write-Host 'Domain Created: ' $dAge.whencreated
    Write-Host ''

# FSMO Holders
    Write-Host 'FSMO Role Holders:' -ForegroundColor Cyan
    $fInfo | Select-Object DomainNamingMaster, SchemaMaster | Format-Table -AutoSize
    $dInfo | Select-Object DomainNamingMaster, SchemaMaster | Format-Table -AutoSize

# Schema Version
    Write-Host 'Schema Version: ' -NoNewline -ForegroundColor Cyan
    $schema = Get-ADObject ($rDSE).schemaNamingContext -Property objectVersion -Server $dServer
    Switch($schema.objectVersion) {
        13 { Write-Host '13 - Server 2000' -ForegroundColor Red; Break }
        30 { Write-Host '30 - Server 2003' -ForegroundColor Red; Break }
        31 { Write-Host '31 - Server 2003 R2' -ForegroundColor Red; Break }
        44 { Write-Host '44 - Server 2008' -ForegroundColor Red; Break }
        47 { Write-Host '47 - Server 2008 R2' -ForegroundColor Yellow; Break }
        56 { Write-Host '56 - Server 2012' -ForegroundColor Yellow; Break }
        69 { Write-Host '69 - Server 2012 R2' -ForegroundColor Green; Break }
        87 { Write-Host '87 - Server 2016' -ForegroundColor Green; Break }
        88 { Write-Host '88 - Server 2019' -ForegroundColor Green; Break }
        Default { Write-Host 'Schema Version Unknown' -ForegroundColor Yellow }
    }
    Write-Host ''

# Tombstone Lifetime
    Write-Host 'Tombstone Lifetime: ' -ForegroundColor Cyan
    $ts = (Get-ADObject -Identity 'CN=Directory Service,CN=Windows NT,CN=Services,$(($rDSE).configurationNamingContext)' `
          -Properties tombstoneLifetime -Server $dServer).tombstoneLifetime
    Write-Host $ts
    Write-Host ''

# Domain Password Policy
    Write-Host 'Domain Password Policy:' -ForegroundColor Cyan
    $dPwd = Get-ADDefaultDomainPasswordPolicy -Server 'DC01.prod.ncidemo.com'
    $dPwd | Select-Object ComplexityEnabled, LockoutDuration, LockoutThreshold, MaxPasswordAge, MinPasswordAge, `
    MinPasswordLength, PasswordHistoryCount, ReversibleEncryptionEnabled, LockoutObservationWindow | Format-List

# AD Backups
    Write-Host 'AD Backups:' -ForegroundColor Cyan
    Get-WinADLastBackup | Format-Table -AutoSize -Wrap -Property *
    Write-Host ''

# AD Recycle Bin
    Write-Host 'AD Recycle Bin:' -ForegroundColor Cyan
    $adRB = (Get-ADOptionalFeature 'Recycle Bin Feature' -Server $dServer).enabledscopes
    If($adRB) {
        Write-Host 'AD Recycle Bin is ENABLED.' -ForegroundColor Green
    } Else {
        Write-Host 'AD Recycle Bin is NOT ENABLED!!' -ForegroundColor Red
    }
    Write-Host ''

# AD Sites and Subnets
    Write-Host 'AD Sites and Subnets:' -ForegroundColor Cyan
    $sites = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest().Sites
    $sitesubnets = @()
    foreach ($site in $sites) {
        foreach($subnet in $site.subnets) {
            $obj = New-Object PSCustomObject -Property @{
                'Site' = $site.name
                'Subnet' = $subnet
                'Server' = $site.Servers
            }
            $sitesubnets += $obj
        }
    }
    $sitesubnets | Format-Table -AutoSize -Wrap
    Write-Host ''

# AD Replication Links
    Write-Host 'AD Replication Links:' -ForegroundColor Cyan
    Get-ADReplicationSiteLink -Filter * -Properties ReplInterval,Options -Server $dServer `
     | Format-Table Name,Cost,ReplInterval,Options,SitesIncluded -AutoSize -Wrap
    Write-Host ''

# AD Trusts
    Write-Host 'Active Directory Trusts:' -ForegroundColor Cyan
    Get-ADTrust -Filter * -Properties SelectiveAuthentication -Server $dServer `
     | Format-Table Name,Direction,ForestTransitive,IntraForest,SelectiveAuthentication -AutoSize -Wrap
    Write-Host ''

# AD Users/Groups

    # Totals
    Write-Host 'User and Group Objects:' -ForegroundColor Cyan
    $users = Get-ADUser -Filter * -Properties name,lastlogondate,enabled -Server $dServer
    $uCount = ($users).count
    $uCountEnabled = ($users | Where-Object {$_.enabled}).count
    $gCount = (Get-ADGroup -Filter * -Server $dServer).count
    $gCountEmpty = (Get-ADGroup -Filter * -Server $dServer -Properties Members | ?{-not $_.members}).count
    [ordered]@{
        'Total User Objects:' = $uCount
        'Enabled User Objects:' = $uCountEnabled
        'Total Groups:' = $gCount
        'Empty Groups:' = $gCountEmpty
    } | Format-Table -HideTableHeaders -AutoSize
    Write-Host ''

    # Inactive Users
    Write-Host 'Inactive User Objects:' -ForegroundColor Cyan
    $30Days = ($date).AddDays(-30)
    $60Days = ($date).AddDays(-60)
    $90Days = ($date).AddDays(-90)
    $uCountI30 = ($users | Where-Object {$_.lastlogondate -lt $30Days -and $_.enabled}).count
    $uCountI60 = ($users | Where-Object {$_.lastlogondate -lt $60Days -and $_.enabled}).count
    $uCountI90 = ($users | Where-Object {$_.lastlogondate -lt $90Days -and $_.enabled}).count
    [ordered]@{
        'Users 30 Days Inactive:' = $uCountI30
        'Users 60 Days Inactive:' = $uCountI60
        'Users 90 Days Inactive:' = $uCountI90
    } | Format-Table -HideTableHeaders -AutoSize
    Write-Host ''

#AD Endpoints

    # Totals
    Write-Host 'Domain Endpoint Objects:' -ForegroundColor Cyan
    $computers = Get-ADComputer -Filter * -Properties name,operatingsystem,lastlogondate,passwordlastset -Server $dServer
    $cCount = ($computers).count
    $computersEnabled = ($computers | Where-Object {$_.enabled})
    $cCountEnabled = ($computersEnabled).count
    $cCountDisabled = ($computers | Where-Object {!$_.enabled}).count
    [ordered]@{
        'Total Computer Objects:' = $cCount
        'Enabled Computer Objects:' = $cCountEnabled
        'Disabled Computer Objects:' = $cCountDisabled
    } | Format-Table -HideTableHeaders -AutoSize
    Write-Host ''

    # Inactive Computers
    Write-Host 'Inactive Computer Objects:' -ForegroundColor Cyan
    $cCountI30 = ($computersEnabled | Where-Object {$_.lastlogondate -lt $30Days}).count
    $cCountI60 = ($computersEnabled | Where-Object {$_.lastlogondate -lt $60Days}).count
    $cCountI90 = ($computersEnabled | Where-Object {$_.lastlogondate -lt $90Days}).count
    $cCountP30 = ($computersEnabled | Where-Object {$_.passwordlastset -lt $30Days}).count
    $cCountP60 = ($computersEnabled | Where-Object {$_.passwordlastset -lt $60Days}).count
    $cCountP90 = ($computersEnabled | Where-Object {$_.passwordlastset -lt $90Days}).count
    [ordered]@{
        'Computers 30 Days Inactive' = $cCountI30
        'Computers 60 Days Inactive' = $cCountI60
        'Computers 90 Days Inactive' = $cCountI90
        'Computers 30 Days Since Password Set' = $cCountP30
        'Computers 60 Days Since Password Set' = $cCountP60
        'Computers 90 Days Since Password Set' = $cCountP90
    } | Format-Table -HideTableHeaders -AutoSize
    Write-Host ''

    # Operating Systems
    Write-Host 'Endpoint Operating System Counts:' -ForegroundColor Cyan
    $computerOSCount = [ordered]@{
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
        '' = ''
    }
    foreach ($c in $computers) {
        Switch -Regex ($c.OperatingSystem) {
            'XP' {$computerOSCount['Windows XP Computers:']++; break}
            'Windows 7' {$computerOSCount['Windows 7 Computers:']++; break}
            'Windows 8' {$computerOSCount['Windows 8 Computers:']++; break}
            'Windows 10' {$computerOSCount['Windows 10 Computers:']++; break}
            'Server 2000' {$computerOSCount['Windows 2000 Servers:']++; break}
            'Server 2003' {$computerOSCount['Windows 2003 Servers:']++; break}
            'Server 2008' {$computerOSCount['Windows 2008 Servers:']++; break}
            'Server 2012' {$computerOSCount['Windows 2012 Servers:']++; break}
            'Server 2016' {$computerOSCount['Windows 2016 Servers:']++; break}
            'Server 2019' {$computerOSCount['Windows 2019 Servers:']++; break}
            Default {$computerOSCount['Unknown - ' + $c.OperatingSystem + ':']++}
        }
    }
    $computerOSCount | Format-Table -HideTableHeaders -AutoSize
    Write-Host ''

# OUs with Blocked Inheritance
    Write-Host 'List of OUs with Blocked Inheritance:' -ForegroundColor Cyan
    Get-ADOrganizationalUnit -SearchBase $rDSE.defaultNamingContext -Filter * -Server $dServer `
     | Where-Object {(Get-GPInheritance $_.DistinguishedName).GpoInheritanceBlocked -eq 'Yes'} `
     | Sort-Object Name | Format-Table Name,DistinguishedName -AutoSize -Wrap
    Write-Host ''

# Empty OUs
    Write-Host 'List of Empty OUs:' -ForegroundColor Cyan
    Get-ADOrganizationalUnit -SearchBase $rDSE.defaultNamingContext -Filter * -Server $dServer `
     | ForEach-Object { If (!(Get-ADObject -Filter * -SearchBase $_ -SearchScope OneLevel -Server $dServer)){$_} } `
     | Sort-Object Name | Format-Table Name,DistinguishedName -AutoSize -Wrap
    Write-Host ''
    
# Unlinked GPOs
    $GPOs = Get-GPO -All -Domain $dDomain
    Write-Host ('Total Count of GPOs: ' + $GPOs.Count) -ForegroundColor Green
    Write-Host 'List of GPOs Not Linked:' -ForegroundColor Yellow
    $GPOs | ForEach-Object {
        If ($_ | Get-GPOReport -ReportType XML -Domain $dDomain | Select-String -NotMatch '<LinksTo>') {
            Write-Host $_.DisplayName
        }
    }
    Write-Host ''

# Duplicate SPNs
    $dSPN = setspn -x -f -p
    Write-Host 'Duplicate SPNs:' -ForegroundColor Green
    $dSPN

# End Script
    Stop-Transcript