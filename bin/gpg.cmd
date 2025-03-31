@echo off
if exist "C:\Program Files\GnuPG\bin\gpg.exe" (
    "C:\Program Files\GnuPG\bin\gpg.exe" %*
    exit /b %ERRORLEVEL%
)
if exist "C:\Program Files (x86)\GnuPG\bin\gpg.exe" (
    "C:\Program Files (x86)\GnuPG\bin\gpg.exe" %*
    exit /b %ERRORLEVEL%
)
echo gpg.program: no native GnuPG install found at known paths 1>&2
exit /b 127
