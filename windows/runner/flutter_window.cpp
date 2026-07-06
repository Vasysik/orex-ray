#include "flutter_window.h"

#include <shellapi.h>

#include <cstdint>
#include <optional>
#include <string>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "process_job.h"
#include "system_proxy_controller.h"

namespace {

constexpr UINT kTrayCallbackMessage = WM_APP + 77;
constexpr UINT kCompleteExitMessage = WM_APP + 78;
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

TrayStatus ParseTrayStatus(const std::string& value) {
  if (value == "connected") return TrayStatus::kConnected;
  if (value == "connecting") return TrayStatus::kConnecting;
  if (value == "disconnecting") return TrayStatus::kDisconnecting;
  if (value == "error") return TrayStatus::kError;
  return TrayStatus::kDisconnected;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

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

  flutter_controller_->engine()->SetNextFrameCallback([&]() { this->Show(); });
  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::OnDestroy() {
  KillTimer(GetHandle(), kExitFallbackTimerId);
  tray_icon_.Remove();
  lifecycle_channel_ = nullptr;
  system_proxy_channel_ = nullptr;
  flutter_controller_ = nullptr;
  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
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
