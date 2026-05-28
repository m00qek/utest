SDK_VERSION ?= 24.10.6
SDK_ARCH ?= x86-64

OPENWRT_VERSION := $(shell echo $(SDK_VERSION) | sed 's/\.[^.]*$$//')
IMAGE_OPENWRT := openwrt/rootfs:$(SDK_ARCH)-openwrt-$(OPENWRT_VERSION)

.PHONY: test shell meta-test package

test:
	docker run --rm \
		-v $(CURDIR)/src/utest.sh:/usr/bin/utest:ro \
		-v $(CURDIR)/src/utest.uc:/usr/share/ucode/utest.uc:ro \
		-v $(CURDIR)/src/utest:/usr/share/ucode/utest:ro \
		-v $(CURDIR):/app \
		-w /app \
		$(IMAGE_OPENWRT) \
		utest $(ARGS)

shell:
	docker run --rm -it \
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
