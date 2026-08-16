#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <netioapi.h>

#include "flutter_window.h"

#include <shellapi.h>
#include <shlobj.h>

#include <algorithm>
#include <cstdint>
#include <chrono>
#include <cstring>
#include <limits>
#include <mutex>
#include <thread>
#include <cwchar>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>

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
constexpr UINT kUpdateExitFallbackTimeoutMs = 4000;
constexpr wchar_t kWindowPlacementRegistryPath[] = L"Software\\OrexRay";
constexpr wchar_t kWindowPlacementRegistryValue[] = L"WindowPlacementV1";
constexpr DWORD kWindowPlacementVersion = 1;
constexpr LONG kMinimumWindowWidthDip = 480;
constexpr LONG kMinimumWindowHeightDip = 360;
constexpr LONG kMaximumStoredWindowDimension = 100000;

struct StoredWindowPlacement {
  DWORD version;
  RECT normal_rect;
  DWORD maximized;
  DWORD dpi;
};

bool IsUsableWindowRect(const RECT& rect) {
  const std::int64_t width =
      static_cast<std::int64_t>(rect.right) - rect.left;
  const std::int64_t height =
      static_cast<std::int64_t>(rect.bottom) - rect.top;
  return width > 0 && height > 0 && width <= kMaximumStoredWindowDimension &&
         height <= kMaximumStoredWindowDimension;
}

LONG ScaleForDpi(LONG value, UINT source_dpi, UINT target_dpi) {
  if (value <= 0 || source_dpi == 0 || target_dpi == 0) return value;
  const LONG scaled = MulDiv(value, static_cast<int>(target_dpi),
                             static_cast<int>(source_dpi));
  return scaled > 0 ? scaled : value;
}

LONG ClampWindowDimension(LONG value, LONG minimum, LONG maximum) {
  if (maximum <= 0) return value;
  if (value < minimum) value = minimum;
  return value > maximum ? maximum : value;
}

LONG ClampWindowPosition(LONG value, LONG minimum, LONG maximum) {
  if (maximum < minimum) return minimum;
  if (value < minimum) return minimum;
  return value > maximum ? maximum : value;
}

bool LoadStoredWindowPlacement(StoredWindowPlacement* placement) {
  if (placement == nullptr) return false;

  HKEY key = nullptr;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kWindowPlacementRegistryPath, 0,
                    KEY_QUERY_VALUE, &key) != ERROR_SUCCESS) {
    return false;
  }

  DWORD type = 0;
  DWORD byte_count = static_cast<DWORD>(sizeof(*placement));
  const LONG status = RegQueryValueExW(
      key, kWindowPlacementRegistryValue, nullptr, &type,
      reinterpret_cast<BYTE*>(placement), &byte_count);
  RegCloseKey(key);

  return status == ERROR_SUCCESS && type == REG_BINARY &&
         byte_count == static_cast<DWORD>(sizeof(*placement)) &&
         placement->version == kWindowPlacementVersion &&
         placement->maximized <= 1 && placement->dpi >= 48 &&
         placement->dpi <= 960 && IsUsableWindowRect(placement->normal_rect);
}

void StoreWindowPlacement(const StoredWindowPlacement& placement) {
  HKEY key = nullptr;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kWindowPlacementRegistryPath, 0,
                      nullptr, 0, KEY_SET_VALUE, nullptr, &key,
                      nullptr) != ERROR_SUCCESS) {
    return;
  }

  RegSetValueExW(key, kWindowPlacementRegistryValue, 0, REG_BINARY,
                 reinterpret_cast<const BYTE*>(&placement),
                 static_cast<DWORD>(sizeof(placement)));
  RegCloseKey(key);
}

bool SetHiddenNormalPlacement(HWND window, const RECT& normal_rect) {
  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  placement.showCmd = SW_HIDE;
  placement.rcNormalPosition = normal_rect;
  return SetWindowPlacement(window, &placement) != FALSE;
}

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

bool IsOrexRayInterfaceName(const wchar_t* name) {
  return name != nullptr && _wcsicmp(name, L"OrexRay") == 0;
}

bool IsUsableOutboundAdapter(const IP_ADAPTER_ADDRESSES* adapter) {
  if (adapter == nullptr || adapter->FriendlyName == nullptr ||
      adapter->OperStatus != IfOperStatusUp ||
      adapter->IfType == IF_TYPE_SOFTWARE_LOOPBACK ||
      adapter->IfType == IF_TYPE_TUNNEL ||
      IsOrexRayInterfaceName(adapter->FriendlyName) ||
      adapter->FirstUnicastAddress == nullptr ||
      adapter->FirstGatewayAddress == nullptr) {
    return false;
  }
  return true;
}

ULONG AdapterMetric(const IP_ADAPTER_ADDRESSES* adapter) {
  if (adapter == nullptr) return std::numeric_limits<ULONG>::max();
  const ULONG ipv4 = adapter->Ipv4Metric;
  const ULONG ipv6 = adapter->Ipv6Metric;
  if (ipv4 == 0) return ipv6 == 0 ? std::numeric_limits<ULONG>::max() : ipv6;
  if (ipv6 == 0) return ipv4;
  return ipv4 < ipv6 ? ipv4 : ipv6;
}

std::string BestOutboundInterfaceName() {
  ULONG size = 0;
  constexpr ULONG flags =
      GAA_FLAG_INCLUDE_PREFIX | GAA_FLAG_INCLUDE_GATEWAYS;
  const ULONG initial = GetAdaptersAddresses(
      AF_UNSPEC, flags, nullptr, nullptr, &size);
  if (initial != ERROR_BUFFER_OVERFLOW || size == 0) return std::string();

  std::vector<unsigned char> buffer(size);
  auto* adapters = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
  if (GetAdaptersAddresses(AF_UNSPEC, flags, nullptr, adapters, &size) !=
      NO_ERROR) {
    return std::string();
  }

  DWORD best_route_index = 0;
  // Prefer Windows' current route decision when it still points to a usable
  // physical adapter. The OrexRay TUN can own the default route while running,
  // so a fallback scan below intentionally excludes the managed TUN adapter.
  const bool has_best_route =
      GetBestInterface(0x01010101, &best_route_index) == NO_ERROR;

  const IP_ADAPTER_ADDRESSES* fallback = nullptr;
  ULONG fallback_metric = std::numeric_limits<ULONG>::max();
  for (auto* adapter = adapters; adapter != nullptr; adapter = adapter->Next) {
    if (!IsUsableOutboundAdapter(adapter)) continue;

    if (has_best_route &&
        (adapter->IfIndex == best_route_index ||
         adapter->Ipv6IfIndex == best_route_index)) {
      return Utf8FromUtf16(adapter->FriendlyName);
    }

    const ULONG metric = AdapterMetric(adapter);
    if (fallback == nullptr || metric < fallback_metric) {
      fallback = adapter;
      fallback_metric = metric;
    }
  }

  return fallback == nullptr ? std::string()
                             : Utf8FromUtf16(fallback->FriendlyName);
}

bool IsManagedTunNotification(const PMIB_IPINTERFACE_ROW row) {
  if (row == nullptr) return false;
  wchar_t alias[IF_MAX_STRING_SIZE + 1] = {};
  if (ConvertInterfaceLuidToAlias(&row->InterfaceLuid, alias,
                                  ARRAYSIZE(alias)) != NO_ERROR) {
    return false;
  }
  return IsOrexRayInterfaceName(alias);
}

std::string InterfaceNameForIndex(NET_IFINDEX index) {
  if (index == 0) return std::string();
  NET_LUID luid{};
  if (ConvertInterfaceIndexToLuid(index, &luid) != NO_ERROR) {
    return std::string();
  }
  wchar_t alias[IF_MAX_STRING_SIZE + 1] = {};
  if (ConvertInterfaceLuidToAlias(&luid, alias, ARRAYSIZE(alias)) != NO_ERROR) {
    return std::string();
  }
  return Utf8FromUtf16(alias);
}

std::string BestIpv4RouteInterfaceName() {
  DWORD index = 0;
  if (GetBestInterface(0x01010101, &index) != NO_ERROR) return std::string();
  return InterfaceNameForIndex(index);
}

std::string BestIpv6RouteInterfaceName() {
  sockaddr_in6 destination{};
  destination.sin6_family = AF_INET6;
  const unsigned char address[16] = {
      0x26, 0x06, 0x47, 0x00, 0x47, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x11, 0x11,
  };
  memcpy(&destination.sin6_addr, address, sizeof(address));
  DWORD index = 0;
  if (GetBestInterfaceEx(reinterpret_cast<sockaddr*>(&destination), &index) !=
      NO_ERROR) {
    return std::string();
  }
  return InterfaceNameForIndex(index);
}

flutter::EncodableMap TunRouteStatus() {
  const std::string ipv4 = BestIpv4RouteInterfaceName();
  const std::string ipv6 = BestIpv6RouteInterfaceName();
  return flutter::EncodableMap{
      {flutter::EncodableValue("ipv4Interface"), flutter::EncodableValue(ipv4)},
      {flutter::EncodableValue("ipv6Interface"), flutter::EncodableValue(ipv6)},
      {flutter::EncodableValue("ipv4Captured"),
       flutter::EncodableValue(ipv4 == "OrexRay")},
      {flutter::EncodableValue("ipv6Captured"),
       flutter::EncodableValue(ipv6 == "OrexRay")},
  };
}

enum class DirectLatencyStatus {
  kSuccess,
  kTimeout,
  kUnavailable,
  kSkipped,
};

struct DirectLatencyResult {
  DirectLatencyStatus status;
  std::int32_t latency_ms = 0;
};

bool EnsureWinsock() {
  static std::once_flag once;
  static bool initialized = false;
  std::call_once(once, []() {
    WSADATA data{};
    initialized = WSAStartup(MAKEWORD(2, 2), &data) == 0;
  });
  return initialized;
}

bool AdapterSupportsFamily(const IP_ADAPTER_ADDRESSES* adapter, int family) {
  if (adapter == nullptr) return false;
  for (auto* address = adapter->FirstUnicastAddress; address != nullptr;
       address = address->Next) {
    const SOCKADDR* socket_address = address->Address.lpSockaddr;
    if (socket_address != nullptr && socket_address->sa_family == family) {
      return true;
    }
  }
  return false;
}

ULONG AdapterMetricForFamily(const IP_ADAPTER_ADDRESSES* adapter,
                             int family) {
  if (adapter == nullptr) return std::numeric_limits<ULONG>::max();
  const ULONG metric = family == AF_INET6 ? adapter->Ipv6Metric
                                          : adapter->Ipv4Metric;
  return metric == 0 ? std::numeric_limits<ULONG>::max() : metric;
}

const IP_ADAPTER_ADDRESSES* BestPhysicalAdapterForFamily(
    const IP_ADAPTER_ADDRESSES* adapters,
    int family) {
  const IP_ADAPTER_ADDRESSES* best = nullptr;
  ULONG best_metric = std::numeric_limits<ULONG>::max();
  for (auto* adapter = adapters; adapter != nullptr; adapter = adapter->Next) {
    if (!IsUsableOutboundAdapter(adapter) ||
        !AdapterSupportsFamily(adapter, family)) {
      continue;
    }
    const ULONG metric = AdapterMetricForFamily(adapter, family);
    if (best == nullptr || metric < best_metric) {
      best = adapter;
      best_metric = metric;
    }
  }
  return best;
}

DirectLatencyStatus ConnectDirectlyOnAdapter(
    const ADDRINFOW* address,
    const IP_ADAPTER_ADDRESSES* adapter,
    DWORD timeout_ms) {
  if (address == nullptr || adapter == nullptr || timeout_ms == 0) {
    return DirectLatencyStatus::kSkipped;
  }

  const int family = address->ai_family;
  const DWORD interface_index = family == AF_INET6 ? adapter->Ipv6IfIndex
                                                     : adapter->IfIndex;
  if (interface_index == 0) return DirectLatencyStatus::kSkipped;

  SOCKET socket = WSASocketW(
      family, SOCK_STREAM, IPPROTO_TCP, nullptr, 0, WSA_FLAG_OVERLAPPED);
  if (socket == INVALID_SOCKET) return DirectLatencyStatus::kUnavailable;

  auto close_socket = [&socket]() {
    if (socket != INVALID_SOCKET) {
      closesocket(socket);
      socket = INVALID_SOCKET;
    }
  };

  // `IP_UNICAST_IF` uses a network-byte-order index for IPv4, while the IPv6
  // variant uses host byte order. Binding the socket itself—not a temporary
  // route—keeps profile checks outside OrexRay's Wintun default route.
  const int interface_level = family == AF_INET6 ? IPPROTO_IPV6 : IPPROTO_IP;
  const int interface_option =
      family == AF_INET6 ? IPV6_UNICAST_IF : IP_UNICAST_IF;
  const DWORD interface_value =
      family == AF_INET6 ? interface_index : htonl(interface_index);
  if (setsockopt(socket, interface_level, interface_option,
                 reinterpret_cast<const char*>(&interface_value),
                 sizeof(interface_value)) == SOCKET_ERROR) {
    close_socket();
    return DirectLatencyStatus::kSkipped;
  }

  u_long nonblocking = 1;
  if (ioctlsocket(socket, FIONBIO, &nonblocking) == SOCKET_ERROR) {
    close_socket();
    return DirectLatencyStatus::kUnavailable;
  }

  const int connect_result = connect(socket, address->ai_addr,
                                     static_cast<int>(address->ai_addrlen));
  if (connect_result == 0) {
    close_socket();
    return DirectLatencyStatus::kSuccess;
  }

  const int connect_error = WSAGetLastError();
  if (connect_error != WSAEWOULDBLOCK && connect_error != WSAEINPROGRESS &&
      connect_error != WSAEALREADY) {
    close_socket();
    return connect_error == WSAETIMEDOUT ? DirectLatencyStatus::kTimeout
                                         : DirectLatencyStatus::kUnavailable;
  }

  fd_set write_set;
  fd_set error_set;
  FD_ZERO(&write_set);
  FD_ZERO(&error_set);
  FD_SET(socket, &write_set);
  FD_SET(socket, &error_set);
  timeval wait{};
  wait.tv_sec = static_cast<long>(timeout_ms / 1000);
  wait.tv_usec = static_cast<long>((timeout_ms % 1000) * 1000);
  const int selected = select(0, nullptr, &write_set, &error_set, &wait);
  if (selected == 0) {
    close_socket();
    return DirectLatencyStatus::kTimeout;
  }
  if (selected == SOCKET_ERROR) {
    close_socket();
    return DirectLatencyStatus::kUnavailable;
  }

  int socket_error = 0;
  int socket_error_length = sizeof(socket_error);
  if (getsockopt(socket, SOL_SOCKET, SO_ERROR,
                 reinterpret_cast<char*>(&socket_error),
                 &socket_error_length) == SOCKET_ERROR) {
    close_socket();
    return DirectLatencyStatus::kUnavailable;
  }
  close_socket();
  if (socket_error == 0) return DirectLatencyStatus::kSuccess;
  return socket_error == WSAETIMEDOUT ? DirectLatencyStatus::kTimeout
                                      : DirectLatencyStatus::kUnavailable;
}

DirectLatencyResult MeasureDirectTcpLatency(const std::string& host,
                                            int port,
                                            DWORD timeout_ms) {
  if (host.empty() || port < 1 || port > 65535 || timeout_ms < 100 ||
      timeout_ms > 10000 || !EnsureWinsock()) {
    return {DirectLatencyStatus::kSkipped};
  }

  const std::wstring wide_host = Utf8ToWide(host);
  if (wide_host.empty()) return {DirectLatencyStatus::kUnavailable};

  const auto started = std::chrono::steady_clock::now();
  ADDRINFOW hints{};
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  hints.ai_protocol = IPPROTO_TCP;
  hints.ai_flags = AI_ADDRCONFIG;
  ADDRINFOW* addresses = nullptr;
  const std::wstring service = std::to_wstring(port);
  if (GetAddrInfoW(wide_host.c_str(), service.c_str(), &hints, &addresses) !=
      0) {
    return {DirectLatencyStatus::kUnavailable};
  }

  ULONG adapter_bytes = 0;
  constexpr ULONG adapter_flags =
      GAA_FLAG_INCLUDE_PREFIX | GAA_FLAG_INCLUDE_GATEWAYS;
  const ULONG adapter_initial = GetAdaptersAddresses(
      AF_UNSPEC, adapter_flags, nullptr, nullptr, &adapter_bytes);
  if (adapter_initial != ERROR_BUFFER_OVERFLOW || adapter_bytes == 0) {
    FreeAddrInfoW(addresses);
    return {DirectLatencyStatus::kSkipped};
  }
  std::vector<unsigned char> adapter_buffer(adapter_bytes);
  auto* adapters =
      reinterpret_cast<IP_ADAPTER_ADDRESSES*>(adapter_buffer.data());
  if (GetAdaptersAddresses(AF_UNSPEC, adapter_flags, nullptr, adapters,
                          &adapter_bytes) != NO_ERROR) {
    FreeAddrInfoW(addresses);
    return {DirectLatencyStatus::kSkipped};
  }

  bool attempted = false;
  bool timed_out = false;
  for (auto* address = addresses; address != nullptr; address = address->ai_next) {
    if (address->ai_family != AF_INET && address->ai_family != AF_INET6) {
      continue;
    }
    const auto* adapter = BestPhysicalAdapterForFamily(adapters,
                                                         address->ai_family);
    if (adapter == nullptr) continue;

    const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - started);
    if (elapsed.count() >= timeout_ms) {
      timed_out = true;
      break;
    }
    const DWORD remaining = static_cast<DWORD>(timeout_ms - elapsed.count());
    const DirectLatencyStatus status =
        ConnectDirectlyOnAdapter(address, adapter, remaining);
    if (status == DirectLatencyStatus::kSuccess) {
      const auto success_elapsed =
          std::chrono::duration_cast<std::chrono::milliseconds>(
              std::chrono::steady_clock::now() - started)
              .count();
      FreeAddrInfoW(addresses);
      return {DirectLatencyStatus::kSuccess,
              static_cast<std::int32_t>(
                  std::max<std::int64_t>(1, std::min<std::int64_t>(
                                               success_elapsed, 60000)))};
    }
    if (status == DirectLatencyStatus::kSkipped) {
      continue;
    }
    attempted = true;
    if (status == DirectLatencyStatus::kTimeout) timed_out = true;
  }
  FreeAddrInfoW(addresses);
  if (timed_out) return {DirectLatencyStatus::kTimeout};
  if (attempted) return {DirectLatencyStatus::kUnavailable};
  return {DirectLatencyStatus::kSkipped};
}

const char* DirectLatencyStatusName(DirectLatencyStatus status) {
  switch (status) {
    case DirectLatencyStatus::kSuccess:
      return "success";
    case DirectLatencyStatus::kTimeout:
      return "timeout";
    case DirectLatencyStatus::kUnavailable:
      return "unavailable";
    case DirectLatencyStatus::kSkipped:
      return "skipped";
  }
  return "skipped";
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
  if (value == "timeout") return TrayStatus::kTimeout;
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

  RestoreWindowPlacement();
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

        if (call.method_name() == "getTunRouteStatus") {
          result->Success(flutter::EncodableValue(TunRouteStatus()));
          return;
        }

        if (call.method_name() == "measureDirectLatency") {
          const auto* arguments = AsMap(call.arguments());
          const std::string host = arguments == nullptr
                                       ? std::string()
                                       : ReadStringArgument(*arguments, "host");
          const auto port = arguments == nullptr
                                ? std::nullopt
                                : ReadIntArgument(*arguments, "port");
          const auto timeout = arguments == nullptr
                                   ? std::nullopt
                                   : ReadIntArgument(*arguments, "timeoutMs");
          if (host.empty() || !port.has_value() || port.value() < 1 ||
              port.value() > 65535 || !timeout.has_value() ||
              timeout.value() < 100 || timeout.value() > 10000) {
            result->Error("invalid_arguments",
                          "Host, port, or timeout is invalid");
            return;
          }

          // A TCP connect can wait for several seconds. The Flutter C++
          // wrapper explicitly permits a MethodResult reply from any thread,
          // so the worker never blocks window input or rendering.
          std::thread(
              [host, port = static_cast<int>(port.value()),
               timeout = static_cast<DWORD>(timeout.value()),
               result = std::move(result)]() mutable {
                const DirectLatencyResult measurement =
                    MeasureDirectTcpLatency(host, port, timeout);
                flutter::EncodableMap response{
                    {flutter::EncodableValue("status"),
                     flutter::EncodableValue(
                         DirectLatencyStatusName(measurement.status))},
                };
                if (measurement.status == DirectLatencyStatus::kSuccess) {
                  response.emplace(flutter::EncodableValue("latencyMs"),
                                   flutter::EncodableValue(
                                       measurement.latency_ms));
                }
                result->Success(flutter::EncodableValue(response));
              })
              .detach();
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
      [](PVOID context, PMIB_IPINTERFACE_ROW row, MIB_NOTIFICATION_TYPE) {
        if (IsManagedTunNotification(row)) return;
        const HWND window = reinterpret_cast<HWND>(context);
        if (window != nullptr) PostMessageW(window, kNetworkChangedMessage, 0, 0);
      },
      reinterpret_cast<PVOID>(GetHandle()), FALSE, &network_change_handle_);

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!start_hidden_) this->ShowInitialWindow();
  });
  flutter_controller_->ForceRedraw();
  return true;
}

void FlutterWindow::OnDestroy() {
  SaveWindowPlacement();
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

  // Inno Setup uses Windows Restart Manager while updating files that belong
  // to the running app. It asks with WM_QUERYENDSESSION and then delivers
  // WM_ENDSESSION with ENDSESSION_CLOSEAPP. Do not route that close through
  // the ordinary close-to-tray path: hiding here leaves the process alive and
  // makes the installer wait for a locked executable.
  if (message == WM_QUERYENDSESSION) {
    return TRUE;
  }

  if (message == WM_ENDSESSION && wparam != FALSE &&
      (lparam & ENDSESSION_CLOSEAPP) != 0) {
    SaveWindowPlacement();
    RequestGracefulExit(kUpdateExitFallbackTimeoutMs);
    return 0;
  }

  if (message == WM_CLOSE) {
    SaveWindowPlacement();
    if (close_to_tray_ && !exit_requested_ && !exit_request_pending_) {
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

  if (message == WM_EXITSIZEMOVE ||
      (message == WM_SIZE &&
       (wparam == SIZE_MAXIMIZED ||
        (wparam == SIZE_RESTORED && restore_maximized_)))) {
    SaveWindowPlacement();
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

void FlutterWindow::RestoreWindowPlacement() {
  HWND window = GetHandle();
  if (window == nullptr) return;

  StoredWindowPlacement saved{};
  if (!LoadStoredWindowPlacement(&saved)) return;

  // WINDOWPLACEMENT stores top-level positions in workspace coordinates. Use
  // SetWindowPlacement first, then use the resulting screen-space rectangle
  // for monitor validation and clamping below.
  if (!SetHiddenNormalPlacement(window, saved.normal_rect)) return;

  RECT restored_rect{};
  if (!GetWindowRect(window, &restored_rect)) return;

  HMONITOR monitor = MonitorFromRect(&restored_rect, MONITOR_DEFAULTTONULL);
  const bool was_offscreen = monitor == nullptr;
  if (monitor == nullptr) monitor = MonitorFromWindow(window, MONITOR_DEFAULTTOPRIMARY);
  if (monitor == nullptr) return;

  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  if (!GetMonitorInfoW(monitor, &monitor_info)) return;

  const RECT work_area = monitor_info.rcWork;
  const LONG work_width = work_area.right - work_area.left;
  const LONG work_height = work_area.bottom - work_area.top;
  if (work_width <= 0 || work_height <= 0) return;

  const UINT target_dpi = FlutterDesktopGetDpiForMonitor(monitor);
  const UINT effective_target_dpi = target_dpi == 0 ? 96 : target_dpi;
  const LONG stored_width = saved.normal_rect.right - saved.normal_rect.left;
  const LONG stored_height = saved.normal_rect.bottom - saved.normal_rect.top;

  if (effective_target_dpi != saved.dpi) {
    RECT scaled_normal_rect = saved.normal_rect;
    scaled_normal_rect.right = scaled_normal_rect.left + ScaleForDpi(
        stored_width, saved.dpi, effective_target_dpi);
    scaled_normal_rect.bottom = scaled_normal_rect.top + ScaleForDpi(
        stored_height, saved.dpi, effective_target_dpi);
    if (!SetHiddenNormalPlacement(window, scaled_normal_rect) ||
        !GetWindowRect(window, &restored_rect)) {
      return;
    }
    monitor = MonitorFromRect(&restored_rect, MONITOR_DEFAULTTONULL);
    if (monitor == nullptr) monitor = MonitorFromWindow(window, MONITOR_DEFAULTTOPRIMARY);
    if (monitor == nullptr || !GetMonitorInfoW(monitor, &monitor_info)) return;
  }

  const RECT effective_work_area = monitor_info.rcWork;
  const LONG effective_work_width =
      effective_work_area.right - effective_work_area.left;
  const LONG effective_work_height =
      effective_work_area.bottom - effective_work_area.top;
  if (effective_work_width <= 0 || effective_work_height <= 0) return;

  const LONG minimum_width =
      ScaleForDpi(kMinimumWindowWidthDip, 96, effective_target_dpi);
  const LONG minimum_height =
      ScaleForDpi(kMinimumWindowHeightDip, 96, effective_target_dpi);
  const LONG width = ClampWindowDimension(
      restored_rect.right - restored_rect.left, minimum_width,
      effective_work_width);
  const LONG height = ClampWindowDimension(
      restored_rect.bottom - restored_rect.top, minimum_height,
      effective_work_height);

  const LONG left = was_offscreen
      ? effective_work_area.left + (effective_work_width - width) / 2
      : ClampWindowPosition(restored_rect.left, effective_work_area.left,
                            effective_work_area.right - width);
  const LONG top = was_offscreen
      ? effective_work_area.top + (effective_work_height - height) / 2
      : ClampWindowPosition(restored_rect.top, effective_work_area.top,
                            effective_work_area.bottom - height);

  SetWindowPos(window, nullptr, left, top, width, height,
               SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_NOZORDER);
  restore_maximized_ = saved.maximized != 0;
}

void FlutterWindow::SaveWindowPlacement() {
  HWND window = GetHandle();
  if (window == nullptr || IsIconic(window)) return;

  WINDOWPLACEMENT placement{};
  placement.length = sizeof(placement);
  if (!GetWindowPlacement(window, &placement) ||
      !IsUsableWindowRect(placement.rcNormalPosition)) {
    return;
  }

  HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  const UINT monitor_dpi = monitor == nullptr
      ? 96
      : FlutterDesktopGetDpiForMonitor(monitor);
  const UINT effective_dpi = monitor_dpi == 0 ? 96 : monitor_dpi;
  restore_maximized_ = IsZoomed(window) != FALSE;
  StoreWindowPlacement(StoredWindowPlacement{
      kWindowPlacementVersion,
      placement.rcNormalPosition,
      restore_maximized_ ? 1U : 0U,
      effective_dpi,
  });
}

void FlutterWindow::ShowInitialWindow() {
  HWND window = GetHandle();
  if (window == nullptr) return;
  ShowWindow(window, restore_maximized_ ? SW_SHOWMAXIMIZED : SW_SHOWNORMAL);
}

void FlutterWindow::ShowAndActivate() {
  HWND window = GetHandle();
  if (window == nullptr) return;

  if (IsIconic(window)) {
    ShowWindow(window, SW_RESTORE);
  } else if (!IsWindowVisible(window) && restore_maximized_) {
    ShowWindow(window, SW_SHOWMAXIMIZED);
  } else {
    ShowWindow(window, SW_SHOW);
  }
  SetWindowPos(window, HWND_TOP, 0, 0, 0, 0,
               SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
  SetForegroundWindow(window);
}

void FlutterWindow::RequestGracefulExit(UINT fallback_timeout_ms) {
  if (exit_requested_ || exit_request_pending_) return;
  exit_request_pending_ = true;

  if (lifecycle_channel_ == nullptr) {
    exit_requested_ = true;
    exit_request_pending_ = false;
    PostMessageW(GetHandle(), kCompleteExitMessage, 0, 0);
    return;
  }

  SetTimer(GetHandle(), kExitFallbackTimerId,
           fallback_timeout_ms == 0 ? kExitFallbackTimeoutMs
                                    : fallback_timeout_ms,
           nullptr);
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
