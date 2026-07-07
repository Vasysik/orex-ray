#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <netioapi.h>

#include "flutter_window.h"

#include <shellapi.h>
#include <shlobj.h>

#include <cstdint>
#include <cwchar>
#include <optional>
#include <string>
#include <vector>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "process_job.h"
#include "system_proxy_controller.h"
#include "utils.h"

namespace {

constexpr UINT kTrayCallbackMessage = WM_APP + 77;
constexpr UINT kCompleteExitMessage = WM_APP + 78;
constexpr UINT kNetworkChangedMessage = WM_APP + 79;
constexpr UINT_PTR kExitFallbackTimerId = 7704;
constexpr UINT kExitFallbackTimeoutMs = 15000;

const flutter::EncodableMap* AsMap(const flutter::EncodableValue* value) {
  return value == nullptr ? nullptr : std::get_if<flutter::EncodableMap>(value);
}

std::string ReadStringArgument(const flutter::EncodableMap& arguments,
                               const char* key) {
  const auto iterator = arguments.find(flutter::EncodableValue(key));
  if (iterator == arguments.end()) return std::string();
  const auto* value = std::get_if<std::string>(&iterator->second);
  return value == nullptr ? std::string() : *value;
}

bool ReadBoolArgument(const flutter::EncodableMap& arguments, const char* key,
                      bool fallback = false) {
  const auto iterator = arguments.find(flutter::EncodableValue(key));
  if (iterator == arguments.end()) return fallback;
  const auto* value = std::get_if<bool>(&iterator->second);
  return value == nullptr ? fallback : *value;
}

std::optional<std::int64_t> ReadIntArgument(
    const flutter::EncodableMap& arguments, const char* key) {
  const auto iterator = arguments.find(flutter::EncodableValue(key));
  if (iterator == arguments.end()) return std::nullopt;
  if (const auto* value = std::get_if<std::int32_t>(&iterator->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<std::int64_t>(&iterator->second)) {
    return *value;
  }
  return std::nullopt;
}

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return std::wstring();
  const int length = MultiByteToWideChar(
      CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  if (length <= 0) return std::wstring();

  std::wstring result(length, L'\0');
  if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                          static_cast<int>(value.size()), result.data(),
                          length) <= 0) {
    return std::wstring();
  }
  return result;
}

bool IsProcessElevated() {
  HANDLE token = nullptr;
  if (!OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) return false;
  TOKEN_ELEVATION elevation{};
  DWORD size = 0;
  const bool elevated =
      GetTokenInformation(token, TokenElevation, &elevation, sizeof(elevation),
                          &size) != FALSE &&
      elevation.TokenIsElevated != 0;
  CloseHandle(token);
  return elevated;
}

std::wstring ModulePath() {
  std::wstring buffer(MAX_PATH, L'\0');
  for (;;) {
    const DWORD length = GetModuleFileNameW(
        nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    if (length == 0) return std::wstring();
    if (length < buffer.size()) {
      buffer.resize(length);
      return buffer;
    }
    buffer.resize(buffer.size() * 2);
  }
}


constexpr wchar_t kStartupRegistryPath[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr wchar_t kStartupValueName[] = L"OrexRay";

bool SetStartupEnabled(bool enabled) {
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kStartupRegistryPath, 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return false;
  }
  LONG status = ERROR_SUCCESS;
  if (enabled) {
    const std::wstring executable = ModulePath();
    if (executable.empty()) {
      RegCloseKey(key);
      return false;
    }
    const std::wstring command = L"\"" + executable +
                                 L"\" --orexray-autostart";
    status = RegSetValueExW(
        key, kStartupValueName, 0, REG_SZ,
        reinterpret_cast<const BYTE*>(command.c_str()),
        static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  } else {
    status = RegDeleteValueW(key, kStartupValueName);
    if (status == ERROR_FILE_NOT_FOUND) status = ERROR_SUCCESS;
  }
  RegCloseKey(key);
  return status == ERROR_SUCCESS;
}

std::string BestOutboundInterfaceName() {
  DWORD interface_index = 0;
  // 1.1.1.1 is byte-order invariant, so this avoids Winsock initialization.
  if (GetBestInterface(0x01010101, &interface_index) != NO_ERROR) {
    return std::string();
  }

  ULONG size = 0;
  GetAdaptersAddresses(AF_UNSPEC, GAA_FLAG_INCLUDE_PREFIX, nullptr, nullptr,
                       &size);
  if (size == 0) return std::string();
  std::vector<unsigned char> buffer(size);
  auto* adapters = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
  if (GetAdaptersAddresses(AF_UNSPEC, GAA_FLAG_INCLUDE_PREFIX, nullptr,
                           adapters, &size) != NO_ERROR) {
    return std::string();
  }
  for (auto* adapter = adapters; adapter != nullptr; adapter = adapter->Next) {
    if (adapter->IfIndex != interface_index &&
        adapter->Ipv6IfIndex != interface_index) {
      continue;
    }
    if (adapter->OperStatus != IfOperStatusUp ||
        adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK ||
        adapter->FriendlyName == nullptr) {
      return std::string();
    }
    return Utf8FromUtf16(adapter->FriendlyName);
  }
  return std::string();
}

std::wstring KnownFolderPath(REFKNOWNFOLDERID folder_id) {
  PWSTR raw_path = nullptr;
  if (FAILED(SHGetKnownFolderPath(folder_id, KF_FLAG_DEFAULT, nullptr,
                                  &raw_path)) ||
      raw_path == nullptr) {
    return std::wstring();
  }
  const std::wstring path(raw_path);
  CoTaskMemFree(raw_path);
  return path;
}

bool IsPathInsideDirectory(const std::wstring& path,
                           const std::wstring& directory) {
  if (path.empty() || directory.empty()) return false;
  std::wstring prefix = directory;
  while (!prefix.empty() &&
         (prefix.back() == L'\\' || prefix.back() == L'/')) {
    prefix.pop_back();
  }
  prefix.push_back(L'\\');
  if (path.size() <= prefix.size()) return false;
  return _wcsnicmp(path.c_str(), prefix.c_str(), prefix.size()) == 0;
}

bool IsProtectedInstall() {
  const std::wstring executable = ModulePath();
  if (executable.empty()) return false;
  const KNOWNFOLDERID* folders[] = {
      &FOLDERID_ProgramFiles,
      &FOLDERID_ProgramFilesX64,
      &FOLDERID_ProgramFilesX86,
  };
  for (const KNOWNFOLDERID* folder : folders) {
    if (IsPathInsideDirectory(executable, KnownFolderPath(*folder))) {
      return true;
    }
  }
  return false;
}

bool RestartElevated() {
  if (!IsProtectedInstall()) return false;
  const std::wstring executable = ModulePath();
  if (executable.empty()) return false;
  const size_t separator = executable.find_last_of(L"\\/");
  const std::wstring working_directory = separator == std::wstring::npos
      ? std::wstring()
      : executable.substr(0, separator);

  SHELLEXECUTEINFOW info{};
  info.cbSize = sizeof(info);
  info.fMask = SEE_MASK_NOCLOSEPROCESS;
  info.lpVerb = L"runas";
  info.lpFile = executable.c_str();
  const bool started_at_login =
      wcsstr(GetCommandLineW(), L"--orexray-autostart") != nullptr;
  const std::wstring parameters = started_at_login
      ? L"--orexray-elevated-restart --orexray-autostart"
      : L"--orexray-elevated-restart";
  info.lpParameters = parameters.c_str();
  info.lpDirectory =
      working_directory.empty() ? nullptr : working_directory.c_str();
  info.nShow = SW_SHOWNORMAL;
  if (!ShellExecuteExW(&info)) return false;
  if (info.hProcess != nullptr) CloseHandle(info.hProcess);
  return true;
}

TrayStatus ParseTrayStatus(const std::string& value) {
  if (value == "connected") return TrayStatus::kConnected;
  if (value == "connecting") return TrayStatus::kConnecting;
  if (value == "disconnecting") return TrayStatus::kDisconnecting;
  if (value == "error") return TrayStatus::kError;
  return TrayStatus::kDisconnected;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project, bool start_hidden)
    : project_(project), start_hidden_(start_hidden) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());

  system_proxy_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "ru.orex.ray/system_proxy",
          &flutter::StandardMethodCodec::GetInstance());

  system_proxy_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "getState") {
          result->Success(
              flutter::EncodableValue(orexray::ReadSystemProxyState()));
          return;
        }

        if (call.method_name() == "setProxy") {
          const auto* arguments = AsMap(call.arguments());
          if (arguments == nullptr) {
            result->Error("invalid_arguments", "Proxy arguments are missing");
            return;
          }

          const std::string server = ReadStringArgument(*arguments, "server");
          const std::string bypass = ReadStringArgument(*arguments, "bypass");
          if (server.empty()) {
            result->Error("invalid_arguments", "Proxy server is empty");
            return;
          }

          std::string error;
          if (!orexray::SetSystemProxy(server, bypass, &error)) {
            result->Error("proxy_apply_failed", error);
            return;
          }
          result->Success(flutter::EncodableValue());
          return;
        }

        if (call.method_name() == "restore") {
          const auto* arguments = AsMap(call.arguments());
          if (arguments == nullptr) {
            result->Error("invalid_arguments", "Proxy state is missing");
            return;
          }

          std::string error;
          if (!orexray::RestoreSystemProxy(*arguments, &error)) {
            result->Error("proxy_restore_failed", error);
            return;
          }
          result->Success(flutter::EncodableValue());
          return;
        }

        result->NotImplemented();
      });

  lifecycle_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "ru.orex.ray/windows_lifecycle",
          &flutter::StandardMethodCodec::GetInstance());

  lifecycle_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "isProcessElevated") {
          result->Success(flutter::EncodableValue(IsProcessElevated()));
          return;
        }

        if (call.method_name() == "isProtectedInstall") {
          result->Success(flutter::EncodableValue(IsProtectedInstall()));
          return;
        }

        if (call.method_name() == "restartElevated") {
          if (!IsProtectedInstall()) {
            result->Error(
                "unsafe_install_location",
                "Automatic elevation is only allowed from Program Files");
            return;
          }
          result->Success(flutter::EncodableValue(RestartElevated()));
          return;
        }

        if (call.method_name() == "setCloseToTray") {
          const auto* value = call.arguments() == nullptr
                                  ? nullptr
                                  : std::get_if<bool>(call.arguments());
          if (value == nullptr) {
            result->Error("invalid_arguments", "Expected a boolean value");
            return;
          }
          close_to_tray_ = *value;
          result->Success(flutter::EncodableValue());
          return;
        }

        if (call.method_name() == "updateTray") {
          const auto* arguments = AsMap(call.arguments());
          if (arguments == nullptr) {
            result->Error("invalid_arguments", "Tray state is missing");
            return;
          }
          tray_icon_.Update(
              ParseTrayStatus(ReadStringArgument(*arguments, "status")),
              Utf8ToWide(ReadStringArgument(*arguments, "targetName")),
              ReadBoolArgument(*arguments, "canDisconnect"));
          result->Success(flutter::EncodableValue());
          return;
        }

        if (call.method_name() == "attachProcess") {
          const auto* arguments = AsMap(call.arguments());
          const auto process_id = arguments == nullptr
                                      ? std::nullopt
                                      : ReadIntArgument(*arguments, "pid");
          if (!process_id.has_value() || process_id.value() <= 0 ||
              process_id.value() > MAXDWORD) {
            result->Error("invalid_arguments", "Process id is invalid");
            return;
          }

          std::string error;
          if (!orexray::AttachProcessToJob(
                  static_cast<DWORD>(process_id.value()), &error)) {
            result->Error("job_attach_failed", error);
            return;
          }
          result->Success(flutter::EncodableValue());
          return;
        }

        if (call.method_name() == "terminateProcessesByPath") {
          const auto* arguments = AsMap(call.arguments());
          const std::string path = arguments == nullptr
                                       ? std::string()
                                       : ReadStringArgument(*arguments, "path");
          if (path.empty()) {
            result->Error("invalid_arguments", "Executable path is empty");
            return;
          }

          std::string error;
          const int terminated =
              orexray::TerminateProcessesByExecutablePath(path, &error);
          if (terminated < 0) {
            result->Error("process_cleanup_failed", error);
            return;
          }
          result->Success(flutter::EncodableValue(terminated));
          return;
        }

        if (call.method_name() == "setStartupEnabled") {
          const auto* value = call.arguments() == nullptr
                                  ? nullptr
                                  : std::get_if<bool>(call.arguments());
          if (value == nullptr) {
            result->Error("invalid_arguments", "Expected a boolean value");
            return;
          }
          if (!SetStartupEnabled(*value)) {
            result->Error("startup_update_failed",
                          "Could not update Windows startup registration");
            return;
          }
          result->Success(flutter::EncodableValue());
          return;
        }

        if (call.method_name() == "getBestOutboundInterface") {
          result->Success(flutter::EncodableValue(BestOutboundInterfaceName()));
          return;
        }

        if (call.method_name() == "completeExit") {
          KillTimer(GetHandle(), kExitFallbackTimerId);
          exit_requested_ = true;
          exit_request_pending_ = false;
          result->Success(flutter::EncodableValue());
          PostMessageW(GetHandle(), kCompleteExitMessage, 0, 0);
          return;
        }

        result->NotImplemented();
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");
  tray_icon_.Add(GetHandle(), kTrayCallbackMessage);

  NotifyIpInterfaceChange(
      AF_UNSPEC,
      [](PVOID context, PMIB_IPINTERFACE_ROW, MIB_NOTIFICATION_TYPE) {
        const HWND window = reinterpret_cast<HWND>(context);
        if (window != nullptr) PostMessageW(window, kNetworkChangedMessage, 0, 0);
      },
      reinterpret_cast<PVOID>(GetHandle()), FALSE, &network_change_handle_);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) this->Show();
  });
  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::OnDestroy() {
  KillTimer(GetHandle(), kExitFallbackTimerId);
  if (network_change_handle_ != nullptr) {
    CancelMibChangeNotify2(network_change_handle_);
    network_change_handle_ = nullptr;
  }
  tray_icon_.Remove();
  lifecycle_channel_ = nullptr;
  system_proxy_channel_ = nullptr;
  flutter_controller_ = nullptr;
  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_POWERBROADCAST && wparam == PBT_APMRESUMEAUTOMATIC) {
    if (lifecycle_channel_ != nullptr) {
      lifecycle_channel_->InvokeMethod("powerResume", nullptr);
    }
    return TRUE;
  }

  if (message == kNetworkChangedMessage) {
    if (lifecycle_channel_ != nullptr) {
      lifecycle_channel_->InvokeMethod("networkChanged", nullptr);
    }
    return 0;
  }

  if (message == WM_CLOSE) {
    if (close_to_tray_ && !exit_requested_) {
      ShowWindow(hwnd, SW_HIDE);
      return 0;
    }
    RequestGracefulExit();
    return 0;
  }

  if (message == kCompleteExitMessage) {
    Destroy();
    return 0;
  }

  if (message == WM_TIMER && wparam == kExitFallbackTimerId) {
    KillTimer(hwnd, kExitFallbackTimerId);
    if (exit_request_pending_) {
      exit_requested_ = true;
      exit_request_pending_ = false;
      PostMessageW(hwnd, kCompleteExitMessage, 0, 0);
    }
    return 0;
  }

  if (taskbar_created_message_ != 0 && message == taskbar_created_message_) {
    tray_icon_.ReAdd();
    return 0;
  }

  if (message == kTrayCallbackMessage) {
    const UINT event = LOWORD(lparam);
    switch (event) {
      case NIN_SELECT:
      case NIN_KEYSELECT:
      case WM_LBUTTONUP:
      case WM_LBUTTONDBLCLK:
        ShowAndActivate();
        return 0;
      case WM_CONTEXTMENU:
      case WM_RBUTTONUP: {
        POINT point{};
        GetCursorPos(&point);
        HandleTrayCommand(tray_icon_.ShowContextMenu(hwnd, point));
        return 0;
      }
      default:
        break;
    }
  }

  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      if (flutter_controller_) {
        flutter_controller_->engine()->ReloadSystemFonts();
      }
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::ShowAndActivate() {
  HWND window = GetHandle();
  if (window == nullptr) return;

  if (IsIconic(window)) {
    ShowWindow(window, SW_RESTORE);
  } else {
    ShowWindow(window, SW_SHOW);
  }
  SetWindowPos(window, HWND_TOP, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  SetForegroundWindow(window);
}

void FlutterWindow::RequestGracefulExit() {
  if (exit_requested_ || exit_request_pending_) return;
  exit_request_pending_ = true;

  if (lifecycle_channel_ == nullptr) {
    exit_requested_ = true;
    exit_request_pending_ = false;
    PostMessageW(GetHandle(), kCompleteExitMessage, 0, 0);
    return;
  }

  SetTimer(GetHandle(), kExitFallbackTimerId, kExitFallbackTimeoutMs, nullptr);
  lifecycle_channel_->InvokeMethod("requestExit", nullptr);
}

void FlutterWindow::RequestTrayDisconnect() {
  if (lifecycle_channel_ == nullptr) return;
  lifecycle_channel_->InvokeMethod("trayDisconnect", nullptr);
}

void FlutterWindow::HandleTrayCommand(UINT command) {
  switch (command) {
    case TrayIcon::kCommandOpen:
      ShowAndActivate();
      break;
    case TrayIcon::kCommandDisconnect:
      RequestTrayDisconnect();
      break;
    case TrayIcon::kCommandExit:
      RequestGracefulExit();
      break;
    default:
      break;
  }
}
