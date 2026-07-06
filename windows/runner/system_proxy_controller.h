#ifndef RUNNER_SYSTEM_PROXY_CONTROLLER_H_
#define RUNNER_SYSTEM_PROXY_CONTROLLER_H_

#include <flutter/encodable_value.h>

#include <string>

namespace orexray {

flutter::EncodableMap ReadSystemProxyState();

bool SetSystemProxy(const std::string& server, const std::string& bypass,
                    std::string* error_message);

bool RestoreSystemProxy(const flutter::EncodableMap& state,
                        std::string* error_message);

}  // namespace orexray

#endif  // RUNNER_SYSTEM_PROXY_CONTROLLER_H_
