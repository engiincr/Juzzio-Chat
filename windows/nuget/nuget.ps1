# Juzzio — "nuget install <Paket> -Version <Sürüm> -ExcludeVersion -OutputDirectory <Klasör>"
# komutunu kurulu .NET SDK ile karşılar (nuget.exe gerekmez). Paketler nuget.org'dan iner.
param([Parameter(Position = 0)][string]$Command, [Parameter(Position = 1)][string]$Package,
      [string]$Version, [switch]$ExcludeVersion, [string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
if ($Command -ne 'install' -or -not $Package -or -not $Version -or -not $OutputDirectory) {
  Write-Error "Desteklenmeyen kullanım: nuget $Command $Package"; exit 1
}
$folder = if ($ExcludeVersion) { $Package } else { "$Package.$Version" }
$dest = Join-Path (Resolve-Path -LiteralPath (New-Item -ItemType Directory -Force -Path $OutputDirectory)).Path $folder
if ((Test-Path $dest) -and (Get-ChildItem $dest -ErrorAction SilentlyContinue)) { Write-Host "$Package zaten var"; exit 0 }
$work = Join-Path ([IO.Path]::GetTempPath()) ("juzzio-nuget-" + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
try {
  $proj = @"
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup><TargetFramework>netstandard2.0</TargetFramework></PropertyGroup>
  <ItemGroup><PackageDownload Include="$Package" Version="[$Version]" /></ItemGroup>
</Project>
"@
  Set-Content -Path (Join-Path $work 'restore.csproj') -Value $proj -Encoding UTF8
  $pk = Join-Path $work 'pk'
  & dotnet restore (Join-Path $work 'restore.csproj') --packages $pk --source https://api.nuget.org/v3/index.json | Out-Host
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  $src = Join-Path (Join-Path $pk $Package.ToLowerInvariant()) $Version.ToLowerInvariant()
  if (-not (Test-Path $src)) { Write-Error "$Package $Version indirilemedi"; exit 1 }
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  Copy-Item -Path (Join-Path $src '*') -Destination $dest -Recurse -Force
  Write-Host "$Package $Version -> $dest"
} finally {
  Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
