#ifndef RUNNER_TRAY_ICON_H_
#define RUNNER_TRAY_ICON_H_

#include <windows.h>

#include <string>

enum class TrayStatus {
  kDisconnected,
  kConnecting,
  kDisconnecting,
  kConnected,
  kTimeout,
  kError,
};

class TrayIcon {
 public:
  static constexpr UINT kCommandOpen = 41001;
  static constexpr UINT kCommandDisconnect = 41002;
  static constexpr UINT kCommandExit = 41003;

  TrayIcon();
  ~TrayIcon();

  bool Add(HWND owner, UINT callback_message);
  void ReAdd();
  void Remove();
  void Update(TrayStatus status, const std::wstring& target_name,
              bool can_disconnect);
  UINT ShowContextMenu(HWND owner, POINT point) const;

 private:
  HICON CreateStatusIcon(TrayStatus status) const;
  std::wstring StatusText() const;
  std::wstring TooltipText() const;
  void ApplyIcon();

  HWND owner_ = nullptr;
  UINT callback_message_ = 0;
  bool added_ = false;
  bool can_disconnect_ = false;
  TrayStatus status_ = TrayStatus::kDisconnected;
  std::wstring target_name_;
  HICON status_icon_ = nullptr;
};

#endif  // RUNNER_TRAY_ICON_H_
