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
        "Private" {Push-Location "C:\src\private"; continue } 
        "PowerShell" {Push-Location "$profile\.."; continue } 
        "core" {Push-Location "C:\src\Infrastructure\source\Core"}
        "edi" {Push-Location "C:\src\edi-fork"; continue }         
        "main" {Push-Location "C:\src\Main"; continue } 
        "infrastructure" {Push-Location "C:\src\Infrastructure"; continue } 
    }
}

New-Alias goto Set-KnownLocation