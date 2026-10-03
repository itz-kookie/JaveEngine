#include "jave/Json.hpp"

#include <charconv>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <stdexcept>

namespace jave {
namespace {

class Parser {
public:
    explicit Parser(const std::string& text) : text_(text) {}

    Json parse() {
        skipSpace();
        Json value = parseValue();
        skipSpace();
        if (position_ != text_.size()) fail("unexpected trailing content");
        return value;
    }

private:
    Json parseValue() {
        if (position_ >= text_.size()) fail("unexpected end of input");
        const char c = text_[position_];
        if (c == '{') return parseObject();
        if (c == '[') return parseArray();
        if (c == '"') return Json(parseString());
        if (c == 't') return parseLiteral("true", Json(true));
        if (c == 'f') return parseLiteral("false", Json(false));
        if (c == 'n') return parseLiteral("null", Json(nullptr));
        if (c == '-' || (c >= '0' && c <= '9')) return Json(parseNumber());
        fail("expected a JSON value");
    }

    Json parseObject() {
        ++position_;
        Json::Object result;
        skipSpace();
        if (consume('}')) return result;
        for (;;) {
            skipSpace();
            if (position_ >= text_.size() || text_[position_] != '"') fail("expected object key");
            std::string key = parseString();
            skipSpace();
            if (!consume(':')) fail("expected ':'");
            skipSpace();
            result.insert_or_assign(std::move(key), parseValue());
            skipSpace();
            if (consume('}')) break;
            if (!consume(',')) fail("expected ',' or '}'");
        }
        return result;
    }

    Json parseArray() {
        ++position_;
        Json::Array result;
        skipSpace();
        if (consume(']')) return result;
        for (;;) {
            skipSpace();
            result.push_back(parseValue());
            skipSpace();
            if (consume(']')) break;
            if (!consume(',')) fail("expected ',' or ']'");
        }
        return result;
    }

    std::string parseString() {
        if (!consume('"')) fail("expected string");
        std::string result;
        while (position_ < text_.size()) {
            char c = text_[position_++];
            if (c == '"') return result;
            if (c == '\\') {
                if (position_ >= text_.size()) fail("unfinished escape");
                switch (text_[position_++]) {
                case '"': result.push_back('"'); break;
                case '\\': result.push_back('\\'); break;
                case '/': result.push_back('/'); break;
                case 'b': result.push_back('\b'); break;
                case 'f': result.push_back('\f'); break;
                case 'n': result.push_back('\n'); break;
                case 'r': result.push_back('\r'); break;
                case 't': result.push_back('\t'); break;
                case 'u': {
                    if (position_ + 4 > text_.size()) fail("short unicode escape");
                    unsigned code = 0;
                    for (int i = 0; i < 4; ++i) {
                        const char h = text_[position_++];
                        code <<= 4;
                        if (h >= '0' && h <= '9') code += static_cast<unsigned>(h - '0');
                        else if (h >= 'a' && h <= 'f') code += static_cast<unsigned>(h - 'a' + 10);
                        else if (h >= 'A' && h <= 'F') code += static_cast<unsigned>(h - 'A' + 10);
                        else fail("invalid unicode escape");
                    }
                    if (code <= 0x7F) result.push_back(static_cast<char>(code));
                    else if (code <= 0x7FF) {
                        result.push_back(static_cast<char>(0xC0 | (code >> 6)));
                        result.push_back(static_cast<char>(0x80 | (code & 0x3F)));
                    } else {
                        result.push_back(static_cast<char>(0xE0 | (code >> 12)));
                        result.push_back(static_cast<char>(0x80 | ((code >> 6) & 0x3F)));
                        result.push_back(static_cast<char>(0x80 | (code & 0x3F)));
                    }
                    break;
                }
                default: fail("invalid escape");
                }
            } else {
                if (static_cast<unsigned char>(c) < 0x20) fail("control character in string");
                result.push_back(c);
            }
        }
        fail("unterminated string");
    }

    double parseNumber() {
        const std::size_t start = position_;
        if (text_[position_] == '-') ++position_;
        if (position_ >= text_.size()) fail("bad number");
        if (text_[position_] == '0') ++position_;
        else {
            if (text_[position_] < '1' || text_[position_] > '9') fail("bad number");
            while (position_ < text_.size() && text_[position_] >= '0' && text_[position_] <= '9') ++position_;
        }
        if (position_ < text_.size() && text_[position_] == '.') {
            ++position_;
            if (position_ >= text_.size() || text_[position_] < '0' || text_[position_] > '9') fail("bad decimal");
            while (position_ < text_.size() && text_[position_] >= '0' && text_[position_] <= '9') ++position_;
        }
        if (position_ < text_.size() && (text_[position_] == 'e' || text_[position_] == 'E')) {
            ++position_;
            if (position_ < text_.size() && (text_[position_] == '+' || text_[position_] == '-')) ++position_;
            if (position_ >= text_.size() || text_[position_] < '0' || text_[position_] > '9') fail("bad exponent");
            while (position_ < text_.size() && text_[position_] >= '0' && text_[position_] <= '9') ++position_;
        }
        const std::string token = text_.substr(start, position_ - start);
        char* end = nullptr;
        const double value = std::strtod(token.c_str(), &end);
        if (!end || *end != '\0' || !std::isfinite(value)) fail("invalid number");
        return value;
    }

    Json parseLiteral(const char* word, Json value) {
        const std::size_t length = std::char_traits<char>::length(word);
        if (text_.compare(position_, length, word) != 0) fail("invalid literal");
        position_ += length;
        return value;
    }

    void skipSpace() {
        while (position_ < text_.size()) {
            const char c = text_[position_];
            if (c != ' ' && c != '\t' && c != '\r' && c != '\n') break;
            ++position_;
        }
    }

    bool consume(char c) {
        if (position_ < text_.size() && text_[position_] == c) { ++position_; return true; }
        return false;
    }

    [[noreturn]] void fail(const std::string& message) const {
        throw std::runtime_error("JSON error at byte " + std::to_string(position_) + ": " + message);
    }

    const std::string& text_;
    std::size_t position_{};
};

std::string escapeString(const std::string& value) {
    std::ostringstream out;
    out << '"';
    for (unsigned char c : value) {
        switch (c) {
        case '"': out << "\\\""; break;
        case '\\': out << "\\\\"; break;
        case '\b': out << "\\b"; break;
        case '\f': out << "\\f"; break;
        case '\n': out << "\\n"; break;
        case '\r': out << "\\r"; break;
        case '\t': out << "\\t"; break;
        default:
            if (c < 0x20) out << "\\u" << std::hex << std::setw(4) << std::setfill('0') << static_cast<int>(c);
            else out << static_cast<char>(c);
        }
    }
    out << '"';
    return out.str();
}

void dumpValue(const Json& json, std::ostringstream& out, int indent, int depth) {
    const auto pad = [&](int level) { for (int i = 0; i < level * indent; ++i) out << ' '; };
    if (json.isNull()) out << "null";
    else if (json.isBool()) out << (json.asBool() ? "true" : "false");
    else if (json.isNumber()) {
        const double n = json.asNumber();
        if (std::floor(n) == n) out << std::fixed << std::setprecision(0) << n;
        else out << std::setprecision(12) << n;
    } else if (json.isString()) out << escapeString(json.asString());
    else if (json.isArray()) {
        const auto& array = json.asArray();
        out << '[';
        for (std::size_t i = 0; i < array.size(); ++i) {
            if (i) out << ',';
            if (indent > 0) { out << '\n'; pad(depth + 1); }
            dumpValue(array[i], out, indent, depth + 1);
        }
        if (!array.empty() && indent > 0) { out << '\n'; pad(depth); }
        out << ']';
    } else {
        const auto& object = json.asObject();
        out << '{';
        std::size_t i = 0;
        for (const auto& [key, value] : object) {
            if (i++) out << ',';
            if (indent > 0) { out << '\n'; pad(depth + 1); }
            out << escapeString(key) << (indent > 0 ? ": " : ":");
            dumpValue(value, out, indent, depth + 1);
        }
        if (!object.empty() && indent > 0) { out << '\n'; pad(depth); }
        out << '}';
    }
}

const Json nullJson;

} // namespace

Json Json::parse(const std::string& text) { return Parser(text).parse(); }

Json Json::fromFile(const std::filesystem::path& path) {
    std::ifstream stream(path, std::ios::binary);
    if (!stream) throw std::runtime_error("Cannot open JSON file: " + path.string());
    std::ostringstream buffer;
    buffer << stream.rdbuf();
    return parse(buffer.str());
}

std::string Json::dump(int indent) const {
    std::ostringstream out;
    dumpValue(*this, out, indent, 0);
    return out.str();
}

void Json::writeFile(const std::filesystem::path& path, int indent) const {
    std::filesystem::create_directories(path.parent_path());
    std::ofstream stream(path, std::ios::binary | std::ios::trunc);
    if (!stream) throw std::runtime_error("Cannot write JSON file: " + path.string());
    stream << dump(indent) << '\n';
}

bool Json::isNull() const { return std::holds_alternative<std::nullptr_t>(value_); }
bool Json::isBool() const { return std::holds_alternative<bool>(value_); }
bool Json::isNumber() const { return std::holds_alternative<double>(value_); }
bool Json::isString() const { return std::holds_alternative<std::string>(value_); }
bool Json::isArray() const { return std::holds_alternative<Array>(value_); }
bool Json::isObject() const { return std::holds_alternative<Object>(value_); }
bool Json::asBool(bool fallback) const { return isBool() ? std::get<bool>(value_) : fallback; }
double Json::asNumber(double fallback) const { return isNumber() ? std::get<double>(value_) : fallback; }
int Json::asInt(int fallback) const { return isNumber() ? static_cast<int>(std::get<double>(value_)) : fallback; }
std::string Json::asString(std::string fallback) const { return isString() ? std::get<std::string>(value_) : std::move(fallback); }
const Json::Array& Json::asArray() const { static const Array empty; return isArray() ? std::get<Array>(value_) : empty; }
const Json::Object& Json::asObject() const { static const Object empty; return isObject() ? std::get<Object>(value_) : empty; }
Json::Array& Json::array() { if (!isArray()) value_ = Array{}; return std::get<Array>(value_); }
Json::Object& Json::object() { if (!isObject()) value_ = Object{}; return std::get<Object>(value_); }
const Json& Json::operator[](std::string_view key) const {
    if (!isObject()) return nullJson;
    const auto& values = std::get<Object>(value_);
    const auto found = values.find(key);
    return found == values.end() ? nullJson : found->second;
}
Json& Json::operator[](std::string key) { return object()[std::move(key)]; }

} // namespace jave
