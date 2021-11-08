
[CmdletBinding()]
Param(
    [Parameter(Mandatory = $True, Position = 1)]
    [string]$Filename,
    [Parameter(Mandatory = $True, Position = 2)]
    [string]$Pkgname,
    [Parameter(Mandatory = $True, Position = 3)]
    [string]$RVersion,
    [Parameter(Mandatory = $True, Position = 4)]
    [string]$build
)

$CheckArgs = ""
$EnvVars = ""
If (Test-Path "rhub-args.txt") { $CheckArgs = [IO.File]::ReadAllText("rhub-args.txt").Trim() }
If (Test-Path "rhub-envs.txt") { $EnvVars = [IO.File]::ReadAllText("rhub-envs.txt").Trim() }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --------------------------------------------------------------------
Write-Verbose "Setting up R Environment..."

$R = "C:\Program Files\R\R-${RVersion}\bin\R"

# Currently only 3.2.5 is special, and the rest use Rtools34 and
# Jeroen's toolchain
# For ucrt we still add c:\rtool40 to PATH, but it is not installed,
# so it does not matter. (But it will be a problem when we'll start
# using the same machine for UCRT and non-UCRT checks.)

If ($RVersion -eq "3.2.5") {
    $rpath = 'C:\Rtools33\bin;C:\Rtools\gcc-4.6.3\bin;' + $env:PATH
    $rbinpref = ''
} ElseIf ($RVersion.Substring(0,1) -eq "3") {
    $rpath = 'C:\Rtools34\bin;' + $env:PATH
    $rbinpref = 'C:/Rtools34/mingw_$(WIN)/bin/'
} Else {
    $rpath = 'C:\rtools40\usr\bin;' + $env:PATH
}

# Hunspell (disguised as aspell)

$rpath = 'C:\hunspell\bin;' + $rpath

# Pandoc

$rpath = 'C:\Program Files\pandoc;' + $rpath

# We need to set this, otherwise R never finds the profile
Set-Variable home (pwd).toString() -Force
(get-psprovider 'FileSystem').Home = $home
[system.environment]::SetEnvironmentVariable("home", "$home")
[system.environment]::SetEnvironmentVariable("USERPROFILE", "$home")

# Some tools need APPDATA set
$appdata = "$home" + "\AppData\Roaming"
mkdir "$appdata" -ErrorAction SilentlyContinue | out-null
[system.environment]::SetEnvironmentVariable("APPDATA", "$appdata")

ls env: | Out-Host

mkdir R -ErrorAction SilentlyContinue | out-null

$rhome = ( $home.replace('\', '/') + '/R' )

Add-Content `
  -Value "options(repos = unlist(utils::modifyList(as.list(getOption('repos')), list('CRAN' = 'https://cloud.r-project.org'))))" `
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

    # Set user supplied env vars, it is supplied as a newline
    # separated list of KEY=value records, in a single string
    if (! $EnvVars -eq "") {
	$EnvVarsArray = ($EnvVars -split '[\r\n]')
        for ($i=0; $i -lt $EnvVarsArray.length; $i++) {
            $keyVal = ($EnvVarsArray[$i] -split '=', 2)
            if ($keyVal.length -eq 2) {
                $StartInfo.EnvironmentVariables[$keyVal[0]] = $keyVal[1]
                Write-Host ('setting ' + $keyVal[0] + ' to ' + $keyVal[1])
            } elseif ($keyVal.length -eq 1 -and ! $keyVal[0] -eq "") {
                $StartInfo.EnvironmentVariables[$keyVal[0]] = ""
                Write-Host ('setting ' + $keyVal[0] + ' to empty')
            }
        }
    }

    # This is after setting user env vars, users cannot override it
    $StartInfo.EnvironmentVariables["PATH"] = $rpath
    if (! $rbinpref -eq '') { $StartInfo.EnvironmentVariables["BINPREF"] = $rbinpref }
    $StartInfo.EnvironmentVariables["TMPDIR"] = ( $home + "\TEMP" )

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
Write-Verbose "Adding BioC repositories..."

Run-R "-q -e `"dir.create(Sys.getenv('R_LIBS_USER'), showWarnings = FALSE, recursive = TRUE)`""
Run-R "-q -e `"install.packages('BiocManager')`""

Add-Content `
  -Value "try(options(repos = BiocManager::repositories())); try(unloadNamespace('BiocManager'))"`
  -Path .Rprofile

Add-Content `
  -Value "if (getRversion() < '3.5.0') { options(repos = c(getOption('repos'), CRANextra = 'http://www.stats.ox.ac.uk/pub/RWin')) }" `
  -Path .Rprofile

# --------------------------------------------------------------------
If ($build -eq "true") {
    Write-Verbose "Running R CMD build..."
    Write-Host ">>>>>============== Running R CMD build"
    tar xzf $Filename
    $tardir=(tar tzf $Filename | select -first 1)
    rm $Filename
    Run-R "CMD build $tardir"
    $Filename=(ls *.tar.gz | select -first 1)[0].Name
}

# --------------------------------------------------------------------
Write-Verbose "Installing package dependencies..."

Write-Host ">>>>>============== Querying package dependencies"

# First we download install-github.R externally, because not all R
# versions support HTTPS. Then we install a version of 'remotes'.

Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/r-lib/remotes/r-hub/install-github.R" `
  -OutFile .\install-github.R

Run-R "-q -e `"source('install-github.R')`$value('r-lib/remotes@r-hub')`""

# Finally, the dependencies

Write-Host ">>>>>============== Installing package dependencies"

If ($RVersion -eq "devel") {
  Run-R "-q -e `"remotes::install_deps('$Filename',dependencies=TRUE,INSTALL_opts='--no-multiarch')`""
} Else {
  Run-R "-q -e `"remotes::install_deps('$Filename',dependencies=TRUE)`""
}

If ($RVersion -eq "devel") {
  Run-R "CMD INSTALL --no-multiarch --build $Filename"
} Else {
  Run-R "CMD INSTALL --build $Filename"
}

# --------------------------------------------------------------------
Write-Verbose ( "Checking " + $Filename )

Write-Host ">>>>>============== Running R CMD check"

Run-R "CMD check $CheckArgs -l $rhome $Filename"

Write-Host ">>>>>============== Done with R CMD check"
Write-Host "+R-HUB-R-HUB-R-HUB Done."
