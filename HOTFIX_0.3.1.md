# OrexRay 0.3.1 hotfix

## Windows

The application manifest now uses `asInvoker`, so `flutter run -d windows` can launch the debug build from a normal terminal.

TUN still may require administrator privileges. For an elevated runtime test, use:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\run_windows_admin.ps1
```

This builds the Windows debug executable and launches it through UAC.

## Android

The Android APK already builds. `INSTALL_FAILED_USER_RESTRICTED: Install canceled by user` is a device-side install restriction or a rejected installation confirmation, not a Gradle compilation failure.
