#pragma once

#include <filesystem>
#include <map>
#include <string>
#include <string_view>
#include <utility>
#include <variant>
#include <vector>

namespace jave {

class Json {
public:
    using Array = std::vector<Json>;
    using Object = std::map<std::string, Json, std::less<>>;
    using Value = std::variant<std::nullptr_t, bool, double, std::string, Array, Object>;

    Json() : value_(nullptr) {}
    Json(std::nullptr_t) : value_(nullptr) {}
    Json(bool value) : value_(value) {}
    Json(double value) : value_(value) {}
    Json(int value) : value_(static_cast<double>(value)) {}
    Json(std::string value) : value_(std::move(value)) {}
    Json(const char* value) : value_(std::string(value)) {}
    Json(Array value) : value_(std::move(value)) {}
    Json(Object value) : value_(std::move(value)) {}

    static Json parse(const std::string& text);
    static Json fromFile(const std::filesystem::path& path);

    [[nodiscard]] std::string dump(int indent = 2) const;
    void writeFile(const std::filesystem::path& path, int indent = 2) const;

    [[nodiscard]] bool isNull() const;
    [[nodiscard]] bool isBool() const;
    [[nodiscard]] bool isNumber() const;
    [[nodiscard]] bool isString() const;
    [[nodiscard]] bool isArray() const;
    [[nodiscard]] bool isObject() const;

    [[nodiscard]] bool asBool(bool fallback = false) const;
    [[nodiscard]] double asNumber(double fallback = 0.0) const;
    [[nodiscard]] int asInt(int fallback = 0) const;
    [[nodiscard]] std::string asString(std::string fallback = {}) const;
    [[nodiscard]] const Array& asArray() const;
    [[nodiscard]] const Object& asObject() const;
    [[nodiscard]] Array& array();
    [[nodiscard]] Object& object();

    [[nodiscard]] const Json& operator[](std::string_view key) const;
    Json& operator[](std::string key);

private:
    Value value_;
};

} // namespace jave
