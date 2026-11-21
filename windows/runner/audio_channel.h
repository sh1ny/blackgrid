#ifndef RUNNER_AUDIO_CHANNEL_H_
#define RUNNER_AUDIO_CHANNEL_H_

#include <windows.h>

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/method_result.h>

#include <memory>

// Private window message the audio channel posts to the Flutter window to
// marshal WinRT completions back to the platform thread. WPARAM carries the
// playback generation and LPARAM an |AudioChannel| event code.
constexpr UINT kAudioChannelMessage = WM_APP + 1;

// Timer id used with SetTimer for the runner-side file playback timeout.
constexpr UINT_PTR kAudioChannelTimerId = 0xA0D10;

// Registers the `blackgrid/audio` channel: installed voices, speech
// synthesis, file playback, stop, the Windows speech settings page and a
// sound file picker. At most one speak/playFile result is pending at a time.
//
// Every method runs on the platform thread. WinRT async work and MediaPlayer
// events run on other threads and only post |kAudioChannelMessage| to the
// window, which forwards to |HandleMessage|. Destroying the object completes
// any pending result with `stopped`, so destroy it before the messenger.
class AudioChannel {
 public:
  AudioChannel(flutter::BinaryMessenger* messenger, HWND window);
  ~AudioChannel();

  AudioChannel(const AudioChannel&) = delete;
  AudioChannel& operator=(const AudioChannel&) = delete;

  // Handles |kAudioChannelMessage| on the platform thread.
  void HandleMessage(WPARAM generation, LPARAM event);

  // Handles WM_TIMER for |kAudioChannelTimerId| on the platform thread.
  void HandleTimer();

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

std::unique_ptr<AudioChannel> RegisterAudioChannel(
    flutter::BinaryMessenger* messenger, HWND window);

#endif  // RUNNER_AUDIO_CHANNEL_H_
