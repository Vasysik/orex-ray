#include "tray_icon.h"

#include <shellapi.h>
#include <windows.h>
#include <gdiplus.h>

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <string>
#include <string_view>
#include <vector>

namespace {

using Gdiplus::Bitmap;
using Gdiplus::Color;
using Gdiplus::Graphics;
using Gdiplus::GraphicsPath;
using Gdiplus::Pen;
using Gdiplus::PointF;
using Gdiplus::RectF;
using Gdiplus::SolidBrush;

constexpr UINT kTrayIconId = 7701;
constexpr int kIconSize = 32;

std::wstring WideFromUtf8(std::string_view value) {
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

Color ArgbColor(unsigned char red, unsigned char green, unsigned char blue,
                unsigned char alpha = 255) {
  return Color(alpha, red, green, blue);
}

Color StatusColor(TrayStatus status) {
  switch (status) {
    case TrayStatus::kConnected:
      return ArgbColor(143, 179, 106);
    case TrayStatus::kConnecting:
      return ArgbColor(212, 121, 57);
    case TrayStatus::kDisconnecting:
      return ArgbColor(133, 65, 50);
    case TrayStatus::kTimeout:
    case TrayStatus::kError:
      return ArgbColor(207, 102, 121);
    case TrayStatus::kDisconnected:
    default:
      return ArgbColor(179, 154, 130);
  }
}

Color CreamColor() {
  return ArgbColor(252, 250, 250);
}

void CopyTooltip(wchar_t* destination, size_t destination_size,
                 const std::wstring& value) {
  if (destination_size == 0) return;
  wcsncpy_s(destination, destination_size, value.c_str(), _TRUNCATE);
}

class GdiplusScope {
 public:
  GdiplusScope() {
    Gdiplus::GdiplusStartupInput startup_input;
    active_ = Gdiplus::GdiplusStartup(&token_, &startup_input, nullptr) ==
              Gdiplus::Ok;
  }

  ~GdiplusScope() {
    if (active_) {
      Gdiplus::GdiplusShutdown(token_);
    }
  }

  bool active() const { return active_; }

 private:
  ULONG_PTR token_ = 0;
  bool active_ = false;
};

void AddArcEllipse(GraphicsPath* path, float left, float top, float width,
                   float height, bool reverse = false) {
  if (path == nullptr) return;
  constexpr int kSegments = 24;
  std::vector<PointF> points;
  points.reserve(kSegments + 1);
  for (int index = 0; index <= kSegments; ++index) {
    const float t = static_cast<float>(index) / static_cast<float>(kSegments);
    const float angle = (reverse ? 1.0f - t : t) * 3.14159265f;
    const float x = left + width * 0.5f + std::cos(angle) * width * 0.5f;
    const float y = top + height * 0.5f + std::sin(angle) * height * 0.5f;
    points.push_back(PointF(x, y));
  }
  path->AddLines(points.data(), static_cast<INT>(points.size()));
}

void DrawOrexMark(Graphics* graphics, const RectF& bounds,
                  const Color& foreground) {
  if (graphics == nullptr) return;

  graphics->SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);

  Pen stroke_pen(foreground, 2.0f);
  stroke_pen.SetStartCap(Gdiplus::LineCapRound);
  stroke_pen.SetEndCap(Gdiplus::LineCapRound);
  stroke_pen.SetLineJoin(Gdiplus::LineJoinRound);

  SolidBrush fill_brush(foreground);

  // ===== Globe =====
  const float globe_left = bounds.X + 4.8f;
  const float globe_top = bounds.Y + 3.8f;
  const float globe_size = bounds.Width - 9.6f;
  const RectF globe(globe_left, globe_top, globe_size, globe_size);

  graphics->DrawEllipse(&stroke_pen, globe);

  // Vertical globe arcs
  graphics->DrawArc(&stroke_pen, globe.X + globe.Width * 0.18f, globe.Y + 1.0f,
                    globe.Width * 0.64f, globe.Height - 2.0f, 90.0f, 180.0f);
  graphics->DrawArc(&stroke_pen, globe.X + globe.Width * 0.30f, globe.Y + 1.0f,
                    globe.Width * 0.40f, globe.Height - 2.0f, 90.0f, 180.0f);

  // Horizontal equator
  graphics->DrawLine(&stroke_pen, globe.X + 1.2f, globe.Y + globe.Height / 2.0f,
                     globe.GetRight() - 1.2f, globe.Y + globe.Height / 2.0f);

  // Upper latitude
  graphics->DrawArc(&stroke_pen, globe.X + 4.0f, globe.Y + 5.5f,
                    globe.Width - 8.0f, globe.Height - 21.0f, 200.0f, 140.0f);

  // Lower latitude
  graphics->DrawArc(&stroke_pen, globe.X + 4.0f, globe.Y + globe.Height - 20.5f,
                    globe.Width - 8.0f, globe.Height - 21.0f, 20.0f, 140.0f);

  // ===== Walnut shell =====
  GraphicsPath shell_path;
  shell_path.StartFigure();
  shell_path.AddBezier(PointF(bounds.X + 5.6f, bounds.Y + 20.2f),
                       PointF(bounds.X + 8.5f, bounds.Y + 15.8f),
                       PointF(bounds.X + 12.2f, bounds.Y + 14.2f),
                       PointF(bounds.X + 16.0f, bounds.Y + 14.0f));
  shell_path.AddBezier(PointF(bounds.X + 16.0f, bounds.Y + 14.0f),
                       PointF(bounds.X + 19.8f, bounds.Y + 14.2f),
                       PointF(bounds.X + 23.5f, bounds.Y + 15.8f),
                       PointF(bounds.X + 26.4f, bounds.Y + 20.2f));
  shell_path.AddBezier(PointF(bounds.X + 26.4f, bounds.Y + 20.2f),
                       PointF(bounds.X + 25.2f, bounds.Y + 25.5f),
                       PointF(bounds.X + 21.2f, bounds.Y + 28.8f),
                       PointF(bounds.X + 16.0f, bounds.Y + 29.4f));
  shell_path.AddBezier(PointF(bounds.X + 16.0f, bounds.Y + 29.4f),
                       PointF(bounds.X + 10.8f, bounds.Y + 28.8f),
                       PointF(bounds.X + 6.8f, bounds.Y + 25.5f),
                       PointF(bounds.X + 5.6f, bounds.Y + 20.2f));
  shell_path.CloseFigure();
  graphics->FillPath(&fill_brush, &shell_path);

  // ===== Squirrel body =====
  graphics->FillEllipse(&fill_brush, bounds.X + 10.2f, bounds.Y + 14.6f, 8.4f,
                        10.0f);

  // Head
  graphics->FillEllipse(&fill_brush, bounds.X + 13.4f, bounds.Y + 11.1f, 7.0f,
                        7.0f);

  // Tail
  GraphicsPath tail_path;
  tail_path.StartFigure();
  tail_path.AddBezier(PointF(bounds.X + 18.9f, bounds.Y + 16.0f),
                      PointF(bounds.X + 24.4f, bounds.Y + 10.3f),
                      PointF(bounds.X + 29.2f, bounds.Y + 12.8f),
                      PointF(bounds.X + 27.8f, bounds.Y + 18.0f));
  tail_path.AddBezier(PointF(bounds.X + 27.8f, bounds.Y + 18.0f),
                      PointF(bounds.X + 26.8f, bounds.Y + 22.3f),
                      PointF(bounds.X + 22.7f, bounds.Y + 24.4f),
                      PointF(bounds.X + 18.7f, bounds.Y + 22.1f));
  tail_path.AddBezier(PointF(bounds.X + 18.7f, bounds.Y + 22.1f),
                      PointF(bounds.X + 21.2f, bounds.Y + 19.6f),
                      PointF(bounds.X + 21.3f, bounds.Y + 17.4f),
                      PointF(bounds.X + 18.9f, bounds.Y + 16.0f));
  tail_path.CloseFigure();
  graphics->FillPath(&fill_brush, &tail_path);

  // Left ear
  GraphicsPath ear_left;
  ear_left.StartFigure();
  ear_left.AddLine(PointF(bounds.X + 12.0f, bounds.Y + 11.9f),
                   PointF(bounds.X + 13.0f, bounds.Y + 7.8f));
  ear_left.AddLine(PointF(bounds.X + 13.0f, bounds.Y + 7.8f),
                   PointF(bounds.X + 15.8f, bounds.Y + 10.8f));
  ear_left.CloseFigure();
  graphics->FillPath(&fill_brush, &ear_left);

  // Right ear
  GraphicsPath ear_right;
  ear_right.StartFigure();
  ear_right.AddLine(PointF(bounds.X + 19.0f, bounds.Y + 11.9f),
                    PointF(bounds.X + 20.0f, bounds.Y + 8.0f));
  ear_right.AddLine(PointF(bounds.X + 20.0f, bounds.Y + 8.0f),
                    PointF(bounds.X + 17.2f, bounds.Y + 10.8f));
  ear_right.CloseFigure();
  graphics->FillPath(&fill_brush, &ear_right);
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

  const std::wstring status_item =
      WideFromUtf8(u8"Статус: ") + StatusText();
  AppendMenuW(menu, MF_STRING | MF_DISABLED | MF_GRAYED, 0,
              status_item.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  const std::wstring open_item = WideFromUtf8(u8"Открыть OrexRay");
  AppendMenuW(menu, MF_STRING, kCommandOpen, open_item.c_str());
  const std::wstring disconnect_item = WideFromUtf8(u8"Отключить");
  AppendMenuW(menu,
              MF_STRING | (can_disconnect_ ? MF_ENABLED : MF_GRAYED),
              kCommandDisconnect, disconnect_item.c_str());
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  const std::wstring exit_item = WideFromUtf8(u8"Выход");
  AppendMenuW(menu, MF_STRING, kCommandExit, exit_item.c_str());

  SetForegroundWindow(owner);
  const UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, point.x, point.y, 0,
      owner, nullptr);
  DestroyMenu(menu);
  PostMessageW(owner, WM_NULL, 0, 0);
  return command;
}

HICON TrayIcon::CreateStatusIcon(TrayStatus status) const {
  GdiplusScope gdiplus;
  if (!gdiplus.active()) return nullptr;

  Bitmap bitmap(kIconSize, kIconSize, PixelFormat32bppARGB);
  Graphics graphics(&bitmap);
  graphics.Clear(Color(0, 0, 0, 0));
  graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);
  graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
  graphics.SetPixelOffsetMode(Gdiplus::PixelOffsetModeHighQuality);

  SolidBrush background(StatusColor(status));
  graphics.FillEllipse(&background, 0.0f, 0.0f, static_cast<Gdiplus::REAL>(kIconSize),
                       static_cast<Gdiplus::REAL>(kIconSize));

  DrawOrexMark(&graphics, RectF(0.0f, 0.0f,
                                static_cast<Gdiplus::REAL>(kIconSize),
                                static_cast<Gdiplus::REAL>(kIconSize)),
               CreamColor());

  HBITMAP color_bitmap = nullptr;
  if (bitmap.GetHBITMAP(Color(0, 0, 0, 0), &color_bitmap) != Gdiplus::Ok ||
      color_bitmap == nullptr) {
    return nullptr;
  }

  constexpr int mask_stride = ((kIconSize + 15) / 16) * 2;
  const std::vector<std::uint8_t> mask_bits(mask_stride * kIconSize, 0);
  HBITMAP mask_bitmap =
      CreateBitmap(kIconSize, kIconSize, 1, 1, mask_bits.data());
  if (mask_bitmap == nullptr) {
    DeleteObject(color_bitmap);
    return nullptr;
  }

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
      return target_name_.empty() ? WideFromUtf8(u8"Защищено")
                                  : WideFromUtf8(u8"Защищено · ") + target_name_;
    case TrayStatus::kConnecting:
      return WideFromUtf8(u8"Подключение…");
    case TrayStatus::kDisconnecting:
      return WideFromUtf8(u8"Отключение…");
    case TrayStatus::kTimeout:
      return WideFromUtf8(u8"Таймаут");
    case TrayStatus::kError:
      return WideFromUtf8(u8"Ошибка");
    case TrayStatus::kDisconnected:
    default:
      return WideFromUtf8(u8"Не подключено");
  }
}

std::wstring TrayIcon::TooltipText() const {
  return WideFromUtf8(u8"OrexRay — ") + StatusText();
}

void TrayIcon::ApplyIcon() {
  HICON next_icon = CreateStatusIcon(status_);
  if (next_icon == nullptr) return;
  if (status_icon_ != nullptr) DestroyIcon(status_icon_);
  status_icon_ = next_icon;
}
