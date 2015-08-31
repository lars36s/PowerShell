import-module .\Utilities.psm1 -Force
$ErrorActionPreference = "Stop"

function Assert-AreEquals($Expected, $Actual, $Message = "Expected $Expected found $Actual")
{
    if ($Expected -ne $Actual)
    {
        throw $message
    }
}
#Format-Size 10304500
#Copy-ItemsRobustly -Source '\\larsro-dev1\d$\builds' -Destination C:\Temp1 -Verbose


# 1. TESTING: Generate a random, unique source directory, with some test files in it
$TestSource = '{0}\{1}' -f $env:temp, [Guid]::NewGuid().ToString();
$null = mkdir -Path $TestSource;
# 1a. TESTING: Create some test source files
1..20 | % -Process { Set-Content -Path $TestSource\$_.txt -Value ('A'*(Get-Random -Minimum 10 -Maximum 2100)); };

# 2. TESTING: Create a random, unique target directory
$TestTarget = '{0}\{1}' -f $env:temp, [Guid]::NewGuid().ToString();
$null = mkdir -Path $TestTarget;

# 3. Call the Copy-WithProgress function
$output = Copy-ItemsRobustly -Source $TestSource -Destination $TestTarget -Verbose;

$ExpectedNumberOfFiles = (gci $TestSource).Count
Assert-AreEquals $ExpectedNumberOfFiles (gci $TestTarget).Count
Assert-AreEquals $ExpectedNumberOfFiles $output.FilesCopied
# 4. Add some new files to the source directory
21..40 | % -Process { Set-Content -Path $TestSource\$_.txt -Value ('A'*(Get-Random -Minimum 950 -Maximum 1400)); };

# 5. Call the Copy-WithProgress function (again)
Copy-ItemsRobustly -Source $TestSource -Destination $TestTarget -Verbose;
