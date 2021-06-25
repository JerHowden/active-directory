Function Export-ScopedUsersAndNestedGroups {

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
        [string]$RootFolder
    )

    $Date = [DateTime]::ParseExact($DateString, 'yyyy-MM-dd HH:mm:ss', $null)
    If(!$InactiveThreshold) { $InactiveThreshold = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge.Days }

    Write-Progress -Id 1 -Activity 'User Scoping' -Status " --- Initializating User Scoping" -PercentComplete 0
    New-Item -Path "$($RootFolder)" -Name "ScopeReport $($Date.ToString('yyyy-MM-dd HH-mm-ss'))" -ItemType "directory"
    $Directory = "$($RootFolder)\ScopeReport $($Date.ToString('yyyy-MM-dd HH-mm-ss'))"

    # Users
        $Users = Get-ADUser -Filter * -Properties distinguishedname,lastlogondate,enabled -Server $Server
        Write-Host "$($Users.count) Users" -ForegroundColor Cyan
        $InactiveUserDate = $Date.AddDays(-1 * $InactiveThreshold)

    # Green Users
        Write-Progress -Id 1 -Activity 'User Scoping' -Status " --- Scoping Green User Objects" -PercentComplete 10
        $GreenUsers = $Users | Where-Object {$_.enabled -and $_.lastlogondate -and $_.lastlogondate -gt $InactiveUserDate} | Select -ExpandProperty DistinguishedName
        Write-Host "$($GreenUsers.count) Green Users" -ForegroundColor Green
        $GreenUsers | Out-File -FilePath "$($Directory)\GreenUsers.txt"

    # Yellow Users
        Write-Progress -Id 1 -Activity 'User Scoping' -Status " --- Scoping Yellow User Objects" -PercentComplete 20
        $YellowUsers = $Users | Where-Object {$_.enabled -and $_.lastlogondate -and $_.lastlogondate -le $InactiveUserDate -and $_.lastlogondate -gt ($Date.AddDays(-365))} | Select -ExpandProperty DistinguishedName
        Write-Host "$($YellowUsers.count) Yellow Users" -ForegroundColor Yellow
        $YellowUsers | Out-File -FilePath "$($Directory)\YellowUsers.txt"

    # Red Users
        Write-Progress -Id 1 -Activity 'User Scoping' -Status " --- Scoping Red User Objects" -PercentComplete 30
        $RedUsers = $Users | Where-Object {(!$_.enabled) -or (!$_.lastlogondate) -or ($_.enabled -and $_.lastlogondate -le ($Date.AddDays(-365)))} | Select -ExpandProperty DistinguishedName
        Write-Host "$($RedUsers.count) Red Users" -ForegroundColor Red
        $RedUsers | Out-File -FilePath "$($Directory)\RedUsers.txt"

    # Groups
        $Groups = Get-ADGroup -Filter * | Select -ExpandProperty distinguishedname

    # Immediate Green Groups
        Write-Progress -Id 1 -Activity 'Green Groups' -Status " --- Getting Immediate Green Groups" -PercentComplete 40
        $StartTimeGreen = $(Get-Date)

        $IGreenGroups = [System.Collections.ArrayList]::new()
        for($i = 0; $i -lt $Groups.count; $i++) {
            $GroupUsers = Get-ADGroupMember -Identity $Groups[$i] | Where-Object {$_.objectclass -eq "user"}
            $FoundGreenUser = $False
            foreach($GroupUser in $GroupUsers) {
                if($GreenUsers -contains $GroupUser) {
                    $FoundGreenUser = $True
                    break
                }
            }
            if($FoundGreenUser) {
                $IGreenGroups.Add($Groups[$i])
            }
            Write-Progress -Id 10 -ParentId 1 -Activity 'Immediate Groups' -Status " --- Scoped $($IGreenGroups.count) Immediate Green Groups" -PercentComplete (100 * $i / $Groups.count)
        }

        $EndTimeGreen = $(Get-Date)
        Write-Host "Found $($IGreenGroups.count) Immediate Green Groups, $(($EndTimeGreen - $StartTimeGreen).Minutes) Minutes Elapsed" -ForegroundColor Green
        $null = $GreenUsers
        [system.gc]::Collect()

    # Nested Green Groups
        $StartTimeGreen = $(Get-Date)

        $MasterGreenGroups = [System.Collections.ArrayList]::new() # Total Green Groups List
        $MasterGreenGroups.AddRange($IGreenGroups)
        $ChildGreenGroups = [System.Collections.ArrayList]::new() # Previous Nesting Level Green Groups List
        $ChildGreenGroups.AddRange($IGreenGroups)
        $NewGreenGroups = [System.Collections.ArrayList]::new() # New Nesting Level Green Groups List
        $ParentGroups = [System.Collections.ArrayList]::new()
        $ParentGroups.AddRange($Groups)
        $NestedStep = 0
        while($True) {
            Write-Progress -Id 1 -Activity 'Green Groups' -Status " --- Scoping Green Groups on Level $($NestedStep)" -PercentComplete 50
            $null = $NewParentGroups
            $NewParentGroups = [System.Collections.ArrayList]::new()
            $NewParentGroups.AddRange($ParentGroups)
            for($i = 0; $i -lt $ParentGroups.count; $i++) {
                $ParentGroupMembers = Get-ADGroupMember -Identity $ParentGroups[$i] | Where-Object {$_.objectclass -eq "group"} | Select -ExpandProperty distinguishedname
                $FoundGreenGroup = $False
                foreach($GroupMember in $ParentGroupMembers) {
                    if($ChildGreenGroups -contains $GroupMember) {
                        $FoundGreenGroup = $True
                        break
                    }
                }
                if($FoundGreenGroup) {
                    $NewGreenGroups.Add($ParentGroups[$i])
                    $NewParentGroups.Remove($ParentGroups[$i])
                }
                Write-Progress -Id 10 -ParentId 1 -Activity 'Green Groups' -Status " --- Scoped $($NewGreenGroups.count) Green Groups" -PercentComplete (100 * $i / $ParentGroups.count)
            }
            if($ParentGroups.count -eq $NewParentGroups.count) {
                Write-Host "Found $($MasterGreenGroups.count) Green Groups" -ForegroundColor Green
                break
            }

            $null = $ChildGreenGroups
            $ChildGreenGroups = [System.Collections.ArrayList]::new()
            $ChildGreenGroups.AddRange($NewGreenGroups)
            $MasterGreenGroups.AddRange($NewGreenGroups)

            $null = $ParentGroups
            $ParentGroups = [System.Collections.ArrayList]::new()
            $ParentGroups.AddRange($NewParentGroups)

            $NestedStep++
        }
        $MasterGreenGroups | Out-File -FilePath "$($Directory)\GroupsWithGreen.txt"

        $EndTimeGreen = $(Get-Date)
        Write-Host "Wrote Green Groups to File, $(($EndTimeGreen - $StartTimeGreen).Minutes) Minutes Elapsed" -ForegroundColor Green
        $null = $IGreenGroups
        $null = $MasterGreenGroups
        $null = $ChildGreenGroups
        $null = $NewGreenGroups
        $null = $ParentGroups
        [system.gc]::Collect()


    # Immediate Yellow Groups
        Write-Progress -Id 1 -Activity 'Yellow Groups' -Status " --- Getting Immediate Yellow Groups" -PercentComplete 60
        $StartTimeYellow = $(Get-Date)

        $IYellowGroups = [System.Collections.ArrayList]::new()
        for($i = 0; $i -lt $Groups.count; $i++) {
            $GroupUsers = Get-ADGroupMember -Identity $Groups[$i] | Where-Object {$_.objectclass -eq "user"}
            $FoundYellowUser = $False
            foreach($GroupUser in $GroupUsers) {
                if($YellowUsers -contains $GroupUser) {
                    $FoundYellowUser = $True
                    break
                }
            }
            if($FoundYellowUser) {
                $IYellowGroups.Add($Groups[$i])
            }
            Write-Progress -Id 10 -ParentId 1 -Activity 'Immediate Groups' -Status " --- Scoped $($IYellowGroups.count) Immediate Yellow Groups" -PercentComplete (100 * $i / $Groups.count)
        }

        $EndTimeYellow = $(Get-Date)
        Write-Host "Found $($IYellowGroups.count) Immediate Yellow Groups, $(($EndTimeYellow - $StartTimeYellow).Minutes) Minutes Elapsed" -ForegroundColor Yellow
        $null = $YellowUsers
        [system.gc]::Collect()

    # Nested Yellow Groups
        $StartTimeYellow = $(Get-Date)

        $MasterYellowGroups = [System.Collections.ArrayList]::new() # Total Yellow Groups List
        $MasterYellowGroups.AddRange($IYellowGroups)
        $ChildYellowGroups = [System.Collections.ArrayList]::new() # Previous Nesting Level Yellow Groups List
        $ChildYellowGroups.AddRange($IYellowGroups)
        $NewYellowGroups = [System.Collections.ArrayList]::new() # New Nesting Level Yellow Groups List
        $ParentGroups = [System.Collections.ArrayList]::new()
        $ParentGroups.AddRange($Groups)
        $NestedStep = 0
        while($True) {
            Write-Progress -Id 1 -Activity 'Yellow Groups' -Status " --- Scoping Yellow Groups on Level $($NestedStep)" -PercentComplete 70
            $null = $NewParentGroups
            $NewParentGroups = [System.Collections.ArrayList]::new()
            $NewParentGroups.AddRange($ParentGroups)
            for($i = 0; $i -lt $ParentGroups.count; $i++) {
                $ParentGroupMembers = Get-ADGroupMember -Identity $ParentGroups[$i] | Where-Object {$_.objectclass -eq "group"} | Select -ExpandProperty distinguishedname
                $FoundYellowGroup = $False
                foreach($GroupMember in $ParentGroupMembers) {
                    if($ChildYellowGroups -contains $GroupMember) {
                        $FoundYellowGroup = $True
                        break
                    }
                }
                if($FoundYellowGroup) {
                    $NewYellowGroups.Add($ParentGroups[$i])
                    $NewParentGroups.Remove($ParentGroups[$i])
                }
                Write-Progress -Id 10 -ParentId 1 -Activity 'Yellow Groups' -Status " --- Scoped $($NewYellowGroups.count) Yellow Groups" -PercentComplete (100 * $i / $ParentGroups.count)
            }
            if($ParentGroups.count -eq $NewParentGroups.count) {
                Write-Host "Found $($MasterYellowGroups.count) Yellow Groups" -ForegroundColor Yellow
                break
            }

            $null = $ChildYellowGroups
            $ChildYellowGroups = [System.Collections.ArrayList]::new()
            $ChildYellowGroups.AddRange($NewYellowGroups)
            $MasterYellowGroups.AddRange($NewYellowGroups)

            $null = $ParentGroups
            $ParentGroups = [System.Collections.ArrayList]::new()
            $ParentGroups.AddRange($NewParentGroups)

            $NestedStep++
        }
        $MasterYellowGroups | Out-File -FilePath "$($Directory)\GroupsWithYellow.txt"

        $EndTimeYellow = $(Get-Date)
        Write-Host "Wrote Yellow Groups to File, $(($EndTimeYellow - $StartTimeYellow).Minutes) Minutes Elapsed" -ForegroundColor Yellow
        $null = $IYellowGroups
        $null = $MasterYellowGroups
        $null = $ChildYellowGroups
        $null = $NewYellowGroups
        $null = $ParentGroups
        [system.gc]::Collect()


    # Immediate Red Groups
        Write-Progress -Id 1 -Activity 'Red Groups' -Status " --- Getting Immediate Red Groups" -PercentComplete 80
        $StartTimeRed = $(Get-Date)

        $IRedGroups = [System.Collections.ArrayList]::new()
        for($i = 0; $i -lt $Groups.count; $i++) {
            $GroupUsers = Get-ADGroupMember -Identity $Groups[$i] | Where-Object {$_.objectclass -eq "user"}
            $FoundRedUser = $False
            foreach($GroupUser in $GroupUsers) {
                if($RedUsers -contains $GroupUser) {
                    $FoundRedUser = $True
                    break
                }
            }
            if($FoundRedUser) {
                $IRedGroups.Add($Groups[$i])
            }
            Write-Progress -Id 10 -ParentId 1 -Activity 'Immediate Groups' -Status " --- Scoped $($IRedGroups.count) Immediate Red Groups" -PercentComplete (100 * $i / $Groups.count)
        }

        $EndTimeRed = $(Get-Date)
        Write-Host "Found $($IRedGroups.count) Immediate Red Groups, $(($EndTimeRed - $StartTimeRed).Minutes) Minutes Elapsed" -ForegroundColor Red
        $null = $RedUsers
        [system.gc]::Collect()

    # Nested Red Groups
        $StartTimeRed = $(Get-Date)

        $MasterRedGroups = [System.Collections.ArrayList]::new() # Total Red Groups List
        $MasterRedGroups.AddRange($IRedGroups)
        $ChildRedGroups = [System.Collections.ArrayList]::new() # Previous Nesting Level Red Groups List
        $ChildRedGroups.AddRange($IRedGroups)
        $NewRedGroups = [System.Collections.ArrayList]::new() # New Nesting Level Red Groups List
        $ParentGroups = [System.Collections.ArrayList]::new()
        $ParentGroups.AddRange($Groups)
        $NestedStep = 0
        while($True) {
            Write-Progress -Id 1 -Activity 'Red Groups' -Status " --- Scoping Red Groups on Level $($NestedStep)" -PercentComplete 90
            $null = $NewParentGroups
            $NewParentGroups = [System.Collections.ArrayList]::new()
            $NewParentGroups.AddRange($ParentGroups)
            for($i = 0; $i -lt $ParentGroups.count; $i++) {
                $ParentGroupMembers = Get-ADGroupMember -Identity $ParentGroups[$i] | Where-Object {$_.objectclass -eq "group"} | Select -ExpandProperty distinguishedname
                $FoundRedGroup = $False
                foreach($GroupMember in $ParentGroupMembers) {
                    if($ChildRedGroups -contains $GroupMember) {
                        $FoundRedGroup = $True
                        break
                    }
                }
                if($FoundRedGroup) {
                    $NewRedGroups.Add($ParentGroups[$i])
                    $NewParentGroups.Remove($ParentGroups[$i])
                }
                Write-Progress -Id 10 -ParentId 1 -Activity 'Red Groups' -Status " --- Scoped $($NewRedGroups.count) Red Groups" -PercentComplete (100 * $i / $ParentGroups.count)
            }
            if($ParentGroups.count -eq $NewParentGroups.count) {
                Write-Host "Found $($MasterRedGroups.count) Red Groups" -ForegroundColor Red
                break
            }

            $null = $ChildRedGroups
            $ChildRedGroups = [System.Collections.ArrayList]::new()
            $ChildRedGroups.AddRange($NewRedGroups)
            $MasterRedGroups.AddRange($NewRedGroups)

            $null = $ParentGroups
            $ParentGroups = [System.Collections.ArrayList]::new()
            $ParentGroups.AddRange($NewParentGroups)

            $NestedStep++
        }
        $MasterRedGroups | Out-File -FilePath "$($Directory)\GroupsWithRed.txt"

        $EndTimeRed = $(Get-Date)
        Write-Host "Wrote Red Groups to File, $(($EndTimeRed - $StartTimeRed).Minutes) Minutes Elapsed" -ForegroundColor Red
        $null = $IRedGroups
        $null = $MasterRedGroups
        $null = $ChildRedGroups
        $null = $NewRedGroups
        $null = $ParentGroups
        [system.gc]::Collect()

    Write-Progress -Id 1 -Activity 'Scoping Report' -Status '--- Completed' -PercentComplete 100
    Write-Host "Scope Report Completed Successfully at $($Directory)"
    Write-Host "The files took $(($(Get-Date) - $Date).Minutes) minutes to generate."

}

Function Export-TypedGroups {

    [CmdletBinding()]
    Param(
        [Parameter(Mandatory,
            HelpMessage='$PSScriptRoot')]
        [string]$RootFolder
    )

    $Directory = Read-Host -Prompt "Please Enter the Directory with the deduplicated group files. They should be in the format: GroupsWithGreen.txt"

    $Directory = "$($RootFolder)\$($Directory)"
    $GroupsWithGreen = Get-Content -Path "$($Directory)\GroupsWithGreen.txt"
    $GroupsWithYellow = Get-Content -Path "$($Directory)\GroupsWithYellow.txt"
    $GroupsWithRed = Get-Content -Path "$($Directory)\GroupsWithRed.txt"

    # Finish User Scoping
    Write-Progress -Id 1 -Activity 'User and Group Scoping' -Status " --- Scoped User Objects!" -PercentComplete 0
    $GroupsCount = $GroupsWithGreen.count + $GroupsWithYellow.count + $GroupsWithRed.count #(includes duplicates)
    Write-Host "$($GroupsCount) Groups, $($GroupsWithGreen.count) Green Groups, $($GroupsWithYellow.count) Yellow Groups, $($GroupsWithRed.count) Red Groups"

    # Categorizing Groups by Type
        $GroupsWithGreenTypes = New-Object int[] $GroupsWithGreen.count
        $GroupsWithYellowTypes = New-Object int[] $GroupsWithYellow.count
        $GroupsWithRedTypes = New-Object int[] $GroupsWithRed.count

        # Green Groups
        Write-Progress -Id 1 -Activity 'User-Group Scoping' -Status " --- " -PercentComplete 25
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
            Write-Progress -Id 10 -ParentId 1 -Activity 'Green User-Group Scoping' -Status " --- Added User-Group Type $($GroupsWithGreenTypes[$i])" -PercentComplete (100 * $i / $GroupsWithGreen.count)
        }
        $GroupsWithGreenObjects = For($i = 0; $i -lt $GroupsWithGreen.count; $i++) {
            [PSCustomObject]@{
                'DN' = $GroupsWithGreen[$i]
                'Type' = $GroupsWithGreenTypes[$i]
            }
        }
        $GroupsWithGreenObjects | Export-Csv -NoTypeInformation -Path "$($Directory)\GroupsWithGreen.csv"
        $null = $GroupsWithGreen
        $null = $GroupsWithGreenTypes
        $null = $GroupsWithGreenObjects
        [system.gc]::Collect()

        # Yellow Groups
        Write-Progress -Id 1 -Activity 'User-Group Scoping' -Status " --- " -PercentComplete 50
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
            Write-Progress -Id 10 -ParentId 1 -Activity 'Yellow User-Group Scoping' -Status " --- Added User-Group Type $($GroupsWithYellowTypes[$i])" -PercentComplete (100 * $i / $GroupsWithYellow.count)
        }
        $GroupsWithYellowObjects = For($i = 0; $i -lt $GroupsWithYellow.count; $i++) {
            [PSCustomObject]@{
                'DN' = $GroupsWithYellow[$i]
                'Type' = $GroupsWithYellowTypes[$i]
            }
        }
        $GroupsWithYellowObjects | Export-Csv -NoTypeInformation -Path "$($Directory)\GroupsWithYellow.csv"
        $null = $GroupsWithYellow
        $null = $GroupsWithYellowTypes
        $null = $GroupsWithYellowObjects
        [system.gc]::Collect()

        #Red Groups
        Write-Progress -Id 1 -Activity 'User-Group Scoping' -Status " --- " -PercentComplete 75
        For($i = 0; $i -lt $GroupsWithRed.count; $i++) {
            If(!$GroupsWithRedTypes[$i]) {
                $GroupsWithRedTypes[$i] = 3
            }
            Write-Progress -Id 10 -ParentId 1 -Activity 'Red User-Group Scoping' -Status " --- Added User-Group Type $($GroupsWithRedTypes[$i])" -PercentComplete (100 * $i / $GroupsWithRed.count)
        }
        $GroupsWithRedObjects = For($i = 0; $i -lt $GroupsWithRed.count; $i++) {
            [PSCustomObject]@{
                'DN' = $GroupsWithRed[$i]
                'Type' = $GroupsWithRedTypes[$i]
            }
        }
        $GroupsWithRedObjects | Export-Csv -NoTypeInformation -Path "$($Directory)\GroupsWithRed.csv"
        $null = $GroupsWithRed
        $null = $GroupsWithRedTypes
        $null = $GroupsWithRedObjects
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

        Write-Host "--- SCOPE REPORT ---"
        Write-Host
        $Step = Read-Host -Prompt "What step of the scope report should this perform?"

        Switch($Step) {
            "1" {
                Export-ScopedUsersAndNestedGroups -Server $Server -DateString ($Date).ToString('yyyy-MM-dd HH:mm:ss') -InactiveThreshold 90 -RootFolder $PSScriptRoot
                Break
            }
            "2" {
                Export-TypedGroups -RootFolder $PSScriptRoot
                Break
            }
            Default {
                Write-Host "Exiting..."
                Return
            }
        }
        


    }

    End {}
}

# Test
Invoke-ADScopeReport -Domain 'prod.ncidemo.com' -DomainController 'DC01'

# Prod
# Invoke-ADScopeReport -Domain '' -DomainController ''
