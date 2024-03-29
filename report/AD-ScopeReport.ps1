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
        $Groups = Get-ADGroup -Filter * -Properties members | Where-Object {$_.members.count} | Select -ExpandProperty distinguishedname | Where-Object {$_ -notlike "CN=Domain Users*"}

    # Immediate Green Groups
        Write-Progress -Id 1 -Activity 'Green Groups' -Status " --- Getting Immediate Green Groups" -PercentComplete 40
        $StartTimeGreen = $(Get-Date)

        $ManualCheckGreenGroups = [System.Collections.ArrayList]::new()
        $IGreenGroups = [System.Collections.ArrayList]::new()
        for($i = 0; $i -lt $Groups.count; $i++) {
            try {
                $GroupUsers = Get-ADGroupMember -Identity $Groups[$i] | Where-Object {$_.objectclass -eq "user"} | Select -ExpandProperty distinguishedname
            } catch {
                $GroupUsers = Get-ADGroup -Identity $Groups[$i] -Properties members | Select -ExpandProperty members | Where-Object {$_ -notlike "*CN=ForeignSecurityPrincipals*"}
                $ManualCheckGreenGroups.Add($Groups[$i])
            }
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
            $TotalSeconds = ($(Get-Date) - $StartTimeGreen).TotalSeconds
            Write-Progress -Id 10 -ParentId 1 -Activity 'Immediate Groups' -Status " --- Scoped $($IGreenGroups.count) Immediate Green Groups" -PercentComplete (100 * $i / $Groups.count) -SecondsRemaining (($TotalSeconds * ($Groups.count/($i+1))) - $TotalSeconds)
        }

        $EndTimeGreen = $(Get-Date)
        Write-Host "Found $($IGreenGroups.count) Immediate Green Groups, $(($EndTimeGreen - $StartTimeGreen).TotalMinutes) Minutes Elapsed" -ForegroundColor Green
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
        $NestedStep = 1
        while($IGreenGroups.count -gt 0) {
            Write-Progress -Id 1 -Activity 'Green Groups' -Status " --- Scoping Green Groups on Level $($NestedStep), $($MasterGreenGroups.count) Total Groups" -PercentComplete 50
            $null = $NewParentGroups
            $NewParentGroups = [System.Collections.ArrayList]::new()
            $NewParentGroups.AddRange($ParentGroups)
            for($i = 0; $i -lt $ParentGroups.count; $i++) {
                $ParentGroupMembers = $null
                try {
                    $ParentGroupMembers = Get-ADGroupMember -Identity $ParentGroups[$i] | Where-Object {$_.objectclass -eq "group"} | Select -ExpandProperty distinguishedname
                } catch {
                    $ParentGroupMembers = Get-ADGroup -Identity $ParentGroups[$i] -Properties members | Select -ExpandProperty members | Where-Object {$_ -notlike "*CN=ForeignSecurityPrincipals*"}
                    $ManualCheckGreenGroups.Add($ParentGroups[$i])
                }
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
                $TotalSeconds = ($(Get-Date) - $StartTimeGreen).TotalSeconds
                Write-Progress -Id 10 -ParentId 1 -Activity 'Green Groups' -Status " --- Scoped $($NewGreenGroups.count) Green Groups" -PercentComplete (100 * $i / $ParentGroups.count) -SecondsRemaining (($TotalSeconds * ($ParentGroups.count/($i+1))) - $TotalSeconds)
            }
            if($ParentGroups.count -eq $NewParentGroups.count) {
                Write-Host "Found $($MasterGreenGroups.count) Green Groups" -ForegroundColor Green
                break
            }

            $null = $ChildGreenGroups
            $ChildGreenGroups = [System.Collections.ArrayList]::new()
            $ChildGreenGroups.AddRange($NewGreenGroups)
            $MasterGreenGroups.AddRange($NewGreenGroups)

            $null = $NewGreenGroups
            $NewGreenGroups = [System.Collections.ArrayList]::new()

            $null = $ParentGroups
            $ParentGroups = [System.Collections.ArrayList]::new()
            $ParentGroups.AddRange($NewParentGroups)

            $NestedStep++
        }
        $MasterGreenGroups | Out-File -FilePath "$($Directory)\GroupsWithGreen.txt"
        $MissedGreenGroups = [System.Collections.ArrayList]::new()
        foreach($LargeGroup in $ManualCheckGreenGroups) {
            if(!($MasterGreenGroups -contains $LargeGroup)) {  $MissedGreenGroups.Add($LargeGroup)  }
        }
        if($MissedGreenGroups.count -gt 0) {  $MissedGreenGroups | Out-File -FilePath "$($Directory)\ManualCheckGroupsWithGreen.txt"  }

        $EndTimeGreen = $(Get-Date)
        Write-Host "Wrote Green Groups to File, $(($EndTimeGreen - $StartTimeGreen).TotalMinutes) Minutes Elapsed" -ForegroundColor Green
        $null = $IGreenGroups
        $null = $MasterGreenGroups
        $null = $ChildGreenGroups
        $null = $NewGreenGroups
        $null = $ParentGroups
        [system.gc]::Collect()


    # Immediate Yellow Groups
        Write-Progress -Id 1 -Activity 'Yellow Groups' -Status " --- Getting Immediate Yellow Groups" -PercentComplete 60
        $StartTimeYellow = $(Get-Date)

        $ManualCheckYellowGroups = [System.Collections.ArrayList]::new()
        $IYellowGroups = [System.Collections.ArrayList]::new()
        for($i = 0; $i -lt $Groups.count; $i++) {
            try {
                $GroupUsers = Get-ADGroupMember -Identity $Groups[$i] | Where-Object {$_.objectclass -eq "user"} | Select -ExpandProperty distinguishedname
            } catch {
                $GroupUsers = Get-ADGroup -Identity $Groups[$i] -Properties members | Select -ExpandProperty members | Where-Object {$_ -notlike "*CN=ForeignSecurityPrincipals*"}
                $ManualCheckYellowGroups.Add($Groups[$i])
            }
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
            $TotalSeconds = ($(Get-Date) - $StartTimeYellow).TotalSeconds
            Write-Progress -Id 10 -ParentId 1 -Activity 'Immediate Groups' -Status " --- Scoped $($IYellowGroups.count) Immediate Yellow Groups" -PercentComplete (100 * $i / $Groups.count) -SecondsRemaining (($TotalSeconds * ($Groups.count/($i+1))) - $TotalSeconds)
        }

        $EndTimeYellow = $(Get-Date)
        Write-Host "Found $($IYellowGroups.count) Immediate Yellow Groups, $(($EndTimeYellow - $StartTimeYellow).TotalMinutes) Minutes Elapsed" -ForegroundColor Yellow
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
        $NestedStep = 1
        while($IYellowGroups.count -gt 0) {
            Write-Progress -Id 1 -Activity 'Yellow Groups' -Status " --- Scoping Yellow Groups on Level $($NestedStep), $($MasterYellowGroups.count) Total Groups" -PercentComplete 70
            $null = $NewParentGroups
            $NewParentGroups = [System.Collections.ArrayList]::new()
            $NewParentGroups.AddRange($ParentGroups)
            for($i = 0; $i -lt $ParentGroups.count; $i++) {
                try {
                    $ParentGroupMembers = Get-ADGroupMember -Identity $ParentGroups[$i] | Where-Object {$_.objectclass -eq "group"} | Select -ExpandProperty distinguishedname
                } catch {
                    $ParentGroupMembers = Get-ADGroup -Identity $ParentGroups[$i] -Properties members | Select -ExpandProperty members | Where-Object {$_ -notlike "*CN=ForeignSecurityPrincipals*"}
                    $ManualCheckGreenGroups.Add($ParentGroups[$i])
                }
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
                $TotalSeconds = ($(Get-Date) - $StartTimeYellow).TotalSeconds
                Write-Progress -Id 10 -ParentId 1 -Activity 'Yellow Groups' -Status " --- Scoped $($NewYellowGroups.count) Yellow Groups" -PercentComplete (100 * $i / $ParentGroups.count) -SecondsRemaining (($TotalSeconds * ($ParentGroups.count/($i+1))) - $TotalSeconds)
            }
            if($ParentGroups.count -eq $NewParentGroups.count) {
                Write-Host "Found $($MasterYellowGroups.count) Yellow Groups" -ForegroundColor Yellow
                break
            }

            $null = $ChildYellowGroups
            $ChildYellowGroups = [System.Collections.ArrayList]::new()
            $ChildYellowGroups.AddRange($NewYellowGroups)
            $MasterYellowGroups.AddRange($NewYellowGroups)

            $null = $NewYellowGroups
            $NewYellowGroups = [System.Collections.ArrayList]::new()

            $null = $ParentGroups
            $ParentGroups = [System.Collections.ArrayList]::new()
            $ParentGroups.AddRange($NewParentGroups)

            $NestedStep++
        }
        $MasterYellowGroups | Out-File -FilePath "$($Directory)\GroupsWithYellow.txt"
        $MissedYellowGroups = [System.Collections.ArrayList]::new()
        foreach($LargeGroup in $ManualCheckYellowGroups) {
            if(!($MasterYellowGroups -contains $LargeGroup)) {  $MissedYellowGroups.Add($LargeGroup)  }
        }
        if($MissedYellowGroups.count -gt 0) {  $MissedYellowGroups | Out-File -FilePath "$($Directory)\ManualCheckGroupsWithYellow.txt"  }

        $EndTimeYellow = $(Get-Date)
        Write-Host "Wrote Yellow Groups to File, $(($EndTimeYellow - $StartTimeYellow).TotalMinutes) Minutes Elapsed" -ForegroundColor Yellow
        $null = $IYellowGroups
        $null = $MasterYellowGroups
        $null = $ChildYellowGroups
        $null = $NewYellowGroups
        $null = $ParentGroups
        [system.gc]::Collect()


    # Immediate Red Groups
        Write-Progress -Id 1 -Activity 'Red Groups' -Status " --- Getting Immediate Red Groups" -PercentComplete 80
        $StartTimeRed = $(Get-Date)

        $ManualCheckRedGroups = [System.Collections.ArrayList]::new()
        $IRedGroups = [System.Collections.ArrayList]::new()
        for($i = 0; $i -lt $Groups.count; $i++) {
            try {
                $GroupUsers = Get-ADGroupMember -Identity $Groups[$i] | Where-Object {$_.objectclass -eq "user"}  | Select -ExpandProperty distinguishedname
            } catch {
                $GroupUsers = Get-ADGroup -Identity $Groups[$i] -Properties members | Select -ExpandProperty members | Where-Object {$_ -notlike "*CN=ForeignSecurityPrincipals*"}
                $ManualCheckRedGroups.Add($Groups[$i])
            }
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
            $TotalSeconds = ($(Get-Date) - $StartTimeRed).TotalSeconds
            Write-Progress -Id 10 -ParentId 1 -Activity 'Immediate Groups' -Status " --- Scoped $($IRedGroups.count) Immediate Red Groups" -PercentComplete (100 * $i / $Groups.count) -SecondsRemaining (($TotalSeconds * ($Groups.count/($i+1))) - $TotalSeconds)
        }

        $EndTimeRed = $(Get-Date)
        Write-Host "Found $($IRedGroups.count) Immediate Red Groups, $(($EndTimeRed - $StartTimeRed).TotalMinutes) Minutes Elapsed" -ForegroundColor Red
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
        $NestedStep = 1
        while($IRedGroups.count -gt 0) {
            Write-Progress -Id 1 -Activity 'Red Groups' -Status " --- Scoping Red Groups on Level $($NestedStep), $($MasterRedGroups.count) Total Groups" -PercentComplete 90
            $null = $NewParentGroups
            $NewParentGroups = [System.Collections.ArrayList]::new()
            $NewParentGroups.AddRange($ParentGroups)
            for($i = 0; $i -lt $ParentGroups.count; $i++) {
                try {
                    $ParentGroupMembers = Get-ADGroupMember -Identity $ParentGroups[$i] | Where-Object {$_.objectclass -eq "group"} | Select -ExpandProperty distinguishedname
                } catch {
                    $ParentGroupMembers = Get-ADGroup -Identity $ParentGroups[$i] -Properties members | Select -ExpandProperty members | Where-Object {$_ -notlike "*CN=ForeignSecurityPrincipals*"}
                    $ManualCheckRedGroups.Add($ParentGroups[$i])
                }
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
                $TotalSeconds = ($(Get-Date) - $StartTimeRed).TotalSeconds
                Write-Progress -Id 10 -ParentId 1 -Activity 'Red Groups' -Status " --- Scoped $($NewRedGroups.count) Red Groups" -PercentComplete (100 * $i / $ParentGroups.count) -SecondsRemaining (($TotalSeconds * ($ParentGroups.count/($i+1))) - $TotalSeconds)
            }
            if($ParentGroups.count -eq $NewParentGroups.count) {
                Write-Host "Found $($MasterRedGroups.count) Red Groups" -ForegroundColor Red
                break
            }

            $null = $ChildRedGroups
            $ChildRedGroups = [System.Collections.ArrayList]::new()
            $ChildRedGroups.AddRange($NewRedGroups)
            $MasterRedGroups.AddRange($NewRedGroups)

            $null = $NewRedGroups
            $NewRedGroups = [System.Collections.ArrayList]::new()

            $null = $ParentGroups
            $ParentGroups = [System.Collections.ArrayList]::new()
            $ParentGroups.AddRange($NewParentGroups)

            $NestedStep++
        }
        $MasterRedGroups | Out-File -FilePath "$($Directory)\GroupsWithRed.txt"
        $MissedRedGroups = [System.Collections.ArrayList]::new()
        foreach($LargeGroup in $ManualCheckRedGroups) {
            if(!($MasterRedGroups -contains $LargeGroup)) {  $MissedRedGroups.Add($LargeGroup)  }
        }
        if($MissedRedGroups.count -gt 0) {  $MissedRedGroups | Out-File -FilePath "$($Directory)\ManualCheckGroupsWithRed.txt"  }

        $EndTimeRed = $(Get-Date)
        Write-Host "Wrote Red Groups to File, $(($EndTimeRed - $StartTimeRed).TotalMinutes) Minutes Elapsed" -ForegroundColor Red
        $null = $IRedGroups
        $null = $MasterRedGroups
        $null = $ChildRedGroups
        $null = $NewRedGroups
        $null = $ParentGroups
        [system.gc]::Collect()

    Write-Progress -Id 1 -Activity 'Scoping Report' -Status '--- Completed' -PercentComplete 100
    Write-Host "Scope Report Completed Successfully at $($Directory)"
    Write-Host "The files took $(($(Get-Date) - $Date).TotalHours) hours to generate."

}

Function Export-ScopedComputersAndNestedGroups {

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
            HelpMessage='Cutoff in days for inactive computers. (90), (180), (360)')]
        [ValidateScript({ ($_.count -gt 0) -and ($_.count -le 12) })]
        [int]$InactiveThreshold,

        [Parameter(Mandatory,
            HelpMessage='Folder to send the export files to.')]
        [string]$RootFolder
    )

    $Date = [DateTime]::ParseExact($DateString, 'yyyy-MM-dd HH:mm:ss', $null)
    If(!$InactiveThreshold) { $InactiveThreshold = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge.Days }

    Write-Progress -Id 1 -Activity 'Computer Scoping' -Status " --- Initializating Computer Scoping" -PercentComplete 0
    New-Item -Path "$($RootFolder)" -Name "ScopeReport $($Date.ToString('yyyy-MM-dd HH-mm-ss'))" -ItemType "directory"
    $Directory = "$($RootFolder)\ScopeReport $($Date.ToString('yyyy-MM-dd HH-mm-ss'))"

    # Computers
        $Computers = Get-ADComputer -Filter * -Properties distinguishedname,lastlogondate,enabled -Server $Server
        Write-Host "$($Computers.count) Computers" -ForegroundColor Cyan
        $InactiveComputerDate = $Date.AddDays(-1 * $InactiveThreshold)

    # Green Computers
        Write-Progress -Id 1 -Activity 'Computer Scoping' -Status " --- Scoping Green Computer Objects" -PercentComplete 10
        $GreenComputers = $Computers | Where-Object {$_.enabled -and $_.lastlogondate -and $_.lastlogondate -gt $InactiveComputerDate} | Select -ExpandProperty DistinguishedName
        Write-Host "$($GreenComputers.count) Green Computers" -ForegroundColor Green
        $GreenComputers | Out-File -FilePath "$($Directory)\GreenComputers.txt"

    # Yellow Computers
        Write-Progress -Id 1 -Activity 'Computer Scoping' -Status " --- Scoping Yellow Computer Objects" -PercentComplete 20
        $YellowComputers = $Computers | Where-Object {$_.enabled -and $_.lastlogondate -and $_.lastlogondate -le $InactiveComputerDate -and $_.lastlogondate -gt ($Date.AddDays(-365))} | Select -ExpandProperty DistinguishedName
        Write-Host "$($YellowComputers.count) Yellow Computers" -ForegroundColor Yellow
        $YellowComputers | Out-File -FilePath "$($Directory)\YellowComputers.txt"

    # Red Computers
        Write-Progress -Id 1 -Activity 'Computer Scoping' -Status " --- Scoping Red Computer Objects" -PercentComplete 30
        $RedComputers = $Computers | Where-Object {(!$_.enabled) -or (!$_.lastlogondate) -or ($_.enabled -and $_.lastlogondate -le ($Date.AddDays(-365)))} | Select -ExpandProperty DistinguishedName
        Write-Host "$($RedComputers.count) Red Computers" -ForegroundColor Red
        $RedComputers | Out-File -FilePath "$($Directory)\RedComputers.txt"

    # Groups
        $Groups = Get-ADGroup -Filter * -Properties members | Where-Object {$_.members.count} | Select -ExpandProperty distinguishedname | Where-Object {$_ -notlike "CN=Domain Computers*"}

    # Immediate Green Groups
        Write-Progress -Id 1 -Activity 'Green Groups' -Status " --- Getting Immediate Green Groups" -PercentComplete 40
        $StartTimeGreen = $(Get-Date)

        $ManualCheckGreenGroups = [System.Collections.ArrayList]::new()
        $IGreenGroups = [System.Collections.ArrayList]::new()
        for($i = 0; $i -lt $Groups.count; $i++) {
            try {
                $GroupComputers = Get-ADGroupMember -Identity $Groups[$i] | Where-Object {$_.objectclass -eq "computer"} | Select -ExpandProperty distinguishedname
            } catch {
                $GroupComputers = Get-ADGroup -Identity $Groups[$i] -Properties members | Select -ExpandProperty members | Where-Object {$_ -notlike "*CN=ForeignSecurityPrincipals*"}
                $ManualCheckGreenGroups.Add($Groups[$i])
            }
            $FoundGreenComputer = $False
            foreach($GroupComputer in $GroupComputers) {
                if($GreenComputers -contains $GroupComputer) {
                    $FoundGreenComputer = $True
                    break
                }
            }
            if($FoundGreenComputer) {
                $IGreenGroups.Add($Groups[$i])
            }
            $TotalSeconds = ($(Get-Date) - $StartTimeGreen).TotalSeconds
            Write-Progress -Id 10 -ParentId 1 -Activity 'Immediate Groups' -Status " --- Scoped $($IGreenGroups.count) Immediate Green Groups" -PercentComplete (100 * $i / $Groups.count) -SecondsRemaining (($TotalSeconds * ($Groups.count/($i+1))) - $TotalSeconds)
        }

        $EndTimeGreen = $(Get-Date)
        Write-Host "Found $($IGreenGroups.count) Immediate Green Groups, $(($EndTimeGreen - $StartTimeGreen).TotalMinutes) Minutes Elapsed" -ForegroundColor Green
        $null = $GreenComputers
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
        $NestedStep = 1
        while($IGreenGroups.count -gt 0) {
            Write-Progress -Id 1 -Activity 'Green Groups' -Status " --- Scoping Green Groups on Level $($NestedStep), $($MasterGreenGroups.count) Total Groups" -PercentComplete 50
            $null = $NewParentGroups
            $NewParentGroups = [System.Collections.ArrayList]::new()
            $NewParentGroups.AddRange($ParentGroups)
            for($i = 0; $i -lt $ParentGroups.count; $i++) {
                $ParentGroupMembers = $null
                try {
                    $ParentGroupMembers = Get-ADGroupMember -Identity $ParentGroups[$i] | Where-Object {$_.objectclass -eq "group"} | Select -ExpandProperty distinguishedname
                } catch {
                    $ParentGroupMembers = Get-ADGroup -Identity $ParentGroups[$i] -Properties members | Select -ExpandProperty members | Where-Object {$_ -notlike "*CN=ForeignSecurityPrincipals*"}
                    $ManualCheckGreenGroups.Add($ParentGroups[$i])
                }
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
                $TotalSeconds = ($(Get-Date) - $StartTimeGreen).TotalSeconds
                Write-Progress -Id 10 -ParentId 1 -Activity 'Green Groups' -Status " --- Scoped $($NewGreenGroups.count) Green Groups" -PercentComplete (100 * $i / $ParentGroups.count) -SecondsRemaining (($TotalSeconds * ($ParentGroups.count/($i+1))) - $TotalSeconds)
            }
            if($ParentGroups.count -eq $NewParentGroups.count) {
                Write-Host "Found $($MasterGreenGroups.count) Green Groups" -ForegroundColor Green
                break
            }

            $null = $ChildGreenGroups
            $ChildGreenGroups = [System.Collections.ArrayList]::new()
            $ChildGreenGroups.AddRange($NewGreenGroups)
            $MasterGreenGroups.AddRange($NewGreenGroups)

            $null = $NewRedGroups
            $NewRedGroups = [System.Collections.ArrayList]::new()

            $null = $ParentGroups
            $ParentGroups = [System.Collections.ArrayList]::new()
            $ParentGroups.AddRange($NewParentGroups)

            $NestedStep++
        }
        $MasterGreenGroups | Out-File -FilePath "$($Directory)\GroupsWithGreen.txt"
        $MissedGreenGroups = [System.Collections.ArrayList]::new()
        foreach($LargeGroup in $ManualCheckGreenGroups) {
            if(!($MasterGreenGroups -contains $LargeGroup)) {  $MissedGreenGroups.Add($LargeGroup)  }
        }
        if($MissedGreenGroups.count -gt 0) {  $MissedGreenGroups | Out-File -FilePath "$($Directory)\ManualCheckGroupsWithGreen.txt"  }

        $EndTimeGreen = $(Get-Date)
        Write-Host "Wrote Green Groups to File, $(($EndTimeGreen - $StartTimeGreen).TotalMinutes) Minutes Elapsed" -ForegroundColor Green
        $null = $IGreenGroups
        $null = $MasterGreenGroups
        $null = $ChildGreenGroups
        $null = $NewGreenGroups
        $null = $ParentGroups
        [system.gc]::Collect()


    # Immediate Yellow Groups
        Write-Progress -Id 1 -Activity 'Yellow Groups' -Status " --- Getting Immediate Yellow Groups" -PercentComplete 60
        $StartTimeYellow = $(Get-Date)

        $ManualCheckYellowGroups = [System.Collections.ArrayList]::new()
        $IYellowGroups = [System.Collections.ArrayList]::new()
        for($i = 0; $i -lt $Groups.count; $i++) {
            try {
                $GroupComputers = Get-ADGroupMember -Identity $Groups[$i] | Where-Object {$_.objectclass -eq "computer"} | Select -ExpandProperty distinguishedname
            } catch {
                $GroupComputers = Get-ADGroup -Identity $Groups[$i] -Properties members | Select -ExpandProperty members | Where-Object {$_ -notlike "*CN=ForeignSecurityPrincipals*"}
                $ManualCheckYellowGroups.Add($Groups[$i])
            }
            $FoundYellowComputer = $False
            foreach($GroupComputer in $GroupComputers) {
                if($YellowComputers -contains $GroupComputer) {
                    $FoundYellowComputer = $True
                    break
                }
            }
            if($FoundYellowComputer) {
                $IYellowGroups.Add($Groups[$i])
            }
            $TotalSeconds = ($(Get-Date) - $StartTimeYellow).TotalSeconds
            Write-Progress -Id 10 -ParentId 1 -Activity 'Immediate Groups' -Status " --- Scoped $($IYellowGroups.count) Immediate Yellow Groups" -PercentComplete (100 * $i / $Groups.count) -SecondsRemaining (($TotalSeconds * ($Groups.count/($i+1))) - $TotalSeconds)
        }

        $EndTimeYellow = $(Get-Date)
        Write-Host "Found $($IYellowGroups.count) Immediate Yellow Groups, $(($EndTimeYellow - $StartTimeYellow).TotalMinutes) Minutes Elapsed" -ForegroundColor Yellow
        $null = $YellowComputers
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
        $NestedStep = 1
        while($IYellowGroups.count -gt 0) {
            Write-Progress -Id 1 -Activity 'Yellow Groups' -Status " --- Scoping Yellow Groups on Level $($NestedStep), $($MasterYellowGroups.count) Total Groups" -PercentComplete 70
            $null = $NewParentGroups
            $NewParentGroups = [System.Collections.ArrayList]::new()
            $NewParentGroups.AddRange($ParentGroups)
            for($i = 0; $i -lt $ParentGroups.count; $i++) {
                try {
                    $ParentGroupMembers = Get-ADGroupMember -Identity $ParentGroups[$i] | Where-Object {$_.objectclass -eq "group"} | Select -ExpandProperty distinguishedname
                } catch {
                    $ParentGroupMembers = Get-ADGroup -Identity $ParentGroups[$i] -Properties members | Select -ExpandProperty members | Where-Object {$_ -notlike "*CN=ForeignSecurityPrincipals*"}
                    $ManualCheckGreenGroups.Add($ParentGroups[$i])
                }
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
                $TotalSeconds = ($(Get-Date) - $StartTimeYellow).TotalSeconds
                Write-Progress -Id 10 -ParentId 1 -Activity 'Yellow Groups' -Status " --- Scoped $($NewYellowGroups.count) Yellow Groups" -PercentComplete (100 * $i / $ParentGroups.count) -SecondsRemaining (($TotalSeconds * ($ParentGroups.count/($i+1))) - $TotalSeconds)
            }
            if($ParentGroups.count -eq $NewParentGroups.count) {
                Write-Host "Found $($MasterYellowGroups.count) Yellow Groups" -ForegroundColor Yellow
                break
            }

            $null = $ChildYellowGroups
            $ChildYellowGroups = [System.Collections.ArrayList]::new()
            $ChildYellowGroups.AddRange($NewYellowGroups)
            $MasterYellowGroups.AddRange($NewYellowGroups)
            
            $null = $NewYellowGroups
            $NewYellowGroups = [System.Collections.ArrayList]::new()

            $null = $ParentGroups
            $ParentGroups = [System.Collections.ArrayList]::new()
            $ParentGroups.AddRange($NewParentGroups)

            $NestedStep++
        }
        $MasterYellowGroups | Out-File -FilePath "$($Directory)\GroupsWithYellow.txt"
        $MissedYellowGroups = [System.Collections.ArrayList]::new()
        foreach($LargeGroup in $ManualCheckYellowGroups) {
            if(!($MasterYellowGroups -contains $LargeGroup)) {  $MissedYellowGroups.Add($LargeGroup)  }
        }
        if($MissedYellowGroups.count -gt 0) {  $MissedYellowGroups | Out-File -FilePath "$($Directory)\ManualCheckGroupsWithYellow.txt"  }

        $EndTimeYellow = $(Get-Date)
        Write-Host "Wrote Yellow Groups to File, $(($EndTimeYellow - $StartTimeYellow).TotalMinutes) Minutes Elapsed" -ForegroundColor Yellow
        $null = $IYellowGroups
        $null = $MasterYellowGroups
        $null = $ChildYellowGroups
        $null = $NewYellowGroups
        $null = $ParentGroups
        [system.gc]::Collect()


    # Immediate Red Groups
        Write-Progress -Id 1 -Activity 'Red Groups' -Status " --- Getting Immediate Red Groups" -PercentComplete 80
        $StartTimeRed = $(Get-Date)

        $ManualCheckRedGroups = [System.Collections.ArrayList]::new()
        $IRedGroups = [System.Collections.ArrayList]::new()
        for($i = 0; $i -lt $Groups.count; $i++) {
            try {
                $GroupComputers = Get-ADGroupMember -Identity $Groups[$i] | Where-Object {$_.objectclass -eq "computer"}  | Select -ExpandProperty distinguishedname
            } catch {
                $GroupComputers = Get-ADGroup -Identity $Groups[$i] -Properties members | Select -ExpandProperty members | Where-Object {$_ -notlike "*CN=ForeignSecurityPrincipals*"}
                $ManualCheckRedGroups.Add($Groups[$i])
            }
            $FoundRedComputer = $False
            foreach($GroupComputer in $GroupComputers) {
                if($RedComputers -contains $GroupComputer) {
                    $FoundRedComputer = $True
                    break
                }
            }
            if($FoundRedComputer) {
                $IRedGroups.Add($Groups[$i])
            }
            $TotalSeconds = ($(Get-Date) - $StartTimeRed).TotalSeconds
            Write-Progress -Id 10 -ParentId 1 -Activity 'Immediate Groups' -Status " --- Scoped $($IRedGroups.count) Immediate Red Groups" -PercentComplete (100 * $i / $Groups.count) -SecondsRemaining (($TotalSeconds * ($Groups.count/($i+1))) - $TotalSeconds)
        }

        $EndTimeRed = $(Get-Date)
        Write-Host "Found $($IRedGroups.count) Immediate Red Groups, $(($EndTimeRed - $StartTimeRed).TotalMinutes) Minutes Elapsed" -ForegroundColor Red
        $null = $RedComputers
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
        $NestedStep = 1
        while($IRedGroups.count -gt 0) {
            Write-Progress -Id 1 -Activity 'Red Groups' -Status " --- Scoping Red Groups on Level $($NestedStep), $($MasterRedGroups.count) Total Groups" -PercentComplete 90
            $null = $NewParentGroups
            $NewParentGroups = [System.Collections.ArrayList]::new()
            $NewParentGroups.AddRange($ParentGroups)
            for($i = 0; $i -lt $ParentGroups.count; $i++) {
                try {
                    $ParentGroupMembers = Get-ADGroupMember -Identity $ParentGroups[$i] | Where-Object {$_.objectclass -eq "group"} | Select -ExpandProperty distinguishedname
                } catch {
                    $ParentGroupMembers = Get-ADGroup -Identity $ParentGroups[$i] -Properties members | Select -ExpandProperty members | Where-Object {$_ -notlike "*CN=ForeignSecurityPrincipals*"}
                    $ManualCheckRedGroups.Add($ParentGroups[$i])
                }
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
                $TotalSeconds = ($(Get-Date) - $StartTimeRed).TotalSeconds
                Write-Progress -Id 10 -ParentId 1 -Activity 'Red Groups' -Status " --- Scoped $($NewRedGroups.count) Red Groups" -PercentComplete (100 * $i / $ParentGroups.count) -SecondsRemaining (($TotalSeconds * ($ParentGroups.count/($i+1))) - $TotalSeconds)
            }
            if($ParentGroups.count -eq $NewParentGroups.count) {
                Write-Host "Found $($MasterRedGroups.count) Red Groups" -ForegroundColor Red
                break
            }

            $null = $ChildRedGroups
            $ChildRedGroups = [System.Collections.ArrayList]::new()
            $ChildRedGroups.AddRange($NewRedGroups)
            $MasterRedGroups.AddRange($NewRedGroups)

            $null = $NewRedGroups
            $NewRedGroups = [System.Collections.ArrayList]::new()

            $null = $ParentGroups
            $ParentGroups = [System.Collections.ArrayList]::new()
            $ParentGroups.AddRange($NewParentGroups)

            $NestedStep++
        }
        $MasterRedGroups | Out-File -FilePath "$($Directory)\GroupsWithRed.txt"
        $MissedRedGroups = [System.Collections.ArrayList]::new()
        foreach($LargeGroup in $ManualCheckRedGroups) {
            if(!($MasterRedGroups -contains $LargeGroup)) {  $MissedRedGroups.Add($LargeGroup)  }
        }
        if($MissedRedGroups.count -gt 0) {  $MissedRedGroups | Out-File -FilePath "$($Directory)\ManualCheckGroupsWithRed.txt"  }

        $EndTimeRed = $(Get-Date)
        Write-Host "Wrote Red Groups to File, $(($EndTimeRed - $StartTimeRed).TotalMinutes) Minutes Elapsed" -ForegroundColor Red
        $null = $IRedGroups
        $null = $MasterRedGroups
        $null = $ChildRedGroups
        $null = $NewRedGroups
        $null = $ParentGroups
        [system.gc]::Collect()

    Write-Progress -Id 1 -Activity 'Scoping Report' -Status '--- Completed' -PercentComplete 100
    Write-Host "Scope Report Completed Successfully at $($Directory)"
    Write-Host "The files took $(($(Get-Date) - $Date).TotalHours) hours to generate."

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
                Export-ScopedComputersAndNestedGroups -Server $Server -DateString ($Date).ToString('yyyy-MM-dd HH:mm:ss') -InactiveThreshold 31 -RootFolder $PSScriptRoot
            }
            "3" {
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
