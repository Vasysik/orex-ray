#include "process_job.h"

#include <tlhelp32.h>

#include <algorithm>
#include <cwctype>
#include <string>
#include <vector>

namespace orexray {
namespace {

HANDLE g_child_process_job = nullptr;

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

std::wstring NormalizePath(const std::wstring& value) {
  if (value.empty()) return std::wstring();

  const DWORD required = GetFullPathNameW(value.c_str(), 0, nullptr, nullptr);
  std::wstring full_path = value;
  if (required > 0) {
    std::vector<wchar_t> buffer(required);
    const DWORD written =
        GetFullPathNameW(value.c_str(), required, buffer.data(), nullptr);
    if (written > 0 && written < required) {
      full_path.assign(buffer.data(), written);
    }
  }

  std::replace(full_path.begin(), full_path.end(), L'/', L'\\');
  std::transform(full_path.begin(), full_path.end(), full_path.begin(),
                 [](wchar_t character) { return std::towlower(character); });
  return full_path;
}

std::string WindowsError(const char* prefix, DWORD error_code) {
  return std::string(prefix) + " (Windows error " +
         std::to_string(error_code) + ")";
}

}  // namespace

bool InitializeChildProcessJob(std::string* error_message) {
  if (g_child_process_job != nullptr) return true;

  HANDLE job = CreateJobObjectW(nullptr, nullptr);
  if (job == nullptr) {
    if (error_message != nullptr) {
      *error_message = WindowsError("Could not create child process job",
                                    GetLastError());
    }
    return false;
  }

  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits,
                               sizeof(limits))) {
    const DWORD error = GetLastError();
    CloseHandle(job);
    if (error_message != nullptr) {
      *error_message =
          WindowsError("Could not configure child process job", error);
    }
    return false;
  }

  g_child_process_job = job;
  return true;
}

void CloseChildProcessJob() {
  if (g_child_process_job == nullptr) return;
  CloseHandle(g_child_process_job);
  g_child_process_job = nullptr;
}

bool AttachProcessToJob(DWORD process_id, std::string* error_message) {
  if (g_child_process_job == nullptr &&
      !InitializeChildProcessJob(error_message)) {
    return false;
  }

  HANDLE process = OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE |
                                   PROCESS_QUERY_LIMITED_INFORMATION,
                               FALSE, process_id);
  if (process == nullptr) {
    if (error_message != nullptr) {
      *error_message =
          WindowsError("Could not open child process", GetLastError());
    }
    return false;
  }

  const BOOL assigned = AssignProcessToJobObject(g_child_process_job, process);
  const DWORD error = assigned ? ERROR_SUCCESS : GetLastError();
  CloseHandle(process);

  if (!assigned) {
    if (error_message != nullptr) {
      *error_message =
          WindowsError("Could not attach child process to OrexRay", error);
    }
    return false;
  }
  return true;
}

int TerminateProcessesByExecutablePath(const std::string& executable_path,
                                       std::string* error_message) {
  const std::wstring target = NormalizePath(Utf8ToWide(executable_path));
  if (target.empty()) {
    if (error_message != nullptr) {
      *error_message = "Executable path is empty or invalid";
    }
    return -1;
  }

  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) {
    if (error_message != nullptr) {
      *error_message =
          WindowsError("Could not enumerate processes", GetLastError());
    }
    return -1;
  }

  int terminated = 0;
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  if (Process32FirstW(snapshot, &entry)) {
    do {
      if (entry.th32ProcessID == 0 ||
          entry.th32ProcessID == GetCurrentProcessId()) {
        continue;
      }

      HANDLE process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION |
                                       PROCESS_TERMINATE | SYNCHRONIZE,
                                   FALSE, entry.th32ProcessID);
      if (process == nullptr) continue;

      std::vector<wchar_t> path_buffer(32768);
      DWORD path_length = static_cast<DWORD>(path_buffer.size());
      const bool same_executable =
          QueryFullProcessImageNameW(process, 0, path_buffer.data(),
                                     &path_length) &&
          NormalizePath(std::wstring(path_buffer.data(), path_length)) == target;

      if (same_executable && TerminateProcess(process, 1)) {
        WaitForSingleObject(process, 2000);
        ++terminated;
      }
      CloseHandle(process);
    } while (Process32NextW(snapshot, &entry));
  }

  CloseHandle(snapshot);
  return terminated;
}

}  // namespace orexray
