# syntax=docker/dockerfile:1
#
# Infrastructure sandbox template — Claude Code base image enriched for IaC work.
#
# Bakes in the Pulumi CLI, Terraform, OpenTofu, the AWS/Azure/gcloud CLIs,
# language servers and golangci-lint (and optionally the .NET SDK), and
# materializes dirien/my-claude-apm-setup into the agent's ~/.claude so skills,
# subagents, guardrail hooks and MCP servers are present the moment the sandbox
# starts — no per-start install cost.
#
# Build from the REPO ROOT so the shared scripts/ tree is in the build context:
#   docker build -f template/Dockerfile -t infrastructure-sandbox:latest .
# then load it into sbx (or push to a registry) — see template/README.md.

ARG BASE=docker/sandbox-templates:claude-code-docker
FROM ${BASE}

# Pin everything; override with --build-arg as needed.
ARG ISK_PULUMI_VERSION=3.255.0
ARG ISK_TERRAFORM_VERSION=1.15.8
ARG ISK_OPENTOFU_VERSION=1.12.5
ARG ISK_AWSCLI_VERSION=2.36.10
ARG ISK_AZ_APT_DIST=noble
ARG ISK_INSTALL_CLOUDS=1
ARG ISK_APM_SETUP_REPO=dirien/my-claude-apm-setup
ARG ISK_APM_SETUP_REF=v0.6.2
ARG ISK_APM_VERSION=0.28.0
ARG ISK_INSTALL_DOTNET=0
ARG ISK_DOTNET_CHANNEL=8.0

# The base runs as `agent` (uid 1000) with passwordless sudo. Provision as that
# user so APM + Claude config land in /home/agent owned by agent.
USER agent

ENV ISK_PULUMI_VERSION=${ISK_PULUMI_VERSION} \
    ISK_TERRAFORM_VERSION=${ISK_TERRAFORM_VERSION} \
    ISK_OPENTOFU_VERSION=${ISK_OPENTOFU_VERSION} \
    ISK_AWSCLI_VERSION=${ISK_AWSCLI_VERSION} \
    ISK_AZ_APT_DIST=${ISK_AZ_APT_DIST} \
    ISK_INSTALL_CLOUDS=${ISK_INSTALL_CLOUDS} \
    ISK_APM_SETUP_REPO=${ISK_APM_SETUP_REPO} \
    ISK_APM_SETUP_REF=${ISK_APM_SETUP_REF} \
    ISK_APM_VERSION=${ISK_APM_VERSION} \
    ISK_INSTALL_DOTNET=${ISK_INSTALL_DOTNET} \
    ISK_DOTNET_CHANNEL=${ISK_DOTNET_CHANNEL} \
    PULUMI_SKIP_UPDATE_CHECK=true \
    AWS_PAGER="" \
    CLOUDSDK_CORE_DISABLE_PROMPTS=1

# Canonical provisioning scripts (single source of truth, shared with the mixin).
COPY --chown=agent:agent scripts/ /home/agent/.local/share/infrastructure-sandbox-kit/scripts/

RUN bash /home/agent/.local/share/infrastructure-sandbox-kit/scripts/provision.sh

# Make Go- and dotnet-tool-installed binaries resolvable in non-login shells too.
# (/home/agent/.local/bin is already on the base PATH; this adds the dotnet tools dir.)
ENV PATH="/home/agent/.local/bin:/home/agent/.dotnet/tools:${PATH}"

WORKDIR /home/agent/workspace
