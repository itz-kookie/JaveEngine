#include "jave/Audio.hpp"

#include <cstdlib>
#include <cwchar>
#include <cstdint>
#include <fstream>
#include <string>
#include <windows.h>
#include <mmsystem.h>

namespace jave {
namespace {
// The legacy MCI driver reports compressed WAV lengths as though their data
// were PCM. Use the decoded sample count in RIFF's fact chunk instead.
double waveDurationMs(const std::filesystem::path& path) {
    std::ifstream file(path, std::ios::binary);
    char header[12]{};
    if (!file.read(header, 12) || std::string(header, 4) != "RIFF" ||
        std::string(header + 8, 4) != "WAVE") return 0;
    const auto u32 = [](const unsigned char* p) {
        return std::uint32_t(p[0]) | (std::uint32_t(p[1]) << 8) |
               (std::uint32_t(p[2]) << 16) | (std::uint32_t(p[3]) << 24);
    };
    std::uint32_t rate = 0, average = 0, samples = 0, dataBytes = 0;
    while (file) {
        char id[4]{};
        unsigned char sizeBytes[4]{};
        if (!file.read(id, 4) || !file.read(reinterpret_cast<char*>(sizeBytes), 4)) break;
        const auto size = u32(sizeBytes);
        const auto next = file.tellg() + std::streamoff(size) + std::streamoff(size & 1);
        if (std::string(id, 4) == "fmt " && size >= 16) {
            unsigned char format[16]{};
            if (!file.read(reinterpret_cast<char*>(format), 16)) return 0;
            rate = u32(format + 4);
            average = u32(format + 8);
        } else if (std::string(id, 4) == "fact" && size >= 4) {
            unsigned char count[4]{};
            if (!file.read(reinterpret_cast<char*>(count), 4)) return 0;
            samples = u32(count);
        } else if (std::string(id, 4) == "data") dataBytes = size;
        file.seekg(next);
    }
    if (rate && samples) return 1000.0 * samples / rate;
    if (average && dataBytes) return 1000.0 * dataBytes / average;
    return 0;
}
} // namespace

AudioPlayer::~AudioPlayer() { stop(); }

bool AudioPlayer::play(const std::filesystem::path& audioPath, double volume) {
    stop();
    if (!std::filesystem::exists(audioPath)) return false;

    // MCI's wave driver still has a legacy full-path length limit. Stage the
    // selected song under a short per-process temp filename so installs in
    // deeply nested folders remain playable.
    std::filesystem::path mediaPath = audioPath;
    std::error_code copyError;
    const auto temporary = std::filesystem::temp_directory_path(copyError);
    if (!copyError) {
        stagedPath_ = temporary / (L"jave_audio_" + std::to_wstring(GetCurrentProcessId()) + audioPath.extension().wstring());
        std::filesystem::copy_file(audioPath, stagedPath_, std::filesystem::copy_options::overwrite_existing, copyError);
        if (!copyError) mediaPath = stagedPath_;
        else stagedPath_.clear();
    }

    const std::wstring open = L"open \"" + mediaPath.wstring() + L"\" type waveaudio alias jave_music";
    if (mciSendStringW(open.c_str(), nullptr, 0, nullptr) != 0) {
        if (!stagedPath_.empty()) {
            std::error_code removeError;
            std::filesystem::remove(stagedPath_, removeError);
            stagedPath_.clear();
        }
        return false;
    }
    mciSendStringW(L"set jave_music time format milliseconds", nullptr, 0, nullptr);
    wchar_t length[32]{};
    durationMs_ = 0.0;
    if (mciSendStringW(L"status jave_music length", length, 32, nullptr) == 0)
        durationMs_ = std::wcstod(length, nullptr);
    const double waveLength = waveDurationMs(mediaPath);
    if (waveLength > 0) durationMs_ = waveLength;
    const int level = static_cast<int>(1000.0 * (volume < 0.0 ? 0.0 : volume > 1.0 ? 1.0 : volume));
    const std::wstring setVolume = L"setaudio jave_music volume to " + std::to_wstring(level);
    mciSendStringW(setVolume.c_str(), nullptr, 0, nullptr);
    if (mciSendStringW(L"play jave_music from 0", nullptr, 0, nullptr) != 0) {
        mciSendStringW(L"close jave_music", nullptr, 0, nullptr);
        if (!stagedPath_.empty()) {
            std::error_code removeError;
            std::filesystem::remove(stagedPath_, removeError);
            stagedPath_.clear();
        }
        return false;
    }
    started_ = std::chrono::steady_clock::now();
    playing_ = true;
    paused_ = false;
    pausedPositionMs_ = 0.0;
    return true;
}

bool AudioPlayer::pause() {
    if (!playing_ || paused_) return false;
    pausedPositionMs_ = positionMs();
    if (mciSendStringW(L"pause jave_music", nullptr, 0, nullptr) != 0) return false;
    paused_ = true;
    return true;
}

bool AudioPlayer::resume() {
    if (!playing_ || !paused_) return false;
    const auto position = static_cast<long long>(pausedPositionMs_ + 0.5);
    const std::wstring command = L"play jave_music from " + std::to_wstring(position);
    if (mciSendStringW(command.c_str(), nullptr, 0, nullptr) != 0) return false;
    started_ = std::chrono::steady_clock::now() - std::chrono::duration_cast<std::chrono::steady_clock::duration>(
        std::chrono::duration<double, std::milli>(pausedPositionMs_));
    paused_ = false;
    return true;
}

void AudioPlayer::stop() {
    if (playing_) {
        mciSendStringW(L"stop jave_music", nullptr, 0, nullptr);
        mciSendStringW(L"close jave_music", nullptr, 0, nullptr);
    }
    playing_ = false;
    paused_ = false;
    pausedPositionMs_ = 0.0;
    if (!stagedPath_.empty()) {
        std::error_code removeError;
        std::filesystem::remove(stagedPath_, removeError);
        stagedPath_.clear();
    }
}

double AudioPlayer::positionMs() const {
    if (!playing_) return 0.0;
    if (paused_) return pausedPositionMs_;
    // MCI status queries are synchronous and can stall the gameplay thread.
    // The monotonic clock is started immediately after playback begins and is
    // corrected on every pause/resume, so it provides stable chart timing
    // without asking the legacy audio driver for a position every frame.
    return std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - started_).count();
}

} // namespace jave
