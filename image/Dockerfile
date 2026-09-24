FROM ubuntu:24.04@sha256:69cecf4bbf72d2d44a9eef1b71fb98c7fb973d78af11399deccef19beb008ad9

ARG TARGETARCH
ARG UBUNTU_SNAPSHOT=20260915T000000Z
ARG RUNNER_VERSION=2.337.0
ARG RUNNER_SHA256=9b1dc70626422526e3c94767cf024896beb15da5342a3f4819bf2feac13e0393
ARG RUNNER_ARCHIVE=actions-runner-linux-arm64-2.337.0.tar.gz

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# TLS verification is disabled only for the first apt-get update, which has no
# CA bundle yet. The four signed InRelease files are then SHA-256 pinned so the
# bootstrap cannot be redirected to older valid Ubuntu metadata.
RUN test "$TARGETARCH" = arm64 \
    && sed -i "s#http://ports.ubuntu.com/ubuntu-ports/#https://snapshot.ubuntu.com/ubuntu/${UBUNTU_SNAPSHOT}/#g" /etc/apt/sources.list.d/ubuntu.sources \
    && printf 'Acquire::https::Verify-Peer "false";\n' > /etc/apt/apt.conf.d/00snapshot-bootstrap-tls \
    && apt-get update \
    && printf '%s  %s\n' \
      1c6a6462e34f4c99282912e68416df300cb1b9ea1b76954847df7baac812d044 "/var/lib/apt/lists/snapshot.ubuntu.com_ubuntu_${UBUNTU_SNAPSHOT}_dists_noble-backports_InRelease" \
      ab92035d2202045bd3ddf4d15bf469d460979a6a94e8f81c59885ba23d36c21b "/var/lib/apt/lists/snapshot.ubuntu.com_ubuntu_${UBUNTU_SNAPSHOT}_dists_noble-security_InRelease" \
      fccd5d3f5d46cfcd9d2c05ffd0720de11fa77c9b8e3b4e47d1874da83c0360b1 "/var/lib/apt/lists/snapshot.ubuntu.com_ubuntu_${UBUNTU_SNAPSHOT}_dists_noble-updates_InRelease" \
      cdb2f31d809f589719a53c6ad15f255b27569c4059542ada282aaa21b8e164b0 "/var/lib/apt/lists/snapshot.ubuntu.com_ubuntu_${UBUNTU_SNAPSHOT}_dists_noble_InRelease" \
      | sha256sum -c - \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      jq \
      libatomic1 \
      make \
      openssh-client \
      procps \
      python3 \
      tini \
      unzip \
    && rm /etc/apt/apt.conf.d/00snapshot-bootstrap-tls \
    && rm -rf /var/lib/apt/lists/* \
    && install -d /opt/actions-runner \
    && curl --fail --location --show-error --silent \
      "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_ARCHIVE}" \
      --output /tmp/actions-runner.tar.gz \
    && printf '%s  %s\n' "$RUNNER_SHA256" /tmp/actions-runner.tar.gz | sha256sum -c - \
    && tar --extract --gzip --file /tmp/actions-runner.tar.gz --directory /opt/actions-runner \
    && /opt/actions-runner/bin/installdependencies.sh \
    && rm /tmp/actions-runner.tar.gz

RUN useradd --create-home --shell /bin/bash runner \
    && install -d -o runner -g runner /runner /runner/_work

COPY --chown=root:root entrypoint.sh /usr/local/bin/runner-entrypoint
RUN chmod 0755 /usr/local/bin/runner-entrypoint

ENV PATH="/opt/actions-runner/externals/node24/bin:${PATH}"
RUN test -x /opt/actions-runner/externals/node24/bin/node \
    && node --version

USER runner
WORKDIR /runner
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/runner-entrypoint"]
CMD ["run"]
