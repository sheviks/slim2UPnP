# Changelog

## [0.0.1] - 2026-03-23

Initial test release.

### Added
- Slimproto client (TCP port 3483) — native implementation from public documentation
- HTTP stream client for fetching audio from LMS
- Decoders: FLAC (libFLAC), PCM/WAV/AIFF (native), DSD/DSF/DFF (native)
- Optional decoders: MP3 (libmpg123), Ogg Vorbis (libvorbisfile), AAC (fdk-aac)
- Optional FFmpeg decoder backend (libavcodec)
- DSD support: DSF, DFF, raw DSD, DoP detection and passthrough
- UPnP control point: SSDP discovery + AVTransport/RenderingControl/ConnectionManager
- Direct renderer connection via `--renderer-url` (skip SSDP, useful for cross-subnet)
- Mini HTTP server (AudioHttpServer) serving decoded audio to UPnP renderer
- WAV streaming with unknown length (RIFF header, data size 0x7FFFFFFF)
- DSF streaming for DSD-capable renderers
- Gapless playback: same-format track chaining (PCM and DSD)
- Ring buffer with flow control between decode thread and HTTP server
- PCM bit depth conversion: S32_LE MSB-aligned to 16/24/32-bit WAV
- LMS autodiscovery via UDP broadcast
- Renderer listing (`--list-renderers`)
- Volume forced to 100% for bit-perfect playback
- Exponential backoff reconnection to LMS
- CMake build system with architecture auto-detection (x64-v2/v3/v4, aarch64)
- Static build option (`-DSTATIC_BUILD=ON`)
