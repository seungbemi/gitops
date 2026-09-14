"""Read-only config backup with SQLite snapshots and verified, unique archives."""
from contextlib import closing
import gzip
import hashlib
import os
from pathlib import Path
import shutil
import sqlite3
import tarfile
import tempfile
from datetime import datetime, timezone


def digest(stream):
    return hashlib.file_digest(stream, "sha256").hexdigest()


def backup(source=Path("/config"), destination=Path("/backups")):
    os.umask(0o077)
    if not any((source / name).is_file() and (source / name).stat().st_size
               for name in ("config.yml", "config.yaml")):
        raise RuntimeError("Missing or empty Frigate configuration")
    if not (source / "frigate.db").is_file():
        raise RuntimeError("Missing Frigate database")

    # Reserve a unique directory on NFS; never replace a previous backup.
    pending = Path(tempfile.mkdtemp(prefix=".partial-", dir=destination))
    try:
        with tempfile.TemporaryDirectory() as temporary:
            staged = Path(temporary) / "config"
            staged.mkdir()
            for path in sorted(source.rglob("*")):
                relative = path.relative_to(source)
                target = staged / relative
                if path.is_symlink():
                    raise RuntimeError("Symlinks in config require explicit backup handling")
                if path.is_dir():
                    target.mkdir(parents=True, exist_ok=True)
                    continue
                # SQLite's backup API includes committed WAL data. Never copy
                # live WAL/SHM/journal files alongside a standalone snapshot.
                if any(path.name.endswith(".db" + suffix)
                       for suffix in ("-wal", "-shm", "-journal")):
                    continue
                if not path.is_file():
                    raise RuntimeError("Unsupported non-regular config file")
                target.parent.mkdir(parents=True, exist_ok=True)
                if path.suffix == ".db":
                    with closing(sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)) as src:
                        with closing(sqlite3.connect(target)) as dst:
                            src.backup(dst)
                            if dst.execute("PRAGMA integrity_check").fetchall() != [("ok",)]:
                                raise RuntimeError("SQLite integrity check failed")
                else:
                    before = path.stat()
                    shutil.copyfile(path, target)
                    after = path.stat()
                    if (before.st_size, before.st_mtime_ns, before.st_ino) != (
                            after.st_size, after.st_mtime_ns, after.st_ino):
                        raise RuntimeError("Configuration changed during backup; retry")

            if not any((staged / name).is_file() and (staged / name).stat().st_size
                       for name in ("config.yml", "config.yaml")):
                raise RuntimeError("Configuration disappeared during backup")
            if not (staged / "frigate.db").is_file():
                raise RuntimeError("Database disappeared during backup")
            expected = {}
            for path in staged.rglob("*"):
                if path.is_file():
                    with path.open("rb") as stream:
                        expected[str(path.relative_to(staged.parent))] = digest(stream)
            archive = pending / "config.tar.gz"
            with tarfile.open(archive, "w:gz") as tar:
                tar.add(staged, arcname="config")
            # Read through the gzip trailer (CRC) and verify every archived file.
            with gzip.open(archive, "rb") as stream:
                while stream.read(1024 * 1024):
                    pass
            with tarfile.open(archive, "r:gz") as tar:
                actual = {member.name: digest(tar.extractfile(member))
                          for member in tar.getmembers() if member.isfile()}
            if actual != expected:
                raise RuntimeError("Archive contents failed verification")
            with archive.open("rb") as stream:
                checksum = digest(stream)
            (pending / "SHA256SUMS").write_text(f"{checksum}  config.tar.gz\n")
            for path in pending.iterdir():
                with path.open("rb") as stream:
                    os.fsync(stream.fileno())
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        final = destination / ("config-" + stamp + "-" + pending.name.removeprefix(".partial-"))
        # The unique reserved suffix avoids collisions across concurrent Jobs.
        pending.rename(final)
        print(f"Verified config archive: {final.name}/config.tar.gz", flush=True)
        return final
    finally:
        if pending.exists():
            shutil.rmtree(pending)


if __name__ == "__main__":
    backup()
