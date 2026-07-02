SDK_VERSION ?= 24.10.6
SDK_ARCH ?= x86-64

OPENWRT_VERSION := $(shell echo $(SDK_VERSION) | sed 's/\.[^.]*$$//')
IMAGE_OPENWRT := openwrt/rootfs:$(SDK_ARCH)-openwrt-$(OPENWRT_VERSION)

# What `make test` runs when no path is given. utest's built-in default is
# test/unit/*_test.uc, which this repo does not have — its suites live under
# examples/. Override per-run, e.g. `make test ARGS="examples/multi"`.
# Note: examples/unit contains intentional demo failures/fatals (shrinking and
# fatal-hook demos); `make meta-test` is the authoritative pass/fail check.
ARGS ?= examples/unit

.PHONY: test shell meta-test package

test:
	@docker run --rm \
		--user $$(id -u):$$(id -g) \
		-v $(CURDIR)/src/utest.sh:/usr/bin/utest:ro \
		-v $(CURDIR)/src/utest.uc:/usr/share/ucode/utest.uc:ro \
		-v $(CURDIR)/src/utest:/usr/share/ucode/utest:ro \
		-v $(CURDIR):/app \
		-w /app \
		$(IMAGE_OPENWRT) \
		utest $(ARGS)

shell:
	@docker run --rm -it \
		--user $$(id -u):$$(id -g) \
		-v $(CURDIR)/src/utest.sh:/usr/bin/utest:ro \
		-v $(CURDIR)/src/utest.uc:/usr/share/ucode/utest.uc:ro \
		-v $(CURDIR)/src/utest:/usr/share/ucode/utest:ro \
		-v $(CURDIR):/app \
		-w /app \
		$(IMAGE_OPENWRT) \
		sh

meta-test:
	./scripts/meta-test.sh

package:
	GIT_COMMIT=$(shell git rev-parse --short=8 HEAD) SDK_VERSION=$(SDK_VERSION) SDK_ARCH=$(SDK_ARCH) ./scripts/build-package.sh
