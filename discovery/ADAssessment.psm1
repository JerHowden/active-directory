# Get public and private function definition files.
$Public = @( Get-ChildItem -Path $PSScriptRoot\public\*.ps1 -ErrorAction SilentlyContinue -Recurse )
$Private = @( Get-ChildItem -Path $PSScriptRoot\private\*.ps1 -ErrorAction SilentlyContinue -Recurse )

# Dot source the files
Foreach ($import in @($Public + $Private)) {
    Try {
        . $import.fullname
    } Catch {
        Write-Error -Message "Failed to import function $($import.fullname): $_"
    }
}

$ModulesOptional = 'ActiveDirectory', 'GroupPolicy'
foreach ($Module in $ModulesOptional) {
    try {
        Import-Module -Name $Module -ErrorAction Stop
    } catch {

    }
}
Export-ModuleMember -Function 'Get-ADAssessment'