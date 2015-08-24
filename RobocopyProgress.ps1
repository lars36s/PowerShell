# Copyright (c) 2015 Lars Romshøj

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

function Format-FileSize ([long]$bytecount)
{
    if ($bytecount -eq 0)
    {
        return "0 Bytes"
    }

    switch -Regex ([math]::truncate([math]::log($bytecount,1024))) {

                      '^0' {"$bytecount Bytes"}

                      '^1' {"{0:n2} KB" -f ($bytecount / 1kb)}

                      '^2' {"{0:n2} MB" -f ($bytecount / 1mb)}

                      '^3' {"{0:n2} GB" -f ($bytecount / 1gb)}

                      '^4' {"{0:n2} TB" -f ($bytecount / 1tb)}

                Default {"{0:n2} PB" -f ($bytecount / 1pb)}

              }
}

function Get-Element ($content, [int]$elementIndex)
{
     $elements = $progressString.Split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)             
     $source = $elements[$elementIndex]

     if ($source)
     {
        $source = $source.Trim()
     }

     return $sorce
}

<#
.Synopsis
   cmdlet for parsing the output from robocopy
.DESCRIPTION
   Generates Progress infoormation and summary object as well as any errors are outputed as actual powershell erros
.EXAMPLE
   robocopy \\nav-fs\VHDs .. Blank* /BYTES /E /IT /W:3 /R:3  | Out-RoboCopyProgress
.EXAMPLE
   robocopy \\nav-fs\VHDs .. Blank* /BYTES /E /IT /W:3 /R:3  | Out-RoboCopyProgress -Verbose
#>
function Out-RoboCopyProgress
{
    [CmdletBinding()]
    Param
    (
        # Param1 help description
        [Parameter(Mandatory=$true,                   
                   ValueFromPipeline=$true,
                   Position=0)]
        $progressString     
    )

    Begin
    {
        $Result = new-object psobject
        $currentFile = ""
        $curentSize = ""    
        $nextMessageIsAnWarrning = $false    
        $currentIssueContext = ""
        $headerCount = 0
        $IsCopyRunning = $false
        $FatalErrors = @()
    }
    Process
    {     
        $progressString = $progressString.Trim()
        if ([string]::IsNullOrWhiteSpace($progressString))
        {
            return
        }

        if (-not $IsCopyRunning)
        {
            if ($progressString.StartsWith("----") )
            {
                $headerCount++
                if ($headerCount -ge 3)
                {
                    $IsCopyRunning = $true
                }

                #return
            }              

            if ($progressString.StartsWith("ROBOCOPY"))
            {
                Write-Progress -PercentComplete 0 -Activity "Robocopy" -Status "Initializing"
            }

            if ($progressString.StartsWith("Source"))
            {                
                $source = Get-Element -content $progressString -elementIndex 2          
            }

            if ($progressString.StartsWith("Dest"))
            {                
                $destination = Get-Element -content $progressString -elementIndex 2
            }          

            Write-Verbose $progressString

            return
        }
                
        if ($progressString.StartsWith("ERROR"))
        {
            $FatalError += "$($progressString): $currentIssueContext"
        }
        

        if ($nextMessageIsAnWarrning)
        {
            Write-Warning "$($currentIssueContext): $progressString"
            $nextMessageIsAnWarrning = $false
            return
        }
        
        $elements = $progressString.Split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)
        if ($elements[2] -eq "ERROR")
        {
            $currentIssueContext = $progressString
            $nextMessageIsAnWarrning = $true
            return
        }

        if ($progressString -eq "The process cannot access the file because it is being used by another process.")
        {
            Write-Warning $progressString
            return
        }

        if ($progressString.StartsWith("Newer") -or $progressString.StartsWith("New File") -or $progressString.StartsWith("Same") -or $progressString.StartsWith("Older"))
        {
            if ($currentFile -ne "")
            {
                Write-Progress -Completed $progress -Activity "Robocopy" -CurrentOperation $currentFile -Status "Copying"
            }

            $elements = $progressString.Split("`t",[System.StringSplitOptions]::RemoveEmptyEntries)             
            $currentFile = $elements[2].Trim()
            $currentSize = $elements[1].Trim()
            $sizeInByes = 0
            if ([Long]::TryParse($currentSize, [ref]$sizeInByes))
            {
                $currentSize = Format-FileSize -bytecount $sizeInByes
            }

            Write-Verbose $progressString
            return
        }

        $progress = 0.0
        if ([double]::TryParse($progressString.TrimEnd('%'), [ref]$progress))
        {            
            Write-Progress -PercentComplete $progress -Activity "Robocopy ($source ==> $destination)" -CurrentOperation "$currentFile ($currentSize)" -Status "Copying"
            return
        }

        #VERBOSE:           Total      Copied   Skipped  Mismatch    FAILED    Extras
        #VERBOSE: Dirs  :        16         0        16         0         0         4
        #VERBOSE: Files :         7         6         0         0         1         0
        #VERBOSE: Bytes : 205520896 201326592         0         0   4194304         0
        #VERBOSE: Times :   0:00:09   0:00:00                       0:00:09   0:00:00
        if ($progressString.StartsWith("Files :"))
        {
            $elements = $progressString.Split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)   
            Add-Member -InputObject $Result -MemberType NoteProperty -Name FilesTotal -Value ([Int]::Parse($elements[2]))
            Add-Member -InputObject $Result -MemberType NoteProperty -Name FilesCopied -Value ([Int]::Parse($elements[3]))
            Add-Member -InputObject $Result -MemberType NoteProperty -Name FilesSkipped -Value ([Int]::Parse($elements[4]))
            Add-Member -InputObject $Result -MemberType NoteProperty -Name FilesMismatch -Value ([Int]::Parse($elements[5]))
            Add-Member -InputObject $Result -MemberType NoteProperty -Name FilesFailed -Value ([Int]::Parse($elements[6]))
            Add-Member -InputObject $Result -MemberType NoteProperty -Name FilesExtra -Value ([Int]::Parse($elements[7]))

        }
        if ($progressString.StartsWith("Dirs :"))
        {
            $elements = $progressString.Split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)   
            Add-Member -InputObject $Result -MemberType NoteProperty -Name DirectoriesTotal -Value ([Long]::Parse($elements[2]))
            Add-Member -InputObject $Result -MemberType NoteProperty -Name DirectoriesCopied -Value ([Long]::Parse($elements[3]))
            Add-Member -InputObject $Result -MemberType NoteProperty -Name DirectoriesSkipped -Value ([Long]::Parse($elements[4]))
            Add-Member -InputObject $Result -MemberType NoteProperty -Name DirectoriesMismatch -Value ([Long]::Parse($elements[5]))
            Add-Member -InputObject $Result -MemberType NoteProperty -Name DirectoriesFailed -Value ([Long]::Parse($elements[6]))
            Add-Member -InputObject $Result -MemberType NoteProperty -Name DirectoriesExtra -Value ([Long]::Parse($elements[7]))
        }
        
        if ($progressString.StartsWith("Bytes :"))
        {
            $elements = $progressString.Split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)   
            Add-Member -InputObject $Result -MemberType NoteProperty -Name BytesTotal -Value ([Long]::Parse($elements[2]))
            Add-Member -InputObject $Result -MemberType NoteProperty -Name BytesCopied -Value ([Long]::Parse($elements[3]))
            Add-Member -InputObject $Result -MemberType NoteProperty -Name BytesTotalDisplay -Value (Format-FileSize $Result.BytesTotal)
            Add-Member -InputObject $Result -MemberType NoteProperty -Name BytesCopiedDisplay -Value (Format-FileSize $Result.BytesCopied)  
        }

        if ($progressString.EndsWith("Bytes/sec."))
        {
            $elements = $progressString.Split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)  
            Add-Member -InputObject $Result -MemberType NoteProperty -Name SpeedBytesPerSecond -Value ([Long]::Parse($elements[2]))
            Add-Member -InputObject $Result -MemberType NoteProperty -Name SpeedDisplay -Value "$(Format-FileSize $Result.SpeedBytesPerSecond)/Sec"
        }

        Write-Verbose $progressString
    }
    End
    {
        Write-Output $Result

        if ($FatalError)
        {
            Write-Error $FatalError           
        }           
    }
}

#$file = [System.io.File]::Open('C:\Users\larsro\Documents\WindowsPowerShell\BlankDisk#1.vhdx', 'Create', 'Write', 'None')

robocopy \\nav-fs\VHDs .. Blank* /BYTES /E /IT /W:3 /R:3  | Out-RoboCopyProgress #-Verbose
#$file.Close()

