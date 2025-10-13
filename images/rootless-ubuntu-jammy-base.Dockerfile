FROM harbor.nbfc.io/proxy_cache/library/ubuntu:22.04


# Docker and Compose arguments
ARG DOCKER_VERSION=27.2.1

# Dumb-init version
ARG DUMB_INIT_VERSION=1.2.5

# Other arguments, expose TARGETPLATFORM for multi-arch builds
ARG DEBUG=false
ARG TARGETPLATFORM

# Label all the things!!
LABEL org.opencontainers.image.source="https://github.com/nubificus/kubernoodles"
LABEL org.opencontainers.image.path="images/rootless-ubuntu-jammy.Dockerfile"
LABEL org.opencontainers.image.title="rootless-ubuntu-jammy"
LABEL org.opencontainers.image.description="An Ubuntu Jammy (22.04 LTS) based runner image for GitHub Actions, rootless"
LABEL org.opencontainers.image.authors="Anastassios Nanos (@ananos)"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.documentation="https://github.com/nubificus/kubernoodles/README.md"

# Set environment variables needed at build or run
ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNER_MANUALLY_TRAP_SIG=1
ENV ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1

# Copy in environment variables not needed at build
COPY images/.env /.env

# Shell setup
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN echo 'DEBIAN_FRONTEND=noninteractive' >> /etc/environment && \
    echo 'TZ=Etc/UTC' >> /etc/environment

# Install base software
RUN apt-get clean && apt-get update \
    && apt-get install -y --no-install-recommends \
    apt-transport-https \
    apt-utils \
    ca-certificates \
    curl \
    gcc \
    git \
    iproute2 \
    iptables \
    jq \
    libyaml-dev \
    locales \
    lsb-release \
    openssl \
    pigz \
    pkg-config \
    software-properties-common \
    time \
    tzdata \
    uidmap \
    unzip \
    wget \
    xz-utils \
    zip \
    gnupg-agent \
    openssh-client \
    make \
    rsync \
    jq \
    sudo \
    python3-pip python3-dev \
    libcurl4-openssl-dev libstb-dev \
    gcc \
    g++ \
    curl \
    gcc-10 g++-10 lcov \
    build-essential cmake gcc-12 g++-12 ninja-build dh-make \
    git-buildpackage \
    libxml2-dev libxslt1-dev \
    libclang-dev cppcheck pkg-config protobuf-c-compiler protobuf-compiler \
    gdb libbabeltrace1 libboost-regex1.74.0 libc6-dbg libdebuginfod-common libdebuginfod1 libsource-highlight-common libsource-highlight4v5 ucf libarchive-dev \
    && apt-get clean \
    && update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100 --slave /usr/bin/g++ g++ /usr/bin/g++-10 \
    && rm -rf /var/lib/apt/lists/*

RUN add-apt-repository -y ppa:git-core/ppa && \
    apt-get update && \
    apt-get -y install --no-install-recommends git && \
    apt-get -y clean && \
    rm -rf /var/cache/apt /var/lib/apt/lists/* /tmp/* /var/tmp/*

# install pip packages for meson
RUN pip install meson gcovr pycobertura codespell

# Runner user
RUN adduser --disabled-password --gecos "" --uid 1000 runner

# Make and set the working directory
RUN mkdir -p /home/runner \
    && chown -R $USERNAME:$GID /home/runner

WORKDIR /home/runner

# Install GitHub CLI
COPY images/software/gh-cli.sh /gh-cli.sh
RUN bash /gh-cli.sh && rm /gh-cli.sh

# Install Docker
RUN export DOCKER_ARCH=x86_64 \
    && export ARCH=$(echo ${TARGETPLATFORM} | cut -d / -f2) \
    && if [ "$ARCH" = "arm64" ]; then export DOCKER_ARCH=aarch64 ; fi \
    && if [ "$ARCH" = "arm" ]; then export DOCKER_ARCH=armhf; fi \
    && curl -fLo docker.tgz https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-${DOCKER_VERSION}.tgz \
    && tar zxvf docker.tgz \
    && rm -rf docker.tgz

RUN install -o root -g root -m 755 docker/* /usr/bin/ && rm -rf docker

# Add the Python "User Script Directory" to the PATH
ENV PATH="${PATH}:${HOME}/.local/bin:/home/runner/bin"
ENV ImageOS=ubuntu22

ENV HOME=/home/runner


RUN git clone https://github.com/Yelp/dumb-init && cd dumb-init && make && cp dumb-init /usr/local/bin/dumb-init

RUN echo "runner ALL= EXEC: NOPASSWD:ALL" >> /etc/sudoers.d/runner

# Install Go depending on the system architecture
ENV GO_VERSION=1.24.1
ARG TARGETARCH
ARG ARCH_INFO=$TARGETARCH
ENV ARCH_INFO=${ARCH_INFO}

WORKDIR /
ARG HOSTARCH
RUN sudo mkdir -p /golang-local && \
    export ARCH=$TARGETARCH \
        && if [ "${ARCH}" = "arm" ]; then export GO_ARCH=armv6l; fi  \
        && if [ "${ARCH}" = "arm64" ]; then export GO_ARCH=arm64; fi  \
        && if [ "${ARCH}" = "amd64" ]; then export GO_ARCH=amd64; fi  \
  && wget "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -O go_archive.tar.gz && \
  tar -zxvf /go_archive.tar.gz -C /golang-local && \
  rm -rf go_archive.tar.gz

ENV PATH=/golang-local/go/bin:$PATH
ENV GOROOT=/golang-local/go
ENV GOPATH=/home/runner/go-local
RUN go version

# Install rust using rustup
ENV RUSTUP_HOME=/opt/rust CARGO_HOME=/opt/cargo PATH=/opt/cargo/bin:$PATH
RUN wget --https-only --secure-protocol=TLSv1_2 -O- https://sh.rustup.rs | sh /dev/stdin -y
RUN chmod a+w /opt/cargo
RUN chmod a+w /opt/rust

ARG VALGRIND_VERSION
ARG TARGETARCH

RUN if [ -z "${VALGRIND_VERSION}" ]; then \
        VALGRIND_VERSION=$(git ls-remote --tags --refs --sort='v:refname' \
            https://sourceware.org/git/valgrind.git | \
            grep -E "refs/tags/VALGRIND_[0-9]+_[0-9]+_[0-9]+$" | \
            awk -F/ 'END{print$NF}'); \
    fi && \
    git clone https://sourceware.org/git/valgrind.git --depth 1 -b "${VALGRIND_VERSION}" && \
    cd valgrind && \
    ./autogen.sh && \
    if [ "$TARGETARCH" = "arm" ]; then \
        ./configure --host=armv7-linux-gnueabihf --prefix=/usr/local; \
    else \
        ./configure --prefix=/usr/local; \
    fi && \
    make -j$(nproc) && \
    make install

#ARG VALGRIND_VERSION
#RUN [ -z "${VALGRIND_VERSION}" ] && \
#    VALGRIND_TAG=$(git ls-remote --tags --refs --sort='v:refname' \
#        https://sourceware.org/git/valgrind.git | \
#        grep -E "refs/tags/VALGRIND_[0-9]+_[0-9]+_[0-9]+$" | awk -F/ 'END{print$NF}') && \
#    VALGRIND_VERSION=${VALGRIND_TAG}; \
#    git clone https://sourceware.org/git/valgrind.git --depth 1 \
#        -b "${VALGRIND_VERSION}" && \
#    cd valgrind && \
#    ./autogen.sh && \
#    ./configure --prefix=/usr/local && \
#    make && \
#    make install
#
WORKDIR /home/runner

# GitHub runner arguments
ARG RUNNER_VERSION=2.328.0
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.6.1

# Runner download supports amd64 as x64
RUN export ARCH=$(echo ${TARGETPLATFORM} | cut -d / -f2) \
    && echo "ARCH: $ARCH" \
    && if [ "$ARCH" = "amd64" ]; then export ARCH=x64 ; fi \
    && curl -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz \
    && tar xzf ./runner.tar.gz \
    && rm runner.tar.gz \
    && ./bin/installdependencies.sh \
    && apt-get autoclean \
    && rm -rf /var/lib/apt/lists/*

# Install container hooks
RUN curl -f -L -o runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/v${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-${RUNNER_CONTAINER_HOOKS_VERSION}.zip \
    && unzip ./runner-container-hooks.zip -d ./k8s \
    && rm runner-container-hooks.zip

# Install dumb-init, arch command on OS X reports "i386" for Intel CPUs regardless of bitness
#RUN ARCH=$(echo ${TARGETPLATFORM} | cut -d / -f2) \
#  && export ARCH \
#  && if [ "$ARCH" = "arm" ]; then export ARCH=armv7l; fi \
#  && if [ "$ARCH" = "arm64" ]; then export ARCH=aarch64 ; fi \
#  && if [ "$ARCH" = "amd64" ] || [ "$ARCH" = "i386" ]; then export ARCH=x86_64 ; fi \
#  && curl -f -L -o /usr/local/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v${DUMB_INIT_VERSION}/dumb-init_${DUMB_INIT_VERSION}_${ARCH} \
#  && chmod +x /usr/local/bin/dumb-init

# Make the rootless runner directory and externals directory executable
RUN mkdir -p /run/user/1000 \
    && chown runner:runner /run/user/1000 \
    && chmod a+x /run/user/1000 \
    && mkdir -p /home/runner/externals \
    && chown runner:runner /home/runner/externals \
    && chmod a+x /home/runner/externals

RUN chmod 777 /usr/local/bin
USER runner

ENTRYPOINT ["/usr/local/bin/dumb-init", "--"]
