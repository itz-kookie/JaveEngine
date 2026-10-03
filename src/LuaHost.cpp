#include "jave/LuaHost.hpp"

#include <algorithm>
#include <utility>

#ifdef JAVE_HAS_LUA
extern "C" {
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
}
#endif

namespace jave {

LuaHost::LuaHost() = default;

LuaHost::~LuaHost() {
#ifdef JAVE_HAS_LUA
    if (state_) lua_close(state_);
#endif
}

bool LuaHost::initialize(LogFn log, AccentFn accent, PlayerFlipFn playerFlip) {
    log_ = std::move(log);
    accent_ = std::move(accent);
    playerFlip_ = std::move(playerFlip);
#ifdef JAVE_HAS_LUA
    state_ = luaL_newstate();
    if (!state_) return false;
    luaL_openlibs(state_);

    lua_pushlightuserdata(state_, this);
    lua_pushcclosure(state_, [](lua_State* lua) -> int {
        auto* self = static_cast<LuaHost*>(lua_touserdata(lua, lua_upvalueindex(1)));
        const char* message = luaL_checkstring(lua, 1);
        if (self && self->log_) self->log_(message ? message : "");
        return 0;
    }, 1);
    lua_setglobal(state_, "jave_log");

    lua_pushcfunction(state_, [](lua_State* lua) -> int {
        lua_pushliteral(lua, "Jave Engine");
        return 1;
    });
    lua_setglobal(state_, "jave_engine_name");

    lua_pushlightuserdata(state_, this);
    lua_pushcclosure(state_, [](lua_State* lua) -> int {
        auto* self = static_cast<LuaHost*>(lua_touserdata(lua, lua_upvalueindex(1)));
        const int r = static_cast<int>(luaL_checkinteger(lua, 1));
        const int g = static_cast<int>(luaL_checkinteger(lua, 2));
        const int b = static_cast<int>(luaL_checkinteger(lua, 3));
        if (self && self->accent_) self->accent_(std::clamp(r, 0, 255), std::clamp(g, 0, 255), std::clamp(b, 0, 255));
        return 0;
    }, 1);
    lua_setglobal(state_, "jave_set_accent");

    lua_pushlightuserdata(state_, this);
    lua_pushcclosure(state_, [](lua_State* lua) -> int {
        auto* self = static_cast<LuaHost*>(lua_touserdata(lua, lua_upvalueindex(1)));
        const bool flip = lua_toboolean(lua, 1) != 0;
        if (self && self->playerFlip_) self->playerFlip_(flip);
        return 0;
    }, 1);
    lua_setglobal(state_, "jave_set_player_flip");
    return true;
#else
    if (log_) log_("Lua support is disabled in this build");
    return false;
#endif
}

void LuaHost::loadScripts(const std::filesystem::path& root, const std::vector<std::filesystem::path>& modRoots) {
#ifdef JAVE_HAS_LUA
    if (!state_) return;
    std::vector<std::filesystem::path> scripts;
    const auto boot = root / "scripts" / "boot.lua";
    if (std::filesystem::exists(boot)) scripts.push_back(boot);
    std::vector<std::filesystem::path> rootScripts;
    const auto rootDirectory = root / "scripts";
    if (std::filesystem::exists(rootDirectory)) {
        for (const auto& entry : std::filesystem::directory_iterator(rootDirectory)) {
            if (entry.is_regular_file() && entry.path().extension() == ".lua" && entry.path() != boot) rootScripts.push_back(entry.path());
        }
    }
    std::sort(rootScripts.begin(), rootScripts.end());
    scripts.insert(scripts.end(), rootScripts.begin(), rootScripts.end());
    std::vector<std::filesystem::path> modScripts;
    for (const auto& mod : modRoots) {
        const auto directory = mod / "scripts";
        if (!std::filesystem::exists(directory)) continue;
        for (const auto& entry : std::filesystem::directory_iterator(directory)) {
            if (entry.is_regular_file() && entry.path().extension() == ".lua") modScripts.push_back(entry.path());
        }
    }
    std::sort(modScripts.begin(), modScripts.end());
    scripts.insert(scripts.end(), modScripts.begin(), modScripts.end());
    for (const auto& script : scripts) {
        if (luaL_dofile(state_, script.string().c_str()) != LUA_OK) {
            const char* error = lua_tostring(state_, -1);
            if (log_) log_("Lua error in " + script.string() + ": " + (error ? error : "unknown error"));
            lua_pop(state_, 1);
        }
    }
#else
    (void)root; (void)modRoots;
#endif
}

void LuaHost::update(double dt) {
#ifdef JAVE_HAS_LUA
    if (!state_) return;
    lua_getglobal(state_, "on_update");
    if (!lua_isfunction(state_, -1)) { lua_pop(state_, 1); return; }
    lua_pushnumber(state_, dt);
    call("on_update", 1);
#else
    (void)dt;
#endif
}

void LuaHost::songStart(const std::string& songId) {
#ifdef JAVE_HAS_LUA
    if (!state_) return;
    const auto invoke = [&](const char* function) {
        lua_getglobal(state_, function);
        if (!lua_isfunction(state_, -1)) { lua_pop(state_, 1); return; }
        lua_pushlstring(state_, songId.c_str(), songId.size());
        call(function, 1);
    };
    invoke("jave_core_song_start");
    invoke("on_song_start");
#else
    (void)songId;
#endif
}

void LuaHost::noteHit(int lane, const std::string& rating) {
#ifdef JAVE_HAS_LUA
    if (!state_) return;
    lua_getglobal(state_, "on_note_hit");
    if (!lua_isfunction(state_, -1)) { lua_pop(state_, 1); return; }
    lua_pushinteger(state_, lane);
    lua_pushlstring(state_, rating.c_str(), rating.size());
    call("on_note_hit", 2);
#else
    (void)lane; (void)rating;
#endif
}

void LuaHost::call(const char* function, int argumentCount) {
#ifdef JAVE_HAS_LUA
    if (lua_pcall(state_, argumentCount, 0, 0) != LUA_OK) {
        const char* error = lua_tostring(state_, -1);
        if (log_) log_(std::string("Lua callback error in ") + function + ": " + (error ? error : "unknown error"));
        lua_pop(state_, 1);
    }
#else
    (void)function; (void)argumentCount;
#endif
}

bool LuaHost::available() const {
#ifdef JAVE_HAS_LUA
    return state_ != nullptr;
#else
    return false;
#endif
}

} // namespace jave
