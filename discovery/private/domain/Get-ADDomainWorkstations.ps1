function Get-ADDomainWorkspaces {

    [CmdletBinding()]
    Param(

    )

    Begin {}
    Process {}
    End {}

}

<#
    @{
        count = [int]
        inactive = [int]
        operatingSystems = @(
            @{
                name = [string]
                count = [int]
                endOfLifeSupport = [date]
                patching = [???]
            }, ...
        )
    }
#>