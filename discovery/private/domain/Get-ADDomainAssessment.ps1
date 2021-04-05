function Get-ADDomainAssessment {

    [CmdletBinding()]
    Param(
        [Parameter(ValueFromPipeline,
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
    )

    # Domain Jobs
    $ConfigurationJob = Start-Job -Name DomainConfiguration -ScriptBlock { 
        param($Server, $Date)
        Get-ADDomainConfiguration -Server $Server -DateString $DateString
    }
    $GPOsJob = Start-Job -Name DomainGPOs -ScriptBlock { 
        param($Server, $Date)
        Get-ADDomainGPOs -Server $Server -DateString $DateString
    }
    $GroupsJob = Start-Job -Name DomainGroups -ScriptBlock { 
        param($Server, $Date)
        Get-ADDomainGroups -Server $Server -DateString $DateString
    }
    $OUsJob = Start-Job -Name DomainOUs -ScriptBlock { 
        param($Server, $Date)
        Get-ADDomainOUs -Server $Server -DateString $DateString
    }
    $SecurityJob = Start-Job -Name DomainSecurity -ScriptBlock { 
        param($Server, $Date)
        Get-ADDomainSecurity -Server $Server -DateString $DateString
    }
    $ServersJob = Start-Job -Name DomainServers -ScriptBlock { 
        param($Server, $Date)
        Get-ADDomainServers -Server $Server -DateString $DateString
    }
    $UsersJob = Start-Job -Name DomainUsers -ScriptBlock { 
        param($Server, $Date)
        Get-ADDomainUsers -Server $Server -DateString $DateString
    }
    $WorkstationsJob = Start-Job -Name DomainWorkstations -ScriptBlock { 
        param($Server, $Date)
        Get-ADDomainWorkstations -Server $Server -DateString $DateString
    }

    # Write Progress
    $DomainJobs = Get-Job | ? { $_.state -eq 'Running' -and $_.name -like 'Domain*' }
    $RunningDomainJobs = $DomainJobs.Count
    while($RunningDomainJobs -gt 0) {
        Write-Progress -Activity 'Domain Assessment' -Status "$RunningDomainJobs Jobs Left:" -PercentComplete (($DomainJobs.Count-$RunningDomainJobs) / $DomainJobs.Count*100)
        $RunningDomainJobs = (Get-Job | ? { $_.state -eq 'Running' -and $_.name -like 'Domain*' }).Count
        Start-Sleep -Seconds 1
    }

}