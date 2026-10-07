cmake_minimum_required(VERSION 3.24)
project(JaveEngine VERSION 0.1.0 LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

option(JAVE_ENABLE_LUA "Build the Lua 5.4 scripting host" ON)

if(NOT WIN32)
  message(FATAL_ERROR "Jave Engine currently targets Windows 10/11.")
endif()

add_executable(JaveEngine WIN32
  src/main.cpp
  src/Json.cpp
  src/Content.cpp
  src/Audio.cpp
  src/Video.cpp
  src/LuaHost.cpp
  src/Engine.cpp
)

target_include_directories(JaveEngine PRIVATE include)
target_compile_definitions(JaveEngine PRIVATE UNICODE _UNICODE NOMINMAX WIN32_LEAN_AND_MEAN _WIN32_WINNT=0x0A00)
if(MSVC)
  target_compile_options(JaveEngine PRIVATE /W4 /permissive- /utf-8)
else()
  target_compile_options(JaveEngine PRIVATE -Wall -Wextra -Wpedantic)
endif()
target_link_libraries(JaveEngine PRIVATE winmm msimg32 shlwapi gdiplus ole32 uuid)

if(JAVE_ENABLE_LUA)
  include(FetchContent)
  FetchContent_Declare(lua_source
    URL https://www.lua.org/ftp/lua-5.4.8.tar.gz
    URL_HASH SHA256=4f18ddae154e793e46eeab727c59ef1c0c0c2b744e7b94219710d76f530629ae
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
  )
  FetchContent_GetProperties(lua_source)
  if(NOT lua_source_POPULATED)
    FetchContent_Populate(lua_source)
  endif()
  file(GLOB LUA_C_SOURCES CONFIGURE_DEPENDS "${lua_source_SOURCE_DIR}/src/*.c")
  list(FILTER LUA_C_SOURCES EXCLUDE REGEX "/lua\.c$")
  list(FILTER LUA_C_SOURCES EXCLUDE REGEX "/luac\.c$")
  add_library(jave_lua STATIC ${LUA_C_SOURCES})
  target_include_directories(jave_lua PUBLIC "${lua_source_SOURCE_DIR}/src")
  target_link_libraries(JaveEngine PRIVATE jave_lua)
  target_compile_definitions(JaveEngine PRIVATE JAVE_HAS_LUA=1)
endif()

set(JAVE_RUNTIME_DIRS assets mods scripts config saves licenses)
foreach(runtime_dir IN LISTS JAVE_RUNTIME_DIRS)
  add_custom_command(TARGET JaveEngine POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
      "${CMAKE_SOURCE_DIR}/${runtime_dir}"
      "$<TARGET_FILE_DIR:JaveEngine>/${runtime_dir}"
  )
endforeach()

set(JAVE_RUNTIME_FILES
  README.md
  LICENSE
  THIRD_PARTY_NOTICES.md
)
foreach(runtime_file IN LISTS JAVE_RUNTIME_FILES)
  add_custom_command(TARGET JaveEngine POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${CMAKE_SOURCE_DIR}/${runtime_file}"
      "$<TARGET_FILE_DIR:JaveEngine>/${runtime_file}"
  )
endforeach()

set_property(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR} PROPERTY VS_STARTUP_PROJECT JaveEngine)

install(TARGETS JaveEngine RUNTIME DESTINATION .)
install(DIRECTORY assets mods scripts config saves licenses DESTINATION .)
install(FILES ${JAVE_RUNTIME_FILES} DESTINATION .)
