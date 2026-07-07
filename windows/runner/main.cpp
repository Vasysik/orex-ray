#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shellapi.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "process_job.h"
#include "utils.h"

namespace {

constexpr wchar_t kSingleInstanceMutex[] =
    L"Local\\OrexRay.SingleInstance.5A3EA2E2-91F2-4DC7-94D4-4E0B4C5586B2";
constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kWindowTitle[] = L"OrexRay";


bool HasCommandLineFlag(const wchar_t* expected) {
  int argument_count = 0;
  wchar_t** arguments = CommandLineToArgvW(GetCommandLineW(), &argument_count);
  if (arguments == nullptr) return false;
  bool found = false;
  for (int index = 1; index < argument_count; ++index) {
    if (_wcsicmp(arguments[index], expected) == 0) {
      found = true;
      break;
    }
  }
  LocalFree(arguments);
  return found;
}

bool ActivateWindow(HWND window) {
  if (window == nullptr) return false;
  if (IsIconic(window)) {
    ShowWindow(window, SW_RESTORE);
  } else {
    ShowWindow(window, SW_SHOW);
  }
  SetWindowPos(window, HWND_TOP, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  SetForegroundWindow(window);
  return true;
}

bool ActivateExistingInstance(int attempts) {
  // A second process can reach this point while the first process is still
  // between creating the mutex and creating its top-level window.
  for (int attempt = 0; attempt < attempts; ++attempt) {
    if (ActivateWindow(FindWindowW(kWindowClassName, kWindowTitle))) {
      return true;
    }
    if (attempt + 1 < attempts) Sleep(50);
  }
  return false;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  // Never search the current working directory for DLL dependencies. The
  // application directory remains available, and the installer/restart path
  // sets it to the protected Program Files location.
  SetDllDirectoryW(L"");

  const bool elevated_restart =
      HasCommandLineFlag(L"--orexray-elevated-restart");

  // A normal second launch activates the existing window. An elevated restart
  // deliberately waits for the unelevated process to release the mutex.
  if (!elevated_restart && ActivateExistingInstance(1)) {
    return EXIT_SUCCESS;
  }

  HANDLE single_instance = nullptr;
  const int mutex_attempts = elevated_restart ? 100 : 1;
  for (int attempt = 0; attempt < mutex_attempts; ++attempt) {
    single_instance = CreateMutexW(nullptr, FALSE, kSingleInstanceMutex);
    if (single_instance == nullptr) return EXIT_FAILURE;
    if (GetLastError() != ERROR_ALREADY_EXISTS) break;

    CloseHandle(single_instance);
    single_instance = nullptr;
    if (!elevated_restart) {
      ActivateExistingInstance(40);
      return EXIT_SUCCESS;
    }
    Sleep(100);
  }
  if (single_instance == nullptr) return EXIT_FAILURE;

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  orexray::InitializeChildProcessJob(nullptr);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments = GetCommandLineArguments();
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 800);
  if (!window.Create(kWindowTitle, origin, size)) {
    orexray::CloseChildProcessJob();
    ::CoUninitialize();
    CloseHandle(single_instance);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  // Closing the job handle is a final crash-safe backstop: every attached Xray
  // process is terminated even if Dart cleanup could not complete.
  orexray::CloseChildProcessJob();
  ::CoUninitialize();
  CloseHandle(single_instance);
  return EXIT_SUCCESS;
}
