FROM node:22-bookworm-slim@sha256:6c74791e557ce11fc957704f6d4fe134a7bc8d6f5ca4403205b2966bd488f6b3

ARG CODEX_VERSION=0.145.0

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git ripgrep bash \
    && npm install --global "@openai/codex@${CODEX_VERSION}" \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY agent-entrypoint /usr/local/bin/bf-agent-entrypoint
RUN chmod 0755 /usr/local/bin/bf-agent-entrypoint

WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/bf-agent-entrypoint"]
