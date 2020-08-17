FROM nvidia/cuda:8.0-devel-ubuntu16.04

LABEL maintainer="Dmitri Rubinstein <dmitri.rubinstein@dfki.de>"

# grab tini for signal processing and zombie killing
ENV TINI_VERSION v0.19.0
RUN set -eux; \
        export DEBIAN_FRONTEND=noninteractive; \
        apt-get update -y; \
        apt-get install -y --no-install-recommends wget ca-certificates; \
        rm -rf /var/lib/apt/lists/*; \
        wget -O /usr/local/bin/tini "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini"; \
        wget -O /usr/local/bin/tini.asc "https://github.com/krallin/tini/releases/download/$TINI_VERSION/tini.asc"; \
        export GNUPGHOME="$(mktemp -d)"; \
        gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 6380DC428747F6C393FEACA59A84159D7001A4E5; \
        gpg --batch --verify /usr/local/bin/tini.asc /usr/local/bin/tini; \
        { command -v gpgconf > /dev/null && gpgconf --kill all || :; }; \
        rm -rf "$GNUPGHOME" /usr/local/bin/tini.asc; \
        chmod +x /usr/local/bin/tini; \
        tini -h

COPY docker-files/entrypoint.sh \
     docker-files/install-driver.sh \
     docker-files/su-entrypoint.c \
     docker-files/su-exec.c \
     /usr/local/bin/

COPY docker-files/cudaenv.sh /etc/profile.d/

ARG APP_USER
ENV APP_USER ${APP_USER:-darknet}

# Add the APP_USER user

RUN set -eux; \
    \
    export DEBIAN_FRONTEND=noninteractive; \
    apt-get update; \
    apt-get install -y sudo; \
    rm -rf /var/lib/apt/lists/*; \
    echo "Adding user ${APP_USER}"; \
    useradd  --uid 6000 -ms /bin/bash "${APP_USER}"; \
    chmod 0660 /etc/sudoers; \
    echo "${APP_USER} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers; \
    chmod 0440 /etc/sudoers; \
    echo "APP_USER=${APP_USER}" >> /config.sh

# Install Darknet

COPY . /usr/src/darknet
WORKDIR /usr/src/darknet

RUN set -eux; \
    \
    export DEBIAN_FRONTEND=noninteractive; \
    chmod +x /usr/local/bin/entrypoint.sh \
             /usr/local/bin/install-driver.sh; \
    \
    nvidia_deps='kmod pciutils'; \
    run_deps='python-pip python-setuptools gstreamer1.0-plugins-good gstreamer1.0-libav libopencv-dev python-opencv python-gst-1.0'; \
    dev_deps='git-core gcc libc-dev make'; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
             $nvidia_deps $run_deps $dev_deps; \
    \
    gcc -DENTRYPOINT="\"/usr/local/bin/entrypoint.sh\"" -Wall \
         /usr/local/bin/su-entrypoint.c -o/usr/local/bin/su-entrypoint; \
    chown root:root /usr/local/bin/su-entrypoint; \
    chmod 4111 /usr/local/bin/su-entrypoint; \
    rm /usr/local/bin/su-entrypoint.c; \
    gcc -Wall \
        /usr/local/bin/su-exec.c -o/usr/local/bin/su-exec; \
    chown root:root /usr/local/bin/su-exec; \
    chmod 0755 /usr/local/bin/su-exec; \
    rm /usr/local/bin/su-exec.c; \
    \
    . /etc/profile.d/cudaenv.sh; \
    sed -i 's/GPU=0/GPU=1/' Makefile; \
    sed -ie "/LDFLAGS=/s|\$| -L$CUDA_STUBS|" Makefile; \
    make; \
    wget https://pjreddie.com/media/files/yolo.weights; \
    \
    pip install -r python/requirements.txt; \
    \
    apt-get purge -y --auto-remove $dev_deps; \
    rm -rf /var/lib/apt/lists/*;

WORKDIR /usr/src/darknet

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ./stream_demo.sh
