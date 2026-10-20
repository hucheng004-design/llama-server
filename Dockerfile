# GitHub Actions 云端构建用（runner 为原生 x86-64，无模拟开销）
# 原理与本地版本相同：Ubuntu 22.04 + CUDA 12.4 基础镜像，静态编译 llama.cpp
FROM nvidia/cuda:12.4.1-devel-ubuntu22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential git wget ca-certificates libcurl4-openssl-dev && \
    rm -rf /var/lib/apt/lists/*

RUN wget -q https://github.com/Kitware/CMake/releases/download/v3.28.3/cmake-3.28.3-linux-x86_64.tar.gz && \
    tar -xzf cmake-3.28.3-linux-x86_64.tar.gz -C /opt && \
    ln -s /opt/cmake-3.28.3-linux-x86_64/bin/cmake /usr/local/bin/cmake && \
    rm cmake-3.28.3-linux-x86_64.tar.gz

ARG LLAMA_VERSION=b11588
RUN git clone --depth 1 --branch ${LLAMA_VERSION} https://github.com/ggml-org/llama.cpp.git /src/llama.cpp || \
    (git clone https://github.com/ggml-org/llama.cpp.git /src/llama.cpp && \
     cd /src/llama.cpp && git checkout ${LLAMA_VERSION})

# 原生 amd64 + 16GB 内存，-j4 提速
RUN cd /src/llama.cpp && \
    cmake -B build \
      -DGGML_CUDA=ON \
      -DCMAKE_CUDA_ARCHITECTURES="86" \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_SHARED_LIBS=OFF \
      -DLLAMA_BUILD_TESTS=OFF \
      -DLLAMA_BUILD_EXAMPLES=OFF && \
    cmake --build build --config Release -j4

FROM nvidia/cuda:12.4.1-runtime-ubuntu22.04

# libcurl：LLAMA_CURL 需要；libgomp1：OpenMP 运行库，基础镜像未自带
RUN apt-get update && \
    apt-get install -y --no-install-recommends libcurl4 libgomp1 && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /src/llama.cpp/build/bin/llama-server /usr/local/bin/
COPY --from=builder /src/llama.cpp/build/bin/llama-cli   /usr/local/bin/

ENTRYPOINT ["llama-server"]
CMD ["--help"]
