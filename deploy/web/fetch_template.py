"""Fetches single export templates out of the official Godot template archive (.tpz, over 1 GB)
with HTTP range requests, so a build downloads a few MB instead of the whole archive.

Usage:  python3 fetch_template.py <tpz url> <target dir> <name>=<sha512> [<name>=<sha512> ...]

Every file is checked twice: the CRC32 from the archive itself (zipfile) and the pinned SHA-512
(see the Dockerfile; computed from the official 4.7.2-stable archive). Pure standard library.
"""
import hashlib
import io
import sys
import urllib.request
import zipfile
from pathlib import Path

CHUNK = 1 << 20
USER_AGENT = "soulwick-web-build"


class HttpRangeFile(io.RawIOBase):
    """Read-only, seekable file over HTTP range requests with a small read-ahead buffer."""

    def __init__(self, url):
        super().__init__()
        request = urllib.request.Request(url, method="HEAD", headers={"User-Agent": USER_AGENT})
        with urllib.request.urlopen(request, timeout=60) as response:
            # Follow redirects once (GitHub release assets live on a signed CDN address).
            self.url = response.geturl()
            self.size = int(response.headers["Content-Length"])
            if response.headers.get("Accept-Ranges", "").lower() != "bytes":
                raise SystemExit("Server does not support range requests: %s" % self.url)
        self.pos = 0
        self.buffer_start = 0
        self.buffer = b""
        self.requests = 0

    def readable(self):
        return True

    def seekable(self):
        return True

    def tell(self):
        return self.pos

    def seek(self, offset, whence=io.SEEK_SET):
        if whence == io.SEEK_SET:
            self.pos = offset
        elif whence == io.SEEK_CUR:
            self.pos += offset
        else:
            self.pos = self.size + offset
        return self.pos

    def _fetch(self, start, length):
        end = min(self.size, start + max(length, CHUNK)) - 1
        request = urllib.request.Request(self.url, headers={"Range": "bytes=%d-%d" % (start, end), "User-Agent": USER_AGENT})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(request, timeout=120) as response:
                    if response.status != 206:
                        raise OSError("expected 206, got %d" % response.status)
                    data = response.read()
                    break
            except OSError:
                if attempt == 3:
                    raise
        self.requests += 1
        self.buffer_start, self.buffer = start, data

    def read(self, size=-1):
        if size is None or size < 0:
            size = self.size - self.pos
        size = max(0, min(size, self.size - self.pos))
        if size == 0:
            return b""
        out = bytearray()
        while len(out) < size:
            offset = self.pos - self.buffer_start
            if offset < 0 or offset >= len(self.buffer):
                self._fetch(self.pos, size - len(out))
                offset = 0
            piece = self.buffer[offset:offset + size - len(out)]
            out += piece
            self.pos += len(piece)
        return bytes(out)

    def readinto(self, target):
        data = self.read(len(target))
        target[:len(data)] = data
        return len(data)


def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    url, target = sys.argv[1], Path(sys.argv[2])
    wanted = dict(arg.split("=", 1) for arg in sys.argv[3:])
    target.mkdir(parents=True, exist_ok=True)
    remote = HttpRangeFile(url)
    with zipfile.ZipFile(io.BufferedReader(remote, buffer_size=CHUNK)) as archive:
        names = {Path(info.filename).name: info for info in archive.infolist() if not info.is_dir()}
        for name, expected in wanted.items():
            if name not in names:
                raise SystemExit("%s is not in the template archive." % name)
            data = archive.read(names[name])  # checks the CRC32
            digest = hashlib.sha512(data).hexdigest()
            if expected and digest != expected.lower():
                raise SystemExit("SHA-512 mismatch for %s:\n  expected %s\n  got      %s" % (name, expected, digest))
            (target / name).write_bytes(data)
            print("%s  %.1f MB  sha512 %s" % (name, len(data) / 1e6, "ok" if expected else digest))
    print("%d range requests for an archive of %.0f MB" % (remote.requests, remote.size / 1e6))


if __name__ == "__main__":
    main()
