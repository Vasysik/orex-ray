#include "tray_icon.h"

#include <shellapi.h>

#include <algorithm>
#include <cstdint>
#include <string>
#include <vector>

namespace {

constexpr UINT kTrayIconId = 7701;
constexpr int kIconSize = 32;

std::uint32_t Argb(unsigned char red, unsigned char green, unsigned char blue) {
  return 0xFF000000u | (static_cast<std::uint32_t>(red) << 16) |
         (static_cast<std::uint32_t>(green) << 8) |
         static_cast<std::uint32_t>(blue);
}

std::uint32_t StatusColor(TrayStatus status) {
  switch (status) {
    case TrayStatus::kConnected:
      return Argb(57, 180, 112);
    case TrayStatus::kConnecting:
      return Argb(232, 154, 66);
    case TrayStatus::kDisconnecting:
      return Argb(210, 112, 58);
    case TrayStatus::kError:
      return Argb(210, 78, 95);
    case TrayStatus::kDisconnected:
    default:
      return Argb(126, 126, 126);
  }
}

void CopyTooltip(wchar_t* destination, size_t destination_size,
                 const std::wstring& value) {
  if (destination_size == 0) return;
  wcsncpy_s(destination, destination_size, value.c_str(), _TRUNCATE);
}

}  // namespace

TrayIcon::TrayIcon() = default;

TrayIcon::~TrayIcon() {
  Remove();
  if (status_icon_ != nullptr) {
    DestroyIcon(status_icon_);
    status_icon_ = nullptr;
  }
}

bool TrayIcon::Add(HWND owner, UINT callback_message) {
  owner_ = owner;
  callback_message_ = callback_message;
  if (owner_ == nullptr) return false;

  ApplyIcon();
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = owner_;
  data.uID = kTrayIconId;
  data.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  data.uCallbackMessage = callback_message_;
  data.hIcon = status_icon_;
  CopyTooltip(data.szTip, ARRAYSIZE(data.szTip), TooltipText());

  if (!Shell_NotifyIconW(NIM_ADD, &data)) return false;

  data.uVersion = NOTIFYICON_VERSION_4;
  Shell_NotifyIconW(NIM_SETVERSION, &data);
  added_ = true;
  return true;
}

void TrayIcon::ReAdd() {
  if (owner_ == nullptr) return;
  added_ = false;
  Add(owner_, callback_message_);
}

void TrayIcon::Remove() {
  if (!added_ || owner_ == nullptr) return;
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = owner_;
  data.uID = kTrayIconId;
  Shell_NotifyIconW(NIM_DELETE, &data);
  added_ = false;
}

void TrayIcon::Update(TrayStatus status, const std::wstring& target_name,
                      bool can_disconnect) {
  status_ = status;
  target_name_ = target_name;
  can_disconnect_ = can_disconnect;
  ApplyIcon();

  if (!added_ || owner_ == nullptr) return;
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = owner_;
  data.uID = kTrayIconId;
  data.uFlags = NIF_ICON | NIF_TIP;
  data.hIcon = status_icon_;
  CopyTooltip(data.szTip, ARRAYSIZE(data.szTip), TooltipText());
  Shell_NotifyIconW(NIM_MODIFY, &data);
}

UINT TrayIcon::ShowContextMenu(HWND owner, POINT point) const {
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) return 0;

  const std::wstring status_item = L"Статус: " + StatusText();
  AppendMenuW(menu, MF_STRING | MF_DISABLED | MF_GRAYED, 0,
              status_item.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kCommandOpen, L"Открыть OrexRay");
  AppendMenuW(menu,
              MF_STRING | (can_disconnect_ ? MF_ENABLED : MF_GRAYED),
              kCommandDisconnect, L"Отключить");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kCommandExit, L"Выход");

  SetForegroundWindow(owner);
  const UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, point.x, point.y, 0,
      owner, nullptr);
  DestroyMenu(menu);
  PostMessageW(owner, WM_NULL, 0, 0);
  return command;
}

HICON TrayIcon::CreateStatusIcon(TrayStatus status) const {
  BITMAPV5HEADER bitmap_info{};
  bitmap_info.bV5Size = sizeof(bitmap_info);
  bitmap_info.bV5Width = kIconSize;
  bitmap_info.bV5Height = -kIconSize;
  bitmap_info.bV5Planes = 1;
  bitmap_info.bV5BitCount = 32;
  bitmap_info.bV5Compression = BI_BITFIELDS;
  bitmap_info.bV5RedMask = 0x00FF0000;
  bitmap_info.bV5GreenMask = 0x0000FF00;
  bitmap_info.bV5BlueMask = 0x000000FF;
  bitmap_info.bV5AlphaMask = 0xFF000000;

  void* raw_pixels = nullptr;
  HDC screen = GetDC(nullptr);
  HBITMAP color_bitmap = CreateDIBSection(
      screen, reinterpret_cast<BITMAPINFO*>(&bitmap_info), DIB_RGB_COLORS,
      &raw_pixels, nullptr, 0);
  ReleaseDC(nullptr, screen);
  if (color_bitmap == nullptr || raw_pixels == nullptr) return nullptr;

  auto* pixels = static_cast<std::uint32_t*>(raw_pixels);
  std::fill(pixels, pixels + kIconSize * kIconSize, 0u);

  const std::uint32_t status_color = StatusColor(status);
  const std::uint32_t cream = Argb(255, 239, 218);
  const int center = kIconSize / 2;
  for (int y = 0; y < kIconSize; ++y) {
    for (int x = 0; x < kIconSize; ++x) {
      const int dx = x - center;
      const int dy = y - center;
      const int distance_squared = dx * dx + dy * dy;
      std::uint32_t color = 0u;
      if (distance_squared <= 14 * 14) color = status_color;
      if (distance_squared <= 9 * 9) color = cream;
      if (distance_squared <= 5 * 5) color = status_color;
      pixels[y * kIconSize + x] = color;
    }
  }

  constexpr int mask_stride = ((kIconSize + 15) / 16) * 2;
  const std::vector<std::uint8_t> mask_bits(mask_stride * kIconSize, 0);
  HBITMAP mask_bitmap =
      CreateBitmap(kIconSize, kIconSize, 1, 1, mask_bits.data());
  ICONINFO icon_info{};
  icon_info.fIcon = TRUE;
  icon_info.hbmColor = color_bitmap;
  icon_info.hbmMask = mask_bitmap;
  HICON icon = CreateIconIndirect(&icon_info);
  DeleteObject(mask_bitmap);
  DeleteObject(color_bitmap);
  return icon;
}

std::wstring TrayIcon::StatusText() const {
  switch (status_) {
    case TrayStatus::kConnected:
      return target_name_.empty() ? L"Защищено"
                                  : L"Защищено · " + target_name_;
    case TrayStatus::kConnecting:
      return L"Подключение…";
    case TrayStatus::kDisconnecting:
      return L"Отключение…";
    case TrayStatus::kError:
      return L"Ошибка";
    case TrayStatus::kDisconnected:
    default:
      return L"Не подключено";
  }
}

std::wstring TrayIcon::TooltipText() const {
  return L"OrexRay — " + StatusText();
}

void TrayIcon::ApplyIcon() {
  HICON next_icon = CreateStatusIcon(status_);
  if (next_icon == nullptr) return;
  if (status_icon_ != nullptr) DestroyIcon(status_icon_);
  status_icon_ = next_icon;
}
