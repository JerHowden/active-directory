# Create 50,000 Users in a Test Group to simulate scale

$names = Get-Content "names.txt" # 10000 names
$ou = "OU=Scale Test,DC=prod,DC=ncidemo,DC=com"

$Groups = Get-ADGroup -Filter * -SearchBase $ou

1..10000 | ForEach-Object {
    $r = Get-Random -Minimum 0 -Maximum $names.count
    New-ADUser -Name "$($names[$_]) $($names[$r])$($_)" -GivenName $names[$_] -Surname "$($names[$r])$($_)" -Path $ou -verbose
}

$NewUsers = Get-ADUser -SearchBase $ou -Filter *

$Groups | ForEach-Object {
    $r = Get-Random -Minimum 0 -Maximum ($NewUsers.count-500)
    $Members = $NewUsers[$r..($r+500)]
    Add-ADGroupMember -Identity $_.distinguishedname -Members $Members -verbose
}