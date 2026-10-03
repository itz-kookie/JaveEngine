#pragma once

#include <chrono>
#include <filesystem>

namespace jave {

class AudioPlayer {
public:
    AudioPlayer() = default;
    ~AudioPlayer();

    bool play(const std::filesystem::path& audioPath, double volume);
    bool pause();
    bool resume();
    void stop();
    [[nodiscard]] bool playing() const { return playing_ && !paused_; }
    [[nodiscard]] bool paused() const { return paused_; }
    [[nodiscard]] double positionMs() const;
    [[nodiscard]] double durationMs() const { return durationMs_; }

private:
    bool playing_{};
    bool paused_{};
    double pausedPositionMs_{};
    double durationMs_{};
    std::chrono::steady_clock::time_point started_{};
    std::filesystem::path stagedPath_;
};

} // namespace jave
