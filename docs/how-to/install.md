# How to install utest

Install the `ucode-utest` package on OpenWrt from the ucode.dev package feed.

---

## Add the feed and install

utest is not part of the official OpenWrt package feeds. It is published in [packages.ucode.dev](https://github.com/m00qek/packages.ucode.dev), a third-party feed whose packages are signed. Trust the feed's signing key, add the feed, then install the package as usual.

**OpenWrt 24.10 (opkg)**:

```bash
wget -O /etc/opkg/keys/a2288d4745630a38 \
  https://m00qek.github.io/packages.ucode.dev/24.10/feed.pub
echo "src/gz ucode.dev https://m00qek.github.io/packages.ucode.dev/24.10" \
  >> /etc/opkg/customfeeds.conf

opkg update
opkg install ucode-utest
```

**OpenWrt 25.12 (apk)**:

```bash
wget -O /etc/apk/keys/packages.ucode.dev.pem \
  https://m00qek.github.io/packages.ucode.dev/25.12/feed.pub.pem
echo "https://m00qek.github.io/packages.ucode.dev/25.12" \
  >> /etc/apk/repositories.d/customfeeds.list

apk update
apk add ucode-utest
```

The feed is only built for OpenWrt 24.10 and 25.12. The [feed's README](https://github.com/m00qek/packages.ucode.dev#readme) lists the architectures each release covers. On 25.12, if your router's architecture (`apk --print-arch`) is not listed there, `apk update` cannot find the feed's index; [install the package file](#install-a-single-package-file) instead.

---

## Install in an OpenWrt container

The official `openwrt/rootfs` Docker images take the same steps, with one addition for 24.10: the image has no `/var/lock`, and `opkg` cannot take its lock file without it. Create the directory first:

```bash
mkdir -p /var/lock
```

See [How-to: Run tests in CI](ci.md) for a complete container recipe.

---

## Install a single package file

If you cannot add a feed, for example to pin an exact version, download the package file and install it directly. The packages are also attached to each [GitHub release](https://github.com/m00qek/utest/releases).

The file names carry the full package version, `<version>-r<release>`, for example `1.5.1-r1`:

```bash
# OpenWrt 24.10
opkg install ./ucode-utest_1.5.1-r1_all.ipk

# OpenWrt 25.12 (the signing key is not installed, so apk must be told to skip verification)
apk add --allow-untrusted ./ucode-utest-1.5.1-r1.apk
```

Without the feed's signature check, verify the file yourself, for example against a known SHA-256 checksum.

---

## Next steps

- Write and run a first test suite: [Tutorial: Writing your first test](../tutorials/user/first-test.md)
- Run the suite on every push: [How-to: Run tests in CI](ci.md)
