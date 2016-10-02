
[CmdletBinding()]
Param(
    [Parameter(Mandatory = $True, Position = 1)]
    [string]$Filename,
    [Parameter(Mandatory = $True, Position = 2)]
    [string]$Pkgname,
    [Parameter(Mandatory = $True, Position = 3)]
    [string]$RVersion
)

# --------------------------------------------------------------------
Write-Verbose "Setting up R Environment..."

$R = "C:\Program Files\R\R-${RVersion}\bin\R"

# Currently only 3.2.5 is special, and the rest use Rtools34 and 
# Jeroen's toolchain

If ($RVersion -eq "3.2.5") {
    $rpath = 'C:\Rtools33\bin;C:\Rtools\gcc-4.6.3\bin;' + $env:PATH
    $rbinpref = ''
} Else {
    $rpath = 'C:\Rtools34\bin;' + $env:PATH
    $rbinpref = 'C:/Rtools34/mingw_$(WIN)/bin/'
}

# We need to set this, otherwise R never finds the profile
Set-Variable home (pwd).toString() -Force
(get-psprovider 'FileSystem').Home = $home
[system.environment]::SetEnvironmentVariable("home", "$home")

mkdir R -ErrorAction SilentlyContinue | out-null

$rhome = ( $home.replace('\', '/') + '/R' )

Add-Content `
  -Value "options(repos = structure(c(CRAN = 'https://cran.rstudio.com'))); .libPaths('$rhome')" `
  -Path .Rprofile

# A function to run R

function Run-R {
    Param(
	[Parameter(Mandatory = $True)]
	[string]$arguments
    )

    $StartInfo = New-Object System.Diagnostics.ProcessStartInfo `
      -Property @{
          FileName = "$R"
	  Arguments = "$arguments"
	  UseShellExecute = $false
	  RedirectStandardOutput = $true
	  RedirectStandardError = $true
	  CreateNoWindow = $true
      }

    $StartInfo.EnvironmentVariables["PATH"] = $rpath
    $StartInfo.EnvironmentVariables["BINPREF"] = $rbinpref

    # Create new process
    $Process = New-Object System.Diagnostics.Process

    # Assign previously created StartInfo properties
    $Process.StartInfo = $StartInfo

    # Register Object Events for stdin\stdout reading
    $OutEvent = Register-ObjectEvent `
      -InputObject $Process `
      -EventName OutputDataReceived `
      -Action { Write-Host $Event.SourceEventArgs.Data }
    $ErrEvent = Register-ObjectEvent `
      -InputObject $Process `
      -EventName ErrorDataReceived `
      -Action { Write-Host $Event.SourceEventArgs.Data }

    # Start process
    [void]$Process.Start()

    # Begin reading stdin\stdout
    $Process.BeginOutputReadLine()
    $Process.BeginErrorReadLine()

    do {
       Start-Sleep 1
    } while (!$Process.HasExited)

    # Unregister events
    $OutEvent.Name, $ErrEvent.Name |
      ForEach-Object {Unregister-Event -SourceIdentifier $_}
}

# --------------------------------------------------------------------
Write-Verbose "Installing package dependencies..."

Write-Host ">>>>>============== Querying package dependencies"

# First we download install-github.R externally, because not all R
# versions support HTTPS. Then we install a version of 'remotes'.

Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/MangoTheCat/remotes/master/install-github.R" `
  -OutFile .\install-github.R

Run-R "-q -e `"source('install-github.R')`$value('mangothecat/remotes')`""

# Finally, the dependencies

Write-Host ">>>>>============== Installing package dependencies"

Run-R "-q -e `"remotes::install_local('$Pkgname', dependencies = TRUE)`""

# --------------------------------------------------------------------
Write-Verbose ( "Checking " + $Filename )

Write-Host ">>>>>============== Running R CMD check"

Run-R "CMD check -l $rhome $Filename"

Write-Host "+R-HUB-R-HUB-R-HUB Done."
