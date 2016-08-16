
[CmdletBinding()]
Param(
    [Parameter(Mandatory=$True,Position=1)]
    [string]$URL
)

$R = 'C:\Program Files\R\R-devel\bin\R'

# --------------------------------------------------------------------
Write-Verbose ( "Downloading " + $URL )


$filename = $URL.Substring($URL.LastIndexOf("/") + 1)

cd $home

Invoke-WebRequest -Uri $URL -OutFile $filename

# --------------------------------------------------------------------
Write-Verbose ( "Extracting " + $filename )

tar xzf $filename

# --------------------------------------------------------------------
Write-Verbose ( "Checking " + $filename )

$R CMD check $filename
