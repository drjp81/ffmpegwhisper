# syntax=docker/dockerfile:1.7

############################
# base-tools: compilers & build helpers (very stable)
############################
FROM ubuntu:24.04 AS base-tools
ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash","-euxo","pipefail","-c"]

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache \
    rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock /var/lib/apt/lists/lock || true \
 && mkdir -p /var/lib/apt/lists/partial /var/cache/apt/archives/partial \
 && dpkg --configure -a || true \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git pkg-config build-essential \
      yasm nasm clang ccache cmake meson ninja-build autoconf automake libtool patchelf \
 && rm -rf /var/lib/apt/lists/*

############################
# nvcodec: NVENC/NVDEC headers → staged install
############################
FROM base-tools AS nvcodec
WORKDIR /src
RUN git clone --depth=1 https://github.com/FFmpeg/nv-codec-headers.git \
 && make -C nv-codec-headers install DESTDIR=/opt/stage PREFIX=/usr

############################
# avisynth: headers-only (fast) → staged install
############################
FROM base-tools AS avisynth
ARG AVS_TAG=v3.7.5
WORKDIR /src
RUN git clone --depth=1 --branch ${AVS_TAG} https://github.com/AviSynth/AviSynthPlus.git \
 && cmake -S AviSynthPlus -B build -G Ninja -DHEADERS_ONLY=ON -DCMAKE_INSTALL_PREFIX=/usr \
 && cmake --build build --target VersionGen -j"$(nproc)" \
 && DESTDIR=/opt/stage cmake --install build

############################
# whisper: libwhisper/ggml (CUDA) → staged install (tagged & canonical libdir)
############################
FROM base-tools AS whisper
ARG CUDAARCHS=86                    
ARG WHISPER_TAG=v1.8.0            

# CUDA toolchain for GGML CUDA
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache \
    apt-get update && apt-get install -y --no-install-recommends nvidia-cuda-toolkit \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth=1 --branch ${WHISPER_TAG} https://github.com/ggml-org/whisper.cpp.git \
 && cmake -S whisper.cpp -B build \
      -DGGML_CUDA=1 \
      -DCMAKE_CUDA_ARCHITECTURES="${CUDAARCHS}" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
      -DCMAKE_INSTALL_LIBDIR=lib \           
      -DCMAKE_INSTALL_INCLUDEDIR=include \   
      -DCMAKE_C_COMPILER_LAUNCHER=ccache \
      -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
 && cmake --build build -j"$(nproc)" \
 && DESTDIR=/opt/stage cmake --install build \
 && PKG_CONFIG_PATH=/opt/stage/usr/lib/pkgconfig:/opt/stage/usr/lib/x86_64-linux-gnu/pkgconfig \
    pkg-config --print-errors --modversion whisper


############################
# ffmpeg-deps: all -dev headers your flags rely on (keep as a superset)
############################
FROM base-tools AS ffmpeg-deps
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache \
    apt-get update && apt-get install -y --no-install-recommends \
      zlib1g-dev libbz2-dev liblzma-dev libxml2-dev libgmp-dev libzvbi-dev \
      libfreetype6-dev libfontconfig1-dev libfribidi-dev libharfbuzz-dev libass-dev \
      libaom-dev libdav1d-dev librav1e-dev libsvtav1enc-dev libvpx-dev \
      libx264-dev libx265-dev libxvidcore-dev libmp3lame-dev libopus-dev \
      libvorbis-dev libtwolame-dev libtheora-dev libwebp-dev libjxl-dev libopenjp2-7-dev \
      libsoxr-dev libspeex-dev libsnappy-dev libgme-dev \
      libbluray-dev libdvdnav-dev libdvdread-dev frei0r-plugins-dev libchromaprint-dev libvidstab-dev \
      libsrt-gnutls-dev libgnutls28-dev librist-dev libssh-dev libzmq3-dev \
      libzimg-dev \
      ocl-icd-opencl-dev opencl-headers \
      libva-dev libdrm-dev libaribb24-dev libvpl-dev \
      libdavs2-dev libopencore-amrnb-dev libopencore-amrwb-dev libopenh264-dev librubberband-dev \
      liblilv-dev lv2-dev libxavs2-dev \
      libsdl2-dev libopenal-dev \
    && rm -rf /var/lib/apt/lists/*

############################
# builder: bring artifacts + deps, then build FFmpeg
############################
FROM ffmpeg-deps AS builder
ARG FFMPEG_VER=8.0
WORKDIR /

COPY --from=nvcodec  /opt/stage/ /
COPY --from=avisynth /opt/stage/ /
COPY --from=whisper  /opt/stage/ /

# Ensure pkg-config can see .pc files
ENV PKG_CONFIG_PATH="/usr/lib/pkgconfig:/usr/lib/x86_64-linux-gnu/pkgconfig:/usr/local/lib/pkgconfig:/usr/share/pkgconfig"
ENV PKG_CONFIG="/usr/bin/pkg-config"

RUN set -euo pipefail && \
    ldconfig && \
    pkg-config --print-errors --modversion whisper && \
    if ! pkg-config --exists ggml; then \
      mkdir -p /usr/lib/pkgconfig && \
      ggml_so="$(ldconfig -p | awk '/libggml.*\.so/{print $4; exit}')" && \
      if [ -z "$ggml_so" ]; then echo "No libggml*.so found"; exit 1; fi && \
      ggml_dir="$(dirname "$ggml_so")" && \
      ggml_base="$(basename "$ggml_so")" && \
      printf '%s\n' \
'prefix=/usr' \
"libdir=${ggml_dir}" \
'includedir=/usr/include' \
'Name: ggml' \
'Description: GGML core library (autogen for pkg-config)' \
'Version: 1.8.0' \
"Libs: -L\${libdir} -l:${ggml_base}" \
'Cflags: -I${includedir}' \
        > /usr/lib/pkgconfig/ggml.pc ; \
    fi && \
    pkg-config --print-errors --exists 'whisper >= 1.7.5'

RUN cat >/tmp/whisper_probe.c <<'EOF'
#include <whisper.h>
int main(void) { return 0; }
EOF

RUN cc $(pkg-config --cflags whisper) /tmp/whisper_probe.c -o /tmp/whisper_probe $(pkg-config --libs whisper) && \
    /tmp/whisper_probe && \
    echo "whisper compile/link probe: OK"

#we need the CUDA toolkit to build
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked,id=apt-cache \
    apt-get update && apt-get install -y --no-install-recommends \
      nvidia-cuda-toolkit \
 && rm -rf /var/lib/apt/lists/*


WORKDIR /build
ADD https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VER}.tar.xz .
RUN tar -xf ffmpeg-${FFMPEG_VER}.tar.xz && rm ffmpeg-${FFMPEG_VER}.tar.xz
WORKDIR /build/ffmpeg-${FFMPEG_VER}

RUN set -e; \
    PKG_CONFIG_PATH="$PKG_CONFIG_PATH" PKG_CONFIG="$PKG_CONFIG" \
    ./configure --prefix=/usr --enable-version3 --enable-gpl \
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
      --enable-libopenh264 --enable-libopenjpeg --enable-libopus \
      --enable-librav1e --enable-librubberband \
      --enable-libsnappy --enable-libsoxr --enable-libsrt --enable-libspeex --enable-libssh \
      --enable-libsvtav1 --enable-libtheora --enable-libtwolame \
      --enable-libvidstab --enable-libvorbis --enable-libvpl \
      --enable-libvpx --enable-libwebp --enable-libx264 \
      --enable-libx265 --enable-libxavs2 --enable-libxml2 --enable-libxvid \
      --enable-libzimg --enable-libzmq --enable-libzvbi --enable-lv2 --enable-lzma \
      --enable-openal --enable-opencl --enable-gnutls --enable-pthreads \
      --enable-runtime-cpudetect --enable-sdl2 --enable-shared \
      --enable-vaapi --enable-whisper --enable-zlib \
    || { echo '--- ffbuild/config.log (tail) ---'; tail -n 200 ffbuild/config.log || true; exit 1; } \
  && make -j"$(nproc)" && make install && ldconfig


# ---- Package a minimal, relocatable runtime (flat /opt/ffmpeg/lib + RPATH) ---
RUN set -euo pipefail \
 && FFMPEG_BIN="$(command -v ffmpeg)" \
 && FFPROBE_BIN="$(command -v ffprobe)" \
 && mkdir -p /opt/ffmpeg/bin /opt/ffmpeg/lib \
 && cp -v "$FFMPEG_BIN" "$FFPROBE_BIN" /opt/ffmpeg/bin/ \
    # collect libs from both bins; flat copy, dereference symlinks, exclude the ELF interp
 && { ldd "$FFMPEG_BIN"; ldd "$FFPROBE_BIN"; } \
      | awk '/=> \//{print $3} /^\//{print $1}' \
      | grep -vE '/ld-linux[^ ]*\.so' \
      | sort -u \
      | xargs -I{} cp -vL {} /opt/ffmpeg/lib/ \
    # explicitly include whisper/ggml (in case they’re dlopened)
 && for n in libwhisper libggml; do \
      p="$(ldconfig -p | awk -v n="$n" '$1 ~ n {print $4; exit}')" ; \
      [ -n "$p" ] && cp -vL "$p" /opt/ffmpeg/lib/ || true ; \
    done \
    # strip & set RPATH so bins prefer /opt/ffmpeg/lib
 && strip --strip-unneeded /opt/ffmpeg/bin/* || true \
 && find /opt/ffmpeg/lib -type f -name '*.so*' -exec strip --strip-unneeded {} + || true \
 && patchelf --set-rpath '$ORIGIN/../lib' /opt/ffmpeg/bin/ffmpeg /opt/ffmpeg/bin/ffprobe \
 && tar -C /opt/ffmpeg -czf /tmp/ffmpeg-runtime.tgz .

############################
# runtime: small, no compilers/headers
############################
FROM ubuntu:24.04 AS runtime
ARG DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash","-euxo","pipefail","-c"]

RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*

COPY --from=builder /tmp/ffmpeg-runtime.tgz /opt/
RUN tar -C /opt -xzf /opt/ffmpeg-runtime.tgz && rm /opt/ffmpeg-runtime.tgz \
 && ln -s /opt/bin/ffmpeg  /usr/local/bin/ffmpeg \
 && ln -s /opt/bin/ffprobe /usr/local/bin/ffprobe

RUN echo "/opt/lib" > /etc/ld.so.conf.d/ffmpeg.conf && ldconfig
# Optional: uncomment to inspect what was built
# RUN ffmpeg -hide_banner -buildconf | sed -n '1,160p'
