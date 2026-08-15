#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "tray_icon.h"
#include "win32_window.h"

class FlutterWindow : public Win32Window {
 public:
  FlutterWindow(const flutter::DartProject& project, bool start_hidden);
  virtual ~FlutterWindow();

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void RestoreWindowPlacement();
  void SaveWindowPlacement();
  void ShowInitialWindow();
  void ShowAndActivate();
  void RequestGracefulExit(UINT fallback_timeout_ms = 0);
  void RequestTrayDisconnect();
  void HandleTrayCommand(UINT command);

  flutter::DartProject project_;
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      system_proxy_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      lifecycle_channel_;
  TrayIcon tray_icon_;
  UINT taskbar_created_message_ = 0;
  bool close_to_tray_ = true;
  bool exit_requested_ = false;
  bool exit_request_pending_ = false;
  bool start_hidden_ = false;
  bool restore_maximized_ = false;
  HANDLE network_change_handle_ = nullptr;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
