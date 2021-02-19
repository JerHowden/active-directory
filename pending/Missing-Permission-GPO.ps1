#Find Group Policies with Missing Permissions
Function Get-GPMissingPermissionsGPOs
{
   $MissingPermissionsGPOArray = New-Object System.Collections.ArrayList
   $GPOs = Get-GPO -all
   foreach ($GPO in $GPOs) {
        If ($GPO.User.Enabled) {
            $GPOPermissionForAuthUsers = Get-GPPermission -Guid $GPO.Id -All | select -ExpandProperty Trustee | ? {$_.Name -eq "Authenticated Users"}
            $GPOPermissionForDomainComputers = Get-GPPermission -Guid $GPO.Id -All | select -ExpandProperty Trustee | ? {$_.Name -eq "Domain Computers"}
            If (!$GPOPermissionForAuthUsers -and !$GPOPermissionForDomainComputers) {
                $MissingPermissionsGPOArray.Add($GPO)| Out-Null
            }
        }
    }
    If ($MissingPermissionsGPOArray.Count -ne 0) {
        Write-Warning  "The following Group Policy Objects do not grant any permissions to the 'Authenticated Users' or 'Domain Computers' groups:"
        foreach ($GPOWithMissingPermissions in $MissingPermissionsGPOArray) {
            Write-Host "'$($GPOWithMissingPermissions.DisplayName)'"
        }
    }
    Else {
        Write-Host "All Group Policy Objects grant required permissions. No issues were found." -ForegroundColor Green
    }
}


#Get Installed Roles on each Domain Controller
$DCsInForest = (Get-ADForest).Domains | % {Get-ADDomainController -Filter * -Server $_}
$DCsRolesArray = @()
foreach ($DC in $DCsInForest) {
    $DCRoles=""
    $Roles = Get-WindowsFeature -ComputerName $DC.HostName | Where-Object {$_.Installed -like "True" -and $_.FeatureType -like "Role"} | Select DisplayName
    foreach ($Role in $Roles) {
        $DCRoles += $Role.DisplayName +","
    }
    try {$DCRoles = $DCRoles.Substring(0,$DCRoles.Length-1)}
    catch {$DCRoles = "Server roles cannot be obtain"}
    $DCObject = New-Object -TypeName PSObject
    Add-Member -InputObject $DCObject -MemberType 'NoteProperty' -Name 'DCName' -Value $DC.HostName
    Add-Member -InputObject $DCObject -MemberType 'NoteProperty' -Name 'Roles' -Value $DCRoles
    $DCsRolesArray += $DCObject
}
$DCsRolesArray | Out-GridView

#Get Domain Controllers for current domain
$DCs = Get-ADGroupMember "Domain Controllers"
#Initiate the clients array
$Clients = @()
Foreach ($DC in $DCs) {
    #Define the netlogon.log path
    $NetLogonFilePath = "\\" + $DC.Name + "\C$\Windows\debug\netlogon.log"
    #Reading the content of the netlogon.log file
    try {$NetLogonFile = Get-Content -Path $NetLogonFilePath -ErrorAction Stop}
    catch {"Error reading $NetLogonFilePath"}
    foreach ($Line in $NetLogonFile) {
        #Splitting the line to isolate each variable
        $ClientData = $Line.split(' ')
        #Creating the client object
        $ClientObject = New-Object -TypeName PSObject
        Add-Member -InputObject $ClientObject -MemberType NoteProperty -Name 'Hostname' -Value $ClientData[5]
        Add-Member -InputObject $ClientObject -MemberType NoteProperty -Name 'IP' -Value $ClientData[6]
        Add-Member -InputObject $ClientObject -MemberType NoteProperty -Name 'DomainController' -Value $DC.Name
        Add-Member -InputObject $ClientObject -MemberType NoteProperty -Name 'Date' -Value $ClientData[0]
        $Clients += $ClientObject
     }
}
$UniqueClients = $Clients | Sort-Object -Property IP -Unique
$UniqueClients | Out-GridView -Title "Clients which are not mapped to any AD sites ($($UniqueClients.Count) in total)"
