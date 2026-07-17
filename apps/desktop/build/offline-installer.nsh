!macro customInstall
  DetailPrint "Installing the offline Hermes framework..."
  ExecWait '"$SYSDIR\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$INSTDIR\resources\offline-payload\install-offline.ps1" -PayloadRoot "$INSTDIR\resources\offline-payload" -HermesHome "$LOCALAPPDATA\hermes" -BrowserRoot "$LOCALAPPDATA\hermes\agent-browser"' $0
  ${If} $0 != 0
    MessageBox MB_ICONSTOP "Hermes framework installation failed with exit code $0."
    Abort
  ${EndIf}
  RMDir /r "$INSTDIR\resources\offline-payload"
!macroend
