[CmdletBinding()] 
#requires -version 3 
param( 
    [parameter(ParameterSetName = "ComputerName", Mandatory = $true, ValueFromPipeline = $true, Position = 0)] 
    $ComputerName, 
    [parameter(ParameterSetName = "ThisComputer")] 
    [switch]$ThisComputer, 
    [switch]$ValueOnly 
) 
 
begin 
{ 
    $rootDse = New-Object System.DirectoryServices.DirectoryEntry("LDAP://RootDSE") 
    $Domain = $rootDse.DefaultNamingContext 
    $root = New-Object System.DirectoryServices.DirectoryEntry("LDAP://$Domain") 
} 
 
process 
{ 
    if ($PSCmdlet.ParameterSetName -ne "ComputerName") 
    { 
        $ComputerName = $env:COMPUTERNAME 
    } 
 
    $searcher = New-Object System.DirectoryServices.DirectorySearcher($root) 
    $searcher.Filter = "(&(objectClass=computer)(name=$ComputerName))" 
    [System.DirectoryServices.SearchResult]$result = $searcher.FindOne() 
    if (!$?) 
    { 
        return 
    } 
    $dn = $result.Properties["distinguishedName"] 
    $ouResult = $dn.Substring($ComputerName.Length + 4) 
    if ($ValueOnly) 
    { 
        $ouResult 
    } else { 
        New-Object PSObject -Property @{"Name" = $ComputerName; "OU" = $ouResult} 
    } 
}