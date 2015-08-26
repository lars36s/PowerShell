function AsLong
{
    [OutputType([Long])]
    Param ([string]$str)
    [long]$value = 0
    if ([Long]::TryParse($str, [ref]$value))
    {
        return $value
    }

    return 0
}

function GetElement ($content, [int]$elementIndex)
{
     $elements = $progressString.Split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)             
     $source = $elements[$elementIndex]

     if ($source)
     {
        $source = $source.Trim()
     }

     return $source
}
<#
.Synopsis
   Cmdlet for parsing the output from robocopy
.DESCRIPTION
   This cmdlet takes the output from Robocopy and uses it to generate:
   - progress information 
   - summary object 
   - Any errors are outputed as actual powershell errors

   This works best if robocopy is not called with the /NP (no progress argument)
    
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
        # Pipe output from robocopy
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
            }              

            if ($progressString.StartsWith("ROBOCOPY"))
            {
                Write-Progress -PercentComplete 0 -Activity "Robocopy" -Status "Initializing"
            }

            if ($progressString.StartsWith("Source"))
            {                
                $source = (GetElement -content $progressString -elementIndex 2)          
            }

            if ($progressString.StartsWith("Dest"))
            {                
                $destination = (GetElement -content $progressString -elementIndex 2)
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
            $elements = $progressString.Split("`t",[System.StringSplitOptions]::RemoveEmptyEntries)             
            $currentFile = $elements[2].Trim()
            $currentSize = $elements[1].Trim()
            $sizeInByes = 0                       

            if ([Long]::TryParse($currentSize, [ref]$sizeInByes))
            {
                $currentSize = Format-FileSize -bytecount $sizeInByes
            }
            
            Write-Progress -PercentComplete 0 -Activity "Robocopy ($source ==> $destination)" -CurrentOperation "$currentFile ($currentSize)" -Status "Copying"

            Write-Verbose $progressString
            return
        }

        $progress = 0.0
        if ([double]::TryParse($progressString.TrimEnd('%'), [ref]$progress))
        {            
            Write-Progress -PercentComplete $progress -Activity "Robocopy ($source ==> $destination)" -CurrentOperation "$currentFile ($currentSize)" -Status "Copying"
            return
        }
        
        Write-Verbose $progressString
        
        if ($progressString.StartsWith("Files :"))
        {
            $elements = $progressString.Split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)   
            Add-Member -InputObject $Result -MemberType NoteProperty -Name FilesTotal -Value (AsLong $elements[2])
            Add-Member -InputObject $Result -MemberType NoteProperty -Name FilesCopied -Value (AsLong $elements[3])
            Add-Member -InputObject $Result -MemberType NoteProperty -Name FilesSkipped -Value (AsLong $elements[4])
            Add-Member -InputObject $Result -MemberType NoteProperty -Name FilesMismatch -Value (AsLong $elements[5])
            Add-Member -InputObject $Result -MemberType NoteProperty -Name FilesFailed -Value (AsLong $elements[6])
            Add-Member -InputObject $Result -MemberType NoteProperty -Name FilesExtra -Value (AsLong $elements[7])
        }

        if ($progressString.StartsWith("Dirs :"))
        {
            $elements = $progressString.Split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)   
            Add-Member -InputObject $Result -MemberType NoteProperty -Name DirectoriesTotal -Value (AsLong $elements[2])
            Add-Member -InputObject $Result -MemberType NoteProperty -Name DirectoriesCopied -Value (AsLong $elements[3])
            Add-Member -InputObject $Result -MemberType NoteProperty -Name DirectoriesSkipped -Value (AsLong $elements[4])
            Add-Member -InputObject $Result -MemberType NoteProperty -Name DirectoriesMismatch -Value (AsLong $elements[5])
            Add-Member -InputObject $Result -MemberType NoteProperty -Name DirectoriesFailed -Value (AsLong $elements[6])
            Add-Member -InputObject $Result -MemberType NoteProperty -Name DirectoriesExtra -Value (AsLong $elements[7])
        }
        
        if ($progressString.StartsWith("Bytes :"))
        {
            $elements = $progressString.Split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)   
            Add-Member -InputObject $Result -MemberType NoteProperty -Name BytesTotal -Value ( AsLong $elements[2])
            Add-Member -InputObject $Result -MemberType NoteProperty -Name BytesCopied -Value (AsLong $elements[3])
            Add-Member -InputObject $Result -MemberType NoteProperty -Name BytesTotalDisplay -Value (Format-FileSize $Result.BytesTotal)
            Add-Member -InputObject $Result -MemberType NoteProperty -Name BytesCopiedDisplay -Value (Format-FileSize $Result.BytesCopied)  
        }

        if ($progressString.EndsWith("Bytes/sec."))
        {
            $elements = $progressString.Split(" ",[System.StringSplitOptions]::RemoveEmptyEntries)  
            Add-Member -InputObject $Result -MemberType NoteProperty -Name SpeedBytesPerSecond -Value (AsLong $elements[2])
            Add-Member -InputObject $Result -MemberType NoteProperty -Name SpeedDisplay -Value "$(Format-FileSize $Result.SpeedBytesPerSecond)/Sec"
        }        
    }
    End
    {
        Write-Progress -Completed -Activity "Robocopy" -CurrentOperation $currentFile -Status "Copying"
            
        Write-Output $Result

        if ($FatalError)
        {
            Write-Error $FatalError           
        }           
    }
}

Export-ModuleMember *-*