#include "flutter_window.h"

#include <optional>
#include <string>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "system_proxy_controller.h"

namespace {

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

  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() { this->Show(); });
  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::OnDestroy() {
  system_proxy_channel_ = nullptr;
  flutter_controller_ = nullptr;
  Win32Window::OnDestroy();
}

LRESULT FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
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
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
