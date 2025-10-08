# syntax=docker/dockerfile:1.7

############################
# 1) Builder
############################
FROM ubuntu:24.04 AS builder
ARG DEBIAN_FRONTEND=noninteractive
ARG CUDAARCHS=75;86;89          # 75 (Turing), 86 (Ampere/RTX 30), 89 (Ada/RTX 40)
ARG FFMPEG_VER=8.0

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]


# Toolchain + all dev headers for your chosen flags
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache \
    # 1) clear any stale locks & ensure dpkg is sane
    rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock \
          /var/cache/apt/archives/lock /var/lib/apt/lists/lock || true \
 && mkdir -p /var/lib/apt/lists/partial /var/cache/apt/archives/partial \
 && dpkg --configure -a || true \
    # 2) do ALL installs in one go (use apt-get, not apt)
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git pkg-config build-essential patchelf \
      yasm nasm clang cmake meson ninja-build autoconf automake libtool \
      zlib1g-dev libssl-dev libbz2-dev liblzma-dev \
      libfreetype6-dev libfontconfig1-dev libfribidi-dev libharfbuzz-dev libass-dev \
      libaom-dev libdav1d-dev librav1e-dev libsvtav1enc-dev libvpx-dev \
      libx264-dev libx265-dev libxvidcore-dev \
      libmp3lame-dev libopus-dev libvorbis-dev libtwolame-dev libtheora-dev \
      libwebp-dev libjxl-dev libopenjp2-7-dev \
      libsoxr-dev libspeex-dev libsnappy-dev libgme-dev \
      libbluray-dev libdvdnav-dev libdvdread-dev \
      frei0r-plugins-dev libchromaprint-dev libvidstab-dev \
      libsrt-openssl-dev librist-dev libssh-dev libzmq3-dev \
      libzimg-dev libplacebo-dev \
      ocl-icd-opencl-dev opencl-headers \
      libvulkan-dev libshaderc-dev vulkan-tools mesa-vulkan-drivers \
      libva-dev libdrm-dev \
      libzvbi-dev libxml2-dev libgmp-dev libsdl2-dev libopenal-dev \
      libaribb24-dev libvpl-dev \
      libdavs2-dev libopencore-amrnb-dev libopencore-amrwb-dev libopenh264-dev librubberband-dev \
      liblilv-dev lv2-dev libxavs2-dev \
      nvidia-cuda-toolkit \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# NVENC/NVDEC headers (official mirror)
RUN git clone --depth=1 https://github.com/FFmpeg/nv-codec-headers.git \
 && make -C nv-codec-headers install

# AviSynth+ headers-only with a real tag so VersionGen succeeds
ARG AVS_TAG=v3.7.3   # or whatever tag you want
RUN git clone --depth=1 --branch ${AVS_TAG} https://github.com/AviSynth/AviSynthPlus.git /build/AviSynthPlus \
 && cmake -S /build/AviSynthPlus -B /build/avisynth-headers -G Ninja \
      -DHEADERS_ONLY=ON -DCMAKE_INSTALL_PREFIX=/usr \
 && cmake --build /build/avisynth-headers --target VersionGen -j"$(nproc)" \
 && cmake --install /build/avisynth-headers \
 && ldconfig


# whisper.cpp (CUDA build; provides libwhisper/ggml + whisper.pc)
RUN git clone --depth=1 https://github.com/ggml-org/whisper.cpp.git
RUN apt-get update && apt-get install -y --no-install-recommends ccache
# whisper.cpp
RUN --mount=type=cache,target=/root/.cache/ccache,id=ccache \
    cmake -S /build/whisper.cpp -B /build/whisper-build \
      -DGGML_CUDA=1 -DCMAKE_CUDA_ARCHITECTURES="${CUDAARCHS}" \
      -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_C_COMPILER_LAUNCHER=ccache \
      -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
 && cmake --build /build/whisper-build -j"$(nproc)" \
 && cmake --install /build/whisper-build && ldconfig

# FFmpeg source
ADD https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VER}.tar.xz ./ffmpeg-${FFMPEG_VER}.tar.xz 
RUN tar -xf "ffmpeg-${FFMPEG_VER}.tar.xz" && rm "ffmpeg-${FFMPEG_VER}.tar.xz"

WORKDIR /build/ffmpeg-${FFMPEG_VER}

# Configure & build (removed contradictory disables; kept shared build)
RUN ./configure --prefix=/usr --enable-version3 --enable-gpl \
    --disable-debug --disable-libfdk-aac \
    --disable-libxcb --disable-w32threads --disable-xlib \
    --enable-avisynth --enable-chromaprint --enable-cuda-llvm \
    --enable-ffnvcodec --enable-filters --enable-fontconfig --enable-frei0r \
    --enable-gmp --enable-iconv --enable-libaom \
    --enable-libaribb24 --enable-libass \
    --enable-libbluray --enable-libdav1d --enable-libdavs2 --enable-libdvdnav \
    --enable-libdvdread --enable-libfreetype --enable-libfribidi \
    --enable-libgme --enable-libharfbuzz --enable-libjxl \
    --enable-libmp3lame --enable-libopencore-amrnb --enable-libopencore-amrwb \
    --enable-libopenh264 --enable-libopenjpeg --enable-libopus --enable-libplacebo --enable-libpulse \
    --enable-librav1e --enable-librubberband --enable-libshaderc \
    --enable-libsnappy --enable-libsoxr --enable-libspeex --enable-libsrt --enable-libssh \
    --enable-libsvtav1 --enable-libtheora --enable-libtwolame \
    --enable-libvidstab --enable-libvorbis --enable-libvpl \
    --enable-libvpx --enable-libwebp --enable-libx264 \
    --enable-libx265 --enable-libxavs2 --enable-libxml2 --enable-libxvid \
    --enable-libzimg --enable-libzmq --enable-libzvbi --enable-lv2 --enable-lzma \
    --enable-nonfree --enable-openal --enable-opencl --enable-openssl --enable-pthreads \
    --enable-runtime-cpudetect --enable-sdl2 --enable-shared \
    --enable-vaapi --enable-whisper --enable-zlib \
 && make -j"$(nproc)" \
 && make install \
 && ldconfig

# Package a minimal, relocatable runtime:
#  - copy ffmpeg/ffprobe + ALL their linked libs (closure)
#  - add whisper/ggml explicitly in case they’re dlopened
#  - strip to reduce size
RUN mkdir -p /opt/ffmpeg/bin /opt/ffmpeg/lib 
# Package a minimal, relocatable runtime (auto-detect paths)
RUN set -euo pipefail \
 && FFMPEG_BIN="$(command -v ffmpeg || true)" \
 && FFPROBE_BIN="$(command -v ffprobe || true)" \
 && { [ -x "$FFMPEG_BIN" ] && [ -x "$FFPROBE_BIN" ]; } \
      || { echo "ffmpeg/ffprobe not found on PATH"; exit 1; } \
 && echo "Using ffmpeg:  $FFMPEG_BIN" \
 && echo "Using ffprobe: $FFPROBE_BIN" \
 && mkdir -p /opt/ffmpeg/bin /opt/ffmpeg/lib \
 && cp -v "$FFMPEG_BIN" "$FFPROBE_BIN" /opt/ffmpeg/bin/ \
    # collect ALL linked libs from both bins
 && { ldd "$FFMPEG_BIN"; ldd "$FFPROBE_BIN"; } \
      | awk '/=> \//{print $3} /^\//{print $1}' \
      | sort -u | xargs -I{} cp -v --parents {} /opt/ffmpeg/lib/ \
    # make sure whisper/ggml are included (in case they’re not pulled by ldd)
 && for n in libwhisper libggml; do \
      so="$(ldconfig -p | awk -v n="$n" '$1 ~ n {print $4; exit}')" ; \
      [ -n "$so" ] && cp -v --parents "$so" /opt/ffmpeg/lib/ || true ; \
    done \
    # strip + set RPATH so it runs with bundled libs
 && strip --strip-unneeded /opt/ffmpeg/bin/* || true \
 && find /opt/ffmpeg/lib -type f -name "*.so*" -exec strip --strip-unneeded {} + || true \
 && patchelf --set-rpath '$ORIGIN/../lib' /opt/ffmpeg/bin/ffmpeg /opt/ffmpeg/bin/ffprobe \
 && tar -C /opt/ffmpeg -czf /tmp/ffmpeg-runtime.tgz .

############################
# 2) Runtime (tiny)
############################
FROM ubuntu:24.04 AS runtime
ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

# Only CA certs (for https inputs) — no compilers, no headers
RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# Unpack the prepacked runtime and expose ffmpeg/ffprobe on PATH
COPY --from=builder /tmp/ffmpeg-runtime.tgz /opt/
RUN tar -C /opt -xzf /opt/ffmpeg-runtime.tgz && rm /opt/ffmpeg-runtime.tgz \
 && ln -s /opt/ffmpeg/bin/ffmpeg  /usr/local/bin/ffmpeg \
 && ln -s /opt/ffmpeg/bin/ffprobe /usr/local/bin/ffprobe

# Optional: show what we built
# RUN ffmpeg -hide_banner -buildconf | sed -n '1,120p'
