FROM harbor.nbfc.io/nubificus/kubernoodles/rootless-ubuntu-jammy-base:generic

USER root

ARG TARGETPLATFORM

RUN add-apt-repository -y ppa:git-core/ppa && \
    apt-get update && \
    apt-get -y install --no-install-recommends git && \
    apt-get -y clean && \
    rm -rf /var/cache/apt /var/lib/apt/lists/* /tmp/* /var/tmp/*

WORKDIR /home/runner

# GitHub runner arguments
ARG RUNNER_VERSION=2.322.0
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
    && chmod a+x /home/runner/externals

RUN chmod 777 /usr/local/bin
USER runner

ENTRYPOINT ["/usr/local/bin/dumb-init", "--"]
