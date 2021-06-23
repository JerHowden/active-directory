# AD Users/Groups
Function Export-ScopedUsersAndGroups {

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

    Write-Progress -Id 1 -Activity '(1/8) User Scoping' -Status " --- Initializating User Scoping" -PercentComplete 0
    New-Item -Path "$($Directory)" -Name "ScopeReport $($Date.ToString('yyyy-MM-dd HH-mm-ss'))" -ItemType "directory"

    # Users
        $Users = Get-ADUser -Filter * -Properties distinguishedname,lastlogondate,enabled,admincount -Server $Server
        Write-Host "$($Users.count) Users" -ForegroundColor Cyan
        $InactiveUserDate = $Date.AddDays(-1 * $InactiveThreshold)

    # Green Users and Groups
        Write-Progress -Id 1 -Activity '(2/8) Green User Scoping' -Status " --- Scoping Green User Objects" -PercentComplete (100 * 1/8)
        $GreenUsers = $Users | Where-Object {$_.enabled -and $_.lastlogondate -and $_.lastlogondate -gt $InactiveUserDate} | Select -ExpandProperty DistinguishedName
        Write-Host "$($GreenUsers.count) Green Users" -ForegroundColor Green
        $GreenUsers | Out-File -FilePath "$($Directory)\ScopeReport $($Date.ToString('yyyy-MM-dd HH-mm-ss'))\GreenUsers.txt"
        
        $GroupsWithGreen = @()
        for($i = 0; $i -lt $GreenUsers.count; $i++) {
            $TempGroups = Get-WinADGroupMemberOf $GreenUsers[$i] | Select -ExpandProperty DistinguishedName
            $pattern = "^({0})$" -f ($GroupsWithGreen -join '|')
            foreach($DN in $TempGroups) {
                if($DN -notmatch $pattern) {
                    $GroupsWithGreen += $DN
                }
            }
            Write-Progress -Id 10 -ParentId 1 -Activity '(2/8) Green User-Group Scoping' -Status " --- Getting Groups with Green Users" -PercentComplete (100 * $i / $GreenUsers.count)
            [system.gc]::Collect()
        }

        Write-Host "$($GroupsWithGreen.count) Green Groups" -ForegroundColor Green
        $GreenUsers | Out-Null
        [system.gc]::Collect()

    # Yellow Users and Groups
        Write-Progress -Id 1 -Activity '(3/8) Yellow User Scoping' -Status " --- Scoping Yellow User Objects" -PercentComplete (100 * 2/8)
        $YellowUsers = $Users | Where-Object {$_.enabled -and $_.lastlogondate -and $_.lastlogondate -le $InactiveUserDate -and $_.lastlogondate -gt ($Date.AddDays(-365))} | Select -ExpandProperty DistinguishedName
        Write-Host "$($YellowUsers.count) Yellow Users" -ForegroundColor Yellow
        $YellowUsers | Out-File -FilePath "$($Directory)\ScopeReport $($Date.ToString('yyyy-MM-dd HH-mm-ss'))\YellowUsers.txt"

        $GroupsWithYellow = @()
        for($i = 0; $i -lt $YellowUsers.count; $i++) {
            $TempGroups = Get-WinADGroupMemberOf $YellowUsers[$i] | Select -ExpandProperty DistinguishedName
            $pattern = "^({0})$" -f ($GroupsWithYellow -join '|')
            foreach($DN in $TempGroups) {
                if($DN -notmatch $pattern) {
                    $GroupsWithYellow += $DN
                }
            }
            Write-Progress -Id 10 -ParentId 1 -Activity '(3/8) Yellow User-Group Scoping' -Status " --- Getting Groups with Yellow Users" -PercentComplete (100 * $i / $YellowUsers.count)
            [system.gc]::Collect()
        }
        
        Write-Host "$($GroupsWithYellow.count) Yellow Groups" -ForegroundColor Yellow
        $YellowUsers | Out-Null
        [system.gc]::Collect()

    # Red Users and Groups
        Write-Progress -Id 1 -Activity '(4/8) Red User Scoping' -Status " --- Scoping Red User Objects" -PercentComplete (100 * 3/8)
        $RedUsers = $Users | Where-Object {(!$_.enabled) -or (!$_.lastlogondate) -or ($_.enabled -and $_.lastlogondate -le ($Date.AddDays(-365)))} | Select -ExpandProperty DistinguishedName
        Write-Host "$($RedUsers.count) Red Users" -ForegroundColor Red
        $RedUsers | Out-File -FilePath "$($Directory)\ScopeReport $($Date.ToString('yyyy-MM-dd HH-mm-ss'))\RedUsers.txt"

        $GroupsWithRed = @()
        for($i = 0; $i -lt $RedUsers.count; $i++) {
            $TempGroups = Get-WinADGroupMemberOf $RedUsers[$i] | Select -ExpandProperty DistinguishedName
            $pattern = "^({0})$" -f ($GroupsWithRed -join '|')
            foreach($DN in $TempGroups) {
                if($DN -notmatch $pattern) {
                    $GroupsWithRed += $DN
                }
            }
            Write-Progress -Id 10 -ParentId 1 -Activity '(4/8) Red User-Group Scoping' -Status " --- Getting Groups with Red Users" -PercentComplete (100 * $i / $RedUsers.count)
            [system.gc]::Collect()
        }

        Write-Host "$($GroupsWithRed.count) Red Groups" -ForegroundColor Red
        $RedUsers | Out-Null
        [system.gc]::Collect()

    # Finish User Scoping
        Write-Progress -Id 1 -Activity '(5/8) User and Group Scoping' -Status " --- Scoped User Objects!" -PercentComplete (100 * 4/8)
        $GroupsCount = $GroupsWithGreen.count + $GroupsWithYellow.count + $GroupsWithRed.count #(includes duplicates)
        Write-Host "$($GroupsCount) Groups, $($GroupsWithGreen.count) Green Groups, $($GroupsWithYellow.count) Yellow Groups, $($GroupsWithRed.count) Red Groups"

    # Categorizing Groups by Type
        $GroupsWithGreenTypes = New-Object int[] $GroupsWithGreen.count
        $GroupsWithYellowTypes = New-Object int[] $GroupsWithYellow.count
        $GroupsWithRedTypes = New-Object int[] $GroupsWithRed.count

        # Green Groups
        Write-Progress -Id 1 -Activity '(6/8) User-Group Scoping' -Status " --- " -PercentComplete (100 * 5/8)
        For($i = 0; $i -lt $GroupsWithGreen.count; $i++) {
            $yellowIndex = $null
            For($j = 0; $j -lt $GroupsWithYellow.count; $j++) {
                If($GroupsWithGreen[$i] -match $GroupsWithYellow[$j]) {
                    $GroupsWithGreenTypes[$i] = 4
                    $GroupsWithYellowTypes[$j] = 4
                    $yellowIndex = $j
                    Break
                }
            }
            For($j = 0; $j -lt $GroupsWithRed.count; $j++) {
                If($GroupsWithGreen[$i] -match $GroupsWithRed[$j]) {
                    If($GroupsWithGreenTypes[$i] -eq 4) {
                        $GroupsWithGreenTypes[$i] = 7
                        $GroupsWithYellowTypes[$yellowIndex] = 7
                        $GroupsWithRedTypes[$j] = 7
                    } Else {
                        $GroupsWithGreenTypes[$i] = 6
                        $GroupsWithRedTypes[$j] = 6
                    }
                    Break
                }
            }
            If(!$GroupsWithGreenTypes[$i]) {
                $GroupsWithGreenTypes[$i] = 1
            }
            Write-Progress -Id 10 -ParentId 1 -Activity '(6/8) Green User-Group Scoping' -Status " --- Added User-Group Type $($GroupsWithGreenTypes[$i])" -PercentComplete (100 * $i / $GroupsWithGreen.count)
        }
        $GroupsWithGreenObjects = For($i = 0; $i -lt $GroupsWithGreen.count; $i++) {
            [PSCustomObject]@{
                'DN' = $GroupsWithGreen[$i]
                'Type' = $GroupsWithGreenTypes[$i]
            }
        }
        $GroupsWithGreenObjects | Export-Csv -NoTypeInformation -Path "$($Directory)\ScopeReport $($Date.ToString('yyyy-MM-dd HH-mm-ss'))\GroupsWithGreen.csv"
        $GroupsWithGreen | Out-Null
        $GroupsWithGreenTypes | Out-Null
        $GroupsWithGreenObjects | Out-Null
        [system.gc]::Collect()

        # Yellow Groups
        Write-Progress -Id 1 -Activity '(7/8) User-Group Scoping' -Status " --- " -PercentComplete (100 * 6/8)
        For($i = 0; $i -lt $GroupsWithYellow.count; $i++) {
            For($j = 0; $j -lt $GroupsWithRed.count; $j++) {
                If($GroupsWithYellow[$i] -match $GroupsWithRed[$j]) {
                    If($GroupsWithYellowTypes[$i] -ne 7) {
                        $GroupsWithYellowTypes[$i] = 5
                        $GroupsWithRedTypes[$j] = 5
                    }
                    Break
                }
            }
            If(!$GroupsWithYellowTypes[$i]) {
                $GroupsWithYellowTypes[$i] = 2
            }
            Write-Progress -Id 10 -ParentId 1 -Activity '(7/8) Yellow User-Group Scoping' -Status " --- Added User-Group Type $($GroupsWithYellowTypes[$i])" -PercentComplete (100 * $i / $GroupsWithYellow.count)
        }
        $GroupsWithYellowObjects = For($i = 0; $i -lt $GroupsWithYellow.count; $i++) {
            [PSCustomObject]@{
                'DN' = $GroupsWithYellow[$i]
                'Type' = $GroupsWithYellowTypes[$i]
            }
        }
        $GroupsWithYellowObjects | Export-Csv -NoTypeInformation -Path "$($Directory)\ScopeReport $($Date.ToString('yyyy-MM-dd HH-mm-ss'))\GroupsWithYellow.csv"
        $GroupsWithYellow | Out-Null
        $GroupsWithYellowTypes | Out-Null
        $GroupsWithYellowObjects | Out-Null
        [system.gc]::Collect()

        #Red Groups
        Write-Progress -Id 1 -Activity '(8/8) User-Group Scoping' -Status " --- " -PercentComplete (100 * 7/8)
        For($i = 0; $i -lt $GroupsWithRed.count; $i++) {
            If(!$GroupsWithRedTypes[$i]) {
                $GroupsWithRedTypes[$i] = 3
            }
            Write-Progress -Id 10 -ParentId 1 -Activity '(8/8) Red User-Group Scoping' -Status " --- Added User-Group Type $($GroupsWithRedTypes[$i])" -PercentComplete (100 * $i / $GroupsWithRed.count)
        }
        $GroupsWithRedObjects = For($i = 0; $i -lt $GroupsWithRed.count; $i++) {
            [PSCustomObject]@{
                'DN' = $GroupsWithRed[$i]
                'Type' = $GroupsWithRedTypes[$i]
            }
        }
        $GroupsWithRedObjects | Export-Csv -NoTypeInformation -Path "$($Directory)\ScopeReport $($Date.ToString('yyyy-MM-dd HH-mm-ss'))\GroupsWithRed.csv"
        $GroupsWithRed | Out-Null
        $GroupsWithRedTypes | Out-Null
        $GroupsWithRedObjects | Out-Null
        [system.gc]::Collect()

        Write-Progress -Id 1 -Activity 'Scope Report Complete' -PercentComplete 100
        Start-Sleep -Seconds 10

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

        Export-ScopedUsersAndGroups -Server $Server -DateString ($Date).ToString('yyyy-MM-dd HH:mm:ss') -InactiveThreshold 90 -Directory $PSScriptRoot


    }

    End {}
}

# Test
Invoke-ADScopeReport -Domain 'prod.ncidemo.com' -DomainController 'DC01'

# Prod
# Invoke-ADScopeReport -Domain '' -DomainController ''
