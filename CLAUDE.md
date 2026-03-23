# CLAUDE.md - slim2UPnP

This file provides guidance to Claude Code when working with this repository.

## Project Overview

**slim2UPnP** is a Slimproto→UPnP bridge with native DSD support. It replaces squeeze2upnp (by Philippe/Ralphy) for users who want to use LMS with a UPnP renderer (e.g., DirettaRendererUPnP) while having full DSD playback capability.

**License**: MIT (no GPL code copied). Slimproto protocol implemented from public documentation.

## Architecture

```
LMS (network)
  → slim2UPnP (single process)
    → SlimprotoClient (TCP port 3483) : control protocol
    → HttpStreamClient (port 9000) : encoded audio stream from LMS
    → Decoder (FLAC/PCM/DSD — native or FFmpeg backend)
    → Mini HTTP Server : serves decoded audio to UPnP renderer
    → UPnP Controller (AVTransport) : controls the UPnP renderer
      → UPnP Renderer (e.g., DirettaRendererUPnP)
        → DAC
```

**Threading**: main (init/signals) + slimproto (TCP LMS) + audio (HTTP→decode→serve) + UPnP controller

## Related Projects (same developer, same machine)

| Project | Path | Description |
|---------|------|-------------|
| slim2diretta | `/home/dominique/slim2Diretta/` | Native LMS player with Diretta output (mono-process) |
| DirettaRendererUPnP | `/home/dominique/DirettaRendererUPnP/` | UPnP renderer with Diretta output |
| squeeze2diretta | `/home/dominique/squeeze2diretta/` | Wrapper (Squeezelite + pipe → Diretta) |

### Code reuse from slim2diretta

The following components are directly reusable (copy, not shared repo):
- `SlimprotoClient.cpp/h` — Slimproto TCP protocol client
- `SlimprotoMessages.h` — Binary protocol message structs
- `HttpStreamClient.cpp/h` — HTTP audio stream fetcher
- `Decoder.h` — Decoder abstract interface
- `FlacDecoder.cpp/h` — FLAC decoder (libFLAC)
- `PcmDecoder.cpp/h` — PCM/WAV/AIFF header parser
- `Mp3Decoder.cpp/h` — MP3 decoder (optional)
- `OggDecoder.cpp/h` — Ogg Vorbis decoder (optional)
- `AacDecoder.cpp/h` — AAC decoder (optional)
- `FfmpegDecoder.cpp/h` — FFmpeg decoder backend (optional)
- `DsdProcessor.cpp/h` — DSD conversions
- `Config.h` — Configuration struct (adapt for UPnP)

### New components to develop

- **UPnPController** — Discover UPnP renderers (SSDP), control playback (AVTransport/SetAVTransportURI, Play, Stop, Pause)
- **AudioHttpServer** — Mini HTTP server that serves decoded audio (PCM/DSD) to the UPnP renderer
- **main.cpp** — Entry point, CLI, orchestration (adapted from slim2diretta)

## Why slim2UPnP instead of squeeze2upnp?

| | squeeze2upnp | slim2UPnP |
|---|---|---|
| **DSD** | No native DSD | Full DSD support (DSF/DFF/DoP) |
| **Architecture** | Squeezelite + bridge | Single binary |
| **Slimproto** | Delegated to Squeezelite | Native implementation |
| **Decoder** | External (Squeezelite) | Internal (libFLAC, FFmpeg) |
| **Control** | Complex IPC | Direct internal signaling |

## Code Style (same as slim2diretta)

- **C++17** standard
- **Classes**: `PascalCase`
- **Functions**: `camelCase`
- **Members**: `m_camelCase`
- **Constants**: `UPPER_SNAKE_CASE`
- **Globals**: `g_camelCase`
- **Indentation**: 4 spaces

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

## UPnP Protocol (new for this project)

### Required UPnP services
- **AVTransport**: SetAVTransportURI, Play, Stop, Pause, GetPositionInfo, GetTransportInfo
- **RenderingControl**: SetVolume, GetVolume (pass-through or force 100%)
- **ConnectionManager**: GetProtocolInfo (to check supported formats)

### Discovery
- SSDP (Simple Service Discovery Protocol) on multicast 239.255.255.250:1900
- Search for `urn:schemas-upnp-org:device:MediaRenderer:1`

### Libraries to consider
- **libupnp** (pupnp) — C library, used by many UPnP projects
- **GUPnP** — GLib-based, higher level
- Custom minimal implementation (if we want zero dependencies)

## Decoder Routing (from slim2diretta)

- **`format=p` (PCM/WAV/AIFF)**: Always uses native `PcmDecoder` (reads WAV/AIFF headers for true sample rate)
- **`format=d` (DSD)**: Always uses native DSD path (raw bitstream, not decoded)
- **`format=f` (FLAC), MP3, AAC, OGG**: Use FFmpeg when `--decoder ffmpeg` is active, native otherwise

## Lessons Learned from slim2diretta (important pitfalls)

### FFmpeg
- **Raw PCM must not use FFmpeg** — Slimproto `rate` field cannot encode rates above ~192kHz; PcmDecoder reads WAV headers for true rate
- **FFmpeg S32 output is already MSB-aligned** — do NOT apply additional shift (caused white noise in v1.2.1)
- **FFmpeg parser flush at EOF** — `av_parser_parse2(NULL, 0)` before decoder flush to recover last frame (gapless)
- **block_align must be set explicitly** for raw PCM without demuxer

### Bit Depth
- All decoders output MSB-aligned int32_t
- Open Diretta/DAC at 24-bit for sources ≤24-bit, 32-bit only for true 32-bit sources
- Some DACs report 32-bit support but physically limited to 24-bit → white noise

### Gapless
- Send silence buffers before ring buffer drains (Roon interprets underruns as errors)
- STMd sent at HTTP EOF, but decode cache may still have minutes of audio
- joinWorkerWithTimeout(1000ms) prevents indefinite blocking during format transitions

### Startup
- Retry target/server discovery indefinitely (important for systems without systemd restart like GentooPlayer/OpenRC)

## Build System

CMake with auto-detection (same pattern as slim2diretta):
- x64-v2 (baseline), x64-v3 (AVX2), x64-v4 (AVX-512)
- aarch64 (RPi4), aarch64-k16 (RPi5 16KB pages)

## Dependencies

- **libFLAC** (BSD-3-Clause) for FLAC decoding
- **libupnp** (or equivalent) for UPnP control
- **POSIX threads** (pthreads)
- **C++17 runtime**
- **Optional**: libmpg123 (MP3), libvorbis (Ogg), fdk-aac (AAC)
- **Optional**: libavcodec + libavutil (FFmpeg decoder backend)

## Cross-Platform & Distribution

Unlike slim2diretta (which depends on the proprietary Diretta SDK), slim2UPnP has **zero proprietary dependencies**. This enables:

- **Precompiled binaries** downloadable directly from GitHub Releases — no dependency on Filippo (GentooPlayer) or Piero (AudioLinux) for builds
- **All Linux platforms**: x64, aarch64 (RPi4/5), armhf — single CI pipeline
- **Windows port** feasible: Slimproto is standard TCP, UPnP is cross-platform, libFLAC/FFmpeg exist on Windows. Adaptations needed: pthreads → std::thread, RT priorities → Windows MMCSS, SSDP multicast
- **macOS port** also possible with minimal effort

This is a major adoption advantage over slim2diretta and squeeze2diretta.

## Important Notes

- Volume forced to 100% for bit-perfect playback
- No automated tests — manual testing with LMS + UPnP renderer + DAC
- Primary target: Linux (cross-platform as stretch goal)
