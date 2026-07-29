# pulumi-sandbox-kit — build the template image, validate the kit, and run.
#
# `sbx` and `docker` run on your HOST (the sandbox CLI is a host tool). Run these
# targets there. See README.md for the full story.

# Image reference for the baked template. Override for your registry, e.g.:
#   make build push IMAGE=ghcr.io/dirien/pulumi-sandbox:v1
IMAGE       ?= pulumi-sandbox:latest
DOCKERFILE  ?= template/Dockerfile
PLATFORM    ?=                      # e.g. linux/arm64 or linux/amd64,linux/arm64
KIT         ?= ./kit
WORKDIR     ?= .

# Pins forwarded to the image build (mirror the defaults in kit/spec.yaml).
PULUMI_VERSION   ?= 3.255.0
ESC_VERSION      ?= 0.26.0
APM_SETUP_REF    ?= v0.4.0
INSTALL_DOTNET   ?= 0
DOTNET_CHANNEL   ?= 8.0

BUILD_ARGS = \
  --build-arg PSK_PULUMI_VERSION=$(PULUMI_VERSION) \
  --build-arg PSK_ESC_VERSION=$(ESC_VERSION) \
  --build-arg PSK_APM_SETUP_REF=$(APM_SETUP_REF) \
  --build-arg PSK_INSTALL_DOTNET=$(INSTALL_DOTNET) \
  --build-arg PSK_DOTNET_CHANNEL=$(DOTNET_CHANNEL)

PLATFORM_ARG = $(if $(PLATFORM),--platform $(PLATFORM),)

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_.-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

## --- Template image ("the perfect template") ------------------------------

.PHONY: build
build: ## Build the baked template image (DOCKER_BUILDKIT). Add INSTALL_DOTNET=1 for Pulumi C#.
	DOCKER_BUILDKIT=1 docker build $(PLATFORM_ARG) -f $(DOCKERFILE) -t $(IMAGE) $(BUILD_ARGS) .

.PHONY: build-dotnet
build-dotnet: ## Build the image with the .NET SDK + csharp-ls included
	$(MAKE) build INSTALL_DOTNET=1

.PHONY: load
load: build ## Build then load the image into sbx's local template store (no registry)
	docker image save $(IMAGE) -o pulumi-sandbox.tar
	sbx template load pulumi-sandbox.tar
	rm -f pulumi-sandbox.tar

.PHONY: push
push: ## Push the image to a registry (set IMAGE=<registry>/<repo>:<tag>)
	docker push $(IMAGE)

## --- Kit (zero-build mixin) ------------------------------------------------

.PHONY: validate
validate: ## Validate the kit spec with sbx
	sbx kit validate $(KIT)

.PHONY: inspect
inspect: ## Show the normalized (canonical) kit spec
	sbx kit inspect $(KIT) --output json

## --- Run -------------------------------------------------------------------

.PHONY: run
run: ## Run Claude on the baked template + kit (fast: tools are pre-baked)
	sbx run --template $(IMAGE) --kit $(KIT) claude $(WORKDIR)

.PHONY: run-kit
run-kit: ## Run Claude on the stock image + kit (zero-build; installs at create time)
	sbx run --kit $(KIT) claude $(WORKDIR)

## --- Maintenance -----------------------------------------------------------

.PHONY: pin
pin: ## Pin the kit's KIT_REF to REF=<tag-or-sha> for reproducible zero-build runs
	@test -n "$(REF)" || { echo "usage: make pin REF=<tag-or-40-char-sha>"; exit 2; }
	perl -0pi -e 's/(KIT_REF=")[^"]*(")/$${1}$(REF)$${2}/' kit/spec.yaml
	@echo "pinned KIT_REF=$(REF) in kit/spec.yaml"

.PHONY: clean
clean: ## Remove build artifacts and the local image
	rm -f pulumi-sandbox.tar
	-docker image rm $(IMAGE) 2>/dev/null || true
