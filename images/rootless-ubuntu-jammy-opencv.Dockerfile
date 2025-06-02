FROM harbor.nbfc.io/nubificus/kubernoodles/rootless-ubuntu-jammy-base:generic

USER root
ARG TARGETPLATFORM

ARG OPENCV_VERSION
# Build and install OpenCV.
RUN [ -z "${OPENCV_VERSION}" ] && \
    OPENCV_TAG=$(git ls-remote --tags --refs --sort='v:refname' \
        https://github.com/opencv/opencv.git | \
        grep -E "refs/tags/[0-9]+\.[0-9]+.[0-9]+$" | awk -F/ 'END{print$NF}') && \
    OPENCV_VERSION=${OPENCV_TAG}; \
    git clone https://github.com/opencv/opencv.git --depth 1 \
        -b "${OPENCV_VERSION}" && \
    git clone https://github.com/opencv/opencv_contrib.git --depth 1 \
        -b "${OPENCV_VERSION}" && \
    cd opencv && \
    cmake -S . -B build \
        -DOPENCV_EXTRA_MODULES_PATH="$(pwd)"/../opencv_contrib/modules \
        -DBUILD_opencv_legacy=OFF && \
    cmake --build build --parallel "$(nproc)" && \
    cmake --install build --prefix=/usr/local && \
    cd .. && rm -rf opencv*

WORKDIR /home/runner

# GitHub runner arguments
ARG RUNNER_VERSION=2.324.0
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
