# Clip Editor ffmpeg

Builds the LGPL v3 `ffmpeg` and `ffprobe` that Clip Editor ships, for Windows x64 and macOS (Apple silicon and Intel).

- Only the libraries the editor needs: libass with freetype, fribidi, harfbuzz and fontconfig (for burned-in captions), plus zlib and iconv.
- H.264 is encoded by the operating system: Media Foundation (`h264_mf`) on Windows, VideoToolbox (`h264_videotoolbox`) on macOS. There is no x264 (GPL) and no OpenH264.
- No `--enable-gpl` and no `--enable-nonfree`. `build.sh` stops if configure does not report LGPL v3.

To build, open **Actions > Build LGPL ffmpeg > Run workflow**. The release it creates holds:

- one zip per platform, with `LICENSE.txt`, `BUILD.txt` (the configure flags) and `licenses/` (one folder per bundled library)
- the matching FFmpeg source
- `SHA256SUMS.txt`

The macOS builds link Homebrew libraries, so they need the runner's macOS or newer: Apple silicon needs macOS 14, Intel needs macOS 15.
