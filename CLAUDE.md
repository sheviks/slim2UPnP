# CLAUDE.md - slim2UPnP

This file provides guidance to Claude Code when working with this repository.

## Project Overview

**slim2UPnP** is a Slimproto→UPnP bridge with native DSD support. It replaces squeeze2upnp (by Philippe/Ralphy) for users who want to use LMS with a UPnP renderer (e.g., DirettaRendererUPnP) while having full DSD playback capability.

**Version**: 0.0.1 (initial test release)
**License**: MIT (no GPL code copied). Slimproto protocol implemented from public documentation.

## Architecture

```
LMS (network)
  → slim2UPnP (single process)
    → SlimprotoClient (TCP port 3483) : control protocol
    → HttpStreamClient (port 9000) : encoded audio stream from LMS
    → Decoder (FLAC/PCM/DSD — native or FFmpeg backend)
    → AudioHttpServer (auto port) : serves decoded audio to UPnP renderer (pull model)
    → UPnPController (SSDP + AVTransport SOAP) : controls the UPnP renderer
      → UPnP Renderer (e.g., DirettaRendererUPnP)
        → DAC
```

**Audio flow** (pull model): decode thread fills ring buffer → UPnP renderer pulls via HTTP GET from AudioHttpServer. This is the inverse of slim2diretta (push to Diretta).

**Threading**: main (init/signals) + slimproto (TCP LMS) + audio (HTTP→decode→ring buffer) + HTTP server (serve to renderer)

## File Structure

```
slim2UPnP/
  src/
    main.cpp                  — Entry point, CLI, orchestration (adapted from slim2diretta)
    AudioHttpServer.h/cpp     — Mini HTTP server + ring buffer (replaces DirettaSync)
    UPnPController.h/cpp      — SSDP discovery + AVTransport/SOAP control (libupnp)
    Config.h                  — Configuration struct
    LogLevel.h                — Logging macros (LOG_ERROR/WARN/INFO/DEBUG)
    SlimprotoClient.h/cpp     — Slimproto TCP protocol client (from slim2diretta)
    SlimprotoMessages.h       — Binary protocol message structs (from slim2diretta)
    HttpStreamClient.h/cpp    — HTTP audio stream fetcher (from slim2diretta)
    Decoder.h/cpp             — Decoder factory + abstract base (from slim2diretta)
    FlacDecoder.h/cpp         — FLAC decoder via libFLAC (from slim2diretta)
    PcmDecoder.h/cpp          — PCM/WAV/AIFF header parser (from slim2diretta)
    DsdProcessor.h/cpp        — DSD format conversions (from slim2diretta)
    DsdStreamReader.h/cpp     — DSF/DFF container parser (from slim2diretta)
    Mp3Decoder.h/cpp          — MP3 decoder via libmpg123 (optional, from slim2diretta)
    OggDecoder.h/cpp          — Ogg Vorbis decoder (optional, from slim2diretta)
    AacDecoder.h/cpp          — AAC decoder via fdk-aac (optional, from slim2diretta)
    FfmpegDecoder.h/cpp       — FFmpeg decoder backend (optional, from slim2diretta)
  CMakeLists.txt              — Build system (libupnp instead of Diretta SDK)
  README.md                   — User documentation
  CHANGELOG.md                — Version history
  LICENSE                     — MIT license
```

## Related Projects (same developer, same machine)

| Project | Path | Description |
|---------|------|-------------|
| slim2diretta | `/home/dominique/slim2Diretta/` | Native LMS player with Diretta output (mono-process) |
| DirettaRendererUPnP | `/home/dominique/DirettaRendererUPnP/` | UPnP renderer with Diretta output |
| squeeze2diretta | `/home/dominique/squeeze2diretta/` | Wrapper (Squeezelite + pipe → Diretta) |

### Code reuse from slim2diretta

The following components are copied (not shared repo) from slim2diretta:
- `SlimprotoClient.cpp/h` — Slimproto TCP protocol client
- `SlimprotoMessages.h` — Binary protocol message structs
- `HttpStreamClient.cpp/h` — HTTP audio stream fetcher
- `Decoder.h/cpp` — Decoder factory + abstract interface
- `FlacDecoder.cpp/h`, `PcmDecoder.cpp/h` — Always-on decoders
- `Mp3Decoder.cpp/h`, `OggDecoder.cpp/h`, `AacDecoder.cpp/h` — Optional decoders
- `FfmpegDecoder.cpp/h` — Optional FFmpeg backend
- `DsdProcessor.cpp/h`, `DsdStreamReader.cpp/h` — DSD handling

### Components developed for slim2UPnP

- **UPnPController** (`src/UPnPController.h/cpp`) — SSDP discovery, direct URL connection, AVTransport/RenderingControl/ConnectionManager SOAP control via libupnp
- **AudioHttpServer** (`src/AudioHttpServer.h/cpp`) — Mini HTTP server with SPSC ring buffer, WAV/DSF header generation, PCM bit depth conversion
- **main.cpp** (`src/main.cpp`) — Orchestration adapted from slim2diretta: stream callback, DSD/PCM paths, gapless chaining, connection loop
- **Config.h** (`src/Config.h`) — UPnP-specific config (renderer name/UUID/URL, HTTP port, network interface)
- **LogLevel.h** (`src/LogLevel.h`) — Standalone logging (no DirettaSync dependency)

## Code Style (same as slim2diretta)

- **C++17** standard
- **Classes**: `PascalCase`
- **Functions**: `camelCase`
- **Members**: `m_camelCase`
- **Constants**: `UPPER_SNAKE_CASE`
- **Globals**: `g_camelCase`
- **Indentation**: 4 spaces

## Key Design Decisions

### Pull model (vs push in slim2diretta)
slim2diretta pushes audio packets to the Diretta target. slim2UPnP uses a **pull model**: the UPnP renderer connects to AudioHttpServer via HTTP GET and pulls audio data. This inversion means:
- AudioHttpServer has a ring buffer (producer: decode thread, consumer: HTTP server thread)
- Flow control via ring buffer level (writeAudio blocks when full, handleClient blocks when empty)
- Gapless: same-format tracks continue the HTTP stream without closing the connection

### Direct renderer connection (`--renderer-url`)
SSDP multicast doesn't work in all environments (WSL2, cross-subnet). The `--renderer-url` option allows direct connection to a renderer's description XML, bypassing SSDP entirely.

### WAV streaming
PCM audio is served as WAV with data chunk size = 0x7FFFFFFF (streaming unknown length). This is universally supported by UPnP renderers. The AudioHttpServer converts S32_LE MSB-aligned decoder output to target bit depth (16/24/32) at write time.

## Slimproto Protocol

Implemented from public documentation (wiki.lyrion.org, SlimDevices wiki). Reference implementations consulted: Rust slimproto crate (MIT), Ada slimp (MIT). **No code copied from squeezelite (GPL v3).**

Key messages: HELO (registration), STAT (status), strm (stream control), audg (volume - forced 100%), setd (device name).

### Key STAT Events
- STMc: Connected
- STMd: Decoder ready (HTTP EOF)
- STMf: Flushed
- STMl: Buffer threshold reached (ready to play)
- STMp: Pause confirmed
- STMr: Resume confirmed
- STMs: Stream started (first bytes received)
- STMu: Track ended naturally

## UPnP Protocol

### Implemented UPnP services
- **AVTransport**: SetAVTransportURI, Play, Stop, Pause, GetPositionInfo, GetTransportInfo
- **RenderingControl**: SetVolume (force 100%), GetVolume
- **ConnectionManager**: GetProtocolInfo (check supported formats)

### Discovery
- SSDP via `UpnpSearchAsync` for `urn:schemas-upnp-org:device:MediaRenderer:1`
- Direct connection via `--renderer-url` (UpnpDownloadXmlDoc + XML parsing)

### Library
**libupnp (pupnp)** — same library as DirettaRendererUPnP (device side). slim2UPnP uses the control point side (`UpnpRegisterClient`, `UpnpSearchAsync`, `UpnpSendAction`).

## Decoder Routing (from slim2diretta)

- **`format=p` (PCM/WAV/AIFF)**: Always uses native `PcmDecoder` (reads WAV/AIFF headers for true sample rate)
- **`format=d` (DSD)**: Always uses native DSD path (raw bitstream via DsdStreamReader)
- **`format=f` (FLAC), MP3, AAC, OGG**: Use FFmpeg when `--decoder ffmpeg` is active, native otherwise

## Lessons Learned from slim2diretta (important pitfalls)

### FFmpeg
- **Raw PCM must not use FFmpeg** — Slimproto `rate` field cannot encode rates above ~192kHz; PcmDecoder reads WAV headers for true rate
- **FFmpeg S32 output is already MSB-aligned** — do NOT apply additional shift (caused white noise in v1.2.1)
- **FFmpeg parser flush at EOF** — `av_parser_parse2(NULL, 0)` before decoder flush to recover last frame (gapless)
- **block_align must be set explicitly** for raw PCM without demuxer

### Bit Depth
- All decoders output MSB-aligned int32_t
- Serve 24-bit WAV for sources ≤24-bit, 32-bit only for true 32-bit sources
- Some DACs/renderers report 32-bit support but physically limited to 24-bit → white noise

### Gapless
- STMd sent at HTTP EOF, but decode cache may still have minutes of audio
- Shared decode cache persists across gapless same-format tracks
- 2-second gapless wait window before declaring track end

### Startup
- Retry renderer/server discovery indefinitely (important for systems without systemd restart like GentooPlayer/OpenRC)

## Build System

CMake with auto-detection (same pattern as slim2diretta):
- x64-v2 (baseline), x64-v3 (AVX2), x64-v4 (AVX-512)
- aarch64 (RPi4), aarch64-k16 (RPi5 16KB pages)
- Static build option: `-DSTATIC_BUILD=ON`
- Production build (no verbose logging): `-DNOLOG=ON`

## Dependencies

- **libFLAC** (BSD-3-Clause) for FLAC decoding
- **libupnp** (BSD) for UPnP control point (SSDP + SOAP + ixml)
- **POSIX threads** (pthreads)
- **C++17 runtime**
- **Optional**: libmpg123 (MP3), libvorbis (Ogg), fdk-aac (AAC)
- **Optional**: libavcodec + libavutil (FFmpeg decoder backend)

## Cross-Platform & Distribution

Unlike slim2diretta (which depends on the proprietary Diretta SDK), slim2UPnP has **zero proprietary dependencies**. This enables:

- **Precompiled static binaries** downloadable directly from GitHub Releases — no compilation needed for end users
- **Static builds** portable across distros of the same architecture (`-DSTATIC_BUILD=ON`)
- **Binaries are architecture-specific**: an x86_64 binary does not run on aarch64. Releases should provide separate binaries per architecture (x64-v2, x64-v3, aarch64)
- **All Linux platforms**: x64, aarch64 (RPi4/5) — single CI pipeline
- **Windows port** feasible: standard TCP + UPnP + libFLAC/FFmpeg all exist on Windows
- **macOS port** also possible with minimal effort

## Important Notes

- Volume forced to 100% for bit-perfect playback
- No automated tests — manual testing with LMS + UPnP renderer + DAC
- Primary target: Linux (cross-platform as stretch goal)
- Version is tracked in `src/main.cpp` (`SLIM2UPNP_VERSION`) and `CMakeLists.txt`
