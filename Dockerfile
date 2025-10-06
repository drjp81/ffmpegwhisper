FROM ubuntu:latest

ENV DEBIAN_FRONTEND=noninteractive

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DEFAULT_TIMEOUT=600 \
    PIP_RETRIES=20
RUN apt update && apt install pkg-config git curl ca-certificates make -y
RUN mkdir /build
WORKDIR /build
RUN git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git
WORKDIR /build/nv-codec-headers
RUN  make && \
     make install



RUN apt install yasm nasm cmake meson ninja-build autoconf automake libtool \
    clang  \
    zlib1g-dev libssl-dev libbz2-dev liblzma-dev \
    libfreetype6-dev libfontconfig1-dev libfribidi-dev libharfbuzz-dev libass-dev \
    libaom-dev libdav1d-dev librav1e-dev libsvtav1-dev libvpx-dev \
    libx264-dev libx265-dev libxvidcore-dev \
    libmp3lame-dev libopus-dev libvorbis-dev libtwolame-dev libtheora-dev \
    libwebp-dev libjxl-dev libopenjp2-7-dev  \
    libsoxr-dev libspeex-dev libsnappy-dev libgme-dev \
    libbluray-dev libdvdnav-dev libdvdread-dev \
    frei0r-plugins-dev libchromaprint-dev libvidstab-dev  \
    libsrt-openssl-dev librist-dev libssh-dev libzmq3-dev \
    libzimg-dev libplacebo-dev \
    ocl-icd-opencl-dev opencl-headers \
    libvulkan-dev libshaderc-dev \
    libva-dev libdrm-dev \
    libzvbi-dev libxml2-dev libgmp-dev libsdl2-dev libopenal-dev \
    libaribb24-dev libvpl-dev \
    nvidia-cuda-toolkit ca-certificates  -y
#RUN  apt-get clean && \
     #rm -rf /var/lib/apt/lists/*
WORKDIR /build
RUN git clone https://github.com/ggml-org/whisper.cpp
WORKDIR /build/whisper.cpp
RUN ./models/download-ggml-model.sh base.en
RUN cmake -B build -DGGML_CUDA=1 && \
    cmake --build build --config Release && \
    make install -C build

# AviSynth+ (provides headers, lib, and avisynth.pc)
RUN git clone https://github.com/AviSynth/AviSynthPlus.git /build/AviSynthPlus \
 && cmake -S /build/AviSynthPlus -B /build/avisynth-build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/usr \
 && cmake --build /build/avisynth-build -j"$(nproc)" \
 && cmake --install /build/avisynth-build \
 && ldconfig
ADD https://ffmpeg.org/releases/ffmpeg-8.0.tar.xz ./ffmpeg-8.0.tar.xz
RUN tar -xvf ./ffmpeg-8.0.tar.xz -C /build && \
    rm ./ffmpeg-8.0.tar.xz
#Missing stuff
RUN apt install liblilv-dev libdavs2-dev libopencore-amrnb-dev libopencore-amrwb-dev libopenh264-dev librubberband-dev libsvtav1enc-dev libxavs2-dev  vulkan-tools libvulkan-dev mesa-vulkan-drivers -y

WORKDIR /build/ffmpeg-8.0
RUN  ./configure --prefix=/usr --enable-version3 --enable-gpl \
 --disable-debug --disable-libdrm --disable-libfdk-aac \
 --disable-libxcb --disable-static --disable-w32threads --disable-xlib \
 --enable-avisynth --enable-chromaprint --enable-cuda-llvm \
 --enable-ffnvcodec  --enable-filters  --enable-fontconfig  --enable-frei0r \
 --enable-gmp  --enable-gpl  --enable-iconv  --enable-libaom \
 --enable-libaribb24  --enable-libass \
 --enable-libbluray  --enable-libdav1d  --enable-libdavs2  --enable-libdvdnav \
 --enable-libdvdread  --enable-libfreetype  --enable-libfribidi \
 --enable-libgme  --enable-libharfbuzz  --enable-libjxl  \
 --enable-libmp3lame  --enable-libopencore-amrnb  --enable-libopencore-amrwb \
 --enable-libopenh264  --enable-libopenjpeg  --enable-libopus  --enable-libplacebo  --enable-libpulse \
 --enable-librav1e  --enable-librubberband --enable-libshaderc \
 --enable-libsnappy  --enable-libsoxr  --enable-libspeex  --enable-libsrt  --enable-libssh \
 --enable-libsvtav1  --enable-libtheora  --enable-libtwolame  \
 --enable-libvidstab  --enable-libvorbis  --enable-libvpl \
 --enable-libvpx   --enable-libwebp  --enable-libx264 \
 --enable-libx265  --enable-libxavs2  --enable-libxml2  --enable-libxvid \
 --enable-libzimg  --enable-libzmq  --enable-libzvbi  --enable-lv2  --enable-lzma \
 --enable-nonfree  --enable-openal  --enable-opencl  --enable-openssl  --enable-pthreads \
 --enable-runtime-cpudetect  --enable-sdl2  --enable-shared \
 --enable-static  --enable-vaapi  --enable-version3  \
 --enable-whisper --enable-zlib && \
make -j"$(nproc)" && \
make install 
ENV  LD_LIBRARY_PATH="/usr/local/lib/:"
