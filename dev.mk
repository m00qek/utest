SDK_ARCH ?= x86-64

IMAGE_OPENWRT := openwrt/rootfs:$(SDK_ARCH)-openwrt-24.10

.PHONY: test meta-test package

test:
	docker run --rm \
		-v $(CURDIR):/app \
		-w /app \
		$(IMAGE_OPENWRT) \
		src/utest.sh $(ARGS)

meta-test:
	./scripts/meta-test.sh

package:
	GIT_COMMIT=$(shell git rev-parse --short=8 HEAD) SDK_VERSION=$(SDK_VERSION) SDK_ARCH=$(SDK_ARCH) ./scripts/build-package.sh
