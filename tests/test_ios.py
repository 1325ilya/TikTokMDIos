import copy
import hashlib
import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from ios import build


def macho(filetype=2, encrypted=False, padding=512):
    segment = bytearray(152)
    struct.pack_into('<II16sQQQQiiII', segment, 0, build.LC_SEGMENT_64, 152, b'__TEXT',
                     0x100000000, 4096, 0, 4096, 5, 5, 1, 0)
    struct.pack_into('<16s16sQQIIIIIIII', segment, 72, b'__text', b'__TEXT',
                     0x100001000, 16, padding, 2, 0, 0, 0x80000400, 0, 0, 0)
    encryption = struct.pack('<6I', build.LC_ENCRYPTION_INFO_64, 24, padding, 16, int(encrypted), 0)
    header = struct.pack('<8I', build.MH_MAGIC_64, build.CPU_ARM64, 0, filetype, 2,
                         len(segment) + len(encryption), 0, 0)
    return (header + segment + encryption).ljust(padding, b'\0') + b'original-code!!!'


def info():
    return {'CFBundleIdentifier': build.BUNDLE_ID, 'CFBundleShortVersionString': build.SUPPORTED_VERSION,
            'CFBundleExecutable': 'TikTok', 'MinimumOSVersion': '14.0',
            'NSAppTransportSecurity': {'NSAllowsArbitraryLoads': False},
            'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False}}


class MachOTest(unittest.TestCase):
    def test_load_command_preserves_binary_data(self):
        original = macho()
        patched = build.add_dylib(original)
        self.assertEqual(len(patched), len(original))
        self.assertEqual(patched[512:], original[512:])
        self.assertEqual(patched[32:208], original[32:208])
        commands = build.load_commands(patched)
        self.assertEqual(len(commands), 3)
        cmd, offset, length = commands[-1]
        self.assertEqual(cmd, build.LC_LOAD_DYLIB)
        self.assertEqual(patched[offset + 24:offset + length].rstrip(b'\0').decode(), build.LOAD_PATH)

    def test_idempotent(self):
        patched = build.add_dylib(macho())
        self.assertEqual(build.add_dylib(patched), patched)

    def test_refuses_encrypted_binary(self):
        with self.assertRaisesRegex(ValueError, 'encrypted'):
            build.add_dylib(macho(encrypted=True))

    def test_refuses_insufficient_header_padding(self):
        with self.assertRaisesRegex(ValueError, 'padding'):
            build.add_dylib(macho(padding=208))

    def test_refuses_nonzero_padding(self):
        raw = bytearray(macho())
        raw[210] = 1
        with self.assertRaisesRegex(ValueError, 'padding'):
            build.add_dylib(bytes(raw))

    def test_refuses_non_arm64_and_fat_files(self):
        for magic, cpu in ((0xCAFEBABE, build.CPU_ARM64), (build.MH_MAGIC_64, 7)):
            raw = bytearray(macho())
            struct.pack_into('<II', raw, 0, magic, cpu)
            with self.assertRaisesRegex(ValueError, 'ARM64'):
                build.add_dylib(raw)

    def test_rejects_truncation(self):
        for raw in (b'', macho()[:24], macho()[:100]):
            with self.assertRaises(ValueError):
                build.add_dylib(raw)

    def test_rejects_invalid_command_sizes(self):
        for size in (0, 7, 15, 4096):
            raw = bytearray(macho())
            struct.pack_into('<I', raw, 36, size)
            with self.assertRaises(ValueError):
                build.add_dylib(raw)

    def test_rejects_invalid_segment(self):
        raw = bytearray(macho())
        struct.pack_into('<I', raw, 32 + 64, 99)
        with self.assertRaisesRegex(ValueError, 'section table'):
            build.add_dylib(raw)

    def test_only_patches_executables(self):
        with self.assertRaisesRegex(ValueError, 'MH_EXECUTE'):
            build.add_dylib(macho(filetype=6))

    def test_rejects_nul_and_external_library_paths(self):
        for name in ('/tmp/library.dylib', build.LOAD_PATH + '\x00extra'):
            with self.assertRaisesRegex(ValueError, 'load path'):
                build.add_dylib(macho(), name)


class IpaTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.ipa = self.root / 'original.ipa'
        self.library = self.root / 'MargyT.dylib'
        self.library.write_bytes(macho(filetype=6))
        self.output = self.root / 'output.ipa'

    def make_ipa(self, metadata=None, extra=None):
        with zipfile.ZipFile(self.ipa, 'w') as archive:
            archive.writestr('Payload/TikTok.app/Info.plist', plistlib.dumps(metadata or info()))
            archive.writestr('Payload/TikTok.app/TikTok', macho())
            archive.writestr('Payload/TikTok.app/Frameworks/MusicallyCore.framework/MusicallyCore', macho(filetype=6))
            archive.writestr('Payload/TikTok.app/Assets.car', b'unchanged-assets')
            archive.writestr('Payload/TikTok.app/_CodeSignature/CodeResources', b'obsolete-signature')
            archive.writestr('Payload/TikTok.app/embedded.mobileprovision', b'old-provisioning')
            for name, data in (extra or {}).items():
                entry = zipfile.ZipInfo()
                entry.filename = name
                archive.writestr(entry, data)

    def test_packages_without_changing_input_or_security_settings(self):
        self.make_ipa()
        before = hashlib.sha256(self.ipa.read_bytes()).digest()
        build.package(self.ipa, self.library, self.output)
        self.assertEqual(hashlib.sha256(self.ipa.read_bytes()).digest(), before)
        with zipfile.ZipFile(self.output) as result:
            self.assertIsNone(result.testzip())
            self.assertEqual(result.read('Payload/TikTok.app/Assets.car'), b'unchanged-assets')
            patched_info = plistlib.loads(result.read('Payload/TikTok.app/Info.plist'))
            for key, value in info().items():
                self.assertEqual(patched_info[key], '15.0' if key == 'MinimumOSVersion' else value)
            self.assertEqual(result.read('Payload/TikTok.app/Frameworks/MargyT.dylib'), self.library.read_bytes())
            self.assertFalse(any('_CodeSignature' in path or 'embedded.mobileprovision' in path for path in result.namelist()))
            self.assertEqual(plistlib.loads(result.read('Payload/TikTok.app/MargyT.bundle/Countries.plist')), build.countries())
            self.assertEqual(result.getinfo('Payload/TikTok.app/Frameworks/MargyT.dylib').external_attr >> 16, 0o100755)

    def test_refuses_to_overwrite_original_or_output(self):
        self.make_ipa()
        self.output.write_bytes(b'keep')
        for path in (self.ipa, self.output, self.library):
            with self.assertRaisesRegex(ValueError, 'new file'):
                build.package(self.ipa, self.library, path)
        self.assertEqual(self.output.read_bytes(), b'keep')

    def test_refuses_wrong_version(self):
        for key, value in (('CFBundleIdentifier', 'another.app'), ('CFBundleShortVersionString', '47.0.0')):
            metadata = copy.deepcopy(info())
            metadata[key] = value
            self.make_ipa(metadata)
            with self.assertRaisesRegex(ValueError, 'unverified'):
                build.package(self.ipa, self.library, self.output)
            self.assertFalse(self.output.exists())

    def test_refuses_unsafe_paths(self):
        for path in ('../escape', '/absolute', 'Payload\\escape'):
            self.make_ipa(extra={path: b''})
            with self.assertRaisesRegex(ValueError, 'Unsafe'):
                build.package(self.ipa, self.library, self.output)
            self.assertFalse(self.output.exists())

    def test_refuses_existing_mod(self):
        self.make_ipa(extra={'Payload/TikTok.app/Frameworks/MargyT.dylib': b'existing'})
        with self.assertRaisesRegex(ValueError, 'already contains'):
            build.package(self.ipa, self.library, self.output)

    def test_refuses_encrypted_core_framework(self):
        self.make_ipa()
        with zipfile.ZipFile(self.ipa) as archive:
            entries = {name: archive.read(name) for name in archive.namelist()}
        entries['Payload/TikTok.app/Frameworks/MusicallyCore.framework/MusicallyCore'] = macho(filetype=6, encrypted=True)
        with zipfile.ZipFile(self.ipa, 'w') as archive:
            for name, data in entries.items():
                archive.writestr(name, data)
        with self.assertRaisesRegex(ValueError, 'encrypted'):
            build.package(self.ipa, self.library, self.output)
        self.assertFalse(self.output.exists())

    def test_refuses_executable_as_library(self):
        self.make_ipa()
        self.library.write_bytes(macho())
        with self.assertRaisesRegex(ValueError, 'MH_DYLIB'):
            build.package(self.ipa, self.library, self.output)

    def test_country_table_preserves_operator_leading_zeroes(self):
        countries = build.countries()
        self.assertGreater(len(countries), 50)
        self.assertEqual(len(countries), len({country['iso'] for country in countries}))
        nl = next(country for country in countries if country['iso'] == 'nl')
        self.assertEqual((nl['mcc'], nl['mnc']), ('204', '08'))
        us = next(country for country in countries if country['iso'] == 'us')
        self.assertEqual((us['mcc'], us['mnc']), ('310', '410'))


if __name__ == '__main__':
    unittest.main()
