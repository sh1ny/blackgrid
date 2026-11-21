#include "audio_channel.h"

#include <unknwn.h>
#include <shobjidl.h>

#include <flutter/standard_method_codec.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.Core.h>
#include <winrt/Windows.Media.Playback.h>
#include <winrt/Windows.Media.SpeechSynthesis.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/Windows.System.h>

#include <algorithm>
#include <cstdint>
#include <mutex>
#include <string>
#include <utility>

namespace {

using flutter::EncodableList;
using flutter::EncodableMap;
using flutter::EncodableValue;
using MethodResultPtr =
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>;

namespace media = winrt::Windows::Media;
namespace streams = winrt::Windows::Storage::Streams;

constexpr char kAudioChannelName[] = "blackgrid/audio";

// Events posted from other threads (LPARAM of |kAudioChannelMessage|).
enum AudioEvent : LPARAM {
  kSynthesized = 1,
  kSynthesisFailed = 2,
  kOpened = 3,
  kEnded = 4,
  kFailed = 5,
};

// A file that reports no duration still gets this long to play.
constexpr UINT kUnknownDurationTimeoutMs = 30000;
// Slack added to the reported duration before the runner gives up.
constexpr UINT kDurationSlackMs = 5000;
constexpr UINT kMaxTimeoutMs = 120000;

enum class PlaybackKind { kNone, kSpeech, kFile };

// State shared with threadpool continuations. It never points back at the
// channel, so a late continuation after teardown only posts to the window.
struct Shared {
  HWND window = nullptr;
  std::mutex mutex;
  streams::IRandomAccessStream stream{nullptr};
  winrt::hstring content_type;
};

void Post(const std::shared_ptr<Shared>& shared, uint64_t generation,
          AudioEvent event) {
  ::PostMessage(shared->window, kAudioChannelMessage,
                static_cast<WPARAM>(generation), static_cast<LPARAM>(event));
}

const EncodableValue* Find(const EncodableMap& map, const char* key) {
  const auto it = map.find(EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

bool GetString(const EncodableMap& map, const char* key, std::string* out) {
  const auto* value = Find(map, key);
  const auto* text = value == nullptr ? nullptr : std::get_if<std::string>(value);
  if (text == nullptr) return false;
  *out = *text;
  return true;
}

bool GetInt(const EncodableMap& map, const char* key, int64_t* out) {
  const auto* value = Find(map, key);
  if (value == nullptr) return false;
  if (const auto* narrow = std::get_if<int32_t>(value)) {
    *out = *narrow;
    return true;
  }
  if (const auto* wide_value = std::get_if<int64_t>(value)) {
    *out = *wide_value;
    return true;
  }
  return false;
}

const EncodableMap* Arguments(
    const flutter::MethodCall<EncodableValue>& call) {
  const auto* args = call.arguments();
  return args == nullptr ? nullptr : std::get_if<EncodableMap>(args);
}

double SpeakingRate(int64_t step) {
  return step < 0 ? 1.0 + static_cast<double>(step) * 0.1
                  : 1.0 + static_cast<double>(step) * 0.4;
}

std::string PercentEncodePath(const std::string& utf8) {
  static const char kHex[] = "0123456789ABCDEF";
  std::string out;
  for (const unsigned char c : utf8) {
    const bool plain = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                       (c >= '0' && c <= '9') || c == '-' || c == '.' ||
                       c == '_' || c == '~' || c == '/' || c == ':';
    if (plain) {
      out.push_back(static_cast<char>(c));
    } else {
      out.push_back('%');
      out.push_back(kHex[c >> 4]);
      out.push_back(kHex[c & 0x0F]);
    }
  }
  return out;
}

winrt::Windows::Foundation::Uri FileUri(const std::wstring& path) {
  std::string utf8 = winrt::to_string(winrt::hstring(path));
  std::replace(utf8.begin(), utf8.end(), '\\', '/');
  const std::string encoded = PercentEncodePath(utf8);
  const std::string uri =
      encoded.rfind("//", 0) == 0 ? "file:" + encoded : "file:///" + encoded;
  return winrt::Windows::Foundation::Uri(winrt::to_hstring(uri));
}

}  // namespace

struct AudioChannel::Impl {
  Impl(flutter::BinaryMessenger* messenger, HWND window_handle)
      : window(window_handle), shared(std::make_shared<Shared>()) {
    shared->window = window_handle;
    channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
        messenger, kAudioChannelName,
        &flutter::StandardMethodCodec::GetInstance());
    channel->SetMethodCallHandler(
        [this](const flutter::MethodCall<EncodableValue>& call,
               MethodResultPtr result) { Handle(call, std::move(result)); });
  }

  ~Impl() {
    // Complete the pending call while the messenger is still alive.
    channel->SetMethodCallHandler(nullptr);
    Finish("stopped", "Playback was stopped.");
    channel.reset();
  }

  HWND window;
  std::shared_ptr<Shared> shared;
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;

  // Pending playback. |result| is null when nothing is pending.
  MethodResultPtr result;
  PlaybackKind kind = PlaybackKind::kNone;
  uint64_t generation = 0;
  double volume = 1.0;
  bool timer_armed = false;

  media::Playback::MediaPlayer player{nullptr};
  media::Core::MediaSource source{nullptr};
  media::Playback::MediaPlayer::MediaOpened_revoker opened_revoker;
  media::Playback::MediaPlayer::MediaEnded_revoker ended_revoker;
  media::Playback::MediaPlayer::MediaFailed_revoker failed_revoker;

  void Handle(const flutter::MethodCall<EncodableValue>& call,
              MethodResultPtr method_result) {
    const std::string& method = call.method_name();
    if (method == "voices") {
      Voices(std::move(method_result));
    } else if (method == "speak") {
      Speak(call, std::move(method_result));
    } else if (method == "playFile") {
      PlayFile(call, std::move(method_result));
    } else if (method == "stop") {
      Finish("stopped", "Playback was stopped.");
      method_result->Success();
    } else if (method == "openVoiceSettings") {
      OpenVoiceSettings(std::move(method_result));
    } else if (method == "pickSoundFile") {
      PickSoundFile(std::move(method_result));
    } else {
      method_result->NotImplemented();
    }
  }

  // Releases the player and timer without completing the result.
  void Teardown() {
    if (timer_armed) {
      ::KillTimer(window, kAudioChannelTimerId);
      timer_armed = false;
    }
    opened_revoker.revoke();
    ended_revoker.revoke();
    failed_revoker.revoke();
    if (player) {
      try {
        player.Pause();
        player.Close();
      } catch (const winrt::hresult_error&) {
      }
      player = nullptr;
    }
    if (source) {
      try {
        source.Close();
      } catch (const winrt::hresult_error&) {
      }
      source = nullptr;
    }
    {
      std::lock_guard<std::mutex> lock(shared->mutex);
      shared->stream = nullptr;
    }
    kind = PlaybackKind::kNone;
  }

  // Completes the pending result exactly once: success when |code| is null,
  // otherwise an error. Safe to call with nothing pending.
  void Finish(const char* code, const char* message) {
    if (!result) return;
    MethodResultPtr pending = std::move(result);
    generation++;
    Teardown();
    if (code == nullptr) {
      pending->Success();
    } else {
      pending->Error(code, message);
    }
  }

  bool RejectIfBusy(MethodResultPtr& method_result) {
    if (!result) return false;
    method_result->Error("busy", "Another sound is already playing.");
    return true;
  }

  void Voices(MethodResultPtr method_result) {
    try {
      EncodableList list;
      for (const auto& voice :
           media::SpeechSynthesis::SpeechSynthesizer::AllVoices()) {
        list.push_back(EncodableValue(EncodableMap{
            {EncodableValue("id"),
             EncodableValue(winrt::to_string(voice.Id()))},
            {EncodableValue("name"),
             EncodableValue(winrt::to_string(voice.DisplayName()))},
            {EncodableValue("language"),
             EncodableValue(winrt::to_string(voice.Language()))},
        }));
      }
      method_result->Success(EncodableValue(std::move(list)));
    } catch (const winrt::hresult_error& error) {
      method_result->Error("voices_failed", winrt::to_string(error.message()));
    }
  }

  void Speak(const flutter::MethodCall<EncodableValue>& call,
             MethodResultPtr method_result) {
    const EncodableMap* args = Arguments(call);
    std::string text;
    int64_t speed = 0;
    int64_t level = 0;
    if (args == nullptr || !GetString(*args, "text", &text) ||
        !GetInt(*args, "speed", &speed) || !GetInt(*args, "volume", &level) ||
        speed < -5 || speed > 5 || level < 0 || level > 100) {
      method_result->Error("bad_arguments", "Invalid speak arguments.");
      return;
    }
    std::string voice_id;
    bool has_voice = false;
    if (const auto* voice = Find(*args, "voice");
        voice != nullptr && !voice->IsNull()) {
      const auto* id = std::get_if<std::string>(voice);
      if (id == nullptr) {
        method_result->Error("bad_arguments", "Invalid speak arguments.");
        return;
      }
      voice_id = *id;
      has_voice = true;
    }
    if (RejectIfBusy(method_result)) return;

    try {
      media::SpeechSynthesis::SpeechSynthesizer synthesizer;
      if (has_voice) {
        const auto wanted = winrt::to_hstring(voice_id);
        media::SpeechSynthesis::VoiceInformation found{nullptr};
        for (const auto& voice :
             media::SpeechSynthesis::SpeechSynthesizer::AllVoices()) {
          if (voice.Id() == wanted) {
            found = voice;
            break;
          }
        }
        if (!found) {
          method_result->Error("voice_missing",
                               "The selected voice is not installed.");
          return;
        }
        synthesizer.Voice(found);
      }
      auto options = synthesizer.Options();
      options.SpeakingRate(SpeakingRate(speed));
      options.AudioVolume(static_cast<double>(level) / 100.0);

      result = std::move(method_result);
      kind = PlaybackKind::kSpeech;
      volume = static_cast<double>(level) / 100.0;
      const uint64_t gen = ++generation;
      const auto state = shared;
      {
        std::lock_guard<std::mutex> lock(state->mutex);
        state->stream = nullptr;
      }
      synthesizer.SynthesizeTextToStreamAsync(winrt::to_hstring(text))
          .Completed([state, gen, synthesizer](const auto& operation,
                                               winrt::Windows::Foundation::
                                                   AsyncStatus status) {
            if (status != winrt::Windows::Foundation::AsyncStatus::Completed) {
              Post(state, gen, kSynthesisFailed);
              return;
            }
            try {
              const auto stream = operation.GetResults();
              {
                std::lock_guard<std::mutex> lock(state->mutex);
                state->stream = stream;
                state->content_type = stream.ContentType();
              }
              Post(state, gen, kSynthesized);
            } catch (const winrt::hresult_error&) {
              Post(state, gen, kSynthesisFailed);
            }
          });
    } catch (const winrt::hresult_error& error) {
      if (result) {
        Finish("speech_failed", winrt::to_string(error.message()).c_str());
      } else {
        method_result->Error("speech_failed",
                             winrt::to_string(error.message()));
      }
    }
  }

  void PlayFile(const flutter::MethodCall<EncodableValue>& call,
                MethodResultPtr method_result) {
    const EncodableMap* args = Arguments(call);
    std::string path;
    int64_t level = 0;
    if (args == nullptr || !GetString(*args, "path", &path) ||
        !GetInt(*args, "volume", &level) || level < 0 || level > 100 ||
        path.empty()) {
      method_result->Error("bad_arguments", "Invalid playFile arguments.");
      return;
    }
    if (RejectIfBusy(method_result)) return;

    const std::wstring wide = winrt::to_hstring(path).c_str();
    const DWORD attributes = ::GetFileAttributesW(wide.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES ||
        (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0) {
      method_result->Error("file_missing", "The sound file does not exist.");
      return;
    }

    result = std::move(method_result);
    kind = PlaybackKind::kFile;
    volume = static_cast<double>(level) / 100.0;
    ++generation;
    try {
      source = media::Core::MediaSource::CreateFromUri(FileUri(wide));
      StartPlayer();
    } catch (const winrt::hresult_error&) {
      Finish("file_unplayable", "The sound file could not be played.");
    }
  }

  // Creates the player for |source| and starts playback.
  void StartPlayer() {
    const auto state = shared;
    const uint64_t gen = generation;
    player = media::Playback::MediaPlayer();
    player.AutoPlay(false);
    player.Volume(volume);
    opened_revoker = player.MediaOpened(
        winrt::auto_revoke, [state, gen](const auto&, const auto&) {
          Post(state, gen, kOpened);
        });
    ended_revoker = player.MediaEnded(
        winrt::auto_revoke, [state, gen](const auto&, const auto&) {
          Post(state, gen, kEnded);
        });
    failed_revoker = player.MediaFailed(
        winrt::auto_revoke, [state, gen](const auto&, const auto&) {
          Post(state, gen, kFailed);
        });
    player.Source(source);
    player.Play();
  }

  void OnMessage(WPARAM message_generation, LPARAM event) {
    if (!result || static_cast<uint64_t>(message_generation) != generation) {
      return;  // Late event for a playback that already completed.
    }
    switch (event) {
      case kSynthesized:
        OnSynthesized();
        break;
      case kSynthesisFailed:
        Finish("speech_failed", "Speech could not be synthesized.");
        break;
      case kOpened:
        OnOpened();
        break;
      case kEnded:
        Finish(nullptr, nullptr);
        break;
      case kFailed:
        if (kind == PlaybackKind::kFile) {
          Finish("file_unplayable", "The sound file could not be played.");
        } else {
          Finish("speech_failed", "Speech could not be played.");
        }
        break;
      default:
        break;
    }
  }

  void OnSynthesized() {
    if (kind != PlaybackKind::kSpeech || player) return;
    try {
      streams::IRandomAccessStream stream{nullptr};
      winrt::hstring content_type;
      {
        std::lock_guard<std::mutex> lock(shared->mutex);
        stream = shared->stream;
        content_type = shared->content_type;
        shared->stream = nullptr;
      }
      if (!stream) {
        Finish("speech_failed", "Speech could not be synthesized.");
        return;
      }
      source = media::Core::MediaSource::CreateFromStream(stream, content_type);
      StartPlayer();
    } catch (const winrt::hresult_error&) {
      Finish("speech_failed", "Speech could not be played.");
    }
  }

  void OnOpened() {
    if (kind != PlaybackKind::kFile || timer_armed || !player) return;
    UINT timeout_ms = kUnknownDurationTimeoutMs;
    try {
      const int64_t ticks = player.NaturalDuration().count();  // 100 ns units.
      if (ticks > 0) {
        const int64_t duration_ms = ticks / 10000;
        timeout_ms = static_cast<UINT>(std::min<int64_t>(
            duration_ms + kDurationSlackMs, kMaxTimeoutMs));
      }
    } catch (const winrt::hresult_error&) {
    }
    if (::SetTimer(window, kAudioChannelTimerId, timeout_ms, nullptr) != 0) {
      timer_armed = true;
    }
  }

  void OnTimer() {
    if (!timer_armed) return;
    Finish("timeout", "The sound file did not finish in time.");
  }

  void OpenVoiceSettings(MethodResultPtr method_result) {
    const auto launched = reinterpret_cast<INT_PTR>(::ShellExecuteW(
        window, L"open", L"ms-settings:speech", nullptr, nullptr, SW_SHOWNORMAL));
    if (launched > 32) {
      method_result->Success();
    } else {
      method_result->Error("launch_failed",
                           "The Windows speech settings could not be opened.");
    }
  }

  void PickSoundFile(MethodResultPtr method_result) {
    try {
      winrt::com_ptr<IFileOpenDialog> dialog;
      winrt::check_hresult(::CoCreateInstance(
          CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER,
          IID_PPV_ARGS(dialog.put())));
      DWORD options = 0;
      winrt::check_hresult(dialog->GetOptions(&options));
      winrt::check_hresult(dialog->SetOptions(
          options | FOS_FORCEFILESYSTEM | FOS_FILEMUSTEXIST));
      const COMDLG_FILTERSPEC filter[] = {
          {L"Sound files (*.wav;*.mp3)", L"*.wav;*.mp3"}};
      winrt::check_hresult(dialog->SetFileTypes(1, filter));
      winrt::check_hresult(dialog->SetFileTypeIndex(1));
      const HRESULT shown = dialog->Show(window);
      if (shown == HRESULT_FROM_WIN32(ERROR_CANCELLED)) {
        method_result->Success();
        return;
      }
      winrt::check_hresult(shown);
      winrt::com_ptr<IShellItem> item;
      winrt::check_hresult(dialog->GetResult(item.put()));
      PWSTR name = nullptr;
      winrt::check_hresult(item->GetDisplayName(SIGDN_FILESYSPATH, &name));
      const std::string path = winrt::to_string(winrt::hstring(name));
      ::CoTaskMemFree(name);
      method_result->Success(EncodableValue(path));
    } catch (const winrt::hresult_error& error) {
      method_result->Error("dialog_failed", winrt::to_string(error.message()));
    }
  }
};

AudioChannel::AudioChannel(flutter::BinaryMessenger* messenger, HWND window)
    : impl_(std::make_unique<Impl>(messenger, window)) {}

AudioChannel::~AudioChannel() = default;

void AudioChannel::HandleMessage(WPARAM generation, LPARAM event) {
  impl_->OnMessage(generation, event);
}

void AudioChannel::HandleTimer() { impl_->OnTimer(); }

std::unique_ptr<AudioChannel> RegisterAudioChannel(
    flutter::BinaryMessenger* messenger, HWND window) {
  return std::make_unique<AudioChannel>(messenger, window);
}
