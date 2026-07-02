SDK_VERSION ?= 24.10.6
SDK_ARCH ?= x86-64

# OpenWrt rootfs image for running tests. Must ship ucode WITH the uloop module:
# the parallel executor drives worker I/O through uloop and has no polling
# fallback. Newer rootfs tags drop the '-openwrt-' infix and carry the full
# version, so this is decoupled from SDK_VERSION (used only by `make package`).
ROOTFS_VERSION ?= 25.12.4
IMAGE_OPENWRT := openwrt/rootfs:$(SDK_ARCH)-$(ROOTFS_VERSION)

# What `make test` runs when no path is given. utest's built-in default is
# test/unit/*_test.uc, which this repo does not have — its suites live under
# examples/. Override per-run, e.g. `make test ARGS="examples/multi"`.
# Note: examples/unit contains intentional demo failures/fatals (shrinking and
# fatal-hook demos); `make meta-test` is the authoritative pass/fail check.
ARGS ?= examples/unit

.PHONY: test shell meta-test package

# --tmpfs /tmp:mode=1777 gives a world-writable /tmp: newer rootfs images ship
# /tmp as 0755 root-owned, so utest.sh's `mktemp -d /tmp/...` run-dir fails under
# --user (an unwritable run dir collapses shim paths to /shims).
test:
	@docker run --rm \
		--user $$(id -u):$$(id -g) \
		--tmpfs /tmp:mode=1777 \
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
		--tmpfs /tmp:mode=1777 \
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
