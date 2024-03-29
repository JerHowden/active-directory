<#

    .SYNOPSIS
    Performs a discovery audit of the client's active directory environment.

    .DESCRIPTION
    Performs a discovery audit of the client's active directory environment.

    .OUTPUTS
    Exports the assessment data in an XML file to the results folder.

    .NOTES
    Written By: Jeremiah Howden
    
    Change Log
    v1.00, 2021-02-24 - Initial Version

#>

Function Get-ADAssessment {

    [CmdletBinding()]
    Param(
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
        [int]$Limit
    )

    # TODO:
    # - Allocate Applications Jobs
    # - Allocate Cloud Jobs
    # - Allocate Governance Jobs
    # - Allocate Tools Jobs

    Begin {

        # Start Forest Jobs

    }

    Process {

        # - DOMAIN -
            # Variables
            $Server = $DomainController + '.' + $Domain
            $RootDSE = Get-ADRootDSE -Server $Server

            # Start Assessment
            #Get-ADDomainAssessment 

    }
    End {

        # Compile and Build XML

    }

}
