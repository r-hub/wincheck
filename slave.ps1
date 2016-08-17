
[CmdletBinding()]
Param(
    [Parameter(Mandatory = $True, Position = 1)]
    [string]$Filename,
    [Parameter(Mandatory = $True, Position = 2)]
    [string]$Pkgname
)

# --------------------------------------------------------------------
Write-Verbose "Setting up R Environment..."

$R = 'C:\Program Files\R\R-devel\bin\R'

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
    
    $Process.WaitForExit()
    
    # Unregister events
    $OutEvent.Name, $ErrEvent.Name |
      ForEach-Object {Unregister-Event -SourceIdentifier $_}
}

& $R -q -e "print('hello'); Sys.sleep(5); print('still')"

Run-R "-q -e `"print('hello'); Sys.sleep(5); print('still')`""

exit

# --------------------------------------------------------------------
Write-Verbose "Installing package dependencies..."

# First we download install-github.R externally, because not all R
# versions support HTTPS. Then we install a version of 'remotes'.

Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/MangoTheCat/remotes/master/install-github.R" `
  -OutFile .\install-github.R

Run-R "-q -e `"source('install-github.R')`$value('mangothecat/remotes')`""

# Finally, the dependencies

Run-R "-q -e `"remotes::install_local('$Pkgname', dependencies = TRUE)`""

# --------------------------------------------------------------------
Write-Verbose ( "Checking " + $Filename )

Run-R "CMD check -l $rhome $Filename"
