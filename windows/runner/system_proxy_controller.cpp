#include "system_proxy_controller.h"

#include <windows.h>
#include <wininet.h>

#include <optional>
#include <string>

namespace orexray {
namespace {

constexpr wchar_t kInternetSettingsPath[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings";

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return std::wstring();
  const int size = MultiByteToWideChar(
      CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
  if (size <= 0) return std::wstring();
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return std::string();
  const int size = WideCharToMultiByte(
      CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0,
      nullptr, nullptr);
  if (size <= 0) return std::string();
  std::string result(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(),
                      static_cast<int>(value.size()), result.data(), size,
                      nullptr, nullptr);
  return result;
}

bool OpenInternetSettings(REGSAM access, HKEY* key, std::string* error_message) {
  const LONG result = RegOpenKeyExW(HKEY_CURRENT_USER, kInternetSettingsPath, 0,
                                    access, key);
  if (result == ERROR_SUCCESS) return true;
  if (error_message != nullptr) {
    *error_message = "Не удалось открыть настройки системного прокси Windows: " +
                     std::to_string(result);
  }
  return false;
}

std::optional<std::wstring> ReadStringValue(HKEY key, const wchar_t* name) {
  DWORD type = 0;
  DWORD size = 0;
  LONG result = RegQueryValueExW(key, name, nullptr, &type, nullptr, &size);
  if (result != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ)) {
    return std::nullopt;
  }

  std::wstring value(size / sizeof(wchar_t), L'\0');
  result = RegQueryValueExW(key, name, nullptr, &type,
                            reinterpret_cast<LPBYTE>(value.data()), &size);
  if (result != ERROR_SUCCESS) return std::nullopt;
  while (!value.empty() && value.back() == L'\0') value.pop_back();
  return value;
}

bool WriteStringValue(HKEY key, const wchar_t* name, const std::wstring& value) {
  const DWORD bytes = static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));
  return RegSetValueExW(key, name, 0, REG_SZ,
                        reinterpret_cast<const BYTE*>(value.c_str()),
                        bytes) == ERROR_SUCCESS;
}

bool WriteDwordValue(HKEY key, const wchar_t* name, DWORD value) {
  return RegSetValueExW(key, name, 0, REG_DWORD,
                        reinterpret_cast<const BYTE*>(&value),
                        sizeof(value)) == ERROR_SUCCESS;
}

void NotifyProxyChanged() {
  InternetSetOptionW(nullptr, INTERNET_OPTION_SETTINGS_CHANGED, nullptr, 0);
  InternetSetOptionW(nullptr, INTERNET_OPTION_REFRESH, nullptr, 0);
  SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                      reinterpret_cast<LPARAM>(L"Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings"),
                      SMTO_ABORTIFHUNG, 1000, nullptr);
}

const flutter::EncodableValue* Find(const flutter::EncodableMap& map,
                                    const char* key) {
  const auto iterator = map.find(flutter::EncodableValue(key));
  return iterator == map.end() ? nullptr : &iterator->second;
}

bool GetBool(const flutter::EncodableMap& map, const char* key,
             bool fallback = false) {
  const auto* value = Find(map, key);
  if (value == nullptr) return fallback;
  if (const auto* result = std::get_if<bool>(value)) return *result;
  return fallback;
}

std::string GetString(const flutter::EncodableMap& map, const char* key) {
  const auto* value = Find(map, key);
  if (value == nullptr) return std::string();
  if (const auto* result = std::get_if<std::string>(value)) return *result;
  return std::string();
}

}  // namespace

flutter::EncodableMap ReadSystemProxyState() {
  flutter::EncodableMap state;
  HKEY key = nullptr;
  std::string error;
  if (!OpenInternetSettings(KEY_QUERY_VALUE, &key, &error)) {
    state[flutter::EncodableValue("enabled")] = flutter::EncodableValue(false);
    state[flutter::EncodableValue("server")] = flutter::EncodableValue("");
    state[flutter::EncodableValue("bypass")] = flutter::EncodableValue("");
    state[flutter::EncodableValue("hasServer")] = flutter::EncodableValue(false);
    state[flutter::EncodableValue("hasBypass")] = flutter::EncodableValue(false);
    return state;
  }

  DWORD enabled = 0;
  DWORD type = REG_DWORD;
  DWORD size = sizeof(enabled);
  if (RegQueryValueExW(key, L"ProxyEnable", nullptr, &type,
                       reinterpret_cast<LPBYTE>(&enabled), &size) !=
      ERROR_SUCCESS) {
    enabled = 0;
  }

  const auto server = ReadStringValue(key, L"ProxyServer");
  const auto bypass = ReadStringValue(key, L"ProxyOverride");
  RegCloseKey(key);

  state[flutter::EncodableValue("enabled")] =
      flutter::EncodableValue(enabled != 0);
  state[flutter::EncodableValue("server")] =
      flutter::EncodableValue(server ? WideToUtf8(*server) : "");
  state[flutter::EncodableValue("bypass")] =
      flutter::EncodableValue(bypass ? WideToUtf8(*bypass) : "");
  state[flutter::EncodableValue("hasServer")] =
      flutter::EncodableValue(server.has_value());
  state[flutter::EncodableValue("hasBypass")] =
      flutter::EncodableValue(bypass.has_value());
  return state;
}

bool SetSystemProxy(const std::string& server, const std::string& bypass,
                    std::string* error_message) {
  HKEY key = nullptr;
  if (!OpenInternetSettings(KEY_SET_VALUE, &key, error_message)) return false;

  const bool success =
      WriteStringValue(key, L"ProxyServer", Utf8ToWide(server)) &&
      WriteStringValue(key, L"ProxyOverride", Utf8ToWide(bypass)) &&
      WriteDwordValue(key, L"ProxyEnable", 1);
  RegCloseKey(key);

  if (!success) {
    if (error_message != nullptr) {
      *error_message = "Windows не смог применить системный прокси.";
    }
    return false;
  }

  NotifyProxyChanged();
  return true;
}

bool RestoreSystemProxy(const flutter::EncodableMap& state,
                        std::string* error_message) {
  HKEY key = nullptr;
  if (!OpenInternetSettings(KEY_SET_VALUE, &key, error_message)) return false;

  bool success = true;
  if (GetBool(state, "hasServer")) {
    success = success && WriteStringValue(
                             key, L"ProxyServer",
                             Utf8ToWide(GetString(state, "server")));
  } else {
    const LONG result = RegDeleteValueW(key, L"ProxyServer");
    success = success && (result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND);
  }

  if (GetBool(state, "hasBypass")) {
    success = success && WriteStringValue(
                             key, L"ProxyOverride",
                             Utf8ToWide(GetString(state, "bypass")));
  } else {
    const LONG result = RegDeleteValueW(key, L"ProxyOverride");
    success = success && (result == ERROR_SUCCESS || result == ERROR_FILE_NOT_FOUND);
  }

  success = success &&
            WriteDwordValue(key, L"ProxyEnable", GetBool(state, "enabled") ? 1 : 0);
  RegCloseKey(key);

  if (!success) {
    if (error_message != nullptr) {
      *error_message = "Windows не смог восстановить предыдущий системный прокси.";
    }
    return false;
  }

  NotifyProxyChanged();
  return true;
}

}  // namespace orexray
