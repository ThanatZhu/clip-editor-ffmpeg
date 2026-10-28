#!/usr/bin/env bash
# Builds the LGPL ffmpeg + ffprobe that Clip Editor bundles, with the shared libraries they load and each library's licence,
# into dist/ffmpeg-<tag>-<target>.zip. Run by .github/workflows/build.yml on Windows (MSYS2 UCRT64) and macOS (Homebrew).
# H.264 export uses the encoder of the operating system (Media Foundation / VideoToolbox), so no x264 (GPL) and no OpenH264.
# Usage: FFMPEG_TAG=n9.0.2 bash build.sh win64|macos-arm64|macos-x64
set -euo pipefail
target=$1 tag=${FFMPEG_TAG:?set FFMPEG_TAG}
root=$PWD prefix=$PWD/prefix name=ffmpeg-$tag-$target
out=$root/dist/$name
mkdir -p "$out/licenses"

git clone --quiet --depth 1 --branch "$tag" https://github.com/FFmpeg/FFmpeg.git src
flags=(--prefix="$prefix" --enable-shared --disable-static --enable-version3 --disable-ffplay --disable-doc --disable-debug
  --disable-sdl2 --disable-xlib --disable-libxcb
  --enable-libass --enable-libfreetype --enable-libfribidi --enable-libharfbuzz --enable-libfontconfig --enable-zlib --enable-iconv)
case $target in
  win64) flags+=(--enable-mediafoundation --enable-w32threads) ;;
  macos-*) flags+=(--enable-videotoolbox --enable-audiotoolbox) ;;
  *) echo "unknown target $target" >&2; exit 1 ;;
esac
(cd src && ./configure "${flags[@]}" | tee "$root/configure.log")
grep -q 'License: LGPL version 3 or later' configure.log || { echo 'configure did not end up LGPL v3' >&2; exit 1; }
make -C src -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)" >/dev/null
make -C src install >/dev/null
cp src/COPYING.LGPLv3 "$out/LICENSE.txt"
cp src/COPYING.LGPLv2.1 "$out/licenses/ffmpeg-COPYING.LGPLv2.1"

licence() { # licence <package> <dir with its licence files>
  local files; files=$(find "$2" -maxdepth 1 -type f \( -iname '*licen*' -o -iname 'copying*' -o -iname 'notice*' \) 2>/dev/null || true)
  [ -n "$files" ] || { echo "no licence file for $1 in $2" >&2; exit 1; }
  mkdir -p "$out/licenses/$1"; cp $files "$out/licenses/$1/"
}

if [ "$target" = win64 ]; then
  cp "$prefix"/bin/ffmpeg.exe "$prefix"/bin/ffprobe.exe "$prefix"/bin/*.dll "$out/"
  # the MSYS2 DLLs ffmpeg loads (ldd lists Windows' own DLLs too; those stay out)
  for dll in $(ldd "$out"/*.exe "$out"/*.dll | awk '$3 ~ /^\/ucrt64\// {print $3}' | sort -u); do
    cp "$dll" "$out/"
    pkg=$(pacman -Qqo "$dll"); pkg=${pkg#mingw-w64-ucrt-x86_64-}
    [ -d "$out/licenses/$pkg" ] || licence "$pkg" "/ucrt64/share/licenses/$pkg"
  done
else
  brew=$(brew --prefix)
  cp "$prefix"/bin/ffmpeg "$prefix"/bin/ffprobe "$out/"
  # licences of every Homebrew keg ffmpeg links, followed through the libraries' own links
  todo=("$prefix"/lib/libav*.dylib "$prefix"/lib/libsw*.dylib) seen=" "
  while [ ${#todo[@]} -gt 0 ]; do
    lib=${todo[0]} todo=("${todo[@]:1}")
    for dep in $(otool -L "$lib" | awk 'NR>1 {print $1}' | grep "^$brew/" || true); do
      case $seen in *" $dep "*) continue ;; esac
      seen="$seen$dep " todo+=("$dep")
      keg=$(echo "$dep" | sed -E 's#.*/(opt|Cellar)/([^/]+)/.*#\2#')
      [ -d "$out/licenses/$keg" ] || licence "$keg" "$brew/opt/$keg"
    done
  done
  # copy ffmpeg's own and Homebrew's dylibs next to the programs and point them at @executable_path/lib
  dylibbundler -cd -of -b -x "$out/ffmpeg" -x "$out/ffprobe" -d "$out/lib" -p @executable_path/lib/ -s "$prefix/lib" >/dev/null
  codesign --force --sign - "$out"/lib/*.dylib "$out/ffmpeg" "$out/ffprobe" # rewritten Mach-O files need a fresh ad-hoc signature
fi

{ echo "FFmpeg $tag for $target, built by ffmpeg-build/build.sh"; echo; echo "configure ${flags[*]}"; } | sed "s#$prefix#<prefix>#g" > "$out/BUILD.txt"
"$out/ffmpeg" -hide_banner -version | head -3
"$out/ffmpeg" -hide_banner -encoders | grep -E 'h264_(mf|videotoolbox)'
(cd dist && if command -v zip >/dev/null; then zip -qr "$name.zip" "$name"; else 7z a -bd "$name.zip" "$name" >/dev/null; fi)
