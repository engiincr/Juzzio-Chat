@echo off
rem Juzzio: nuget.exe yoksa flutter_inappwebview_windows'un "nuget install" cagrisini
rem kurulu .NET SDK (dotnet restore) ile karsilar. Paketler nuget.org'dan iner.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0nuget.ps1" %*
exit /b %errorlevel%
