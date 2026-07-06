#ifndef RUNNER_PROCESS_JOB_H_
#define RUNNER_PROCESS_JOB_H_

#include <windows.h>

#include <string>

namespace orexray {

bool InitializeChildProcessJob(std::string* error_message);
void CloseChildProcessJob();
bool AttachProcessToJob(DWORD process_id, std::string* error_message);
int TerminateProcessesByExecutablePath(const std::string& executable_path,
                                       std::string* error_message);

}  // namespace orexray

#endif  // RUNNER_PROCESS_JOB_H_
