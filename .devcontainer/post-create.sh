#!/bin/sh

# Pre-pull the test rootfs so the first `make test` / `make meta-test` does not
# stall on it. Ask the Makefile for the image rather than duplicating it here.
# Best effort: the docker-in-docker daemon may still be starting up.
image="$(make -s --eval 'print-image: ; @echo $(IMAGE_OPENWRT)' print-image)"
docker pull "$image" || echo "post-create: could not pre-pull $image; make will pull it on demand" >&2
