FROM harbor.nbfc.io/nubificus/kubernoodles/rootless-ubuntu-jammy-base:generic

USER root
ARG TARGETPLATFORM
ARG LLVM_VERSION=17

RUN wget https://apt.llvm.org/llvm.sh && \
    chmod +x llvm.sh && \
    sudo ./llvm.sh "${LLVM_VERSION}" && \
    rm llvm.sh && \
    apt-get -y clean && \
    rm -rf /var/cache/apt /var/lib/apt/lists/* /tmp/* /var/tmp/*

ARG TARGETARCH
# Install Bazelisk as Bazel
RUN BAZELISK="bazelisk-linux-${TARGETARCH}" && \
    VERSION="v1.20.0" && \
    wget "https://github.com/bazelbuild/bazelisk/releases/download/${VERSION}/${BAZELISK}" && \
    chmod +x "${BAZELISK}" && \
    mv "${BAZELISK}" /usr/local/bin/bazel

ARG TF_VERSION=v2.17.0
# Build and install TensorFlow
RUN git clone -b "${TF_VERSION}" --recursive --depth 1 \
        https://github.com/tensorflow/tensorflow.git && \
    cd tensorflow && \
    ./configure && \
    bazel \
        --host_jvm_args=-Xmx2g \
        build --jobs=HOST_CPUS*.8 \
            --local_ram_resources=HOST_RAM*.4 \
            --config=v2 \
            --copt=-O3 \
            --verbose_failures \
            --discard_analysis_cache \
            -c opt \
            //tensorflow:libtensorflow.so \
            //tensorflow:libtensorflow_cc.so \
            //tensorflow:libtensorflow_framework.so \
            //tensorflow:install_headers \
            --config=monolithic \
            //tensorflow/lite/c:libtensorflowlite_c.so \
            //tensorflow/lite:libtensorflowlite.so \
            //tensorflow/lite/delegates/flex:tensorflowlite_flex && \
    OUT_DIR=bazel-bin/tensorflow && \
    rsync -aPm \
        --exclude='internal' --exclude='testing' --exclude='ios' \
        --exclude='python' --exclude='java' --exclude='objc' --exclude='swift' \
        --exclude='*internal*.h' --exclude='*test*.h' \
        --include='*/' --include='*.h' \
        --exclude='*' \
        tensorflow/lite/* "${OUT_DIR}/include/tensorflow/lite" && \
    PREFIX=/usr/local && \
    cp -r "${OUT_DIR}"/include "${PREFIX}/" && \
    find "${OUT_DIR}" -path '*runfiles' -prune -o -name 'libtensorflow*.so*' \
        -exec cp -a {} "${PREFIX}/lib/" \; && \
    rm -rf "${PREFIX}"/lib/*.params* "${PREFIX}"/lib/*.runfiles* && \
    rm -rf /root/.cache && \
    cd .. && rm -rf tensorflow

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
    && chown -R runner:runner /home/runner \
    && chmod a+x /home/runner/externals

RUN chmod 777 /usr/local/bin
USER runner

ENTRYPOINT ["/usr/local/bin/dumb-init", "--"]
