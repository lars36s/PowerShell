Add-Type -TypeDefinition @"
   public enum Locations
   {
      Private,
      PowerShell,
      edi,
      main,
      infrastructure
   }
"@

function Set-KnownLocation {
    param ( [Locations]$KnownLocation)

    switch ($KnownLocation)
    {
        "Private" {Push-Location "C:\repos\private"; continue } 
        "PowerShell" {Push-Location "$profile\.."; continue } 
        "core" {Push-Location "C:\Depot\Infrastructure\source\Core"}
        "edi" {Push-Location "C:\repos\edi-fork"; continue }         
        "main" {Push-Location "C:\Depot\Main"; continue } 
        "infrastructure" {Push-Location "C:\Depot\Infrastructure"; continue } 
    }
}

New-Alias goto Set-KnownLocation