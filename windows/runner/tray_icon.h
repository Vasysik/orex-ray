#ifndef RUNNER_TRAY_ICON_H_
#define RUNNER_TRAY_ICON_H_

#include <windows.h>
#include <cstdint>

#include <string>

enum class TrayStatus {
  kDisconnected,
  kConnecting,
  kDisconnecting,
  kConnected,
  kChecking,
  kUnavailable,
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
              bool can_disconnect, const std::wstring& label,
              std::uint32_t color_rgb, std::uint32_t mark_rgb);
  UINT ShowContextMenu(HWND owner, POINT point) const;

 private:
  HICON CreateStatusIcon() const;
  std::wstring StatusText() const;
  std::wstring TooltipText() const;
  void ApplyIcon();

  HWND owner_ = nullptr;
  UINT callback_message_ = 0;
  bool added_ = false;
  bool can_disconnect_ = false;
  TrayStatus status_ = TrayStatus::kDisconnected;
  // Placeholder until Dart sends the first theme-resolved status color.
  std::uint32_t color_rgb_ = 0xD47939;
  std::uint32_t mark_rgb_ = 0xFCFAFA;
  std::wstring label_;
  std::wstring target_name_;
  HICON status_icon_ = nullptr;
};

#endif  // RUNNER_TRAY_ICON_H_
