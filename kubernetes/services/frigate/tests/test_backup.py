import hashlib
import importlib.util
from pathlib import Path
import sqlite3
import tarfile
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("backup", Path(__file__).parents[1] / "files/backup.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BackupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.source = self.root / "config"
        self.dest = self.root / "backups"
        self.source.mkdir()
        self.dest.mkdir()
        (self.source / "config.yml").write_text("mqtt:\n  enabled: false\n")
        self.db = sqlite3.connect(self.source / "frigate.db")
        self.addCleanup(self.db.close)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("CREATE TABLE events (id INTEGER)")
        self.db.execute("INSERT INTO events VALUES (42)")
        self.db.commit()
        self.legacy = self.dest / "backups.tar.gz"
        self.legacy.write_bytes(b"last good archive")

    def run_backup(self):
        return module.backup(self.source, self.dest)

    def assert_preserved(self):
        self.assertEqual(self.legacy.read_bytes(), b"last good archive")
        self.assertEqual(list(self.dest.glob(".partial-*")), [])

    def test_wal_snapshot_and_unique_archives(self):
        # Keep the writer open so committed rows remain in the WAL.
        self.assertTrue((self.source / "frigate.db-wal").exists())
        first = self.run_backup()
        second = self.run_backup()
        self.assertNotEqual(first, second)
        archive = first / "config.tar.gz"
        self.assertEqual((first / "SHA256SUMS").read_text().split()[0],
                         hashlib.sha256(archive.read_bytes()).hexdigest())
        with tarfile.open(archive) as tar:
            self.assertIn("config/config.yml", tar.getnames())
            self.assertNotIn("config/frigate.db-wal", tar.getnames())
            self.assertNotIn("config/frigate.db-shm", tar.getnames())
            restored = self.root / "restored.db"
            restored.write_bytes(tar.extractfile("config/frigate.db").read())
        with sqlite3.connect(restored) as db:
            self.assertEqual(db.execute("PRAGMA integrity_check").fetchone(), ("ok",))
            self.assertEqual(db.execute("SELECT id FROM events").fetchall(), [(42,)])
        self.assert_preserved()

    def test_missing_config_does_not_publish(self):
        (self.source / "config.yml").unlink()
        with self.assertRaises(RuntimeError):
            self.run_backup()
        self.assertEqual(list(self.dest.glob("config-*")), [])
        self.assert_preserved()

    def test_corrupt_database_does_not_publish(self):
        (self.source / "other.db").write_bytes(b"not a database")
        with self.assertRaises(sqlite3.DatabaseError):
            self.run_backup()
        self.assertEqual(list(self.dest.glob("config-*")), [])
        self.assert_preserved()

    def test_failed_archive_verification_does_not_publish(self):
        with patch.object(module.gzip, "open", side_effect=OSError("corrupt gzip")):
            with self.assertRaises(OSError):
                self.run_backup()
        self.assertEqual(list(self.dest.glob("config-*")), [])
        self.assert_preserved()

    def test_symlink_cannot_escape_config(self):
        (self.source / "outside").symlink_to(self.legacy)
        with self.assertRaises(RuntimeError):
            self.run_backup()
        self.assert_preserved()


if __name__ == "__main__":
    unittest.main()
