import argparse
import copy
import os
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ('MTCore.m', 'MTSettings.m', 'MTHooks.m', 'MTAppearance.m')
LOAD_PATH = '@executable_path/Frameworks/MargyT.dylib'
BUNDLE_ID = 'com.zhiliaoapp.musically'
SUPPORTED_VERSION = '46.9.0'
MH_MAGIC_64 = 0xFEEDFACF
CPU_ARM64 = 0x0100000C
LC_SEGMENT_64 = 0x19
LC_LOAD_DYLIB = 0xC
LC_ENCRYPTION_INFO_64 = 0x2C


def load_commands(raw):
    if len(raw) < 32:
        raise ValueError('Truncated Mach-O header')
    magic, cpu, subtype, filetype, count, size, flags, reserved = struct.unpack_from('<8I', raw)
    if magic != MH_MAGIC_64 or cpu != CPU_ARM64:
        raise ValueError('Expected a thin, little-endian ARM64 Mach-O')
    if count > size // 8 or 32 + size > len(raw):
        raise ValueError('Invalid Mach-O load command table')
    offset = 32
    commands = []
    for _ in range(count):
        if offset + 8 > 32 + size:
            raise ValueError('Truncated Mach-O command')
        cmd, length = struct.unpack_from('<II', raw, offset)
        if length < 8 or length % 8 or offset + length > 32 + size:
            raise ValueError('Invalid Mach-O command size')
        if cmd == LC_ENCRYPTION_INFO_64:
            if length < 24 or struct.unpack_from('<I', raw, offset + 16)[0]:
                raise ValueError('The executable is encrypted; supply your own decrypted IPA')
        commands.append((cmd, offset, length))
        offset += length
    if offset != 32 + size:
        raise ValueError('Mach-O command count and size disagree')
    return commands


def add_dylib(raw, path=LOAD_PATH):
    commands = load_commands(raw)
    if struct.unpack_from('<I', raw, 12)[0] != 2:
        raise ValueError('Expected MH_EXECUTE for the app entry point')
    if not path.startswith('@executable_path/') or '\x00' in path:
        raise ValueError('Invalid library load path')
    count, size = struct.unpack_from('<II', raw, 16)
    end = 32 + size
    first_data = len(raw)
    for cmd, offset, length in commands:
        if cmd in (LC_LOAD_DYLIB, 0x80000018, 0x8000001F, 0x80000023):
            if length < 24:
                raise ValueError('Truncated dylib command')
            name_offset = struct.unpack_from('<I', raw, offset + 8)[0]
            if name_offset < 24 or name_offset >= length:
                raise ValueError('Invalid dylib name offset')
            name = raw[offset + name_offset:offset + length].split(b'\0', 1)[0]
            if name == path.encode('utf-8'):
                return raw
        if cmd != LC_SEGMENT_64:
            continue
        if length < 72:
            raise ValueError('Truncated segment command')
        fileoff, filesize = struct.unpack_from('<QQ', raw, offset + 40)
        if filesize and fileoff:
            first_data = min(first_data, fileoff)
        sections = struct.unpack_from('<I', raw, offset + 64)[0]
        if 72 + sections * 80 != length:
            raise ValueError('Invalid segment section table')
        for index in range(sections):
            section = offset + 72 + index * 80
            section_size = struct.unpack_from('<Q', raw, section + 40)[0]
            section_offset = struct.unpack_from('<I', raw, section + 48)[0]
            kind = struct.unpack_from('<I', raw, section + 64)[0] & 0xFF
            if section_size and section_offset and kind not in (1, 0xC, 0x12):
                first_data = min(first_data, section_offset)
    name = path.encode('utf-8') + b'\0'
    length = (24 + len(name) + 7) & ~7
    if first_data == len(raw) or first_data < end + length or any(raw[end:end + length]):
        raise ValueError('Not enough verified zero-filled Mach-O header padding; no bytes were moved')
    output = bytearray(raw)
    command = struct.pack('<6I', LC_LOAD_DYLIB, length, 24, 0, 0, 0) + name
    output[end:end + length] = command.ljust(length, b'\0')
    struct.pack_into('<II', output, 16, count + 1, size + length)
    return bytes(output)


def countries():
    bundled = Path(__file__).with_name('Countries.plist')
    if bundled.is_file():
        return plistlib.loads(bundled.read_bytes())
    source = ROOT / 'inject/java/cat/narezany/margyt/Margy.java'
    rows = re.findall(r'\{"([a-z]{2})",\s*"(\d{5,6})",\s*"([^"]+)",\s*"([^"]+)"\}', source.read_text(encoding='utf-8'))
    if not rows or len({row[0] for row in rows}) != len(rows):
        raise ValueError('Cannot read the Android country table')
    return [{'iso': iso, 'mcc': operator[:3], 'mnc': operator[3:], 'carrier': carrier, 'name': name}
            for iso, operator, carrier, name in rows]


def ipa_info(archive):
    names = archive.namelist()
    if len(set(names)) != len(names):
        raise ValueError('Duplicate IPA archive paths')
    for entry in archive.infolist():
        name = entry.orig_filename
        path = PurePosixPath(name)
        if not name or path.is_absolute() or '..' in path.parts or '\\' in name or '\x00' in name or ':' in name:
            raise ValueError('Unsafe IPA archive path')
    infos = [name for name in names if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist', name)]
    if len(infos) != 1:
        raise ValueError('Expected exactly one app in Payload')
    info_path = infos[0]
    info = plistlib.loads(archive.read(info_path))
    if info.get('CFBundleIdentifier') != BUNDLE_ID or info.get('CFBundleShortVersionString') != SUPPORTED_VERSION:
        raise ValueError(f'This adapter targets {BUNDLE_ID} {SUPPORTED_VERSION}; refusing an unverified app version')
    executable = info.get('CFBundleExecutable', '')
    if not re.fullmatch(r'[A-Za-z0-9_.-]+', executable) or executable in ('.', '..'):
        raise ValueError('Invalid CFBundleExecutable')
    app = info_path.rsplit('/', 1)[0]
    return app, info_path, info, f'{app}/{executable}'


def package(ipa, library, output):
    ipa, library, output = Path(ipa), Path(library), Path(output)
    if output.resolve() in (ipa.resolve(), library.resolve()) or output.exists():
        raise ValueError('Output must be a new file, distinct from both inputs')
    lib = library.read_bytes()
    load_commands(lib)
    if struct.unpack_from('<I', lib, 12)[0] != 6:
        raise ValueError('Expected MH_DYLIB for MargyT')
    with zipfile.ZipFile(ipa) as source:
        app, info_path, info, executable = ipa_info(source)
        destination = f'{app}/Frameworks/MargyT.dylib'
        resources = f'{app}/MargyT.bundle/Countries.plist'
        if destination in source.namelist() or resources in source.namelist():
            raise ValueError('This IPA already contains MargyT; start with the original IPA')
        core = f'{app}/Frameworks/MusicallyCore.framework/MusicallyCore'
        if core not in source.namelist():
            raise ValueError('Missing MusicallyCore framework')
        with source.open(core) as reader:
            load_commands(reader.read(65536))
        patched = add_dylib(source.read(executable))
        metadata = copy.deepcopy(info)
        minimum = tuple(int(part) for part in metadata.get('MinimumOSVersion', '0').split('.'))
        if minimum < (15, 0):
            metadata['MinimumOSVersion'] = '15.0'
        metadata['MargyTPortVersion'] = '0.2.0-dev'
        replacements = {executable: patched, info_path: plistlib.dumps(metadata, fmt=plistlib.FMT_BINARY)}
        output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(dir=output.parent, suffix='.ipa.tmp', delete=False) as pending:
            temporary = Path(pending.name)
        try:
            with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as target:
                for entry in source.infolist():
                    parts = PurePosixPath(entry.filename).parts
                    if '_CodeSignature' in parts or parts[-1] == 'embedded.mobileprovision':
                        continue
                    with target.open(copy.copy(entry), 'w', force_zip64=True) as writer:
                        if entry.filename in replacements:
                            writer.write(replacements[entry.filename])
                        else:
                            with source.open(entry) as reader:
                                shutil.copyfileobj(reader, writer, length=1024 * 1024)
                for name, data, mode in ((destination, lib, 0o100755), (resources, plistlib.dumps(countries()), 0o100644)):
                    entry = zipfile.ZipInfo(name)
                    entry.create_system = 3
                    entry.external_attr = mode << 16
                    entry.compress_type = zipfile.ZIP_DEFLATED
                    target.writestr(entry, data)
            with zipfile.ZipFile(temporary) as verify:
                if verify.testzip() is not None:
                    raise ValueError('Output IPA CRC verification failed')
                if add_dylib(verify.read(executable)) != patched:
                    raise ValueError('Output load command verification failed')
            os.link(temporary, output)
        finally:
            temporary.unlink(missing_ok=True)
    return output


def compile_library(sdk, clang, linker, build_dir):
    sdk, build_dir = Path(sdk), Path(build_dir)
    if not (sdk / 'System/Library/Frameworks/UIKit.framework/Headers/UIKit.h').is_file():
        raise ValueError('SDK is missing UIKit headers')
    build_dir.mkdir(parents=True, exist_ok=True)
    objects = []
    for name in SOURCES:
        obj = build_dir / (Path(name).stem + '.o')
        subprocess.run([str(clang), '--no-default-config', '-target', 'arm64-apple-ios15.0',
                        '-isysroot', str(sdk), '-fobjc-arc', '-fblocks', '-O2', '-Wall', '-Wextra',
                        '-Werror', '-Wno-unused-parameter', '-fvisibility=hidden',
                        '-c', str(ROOT / 'ios' / name), '-o', str(obj)], check=True)
        objects.append(str(obj))
    library = build_dir / 'MargyT.dylib'
    frameworks = [arg for name in ('Foundation', 'UIKit', 'QuartzCore', 'CoreTelephony') for arg in ('-framework', name)]
    if linker:
        subprocess.run([str(linker), '-flavor', 'darwin', '-arch', 'arm64', '-platform_version', 'ios', '15.0', '16.5',
                        '-dylib', '-install_name', '@rpath/MargyT.dylib', '-syslibroot', str(sdk),
                        '-no_fixup_chains', '-adhoc_codesign', '-lSystem', '-lobjc', *frameworks,
                        '-o', str(library), *objects], check=True)
    else:
        subprocess.run([str(clang), '--no-default-config', '-target', 'arm64-apple-ios15.0', '-isysroot', str(sdk),
                        '-dynamiclib', '-Wl,-install_name,@rpath/MargyT.dylib', *frameworks,
                        '-o', str(library), *objects], check=True)
    load_commands(library.read_bytes())
    return library


def main():
    parser = argparse.ArgumentParser(description='Build the experimental MargyT iOS adapter and an unsigned IPA. Re-sign with your own provisioning before installation.')
    parser.add_argument('--sdk', type=Path)
    parser.add_argument('--clang', default=os.environ.get('CLANG', shutil.which('clang')))
    parser.add_argument('--linker', default=os.environ.get('LD64'))
    parser.add_argument('--build-dir', type=Path, default=ROOT / 'build/ios')
    parser.add_argument('--library', type=Path, help='Package an already compiled MargyT dylib')
    parser.add_argument('--ipa', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if bool(args.ipa) != bool(args.output):
        parser.error('--ipa and --output must be supplied together')
    if args.output and args.output.exists():
        parser.error('Output already exists; choose a new path')
    if args.library:
        library = args.library
    else:
        if not args.sdk and sys.platform == 'darwin':
            args.sdk = Path(subprocess.check_output(['xcrun', '--sdk', 'iphoneos', '--show-sdk-path'], text=True).strip())
        if not args.sdk or not args.clang:
            parser.error('Supply --sdk and --clang, or run on macOS with Xcode')
        if sys.platform == 'win32' and not args.linker:
            parser.error('Windows requires a Mach-O capable LLD using --linker')
        library = compile_library(args.sdk, args.clang, args.linker, args.build_dir)
    print(f'Library: {library}')
    if args.ipa:
        output = package(args.ipa, library, args.output)
        print(f'Unsigned IPA: {output}')
        print('Re-sign the app and embedded frameworks with your own iOS signing tool. Not verified on an iPhone; iOS 27 compatibility is unconfirmed.')


if __name__ == '__main__':
    main()
