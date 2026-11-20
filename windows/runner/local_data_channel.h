#ifndef RUNNER_LOCAL_DATA_CHANNEL_H_
#define RUNNER_LOCAL_DATA_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>

// Registers the `blackgrid/local_data` channel, which answers `localDataPath`
// with the per-user local application data folder.
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterLocalDataChannel(flutter::BinaryMessenger* messenger);

#endif
