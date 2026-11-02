"""Native CLI integration checks; never registers an agent or changes the user's app."""
import hashlib
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(sys.platform == "darwin" and platform.machine() == "arm64", "requires Apple silicon macOS")
class StandaloneInstall(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        (ROOT / ".build").mkdir(exist_ok=True)
        cls.work = tempfile.TemporaryDirectory(prefix="integration-", dir=ROOT / ".build")
        cls.directory = Path(cls.work.name)
        cls.app = cls.directory / "fixture/Rex Beta.app"
        executable = cls.app / "Contents/MacOS/Rex"
        executable.parent.mkdir(parents=True)
        cls.unrelated = cls.directory / "unrelated.dylib"
        library_source = cls.directory / "library.c"
        library_source.write_text("int external_marker(void) { return 0; }\n")
        main_source = cls.directory / "main.c"
        main_source.write_text("extern int external_marker(void); int main(void) { return external_marker(); }\n")
        cls.native = cls.directory / "Rex.arm64"
        intel = cls.directory / "Rex.x86_64"
        intel_source = cls.directory / "intel.c"
        intel_source.write_text("int main(void) { return 0; }\n")
        for command in [
            ["xcrun", "clang", "-dynamiclib", "-arch", "arm64", str(library_source),
             f"-Wl,-install_name,{cls.unrelated}", "-o", str(cls.unrelated)],
            ["xcrun", "clang", "-arch", "arm64", "-Wl,-headerpad,0x1000", str(main_source),
             str(cls.unrelated), "-o", str(cls.native)],
            ["xcrun", "clang", "-arch", "x86_64", str(intel_source), "-o", str(intel)],
            ["lipo", "-create", str(cls.native), str(intel), "-output", str(executable)],
        ]:
            subprocess.run(command, check=True, capture_output=True, text=True)
        (cls.app / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleExecutable": "Rex", "CFBundleIdentifier": "dev.rexmod-vntyping.fixture",
            "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
        }))
        subprocess.run(["codesign", "-f", "-s", "-", str(cls.app)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    def call(self, *command, expected=0, env=None):
        result = subprocess.run(command, env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return result

    def test_standalone_install_idempotence_and_uninstall(self):
        home = self.directory / "home"
        app = self.directory / "installed/Rex Beta.app"
        shutil.copytree(self.app, app)
        original = (app / "Contents/MacOS/Rex").read_bytes()
        env = dict(os.environ, HOME=str(home), REX_APP=str(app))
        prefix = home / "Library/Application Support/rexmod-vntyping"
        self.call("/bin/sh", str(ROOT / "install.sh"), "--no-agent", env=env)
        self.call("/bin/sh", str(prefix / "patch.sh"), "--check", env=env)
        self.call("codesign", "--verify", "--strict", str(app))
        self.assertEqual(self.call("lipo", "-archs", str(app / "Contents/MacOS/Rex")).stdout.strip(), "arm64")
        self.call(str(app / "Contents/MacOS/Rex"))
        entitlements = self.call("codesign", "-d", "--entitlements", "-", "--xml", str(app))
        self.assertIs(plistlib.loads(entitlements.stdout.encode())["com.apple.security.cs.disable-library-validation"], True)
        libraries = self.call("otool", "-L", str(app / "Contents/MacOS/Rex")).stdout
        self.assertIn(str(self.unrelated), libraries)
        self.assertEqual(libraries.count(str(prefix / "RexVietnameseInput.dylib")), 1)
        self.assertEqual((prefix / "backup/Rex Beta.app/Contents/MacOS/Rex").read_bytes(), original)
        self.assertFalse((home / "Library/LaunchAgents").exists())
        before = hashlib.sha256((app / "Contents/MacOS/Rex").read_bytes()).digest()
        self.call("/bin/sh", str(prefix / "patch.sh"), env=env)
        self.assertEqual(hashlib.sha256((app / "Contents/MacOS/Rex").read_bytes()).digest(), before)
        self.call("/bin/sh", str(prefix / "install.sh"), "--remove", env=env)
        self.call("/bin/sh", str(prefix / "patch.sh"), "--check", expected=3, env=env)
        self.call("codesign", "--verify", "--strict", str(app))
        self.assertIn(str(self.unrelated), self.call("otool", "-L", str(app / "Contents/MacOS/Rex")).stdout)
        self.call("/bin/sh", str(prefix / "install.sh"), "--remove", env=env)

    def test_unsafe_binary_edits_leave_the_file_unchanged(self):
        target = self.directory / "candidate"
        for contents, library, reason in [
            (b"not a Mach-O file", "/test.dylib", "truncated Mach-O header"),
            (self.native.read_bytes(), "/" + "x" * 65536, "header padding"),
        ]:
            with self.subTest(reason=reason):
                target.write_bytes(contents)
                result = self.call(sys.executable, "-I", str(ROOT / "scripts/dylib-load-command.py"),
                                   str(target), library, expected=1)
                self.assertIn(reason, result.stderr)
                self.assertEqual(target.read_bytes(), contents)


if __name__ == "__main__":
    unittest.main()
