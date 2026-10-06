#ifndef RUNNER_CREDENTIAL_PROTECTOR_H_
#define RUNNER_CREDENTIAL_PROTECTOR_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterCredentialProtector(flutter::BinaryMessenger* messenger);

#endif
