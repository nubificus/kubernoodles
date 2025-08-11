FROM harbor.nbfc.io/nubificus/kubernoodles/rootless-ubuntu-jammy-base:generic

USER root
ARG TARGETPLATFORM
ARG TORCH_VERSION=v2.7.1
# Build and install PyTorch
RUN [ -z "${TORCH_VERSION}" ] && \
    TORCH_TAG=$(git ls-remote --tags --refs --sort='v:refname' \
        https://github.com/pytorch/pytorch | \
        grep -E "refs/tags/v[0-9]+\.[0-9]+.[0-9]+$" | awk -F/ 'END{print$NF}') && \
    TORCH_VERSION=${TORCH_TAG}; \
    git clone https://github.com/pytorch/pytorch --depth 1 --recursive \
        -b "${TORCH_VERSION}" && \
    cd pytorch && \
    pip install pyyaml typing_extensions && \
    export _GLIBCXX_USE_CXX11_ABI=1 && \
    export USE_CUDA=0 && \
    cmake -S . -B build && \
    cmake --build build --parallel "$(nproc)" && \
    cmake --install build --prefix=/usr/local && \
    cd .. && rm -rf pytorch

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
    && unzip -o ./runner-container-hooks.zip -d ./k8s \
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
    && chown -R runner:runner /home/runner/ \
    && chmod a+x /home/runner/externals

RUN chmod 777 /usr/local/bin
USER runner

ENTRYPOINT ["/usr/local/bin/dumb-init", "--"]
