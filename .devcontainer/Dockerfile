FROM mcr.microsoft.com/devcontainers/base:debian

# Host-side tooling only: tests and packaging run inside the openwrt/rootfs and
# openwrt/sdk images (see the Makefile), driven by the docker-in-docker feature.
RUN apt-get update \
	&& export DEBIAN_FRONTEND=noninteractive \
	&& apt-get install -y --no-install-recommends \
		make \
		python3 \
		python3-venv \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*

# Docs toolchain, pinned to the version used by .github/workflows/docs.yml.
ARG MKDOCS_MATERIAL_VERSION=9.5.17
RUN python3 -m venv /opt/mkdocs \
	&& /opt/mkdocs/bin/pip install --no-cache-dir "mkdocs-material==${MKDOCS_MATERIAL_VERSION}"
ENV PATH="/opt/mkdocs/bin:${PATH}"
