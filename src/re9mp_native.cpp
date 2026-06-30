#include <reframework/API.h>

#include <winsock2.h>
#include <ws2tcpip.h>
#include <iphlpapi.h>
#include <windows.h>
#include <winver.h>

#include <atomic>
#include <chrono>
#include <cstring>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <mutex>
#include <optional>
#include <random>
#include <sstream>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

namespace {
constexpr int kProtocolVersion = 1;
constexpr int kPort = 27777;
constexpr const char* kModVersion = "0.1.0";
constexpr const char* kDataDir = "reframework/data/re9mp";
constexpr const char* kCommandPath = "reframework/data/re9mp/command.json";
constexpr const char* kLocalPath = "reframework/data/re9mp/local_snapshot.json";
constexpr const char* kStatusPath = "reframework/data/re9mp/status.json";
constexpr const char* kRemotePath = "reframework/data/re9mp/remote_snapshot.json";

enum class Mode {
    Idle,
    Host,
    Client,
};

struct Snapshot {
    bool valid{false};
    uint64_t seq{0};
    uint64_t lua_time_ms{0};
    std::string scene{};
    float px{0.0f};
    float py{0.0f};
    float pz{0.0f};
    float qx{0.0f};
    float qy{0.0f};
    float qz{0.0f};
    float qw{1.0f};
    float vx{0.0f};
    float vy{0.0f};
    float vz{0.0f};
    uint32_t flags{0};
    std::string motion{};
    std::string stance{};
};

struct Command {
    uint64_t id{0};
    std::string action{};
    std::string endpoint{};
    std::string scene{};
};

struct RemoteSnapshot {
    Snapshot snap{};
    uint64_t recv_ms{0};
    std::string peer{};
};

struct NetState {
    Mode mode{Mode::Idle};
    SOCKET sock{INVALID_SOCKET};
    sockaddr_storage peer_addr{};
    int peer_addr_len{0};
    bool has_peer{false};
    bool connected{false};
    bool scene_mismatch{false};
    std::string scene_locked{};
    std::string token{};
    std::string endpoint{};
    std::string last_error{"Idle"};
    std::string local_ip{};
    std::string build_id{};
    std::string exe_version{};
    uint64_t command_id{0};
    uint64_t next_snapshot_ms{0};
    uint64_t next_hello_ms{0};
    uint64_t next_ping_ms{0};
    uint64_t last_rx_ms{0};
    uint64_t last_status_ms{0};
    uint64_t ping_nonce{0};
    int ping_ms{-1};
    uint64_t packets_sent{0};
    uint64_t packets_received{0};
    uint64_t packets_dropped{0};
    Snapshot local{};
    std::optional<RemoteSnapshot> remote{};
};

std::atomic_bool g_running{false};
std::thread g_worker{};
const REFrameworkPluginFunctions* g_ref{nullptr};
std::mutex g_log_mutex{};

uint64_t steady_ms() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count();
}

void log_info(const std::string& msg) {
    std::lock_guard<std::mutex> _{g_log_mutex};
    if (g_ref != nullptr && g_ref->log_info != nullptr) {
        g_ref->log_info("[RE9MP] %s", msg.c_str());
    }
}

void log_warn(const std::string& msg) {
    std::lock_guard<std::mutex> _{g_log_mutex};
    if (g_ref != nullptr && g_ref->log_warn != nullptr) {
        g_ref->log_warn("[RE9MP] %s", msg.c_str());
    }
}

std::string read_file(const std::filesystem::path& path) {
    std::ifstream in(path, std::ios::binary);
    if (!in) {
        return {};
    }
    std::ostringstream ss;
    ss << in.rdbuf();
    return ss.str();
}

bool write_file_atomic(const std::filesystem::path& path, const std::string& data) {
    std::error_code ec;
    std::filesystem::create_directories(path.parent_path(), ec);
    const auto tmp = path.string() + ".tmp";
    {
        std::ofstream out(tmp, std::ios::binary | std::ios::trunc);
        if (!out) {
            return false;
        }
        out << data;
    }
    MoveFileExA(tmp.c_str(), path.string().c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH);
    return true;
}

std::string json_escape(std::string_view s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (const char c : s) {
        switch (c) {
        case '\\': out += "\\\\"; break;
        case '"': out += "\\\""; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default:
            if (static_cast<unsigned char>(c) < 0x20) {
                out += ' ';
            } else {
                out += c;
            }
            break;
        }
    }
    return out;
}

std::optional<size_t> find_json_value(std::string_view json, std::string_view key) {
    const std::string needle = "\"" + std::string(key) + "\"";
    const auto key_pos = json.find(needle);
    if (key_pos == std::string_view::npos) {
        return std::nullopt;
    }
    const auto colon = json.find(':', key_pos + needle.size());
    if (colon == std::string_view::npos) {
        return std::nullopt;
    }
    size_t pos = colon + 1;
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t' || json[pos] == '\n' || json[pos] == '\r')) {
        ++pos;
    }
    if (pos >= json.size()) {
        return std::nullopt;
    }
    return pos;
}

std::optional<std::string> json_string(std::string_view json, std::string_view key) {
    const auto pos_opt = find_json_value(json, key);
    if (!pos_opt || json[*pos_opt] != '"') {
        return std::nullopt;
    }
    std::string out;
    for (size_t i = *pos_opt + 1; i < json.size(); ++i) {
        const char c = json[i];
        if (c == '"') {
            return out;
        }
        if (c == '\\' && i + 1 < json.size()) {
            const char n = json[++i];
            if (n == 'n') out += '\n';
            else if (n == 'r') out += '\r';
            else if (n == 't') out += '\t';
            else out += n;
        } else {
            out += c;
        }
    }
    return std::nullopt;
}

std::optional<double> json_number(std::string_view json, std::string_view key) {
    const auto pos_opt = find_json_value(json, key);
    if (!pos_opt) {
        return std::nullopt;
    }
    size_t end = *pos_opt;
    while (end < json.size()) {
        const char c = json[end];
        if ((c >= '0' && c <= '9') || c == '-' || c == '+' || c == '.' || c == 'e' || c == 'E') {
            ++end;
        } else {
            break;
        }
    }
    if (end == *pos_opt) {
        return std::nullopt;
    }
    try {
        return std::stod(std::string(json.substr(*pos_opt, end - *pos_opt)));
    } catch (...) {
        return std::nullopt;
    }
}

std::optional<bool> json_bool(std::string_view json, std::string_view key) {
    const auto pos_opt = find_json_value(json, key);
    if (!pos_opt) {
        return std::nullopt;
    }
    if (json.substr(*pos_opt, 4) == "true") return true;
    if (json.substr(*pos_opt, 5) == "false") return false;
    return std::nullopt;
}

std::vector<std::string> split_pipe(std::string_view text) {
    std::vector<std::string> parts;
    size_t start = 0;
    while (start <= text.size()) {
        const auto pos = text.find('|', start);
        if (pos == std::string_view::npos) {
            parts.emplace_back(text.substr(start));
            break;
        }
        parts.emplace_back(text.substr(start, pos - start));
        start = pos + 1;
    }
    return parts;
}

std::string mode_name(Mode mode) {
    switch (mode) {
    case Mode::Host: return "host";
    case Mode::Client: return "client";
    default: return "idle";
    }
}

std::string random_token() {
    std::random_device rd;
    std::mt19937_64 rng(rd());
    std::uniform_int_distribution<uint64_t> dist;
    std::ostringstream ss;
    ss << std::hex << std::setfill('0') << std::setw(16) << dist(rng);
    return ss.str();
}

std::string sockaddr_to_string(const sockaddr_storage& addr) {
    char ip[INET6_ADDRSTRLEN]{};
    uint16_t port = 0;
    if (addr.ss_family == AF_INET) {
        const auto* in = reinterpret_cast<const sockaddr_in*>(&addr);
        InetNtopA(AF_INET, const_cast<in_addr*>(&in->sin_addr), ip, sizeof(ip));
        port = ntohs(in->sin_port);
    } else if (addr.ss_family == AF_INET6) {
        const auto* in6 = reinterpret_cast<const sockaddr_in6*>(&addr);
        InetNtopA(AF_INET6, const_cast<in6_addr*>(&in6->sin6_addr), ip, sizeof(ip));
        port = ntohs(in6->sin6_port);
    }
    std::ostringstream ss;
    ss << ip << ":" << port;
    return ss.str();
}

bool sockaddr_same_peer(const sockaddr_storage& a, int a_len, const sockaddr_storage& b, int b_len) {
    if (a.ss_family != b.ss_family || a_len != b_len) {
        return false;
    }
    if (a.ss_family == AF_INET) {
        const auto* aa = reinterpret_cast<const sockaddr_in*>(&a);
        const auto* bb = reinterpret_cast<const sockaddr_in*>(&b);
        return aa->sin_port == bb->sin_port && aa->sin_addr.S_un.S_addr == bb->sin_addr.S_un.S_addr;
    }
    if (a.ss_family == AF_INET6) {
        const auto* aa = reinterpret_cast<const sockaddr_in6*>(&a);
        const auto* bb = reinterpret_cast<const sockaddr_in6*>(&b);
        return aa->sin6_port == bb->sin6_port && memcmp(&aa->sin6_addr, &bb->sin6_addr, sizeof(in6_addr)) == 0;
    }
    return false;
}

bool send_packet(NetState& st, const sockaddr_storage& addr, int addr_len, const std::string& packet) {
    if (st.sock == INVALID_SOCKET) {
        return false;
    }
    const int sent = sendto(st.sock, packet.c_str(), static_cast<int>(packet.size()), 0,
        reinterpret_cast<const sockaddr*>(&addr), addr_len);
    if (sent == SOCKET_ERROR) {
        ++st.packets_dropped;
        return false;
    }
    ++st.packets_sent;
    return true;
}

std::string get_exe_path_utf8() {
    wchar_t path[MAX_PATH]{};
    GetModuleFileNameW(nullptr, path, MAX_PATH);
    int needed = WideCharToMultiByte(CP_UTF8, 0, path, -1, nullptr, 0, nullptr, nullptr);
    if (needed <= 0) {
        return {};
    }
    std::string out(static_cast<size_t>(needed), '\0');
    WideCharToMultiByte(CP_UTF8, 0, path, -1, out.data(), needed, nullptr, nullptr);
    if (!out.empty() && out.back() == '\0') {
        out.pop_back();
    }
    return out;
}

std::string get_exe_version() {
    wchar_t path[MAX_PATH]{};
    GetModuleFileNameW(nullptr, path, MAX_PATH);
    DWORD handle = 0;
    const DWORD size = GetFileVersionInfoSizeW(path, &handle);
    if (size == 0) {
        return "unknown";
    }
    std::vector<uint8_t> data(size);
    if (!GetFileVersionInfoW(path, 0, size, data.data())) {
        return "unknown";
    }
    VS_FIXEDFILEINFO* info = nullptr;
    UINT info_len = 0;
    if (!VerQueryValueW(data.data(), L"\\", reinterpret_cast<void**>(&info), &info_len) || info == nullptr) {
        return "unknown";
    }
    std::ostringstream ss;
    ss << HIWORD(info->dwFileVersionMS) << "."
       << LOWORD(info->dwFileVersionMS) << "."
       << HIWORD(info->dwFileVersionLS) << "."
       << LOWORD(info->dwFileVersionLS);
    return ss.str();
}

std::string extract_vdf_value(std::string_view text, std::string_view key) {
    const std::string needle = "\"" + std::string(key) + "\"";
    const auto pos = text.find(needle);
    if (pos == std::string_view::npos) {
        return {};
    }
    const auto first = text.find('"', pos + needle.size());
    if (first == std::string_view::npos) {
        return {};
    }
    const auto second = text.find('"', first + 1);
    if (second == std::string_view::npos) {
        return {};
    }
    return std::string(text.substr(first + 1, second - first - 1));
}

std::string get_steam_build_id() {
    try {
        const std::filesystem::path exe = std::filesystem::u8path(get_exe_path_utf8());
        const auto game_dir = exe.parent_path();
        const auto manifest = game_dir.parent_path().parent_path() / "appmanifest_3764200.acf";
        const auto text = read_file(manifest);
        const auto build = extract_vdf_value(text, "buildid");
        return build.empty() ? "unknown" : build;
    } catch (...) {
        return "unknown";
    }
}

bool is_private_ipv4(uint32_t host_order) {
    const uint8_t a = static_cast<uint8_t>((host_order >> 24) & 0xff);
    const uint8_t b = static_cast<uint8_t>((host_order >> 16) & 0xff);
    return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}

bool is_tailscale_ipv4(uint32_t host_order) {
    const uint8_t a = static_cast<uint8_t>((host_order >> 24) & 0xff);
    const uint8_t b = static_cast<uint8_t>((host_order >> 16) & 0xff);
    return a == 100 && b >= 64 && b <= 127;
}

std::string get_best_local_ip() {
    ULONG size = 16 * 1024;
    std::vector<uint8_t> buffer(size);
    auto* addrs = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
    DWORD ret = GetAdaptersAddresses(AF_INET, GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
        nullptr, addrs, &size);
    if (ret == ERROR_BUFFER_OVERFLOW) {
        buffer.resize(size);
        addrs = reinterpret_cast<IP_ADAPTER_ADDRESSES*>(buffer.data());
        ret = GetAdaptersAddresses(AF_INET, GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST | GAA_FLAG_SKIP_DNS_SERVER,
            nullptr, addrs, &size);
    }
    if (ret != NO_ERROR) {
        return "127.0.0.1";
    }

    std::string first_private;
    std::string first_any;
    for (auto* adapter = addrs; adapter != nullptr; adapter = adapter->Next) {
        if (adapter->OperStatus != IfOperStatusUp) {
            continue;
        }
        for (auto* unicast = adapter->FirstUnicastAddress; unicast != nullptr; unicast = unicast->Next) {
            if (unicast->Address.lpSockaddr == nullptr || unicast->Address.lpSockaddr->sa_family != AF_INET) {
                continue;
            }
            auto* sin = reinterpret_cast<sockaddr_in*>(unicast->Address.lpSockaddr);
            const uint32_t host = ntohl(sin->sin_addr.S_un.S_addr);
            if ((host >> 24) == 127 || host == 0) {
                continue;
            }
            char ip[INET_ADDRSTRLEN]{};
            InetNtopA(AF_INET, &sin->sin_addr, ip, sizeof(ip));
            if (is_tailscale_ipv4(host)) {
                return ip;
            }
            if (first_private.empty() && is_private_ipv4(host)) {
                first_private = ip;
            }
            if (first_any.empty()) {
                first_any = ip;
            }
        }
    }
    if (!first_private.empty()) return first_private;
    if (!first_any.empty()) return first_any;
    return "127.0.0.1";
}

Command read_command() {
    Command cmd{};
    const auto text = read_file(kCommandPath);
    if (text.empty()) {
        return cmd;
    }
    if (auto id = json_number(text, "id")) cmd.id = static_cast<uint64_t>(*id);
    if (auto action = json_string(text, "action")) cmd.action = *action;
    if (auto endpoint = json_string(text, "endpoint")) cmd.endpoint = *endpoint;
    if (auto scene = json_string(text, "scene")) cmd.scene = *scene;
    return cmd;
}

Snapshot read_local_snapshot() {
    Snapshot snap{};
    const auto text = read_file(kLocalPath);
    if (text.empty()) {
        return snap;
    }
    snap.valid = json_bool(text, "valid").value_or(false);
    if (auto v = json_number(text, "seq")) snap.seq = static_cast<uint64_t>(*v);
    if (auto v = json_number(text, "time_ms")) snap.lua_time_ms = static_cast<uint64_t>(*v);
    if (auto v = json_string(text, "scene")) snap.scene = *v;
    if (auto v = json_number(text, "px")) snap.px = static_cast<float>(*v);
    if (auto v = json_number(text, "py")) snap.py = static_cast<float>(*v);
    if (auto v = json_number(text, "pz")) snap.pz = static_cast<float>(*v);
    if (auto v = json_number(text, "qx")) snap.qx = static_cast<float>(*v);
    if (auto v = json_number(text, "qy")) snap.qy = static_cast<float>(*v);
    if (auto v = json_number(text, "qz")) snap.qz = static_cast<float>(*v);
    if (auto v = json_number(text, "qw")) snap.qw = static_cast<float>(*v);
    if (auto v = json_number(text, "vx")) snap.vx = static_cast<float>(*v);
    if (auto v = json_number(text, "vy")) snap.vy = static_cast<float>(*v);
    if (auto v = json_number(text, "vz")) snap.vz = static_cast<float>(*v);
    if (auto v = json_number(text, "flags")) snap.flags = static_cast<uint32_t>(*v);
    if (auto v = json_string(text, "motion")) snap.motion = *v;
    if (auto v = json_string(text, "stance")) snap.stance = *v;
    return snap;
}

std::string snapshot_packet(const Snapshot& s) {
    std::ostringstream ss;
    ss << std::fixed << std::setprecision(5);
    ss << "SNAP|" << s.seq << "|" << steady_ms() << "|"
       << s.scene << "|"
       << s.px << "|" << s.py << "|" << s.pz << "|"
       << s.qx << "|" << s.qy << "|" << s.qz << "|" << s.qw << "|"
       << s.vx << "|" << s.vy << "|" << s.vz << "|"
       << s.flags << "|" << s.motion << "|" << s.stance;
    return ss.str();
}

std::optional<Snapshot> packet_to_snapshot(const std::vector<std::string>& parts) {
    if (parts.size() < 17 || parts[0] != "SNAP") {
        return std::nullopt;
    }
    try {
        Snapshot s{};
        s.valid = true;
        s.seq = std::stoull(parts[1]);
        s.lua_time_ms = std::stoull(parts[2]);
        s.scene = parts[3];
        s.px = std::stof(parts[4]);
        s.py = std::stof(parts[5]);
        s.pz = std::stof(parts[6]);
        s.qx = std::stof(parts[7]);
        s.qy = std::stof(parts[8]);
        s.qz = std::stof(parts[9]);
        s.qw = std::stof(parts[10]);
        s.vx = std::stof(parts[11]);
        s.vy = std::stof(parts[12]);
        s.vz = std::stof(parts[13]);
        s.flags = static_cast<uint32_t>(std::stoul(parts[14]));
        s.motion = parts[15];
        s.stance = parts[16];
        return s;
    } catch (...) {
        return std::nullopt;
    }
}

void write_remote_snapshot(const NetState& st) {
    if (!st.remote) {
        write_file_atomic(kRemotePath, "{\n  \"valid\": false\n}\n");
        return;
    }
    const auto& r = *st.remote;
    const auto age = steady_ms() > r.recv_ms ? steady_ms() - r.recv_ms : 0;
    std::ostringstream ss;
    ss << std::fixed << std::setprecision(5);
    ss << "{\n"
       << "  \"valid\": true,\n"
       << "  \"seq\": " << r.snap.seq << ",\n"
       << "  \"recv_age_ms\": " << age << ",\n"
       << "  \"peer\": \"" << json_escape(r.peer) << "\",\n"
       << "  \"scene\": \"" << json_escape(r.snap.scene) << "\",\n"
       << "  \"px\": " << r.snap.px << ",\n"
       << "  \"py\": " << r.snap.py << ",\n"
       << "  \"pz\": " << r.snap.pz << ",\n"
       << "  \"qx\": " << r.snap.qx << ",\n"
       << "  \"qy\": " << r.snap.qy << ",\n"
       << "  \"qz\": " << r.snap.qz << ",\n"
       << "  \"qw\": " << r.snap.qw << ",\n"
       << "  \"vx\": " << r.snap.vx << ",\n"
       << "  \"vy\": " << r.snap.vy << ",\n"
       << "  \"vz\": " << r.snap.vz << ",\n"
       << "  \"flags\": " << r.snap.flags << ",\n"
       << "  \"motion\": \"" << json_escape(r.snap.motion) << "\",\n"
       << "  \"stance\": \"" << json_escape(r.snap.stance) << "\"\n"
       << "}\n";
    write_file_atomic(kRemotePath, ss.str());
}

void write_status(const NetState& st) {
    const std::string state = st.connected ? "connected" :
        (st.mode == Mode::Host ? "listening" : (st.mode == Mode::Client ? "connecting" : "idle"));
    const std::string join_code = (st.mode == Mode::Host && !st.token.empty())
        ? (st.local_ip + ":" + std::to_string(kPort) + ":" + st.token)
        : "";
    const std::string peer = st.has_peer ? sockaddr_to_string(st.peer_addr) : "";
    const auto remote_age = st.remote ? (steady_ms() > st.remote->recv_ms ? steady_ms() - st.remote->recv_ms : 0) : 0;

    std::ostringstream ss;
    ss << "{\n"
       << "  \"valid\": true,\n"
       << "  \"protocol\": " << kProtocolVersion << ",\n"
       << "  \"mod_version\": \"" << kModVersion << "\",\n"
       << "  \"mode\": \"" << mode_name(st.mode) << "\",\n"
       << "  \"state\": \"" << state << "\",\n"
       << "  \"connected\": " << (st.connected ? "true" : "false") << ",\n"
       << "  \"scene_mismatch\": " << (st.scene_mismatch ? "true" : "false") << ",\n"
       << "  \"scene_locked\": \"" << json_escape(st.scene_locked) << "\",\n"
       << "  \"local_scene\": \"" << json_escape(st.local.scene) << "\",\n"
       << "  \"local_player_valid\": " << (st.local.valid ? "true" : "false") << ",\n"
       << "  \"token\": \"" << json_escape(st.token) << "\",\n"
       << "  \"endpoint\": \"" << json_escape(st.endpoint) << "\",\n"
       << "  \"join_code\": \"" << json_escape(join_code) << "\",\n"
       << "  \"local_ip\": \"" << json_escape(st.local_ip) << "\",\n"
       << "  \"peer\": \"" << json_escape(peer) << "\",\n"
       << "  \"last_error\": \"" << json_escape(st.last_error) << "\",\n"
       << "  \"ping_ms\": " << st.ping_ms << ",\n"
       << "  \"packets_sent\": " << st.packets_sent << ",\n"
       << "  \"packets_received\": " << st.packets_received << ",\n"
       << "  \"packets_dropped\": " << st.packets_dropped << ",\n"
       << "  \"remote_age_ms\": " << remote_age << ",\n"
       << "  \"build_id\": \"" << json_escape(st.build_id) << "\",\n"
       << "  \"exe_version\": \"" << json_escape(st.exe_version) << "\"\n"
       << "}\n";
    write_file_atomic(kStatusPath, ss.str());
}

void close_socket(NetState& st) {
    if (st.sock != INVALID_SOCKET) {
        closesocket(st.sock);
        st.sock = INVALID_SOCKET;
    }
}

void stop_network(NetState& st, const std::string& reason = "Idle") {
    if (st.connected && st.has_peer) {
        send_packet(st, st.peer_addr, st.peer_addr_len, "BYE|" + reason);
    }
    close_socket(st);
    st.mode = Mode::Idle;
    st.connected = false;
    st.has_peer = false;
    st.scene_mismatch = false;
    st.scene_locked.clear();
    st.endpoint.clear();
    st.last_error = reason;
    st.remote.reset();
    write_remote_snapshot(st);
}

bool make_nonblocking(SOCKET sock) {
    u_long enabled = 1;
    return ioctlsocket(sock, FIONBIO, &enabled) == 0;
}

bool start_host(NetState& st) {
    stop_network(st, "Restarting host");
    st.sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (st.sock == INVALID_SOCKET) {
        st.last_error = "socket() failed";
        return false;
    }
    make_nonblocking(st.sock);
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(kPort);
    if (bind(st.sock, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == SOCKET_ERROR) {
        st.last_error = "bind UDP 27777 failed";
        close_socket(st);
        return false;
    }
    st.mode = Mode::Host;
    st.connected = false;
    st.has_peer = false;
    st.scene_mismatch = false;
    st.token = random_token();
    st.scene_locked = st.local.scene;
    st.local_ip = get_best_local_ip();
    st.last_error = "Host listening";
    log_info("Host listening on UDP 27777, token " + st.token);
    return true;
}

bool parse_endpoint(const std::string& endpoint, std::string& ip, uint16_t& port, std::string& token) {
    const auto first = endpoint.find(':');
    const auto second = first == std::string::npos ? std::string::npos : endpoint.find(':', first + 1);
    if (first == std::string::npos || second == std::string::npos) {
        return false;
    }
    ip = endpoint.substr(0, first);
    try {
        port = static_cast<uint16_t>(std::stoul(endpoint.substr(first + 1, second - first - 1)));
    } catch (...) {
        return false;
    }
    token = endpoint.substr(second + 1);
    return !ip.empty() && port != 0 && !token.empty();
}

bool start_client(NetState& st, const std::string& endpoint) {
    stop_network(st, "Restarting client");
    std::string ip;
    uint16_t port = 0;
    std::string token;
    if (!parse_endpoint(endpoint, ip, port, token)) {
        st.last_error = "Join code must be ip:port:token";
        return false;
    }
    st.sock = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
    if (st.sock == INVALID_SOCKET) {
        st.last_error = "socket() failed";
        return false;
    }
    make_nonblocking(st.sock);
    sockaddr_in server{};
    server.sin_family = AF_INET;
    server.sin_port = htons(port);
    if (InetPtonA(AF_INET, ip.c_str(), &server.sin_addr) != 1) {
        st.last_error = "Invalid IPv4 address";
        close_socket(st);
        return false;
    }
    st.mode = Mode::Client;
    st.connected = false;
    st.has_peer = true;
    st.peer_addr = {};
    memcpy(&st.peer_addr, &server, sizeof(server));
    st.peer_addr_len = sizeof(server);
    st.scene_mismatch = false;
    st.scene_locked = st.local.scene;
    st.endpoint = endpoint;
    st.token = token;
    st.next_hello_ms = 0;
    st.last_error = "Connecting";
    log_info("Client connecting to " + endpoint);
    return true;
}

std::string make_hello(const NetState& st) {
    std::ostringstream ss;
    ss << "HELLO|" << kProtocolVersion << "|" << st.token << "|" << kModVersion << "|"
       << st.build_id << "|" << st.exe_version << "|" << st.local.scene;
    return ss.str();
}

std::string make_welcome(const NetState& st) {
    std::ostringstream ss;
    ss << "WELCOME|" << kProtocolVersion << "|" << kModVersion << "|"
       << st.build_id << "|" << st.exe_version << "|" << st.local.scene;
    return ss.str();
}

void handle_packet(NetState& st, const std::string& packet, const sockaddr_storage& from, int from_len) {
    const auto parts = split_pipe(packet);
    if (parts.empty()) {
        return;
    }
    ++st.packets_received;
    st.last_rx_ms = steady_ms();

    if (parts[0] == "HELLO" && st.mode == Mode::Host) {
        if (parts.size() < 7) {
            send_packet(st, from, from_len, "DENY|Malformed HELLO");
            return;
        }
        const auto proto = std::stoi(parts[1]);
        const auto& token = parts[2];
        const auto& peer_build = parts[4];
        const auto& peer_exe = parts[5];
        const auto& peer_scene = parts[6];
        if (proto != kProtocolVersion) {
            send_packet(st, from, from_len, "DENY|Protocol mismatch");
            return;
        }
        if (token != st.token) {
            send_packet(st, from, from_len, "DENY|Bad session token");
            return;
        }
        if (peer_build != st.build_id) {
            send_packet(st, from, from_len, "DENY|BuildID mismatch");
            return;
        }
        if (peer_exe != st.exe_version) {
            send_packet(st, from, from_len, "DENY|re9.exe version mismatch");
            return;
        }
        if (!st.scene_locked.empty() && peer_scene != st.scene_locked) {
            st.scene_mismatch = true;
            send_packet(st, from, from_len, "DENY|Scene mismatch: host=" + st.scene_locked + " client=" + peer_scene);
            return;
        }
        st.peer_addr = from;
        st.peer_addr_len = from_len;
        st.has_peer = true;
        st.connected = true;
        st.scene_mismatch = false;
        st.last_error = "Remote connected";
        send_packet(st, from, from_len, make_welcome(st));
        return;
    }

    if (parts[0] == "WELCOME" && st.mode == Mode::Client) {
        if (parts.size() >= 7) {
            const auto proto = std::stoi(parts[1]);
            const auto& host_build = parts[4];
            const auto& host_exe = parts[5];
            const auto& host_scene = parts[6];
            if (proto == kProtocolVersion && host_build == st.build_id && host_exe == st.exe_version && host_scene == st.scene_locked) {
                st.connected = true;
                st.scene_mismatch = false;
                st.last_error = "Connected";
            } else {
                st.scene_mismatch = host_scene != st.scene_locked;
                st.last_error = "WELCOME mismatch";
            }
        }
        return;
    }

    if (parts[0] == "DENY") {
        st.connected = false;
        st.scene_mismatch = packet.find("Scene mismatch") != std::string::npos;
        st.last_error = parts.size() > 1 ? parts[1] : "Denied";
        return;
    }

    if (parts[0] == "BYE") {
        st.connected = false;
        st.last_error = parts.size() > 1 ? parts[1] : "Peer disconnected";
        st.remote.reset();
        write_remote_snapshot(st);
        return;
    }

    if (parts[0] == "PING" && parts.size() >= 3 && st.has_peer) {
        send_packet(st, from, from_len, "PONG|" + parts[1] + "|" + parts[2]);
        return;
    }

    if (parts[0] == "PONG" && parts.size() >= 3) {
        try {
            const auto sent_ms = std::stoull(parts[2]);
            const auto now = steady_ms();
            st.ping_ms = now >= sent_ms ? static_cast<int>(now - sent_ms) : -1;
        } catch (...) {
        }
        return;
    }

    if (parts[0] == "SNAP") {
        if (st.has_peer && !sockaddr_same_peer(st.peer_addr, st.peer_addr_len, from, from_len)) {
            ++st.packets_dropped;
            return;
        }
        auto snap = packet_to_snapshot(parts);
        if (!snap) {
            ++st.packets_dropped;
            return;
        }
        if (!st.scene_locked.empty() && snap->scene != st.scene_locked) {
            st.scene_mismatch = true;
            st.last_error = "Remote scene changed";
            return;
        }
        st.remote = RemoteSnapshot{*snap, steady_ms(), sockaddr_to_string(from)};
        st.connected = true;
        write_remote_snapshot(st);
    }
}

void recv_packets(NetState& st) {
    if (st.sock == INVALID_SOCKET) {
        return;
    }
    for (int i = 0; i < 64; ++i) {
        char buffer[2048]{};
        sockaddr_storage from{};
        int from_len = sizeof(from);
        const int received = recvfrom(st.sock, buffer, sizeof(buffer) - 1, 0,
            reinterpret_cast<sockaddr*>(&from), &from_len);
        if (received == SOCKET_ERROR) {
            const auto err = WSAGetLastError();
            if (err == WSAEINVAL && st.connected) {
                return;
            }
            if (err != WSAEWOULDBLOCK) {
                st.last_error = "recvfrom failed: " + std::to_string(err);
            }
            return;
        }
        buffer[received] = '\0';
        try {
            handle_packet(st, std::string(buffer, static_cast<size_t>(received)), from, from_len);
        } catch (...) {
            ++st.packets_dropped;
        }
    }
}

void network_tick(NetState& st) {
    const auto now = steady_ms();
    recv_packets(st);

    if (st.mode == Mode::Client && !st.connected && st.has_peer && now >= st.next_hello_ms) {
        send_packet(st, st.peer_addr, st.peer_addr_len, make_hello(st));
        st.next_hello_ms = now + 500;
    }

    if (st.connected && now >= st.next_ping_ms && st.has_peer) {
        ++st.ping_nonce;
        send_packet(st, st.peer_addr, st.peer_addr_len, "PING|" + std::to_string(st.ping_nonce) + "|" + std::to_string(now));
        st.next_ping_ms = now + 1000;
    }

    if (st.connected && st.has_peer && st.local.valid && now >= st.next_snapshot_ms) {
        if (!st.scene_locked.empty() && st.local.scene != st.scene_locked) {
            st.connected = false;
            st.scene_mismatch = true;
            st.last_error = "Local scene changed";
        } else {
            send_packet(st, st.peer_addr, st.peer_addr_len, snapshot_packet(st.local));
        }
        st.next_snapshot_ms = now + 33;
    }

    if (st.connected && st.last_rx_ms != 0 && now > st.last_rx_ms + 3000) {
        st.connected = false;
        st.last_error = "Remote timeout";
        st.remote.reset();
        write_remote_snapshot(st);
    }
}

void process_command(NetState& st, const Command& cmd) {
    if (cmd.id == 0 || cmd.id == st.command_id) {
        return;
    }
    st.command_id = cmd.id;
    if (cmd.action == "host") {
        if (!st.local.valid || st.local.scene.empty()) {
            st.last_error = "Cannot host: player/scene not detected";
            return;
        }
        start_host(st);
    } else if (cmd.action == "join") {
        if (!st.local.valid || st.local.scene.empty()) {
            st.last_error = "Cannot join: player/scene not detected";
            return;
        }
        start_client(st, cmd.endpoint);
    } else if (cmd.action == "disconnect" || cmd.action == "stop") {
        stop_network(st, "Disconnected");
    } else {
        st.last_error = "Unknown command: " + cmd.action;
    }
}

void worker_main() {
    WSADATA wsa{};
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) {
        log_warn("WSAStartup failed");
        return;
    }

    NetState st{};
    st.local_ip = get_best_local_ip();
    st.build_id = get_steam_build_id();
    st.exe_version = get_exe_version();
    std::filesystem::create_directories(kDataDir);
    write_remote_snapshot(st);
    write_status(st);
    log_info("Native networking ready: build " + st.build_id + ", re9.exe " + st.exe_version);

    while (g_running.load(std::memory_order_acquire)) {
        st.local = read_local_snapshot();
        process_command(st, read_command());
        network_tick(st);

        const auto now = steady_ms();
        if (now >= st.last_status_ms + 200) {
            st.local_ip = get_best_local_ip();
            write_status(st);
            st.last_status_ms = now;
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }

    stop_network(st, "Plugin shutting down");
    write_status(st);
    WSACleanup();
}

void start_worker() {
    bool expected = false;
    if (!g_running.compare_exchange_strong(expected, true)) {
        return;
    }
    g_worker = std::thread(worker_main);
}

void stop_worker() {
    if (!g_running.exchange(false)) {
        return;
    }
    if (g_worker.joinable()) {
        g_worker.join();
    }
}
}

extern "C" __declspec(dllexport) void reframework_plugin_required_version(REFrameworkPluginVersion* version) {
    version->major = REFRAMEWORK_PLUGIN_VERSION_MAJOR;
    version->minor = REFRAMEWORK_PLUGIN_VERSION_MINOR;
    version->patch = REFRAMEWORK_PLUGIN_VERSION_PATCH;
    version->game_name = nullptr;
}

extern "C" __declspec(dllexport) bool reframework_plugin_initialize(const REFrameworkPluginInitializeParam* param) {
    if (param == nullptr || param->functions == nullptr) {
        return false;
    }
    g_ref = param->functions;
    start_worker();
    log_info("Loaded re9mp native plugin");
    return true;
}

BOOL APIENTRY DllMain(HMODULE, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_DETACH) {
        stop_worker();
    }
    return TRUE;
}
