#include "jave/Content.hpp"

#include <algorithm>
#include <cmath>
#include <stdexcept>
#include <utility>

namespace jave {

void SpriteAnimation::update(double deltaMs) {
    if (!playing || frames.empty()) return;
    elapsedMs += deltaMs;
    while (elapsedMs >= frames[currentFrame].durationMs) {
        elapsedMs -= frames[currentFrame].durationMs;
        ++currentFrame;
        if (currentFrame >= frames.size()) {
            if (looping) currentFrame = 0;
            else { currentFrame = frames.size() - 1; playing = false; break; }
        }
    }
}

void SpriteAnimation::reset() { currentFrame = 0; elapsedMs = 0; playing = true; }

void ContentLibrary::reloadStage(Song& song) const {
    if (song.stageConfigPath.empty() || !std::filesystem::is_regular_file(song.stageConfigPath)) return;
    const Json stage = Json::fromFile(song.stageConfigPath);
    const auto readPoint = [](const Json& value, std::array<double, 2> fallback) {
        const auto& items = value.asArray();
        return items.size() == 2 ? std::array<double, 2>{items[0].asNumber(fallback[0]), items[1].asNumber(fallback[1])} : fallback;
    };
    song.playerPosition = readPoint(stage["boyfriend"], song.playerPosition);
    song.opponentPosition = readPoint(stage["opponent"], song.opponentPosition);
    song.girlfriendPosition = readPoint(stage["girlfriend"], song.girlfriendPosition);
    song.cameraPlayer = readPoint(stage["cameraBoyfriend"], song.cameraPlayer);
    song.cameraOpponent = readPoint(stage["cameraOpponent"], song.cameraOpponent);
    song.cameraGirlfriend = readPoint(stage["cameraGirlfriend"], song.cameraGirlfriend);
    song.stageZoom = stage["defaultZoom"].asNumber(song.stageZoom);
    song.cameraSpeed = stage["cameraSpeed"].asNumber(song.cameraSpeed);
    song.hideGirlfriend = stage["hideGirlfriend"].asBool(song.hideGirlfriend);
    song.stageLayout = stage["layout"];
}

ContentLibrary::ContentLibrary(std::filesystem::path root) : root_(std::move(root)) {}

void ContentLibrary::scan() {
    songs_.clear();
    weeks_.clear();
    mods_.clear();

    const auto modRoot = root_ / "mods";
    if (std::filesystem::exists(modRoot)) {
        for (const auto& entry : std::filesystem::directory_iterator(modRoot)) {
            if (!entry.is_directory()) continue;
            const auto manifest = entry.path() / "mod.json";
            if (!std::filesystem::exists(manifest)) continue;
            try {
                const Json json = Json::fromFile(manifest);
                ModInfo mod;
                mod.root = entry.path();
                mod.id = json["id"].asString(entry.path().filename().string());
                mod.name = json["name"].asString(mod.id);
                mod.version = json["version"].asString("0.0.0");
                mod.author = json["author"].asString("Unknown");
                mod.description = json["description"].asString();
                mod.enabled = json["enabled"].asBool(true);
                mods_.push_back(std::move(mod));
            } catch (...) {}
        }
    }
    std::sort(mods_.begin(), mods_.end(), [](const ModInfo& a, const ModInfo& b) { return a.name < b.name; });

    const auto scanSongs = [&](const std::filesystem::path& packageRoot) {
        const auto songRoot = packageRoot / "songs";
        if (!std::filesystem::exists(songRoot)) return;
        for (const auto& entry : std::filesystem::directory_iterator(songRoot)) {
            if (!entry.is_directory()) continue;
            const auto manifest = entry.path() / "song.json";
            if (!std::filesystem::exists(manifest)) continue;
            try {
                const Json json = Json::fromFile(manifest);
                Song song;
                song.id = json["id"].asString(entry.path().filename().string());
                song.title = json["title"].asString(song.id);
                song.artist = json["artist"].asString("Unknown artist");
                song.description = json["description"].asString();
                song.license = json["license"].asString("Unspecified");
                song.bpm = json["bpm"].asNumber(120.0);
                song.order = json["order"].asInt(100000);
                song.weekId = json["week"].asString();
                song.stage = json["stage"].asString("stage");
                song.playerCharacter = json["playerCharacter"].asString("bf");
                song.opponentCharacter = json["opponentCharacter"].asString("dad");
                song.girlfriendCharacter = json["girlfriendCharacter"].asString("gf");
                song.audioPath = packageRoot / std::filesystem::path(json["audio"].asString());
                song.chartPath = packageRoot / std::filesystem::path(json["chart"].asString());
                song.stageImage = packageRoot / std::filesystem::path(json["stageImage"].asString());
                song.playerVisual = packageRoot / std::filesystem::path(json["playerVisual"].asString());
                song.opponentVisual = packageRoot / std::filesystem::path(json["opponentVisual"].asString());
                song.girlfriendVisual = packageRoot / std::filesystem::path(json["girlfriendVisual"].asString());
                song.playerIcon = packageRoot / std::filesystem::path(json["playerIcon"].asString());
                song.opponentIcon = packageRoot / std::filesystem::path(json["opponentIcon"].asString());
                const auto readPoint = [](const Json& value, std::array<double, 2> fallback) {
                    const auto& items = value.asArray();
                    if (items.size() == 2) return std::array<double, 2>{items[0].asNumber(fallback[0]), items[1].asNumber(fallback[1])};
                    return fallback;
                };
                song.playerPosition = readPoint(json["boyfriendPosition"], song.playerPosition);
                song.opponentPosition = readPoint(json["opponentPosition"], song.opponentPosition);
                song.girlfriendPosition = readPoint(json["girlfriendPosition"], song.girlfriendPosition);
                song.cameraPlayer = readPoint(json["cameraBoyfriend"], song.cameraPlayer);
                song.cameraOpponent = readPoint(json["cameraOpponent"], song.cameraOpponent);
                song.cameraGirlfriend = readPoint(json["cameraGirlfriend"], song.cameraGirlfriend);
                song.stageZoom = json["defaultZoom"].asNumber(0.9);
                song.cameraSpeed = json["cameraSpeed"].asNumber(1.0);
                song.hideGirlfriend = json["hideGirlfriend"].asBool(false);
                // Active package stage data is authoritative, not song copies.
                song.stageConfigPath = packageRoot / "data" / "stages" / (song.stage + ".json");
                reloadStage(song);
                if (song.id.empty() || !std::filesystem::exists(song.chartPath)) continue;
                songs_.push_back(std::move(song));
            } catch (...) {
                // Invalid packages are skipped; the engine log reports load errors when selected.
            }
        }
    };
    scanSongs(root_);
    for (const ModInfo& mod : mods_) if (mod.enabled) scanSongs(mod.root);
    std::sort(songs_.begin(), songs_.end(), [](const Song& a, const Song& b) {
        if (a.order != b.order) return a.order < b.order;
        return a.title < b.title;
    });

    const auto scanWeeks = [&](const std::filesystem::path& packageRoot) {
        const auto weekFile = packageRoot / "data" / "weeks.json";
        if (!std::filesystem::exists(weekFile)) return;
        try {
            const Json json = Json::fromFile(weekFile);
            for (const Json& item : json["weeks"].asArray()) {
                Week week;
                week.id = item["id"].asString();
                week.name = item["name"].asString(week.id);
                week.storyName = item["storyName"].asString();
                for (const Json& song : item["songs"].asArray()) week.songIds.push_back(song.asString());
                const auto& color = item["color"].asArray();
                if (color.size() == 3) for (std::size_t i = 0; i < 3; ++i) week.color[i] = std::clamp(color[i].asInt(week.color[i]), 0, 255);
                if (!week.id.empty() && !week.songIds.empty()) weeks_.push_back(std::move(week));
            }
        } catch (...) {}
    };
    scanWeeks(root_);
    for (const ModInfo& mod : mods_) if (mod.enabled) scanWeeks(mod.root);
}

const Song* ContentLibrary::findSong(std::string_view id) const {
    const auto found = std::find_if(songs_.begin(), songs_.end(), [&](const Song& song) { return song.id == id; });
    return found == songs_.end() ? nullptr : &*found;
}

void ContentLibrary::toggleMod(std::size_t index) {
    if (index >= mods_.size()) return;
    ModInfo& mod = mods_[index];
    mod.enabled = !mod.enabled;
    Json json = Json::fromFile(mod.root / "mod.json");
    json["enabled"] = mod.enabled;
    json.writeFile(mod.root / "mod.json");
}

Chart ContentLibrary::loadChart(const Song& song) const {
    const Json json = Json::fromFile(song.chartPath);
    if (json["format"].asString() != "jave-chart-v1") throw std::runtime_error("Unsupported chart format");

    Chart chart;
    chart.songId = json["song"].asString(song.id);
    chart.difficulty = json["difficulty"].asString("normal");
    chart.bpm = json["bpm"].asNumber(song.bpm);
    chart.offsetMs = json["offsetMs"].asNumber(0.0);
    if (chart.bpm <= 0.0 || chart.bpm > 1000.0) throw std::runtime_error("Chart BPM is out of range");

    for (const Json& item : json["notes"].asArray()) {
        if (!item.isObject()) throw std::runtime_error("A chart note is not an object");
        Note note;
        note.timeMs = item["timeMs"].asNumber(-1.0) + chart.offsetMs;
        note.lane = item["lane"].asInt(-1);
        note.lengthMs = std::max(0.0, item["lengthMs"].asNumber(0.0));
        note.player = item["owner"].asString("player") != "opponent";
        if (note.timeMs < 0.0 || note.lane < 0 || note.lane > 3) throw std::runtime_error("Invalid chart note");
        chart.durationMs = std::max(chart.durationMs, note.timeMs + note.lengthMs);
        chart.notes.push_back(note);
    }
    for (const Json& item : json["cameraEvents"].asArray()) {
        if (!item.isObject()) continue;
        CameraEvent event;
        event.timeMs = item["timeMs"].asNumber(0.0) + chart.offsetMs;
        event.type = item["type"].asString();
        event.target = item["target"].asString();
        event.x = item["x"].asNumber(0.0);
        event.y = item["y"].asNumber(0.0);
        event.amount = item["amount"].asNumber(0.0);
        if (!event.type.empty()) chart.cameraEvents.push_back(std::move(event));
    }
    std::stable_sort(chart.cameraEvents.begin(), chart.cameraEvents.end(), [](const CameraEvent& a, const CameraEvent& b) {
        return a.timeMs < b.timeMs;
    });
    if (chart.notes.empty()) throw std::runtime_error("Chart has no notes");
    std::stable_sort(chart.notes.begin(), chart.notes.end(), [](const Note& a, const Note& b) {
        return a.timeMs < b.timeMs;
    });
    chart.durationMs += 2000.0;
    return chart;
}

Settings ContentLibrary::loadSettings(const std::filesystem::path& root) {
    Settings settings;
    auto load = [&](const std::filesystem::path& path) {
        if (!std::filesystem::exists(path)) return;
        const Json json = Json::fromFile(path);
        settings.masterVolume = std::clamp(json["masterVolume"].asNumber(settings.masterVolume), 0.0, 1.0);
        settings.noteSpeed = std::clamp(json["noteSpeed"].asNumber(settings.noteSpeed), 0.5, 2.5);
        settings.downscroll = json["downscroll"].asBool(settings.downscroll);
        settings.fullscreen = json["fullscreen"].asBool(settings.fullscreen);
        settings.showFps = json["showFps"].asBool(settings.showFps);
        const auto& binds = json["keybinds"].asArray();
        if (binds.size() == 4) {
            for (std::size_t i = 0; i < 4; ++i) {
                const int key = binds[i].asInt(settings.keybinds[i]);
                if (key > 0 && key < 256) settings.keybinds[i] = key;
            }
        }
    };
    try {
        load(root / "config" / "default.json");
        load(root / "config" / "settings.json");
    } catch (...) {}
    return settings;
}

void ContentLibrary::saveSettings(const std::filesystem::path& root, const Settings& settings) {
    Json json(Json::Object{});
    json["masterVolume"] = settings.masterVolume;
    json["noteSpeed"] = settings.noteSpeed;
    json["downscroll"] = settings.downscroll;
    json["fullscreen"] = settings.fullscreen;
    json["showFps"] = settings.showFps;
    Json binds(Json::Array{});
    for (int key : settings.keybinds) binds.array().emplace_back(key);
    json["keybinds"] = std::move(binds);
    json.writeFile(root / "config" / "settings.json");
}

} // namespace jave
