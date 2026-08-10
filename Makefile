# infrastructure-sandbox-kit — build the template image, validate the kit, and run.
#
# `sbx` and `docker` run on your HOST (the sandbox CLI is a host tool). Run these
# targets there. See README.md for the full story.

# Image NAME for the baked template (no tag). It is built, loaded and pushed as
# BOTH :$(VERSION) and :latest. Override for your registry, e.g.:
#   make build push IMAGE=ghcr.io/dirien/infrastructure-sandbox
IMAGE       ?= infrastructure-sandbox
# Version tag for the image + the published kit. Defaults to the latest git tag.
VERSION     ?= $(shell git describe --tags --abbrev=0 2>/dev/null || echo v0.6.0)
DOCKERFILE  ?= template/Dockerfile
PLATFORM    ?=                      # e.g. linux/arm64 or linux/amd64,linux/arm64
KIT         ?= ./kit
WORKDIR     ?= .
REGISTRY    ?= ghcr.io/dirien       # OCI registry for `make publish-kit`

# Every build/push/load stamps the image with the version tag and latest.
IMAGE_TAGS = -t $(IMAGE):$(VERSION) -t $(IMAGE):latest

# Pins forwarded to the image build (mirror the defaults in kit/spec.yaml).
PULUMI_VERSION     ?= 3.255.0
TERRAFORM_VERSION  ?= 1.15.8
OPENTOFU_VERSION   ?= 1.12.5
AWSCLI_VERSION     ?= 2.36.10
AZ_APT_DIST        ?= noble
INSTALL_CLOUDS     ?= 1
APM_SETUP_REF      ?= v0.6.0
APM_VERSION        ?= 0.26.0
HUMANIZER_REF      ?= 1b48564898e999219882660237fde01bf4843a0f
INSTALL_DOTNET     ?= 0
DOTNET_CHANNEL     ?= 8.0

BUILD_ARGS = \
  --build-arg ISK_PULUMI_VERSION=$(PULUMI_VERSION) \
  --build-arg ISK_TERRAFORM_VERSION=$(TERRAFORM_VERSION) \
  --build-arg ISK_OPENTOFU_VERSION=$(OPENTOFU_VERSION) \
  --build-arg ISK_AWSCLI_VERSION=$(AWSCLI_VERSION) \
  --build-arg ISK_AZ_APT_DIST=$(AZ_APT_DIST) \
  --build-arg ISK_INSTALL_CLOUDS=$(INSTALL_CLOUDS) \
  --build-arg ISK_APM_SETUP_REF=$(APM_SETUP_REF) \
  --build-arg ISK_APM_VERSION=$(APM_VERSION) \
  --build-arg ISK_HUMANIZER_REF=$(HUMANIZER_REF) \
  --build-arg ISK_INSTALL_DOTNET=$(INSTALL_DOTNET) \
  --build-arg ISK_DOTNET_CHANNEL=$(DOTNET_CHANNEL)

PLATFORM_ARG = $(if $(PLATFORM),--platform $(PLATFORM),)

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -hE '^[a-zA-Z0-9_.-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

## --- Template image ("the perfect template") ------------------------------

.PHONY: build
build: ## Build the image as :$(VERSION) + :latest. INSTALL_DOTNET=1 adds .NET; INSTALL_CLOUDS=0 drops the cloud CLIs.
	DOCKER_BUILDKIT=1 docker build $(PLATFORM_ARG) -f $(DOCKERFILE) $(IMAGE_TAGS) $(BUILD_ARGS) .

.PHONY: build-dotnet
build-dotnet: ## Build the image with the .NET SDK + csharp-ls included
	$(MAKE) build INSTALL_DOTNET=1

.PHONY: build-lean
build-lean: ## Build a leaner image without the AWS/Azure/gcloud CLIs
	$(MAKE) build INSTALL_CLOUDS=0

.PHONY: load
load: build ## Build then load the image (both tags) into sbx's local template store
	docker image save $(IMAGE):$(VERSION) $(IMAGE):latest -o infrastructure-sandbox.tar
	sbx template load infrastructure-sandbox.tar
	rm -f infrastructure-sandbox.tar

.PHONY: push
push: ## Push the image to a registry as :$(VERSION) and :latest (set IMAGE=<registry>/<repo>)
	docker push $(IMAGE):$(VERSION)
	docker push $(IMAGE):latest

.PHONY: publish-kit
publish-kit: ## Push the kit to an OCI registry as :$(VERSION) and :latest; needs sbx + docker login
	REGISTRY=$(REGISTRY) TAG=$(VERSION) ./scripts/push-kit.sh
	REGISTRY=$(REGISTRY) TAG=latest    ./scripts/push-kit.sh

## --- Kit (zero-build mixin) ------------------------------------------------

.PHONY: validate
validate: ## Validate the kit spec with sbx
	sbx kit validate $(KIT)

.PHONY: inspect
inspect: ## Show the normalized (canonical) kit spec
	sbx kit inspect $(KIT) --json

## --- Run -------------------------------------------------------------------

.PHONY: run
run: ## Run Claude on the baked template + kit (fast: tools are pre-baked)
	sbx run --template $(IMAGE):$(VERSION) --kit $(KIT) claude $(WORKDIR)

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
clean: ## Remove build artifacts and the local image (both tags)
	rm -f infrastructure-sandbox.tar
	-docker image rm $(IMAGE):$(VERSION) $(IMAGE):latest 2>/dev/null || true
