#ifndef RUNNER_RECYCLE_CHANNEL_H_
#define RUNNER_RECYCLE_CHANNEL_H_

#include <windows.h>

#include <flutter/binary_messenger.h>

#include <memory>

// Worker completions are delivered to the platform thread through this message.
constexpr UINT kRecycleChannelMessage = WM_APP + 2;

class RecycleChannel {
 public:
  RecycleChannel(flutter::BinaryMessenger* messenger, HWND window);
  ~RecycleChannel();

  RecycleChannel(const RecycleChannel&) = delete;
  RecycleChannel& operator=(const RecycleChannel&) = delete;

  void HandleMessage(WPARAM generation);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

std::unique_ptr<RecycleChannel> RegisterRecycleChannel(
    flutter::BinaryMessenger* messenger, HWND window);

#endif  // RUNNER_RECYCLE_CHANNEL_H_
