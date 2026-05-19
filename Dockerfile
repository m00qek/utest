ARG SDK_ARCH=x86-64
ARG SDK_VERSION=24.10.5

FROM openwrt/sdk:${SDK_ARCH}-${SDK_VERSION}

ARG PKG_DEPENDS=ucode

USER root

RUN ./scripts/feeds update -a && \
    for dep in ${PKG_DEPENDS}; do \
        ./scripts/feeds install "$dep"; \
    done && \
    make defconfig
