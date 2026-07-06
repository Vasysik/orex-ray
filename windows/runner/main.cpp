#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

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
  // Also catch a still-running pre-single-instance OrexRay build. This keeps a
  // user from accidentally starting the new build next to an older window.
  if (ActivateExistingInstance(1)) {
    return EXIT_SUCCESS;
  }

  HANDLE single_instance =
      CreateMutexW(nullptr, FALSE, kSingleInstanceMutex);
  if (single_instance == nullptr) {
    return EXIT_FAILURE;
  }
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateExistingInstance(40);
    CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }

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
  Win32Window::Size size(1280, 840);
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
