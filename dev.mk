PKG_NAME    := $(shell grep '^PKG_NAME:=' Makefile | cut -d= -f2)
SDK_ARCH    ?= x86-64
SDK_VERSION ?= 24.10.5

IMAGE_BUILDER := $(PKG_NAME)-builder:$(SDK_ARCH)-$(SDK_VERSION)
IMAGE_TESTER  := $(PKG_NAME)-tester:$(SDK_ARCH)-$(SDK_VERSION)
PKG_SDK_DIR   := /builder/package/$(PKG_NAME)

VERBOSE  ?= 0
REPORTER := $(if $(filter 1,$(VERBOSE)),detailed,compact)

.PHONY: test package

test:
	docker run --rm \
		-v $(CURDIR):/app:ro \
		-w /app \
		$(IMAGE_TESTER) \
		src/utest.sh --reporter=$(REPORTER) $(ARGS)

package:
	mkdir -p bin
	docker run --rm \
		-v $(CURDIR)/Makefile:$(PKG_SDK_DIR)/Makefile:ro \
		-v $(CURDIR)/src:$(PKG_SDK_DIR)/src:ro \
		-v $(CURDIR)/files:$(PKG_SDK_DIR)/files:ro \
		-v $(CURDIR)/LICENSE:$(PKG_SDK_DIR)/LICENSE:ro \
		-v $(CURDIR)/bin:/builder/bin \
		$(IMAGE_BUILDER) \
		make package/$(PKG_NAME)/compile V=s
