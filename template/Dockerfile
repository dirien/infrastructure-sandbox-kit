# syntax=docker/dockerfile:1
#
# Pulumi sandbox template — Claude Code base image enriched for Pulumi work.
#
# Bakes in the Pulumi CLI + ESC, language servers, golangci-lint (and optionally
# the .NET SDK), and materializes dirien/my-claude-apm-setup into the agent's
# ~/.claude so skills, subagents, guardrail hooks and MCP servers are present the
# moment the sandbox starts — no per-start install cost.
#
# Build from the REPO ROOT so the shared scripts/ tree is in the build context:
#   docker build -f template/Dockerfile -t pulumi-sandbox:latest .
# then load it into sbx (or push to a registry) — see template/README.md.

ARG BASE=docker/sandbox-templates:claude-code-docker
FROM ${BASE}

# Pin everything; override with --build-arg as needed.
ARG PSK_PULUMI_VERSION=3.255.0
ARG PSK_ESC_VERSION=0.26.0
ARG PSK_APM_SETUP_REPO=dirien/my-claude-apm-setup
ARG PSK_APM_SETUP_REF=v0.4.0
ARG PSK_INSTALL_DOTNET=0
ARG PSK_DOTNET_CHANNEL=8.0

# The base runs as `agent` (uid 1000) with passwordless sudo. Provision as that
# user so APM + Claude config land in /home/agent owned by agent.
USER agent

ENV PSK_PULUMI_VERSION=${PSK_PULUMI_VERSION} \
    PSK_ESC_VERSION=${PSK_ESC_VERSION} \
    PSK_APM_SETUP_REPO=${PSK_APM_SETUP_REPO} \
    PSK_APM_SETUP_REF=${PSK_APM_SETUP_REF} \
    PSK_INSTALL_DOTNET=${PSK_INSTALL_DOTNET} \
    PSK_DOTNET_CHANNEL=${PSK_DOTNET_CHANNEL} \
    PULUMI_SKIP_UPDATE_CHECK=true

# Canonical provisioning scripts (single source of truth, shared with the mixin).
COPY --chown=agent:agent scripts/ /home/agent/.local/share/pulumi-sandbox-kit/scripts/

RUN bash /home/agent/.local/share/pulumi-sandbox-kit/scripts/provision.sh

# Make Go- and dotnet-tool-installed binaries resolvable in non-login shells too.
# (/home/agent/.local/bin is already on the base PATH; this adds the dotnet tools dir.)
ENV PATH="/home/agent/.local/bin:/home/agent/.dotnet/tools:${PATH}"

WORKDIR /home/agent/workspace
