FROM ubuntu:22.04

# GitHub runner arguments
ARG RUNNER_VERSION=2.319.1
ARG RUNNER_CONTAINER_HOOKS_VERSION=0.6.1

# Docker and Compose arguments
ARG DOCKER_VERSION=27.2.0
ARG COMPOSE_VERSION=v2.29.2

# Dumb-init version
ARG DUMB_INIT_VERSION=1.2.5

# Other arguments, expose TARGETPLATFORM for multi-arch builds
ARG DEBUG=false
ARG TARGETPLATFORM

# Label all the things!!
LABEL org.opencontainers.image.source="https://github.com/some-natalie/kubernoodles"
LABEL org.opencontainers.image.path="images/rootless-ubuntu-jammy.Dockerfile"
LABEL org.opencontainers.image.title="rootless-ubuntu-jammy"
LABEL org.opencontainers.image.description="An Ubuntu Jammy (22.04 LTS) based runner image for GitHub Actions, rootless"
LABEL org.opencontainers.image.authors="Natalie Somersall (@some-natalie)"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.documentation="https://github.com/some-natalie/kubernoodles/README.md"

# Set environment variables needed at build or run
ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNER_MANUALLY_TRAP_SIG=1
ENV ACTIONS_RUNNER_PRINT_LOG_TO_STDOUT=1

# Copy in environment variables not needed at build
COPY images/.env /.env

# Shell setup
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install base software
RUN apt-get update \
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
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Runner user
RUN adduser --disabled-password --gecos "" --uid 1000 runner

# Make and set the working directory
RUN mkdir -p /home/runner \
    && chown -R $USERNAME:$GID /home/runner

WORKDIR /home/runner

# Install GitHub CLI
COPY images/software/gh-cli.sh /gh-cli.sh
RUN bash /gh-cli.sh && rm /gh-cli.sh

## Install kubectl
#COPY images/software/kubectl.sh /kubectl.sh
#RUN bash /kubectl.sh && rm /kubectl.sh

## Install helm
#RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install Docker
RUN export DOCKER_ARCH=x86_64 \
    && export RUNNER_ARCH=$(echo ${TARGETPLATFORM} | cut -d / -f2) \
    && if [ "$RUNNER_ARCH" = "arm64" ]; then export DOCKER_ARCH=aarch64 ; fi \
    && if [ "$RUNNER_ARCH" = "arm" ]; then export DOCKER_ARCH=armhf; fi \
    && curl -fLo docker.tgz https://download.docker.com/linux/static/stable/${DOCKER_ARCH}/docker-${DOCKER_VERSION}.tgz \
    && tar zxvf docker.tgz \
    && rm -rf docker.tgz

RUN install -o root -g root -m 755 docker/* /usr/bin/ && rm -rf docker

# Runner download supports amd64 as x64
RUN export ARCH=$(echo ${TARGETPLATFORM} | cut -d / -f2) \
    && echo "ARCH: $ARCH" \
    && if [ "$ARCH" = "aarch64" ]; then export ARCH=arm64 ; fi \
    && if [ "$ARCH" = "armv7l" ]; then export ARCH=arm ; fi \
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

# Add the Python "User Script Directory" to the PATH
ENV PATH="${PATH}:${HOME}/.local/bin:/home/runner/bin"
ENV ImageOS=ubuntu22

ENV HOME=/home/runner

# No group definition, as that makes it harder to run docker.
USER runner

#RUN curl --create-dirs -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-Linux-x86_64" -o /home/runner/bin/docker-compose ; \
#  chmod +x /home/runner/bin/docker-compose

USER root

RUN echo 'DEBIAN_FRONTEND=noninteractive' >> /etc/environment && \
    echo 'TZ=Etc/UTC' >> /etc/environment
RUN apt update && \
    apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    curl && \
    apt-get -y clean && \
    rm -rf /var/cache/apt /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install build-essential lcov and update cmake
RUN apt-get update && \
    apt-get install -y --no-install-recommends software-properties-common && \
    apt-get install -y --no-install-recommends gcc-10 g++-10 lcov && \
    update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100 --slave /usr/bin/g++ g++ /usr/bin/g++-10 && \
    apt-get install -y --no-install-recommends build-essential cmake gcc-12 g++-12 ninja-build dh-make \
       git-buildpackage \
       libxml2-dev libxslt1-dev \
       libclang-dev valgrind cppcheck pkg-config protobuf-c-compiler protobuf-compiler && \
    apt-get -y clean && \
    rm -rf /var/cache/apt /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN git clone https://github.com/Yelp/dumb-init && cd dumb-init && make && cp dumb-init /usr/local/bin/dumb-init

RUN apt update && \
    apt-get install -y --no-install-recommends sudo python3-pip python3-dev

# install pip packages for meson
RUN pip install meson gcovr pycobertura codespell

RUN echo "runner ALL= EXEC: NOPASSWD:ALL" >> /etc/sudoers.d/runner

# Install Go depending on the system architecture
ENV GO_VERSION=1.20.3
ARG TARGETARCH
ARG ARCH_INFO=$TARGETARCH
ENV ARCH_INFO=${ARCH_INFO}

WORKDIR /
RUN sudo mkdir -p /golang && \
  wget "https://go.dev/dl/go${GO_VERSION}.linux-$TARGETARCH.tar.gz" -O go_archive.tar.gz && \
  tar -zxvf /go_archive.tar.gz -C /golang && \
  rm -rf go_archive.tar.gz

ENV PATH=/golang/go/bin:$PATH
ENV GOROOT=/golang/go
ENV GOPATH=/home/runner/go
RUN go version

WORKDIR /home/runner

USER runner

ENTRYPOINT ["/usr/local/bin/dumb-init", "--"]
