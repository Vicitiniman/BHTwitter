# Dependencies

Each dependency lives in a folder named after it, with the upstream repo as a
submodule at `upstream/` and any wrapper files in the folder root.

## flex

https://github.com/FLEXTool/FLEX, wrapped as the `libbhFLEX` subproject
(Makefile and injection filter plist in the folder root).

## zxPluginsInject

https://github.com/asdfzxcvbn/zxPluginsInject (v1.0.1), only built for
sideloaded packages. Built directly from `upstream/`.

## ffmpeg-kit-next

https://github.com/arthenica/ffmpeg-kit-next (v8.1.0), source of the
libffmpegkit wrapper and the pin for the FFmpeg version below. Only needed
when regenerating the prebuilt libraries.

`build/` (headers at the top, libraries in `lib/`) holds the built stack:
ffmpeg-kit-next 8.1.0 (FFmpeg n8.1.2), arm64 iOS, static only. Not tracked
in git: `build.sh` runs `build-ffmpeg.sh` automatically when the libraries
are missing, compiling with Xcode on macOS or cross-compiling with the
Theos toolchain on Linux (cached under /tmp afterwards). FFmpeg is trimmed
to the components the media download flows use (HLS/HTTPS demux,
H.264/HEVC/AAC decode, scale, VideoToolbox H.264 encode, palette-based
GIF encode, mp4/gif mux), with TLS provided by the system SecureTransport
backend instead of OpenSSL.
The FFmpeg tag must stay in lockstep with the submodule (its vendored
fftools sources compile against FFmpeg internals).

## Machine prerequisites

- **Theos** at `$THEOS`.
- **cyan** (pyzule-rw) for the IPA merge steps in `build.sh`.
