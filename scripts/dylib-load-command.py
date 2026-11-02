#!/usr/bin/python3
"""Add, remove or check one dylib load command in a thin arm64 Mach-O file."""
import argparse
from pathlib import Path
import struct
import sys

HEADER_SIZE = 32
LC_SEGMENT_64 = 0x19
LC_LOAD_WEAK_DYLIB = 0x80000018
LOAD_COMMANDS = {0xC, LC_LOAD_WEAK_DYLIB, 0x8000001F, 0x80000023, 0x20}


def read_commands(data):
    if len(data) < HEADER_SIZE:
        raise ValueError("truncated Mach-O header")
    magic, cpu, _, file_type, count, size, _, _ = struct.unpack_from("<8I", data)
    if magic != 0xFEEDFACF or cpu != 0x0100000C or file_type not in {2, 6, 8}:
        raise ValueError("expected a thin little-endian arm64 executable, dylib or bundle")
    end = HEADER_SIZE + size
    if end > len(data):
        raise ValueError("load commands extend beyond the file")
    commands, payload_offsets = [], []
    position = HEADER_SIZE
    for _ in range(count):
        if position + 8 > end:
            raise ValueError("truncated load command")
        kind, length = struct.unpack_from("<2I", data, position)
        if length < 8 or length % 8 or position + length > end:
            raise ValueError("invalid load command size")
        command = bytes(data[position:position + length])
        if kind in LOAD_COMMANDS:
            if length < 24:
                raise ValueError("truncated dylib load command")
            name_offset = struct.unpack_from("<I", command, 8)[0]
            if name_offset < 24 or name_offset >= length or b"\0" not in command[name_offset:]:
                raise ValueError("invalid dylib name")
        if kind == LC_SEGMENT_64:
            if length < 72:
                raise ValueError("truncated segment command")
            file_offset, file_size = struct.unpack_from("<2Q", command, 40)
            sections = struct.unpack_from("<I", command, 64)[0]
            if 72 + sections * 80 > length:
                raise ValueError("truncated section table")
            if file_offset and file_size:
                payload_offsets.append(file_offset)
            for section in range(sections):
                start = 72 + section * 80
                offset = struct.unpack_from("<I", command, start + 48)[0]
                section_type = struct.unpack_from("<I", command, start + 64)[0] & 0xFF
                if offset and section_type not in {1, 0xC, 0x12}:
                    payload_offsets.append(offset)
        commands.append(command)
        position += length
    if position != end:
        raise ValueError("load command count and size disagree")
    return commands, min(payload_offsets, default=len(data))


def references(command, name):
    if struct.unpack_from("<I", command)[0] not in LOAD_COMMANDS:
        return False
    start = struct.unpack_from("<I", command, 8)[0]
    return command[start:].split(b"\0", 1)[0] == name


def update(path, name, action):
    data = bytearray(path.read_bytes())
    commands, payload = read_commands(data)
    encoded = name.encode("utf-8")
    if not encoded or b"\0" in encoded:
        raise ValueError("dylib path must be nonempty and contain no NUL")
    found = any(references(command, encoded) for command in commands)
    if action == "check":
        print("present" if found else "absent")
        return 0 if found else 3
    if (action == "add" and found) or (action == "remove" and not found):
        print("already present" if found else "already absent")
        return 0
    old_size = sum(map(len, commands))
    if action == "remove":
        commands = [command for command in commands if not references(command, encoded)]
    else:
        length = (24 + len(encoded) + 1 + 7) & ~7
        command = struct.pack("<6I", LC_LOAD_WEAK_DYLIB, length, 24, 0, 0x10000, 0x10000)
        commands.append((command + encoded + b"\0").ljust(length, b"\0"))
    packed = b"".join(commands)
    old_end, new_end = HEADER_SIZE + old_size, HEADER_SIZE + len(packed)
    if payload < old_end or payload > len(data) or new_end > payload:
        raise ValueError("insufficient Mach-O header padding; file left unchanged")
    if new_end > old_end and any(data[old_end:new_end]):
        raise ValueError("nonzero bytes in header padding; file left unchanged")
    data[HEADER_SIZE:HEADER_SIZE + max(old_size, len(packed))] = packed.ljust(
        max(old_size, len(packed)), b"\0"
    )
    struct.pack_into("<2I", data, 16, len(commands), len(packed))
    path.write_bytes(data)
    print("added dylib load command" if action == "add" else "removed dylib load command")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    options = parser.add_mutually_exclusive_group()
    options.add_argument("--check", action="store_true")
    options.add_argument("--remove", action="store_true")
    parser.add_argument("binary", type=Path)
    parser.add_argument("dylib")
    args = parser.parse_args()
    try:
        action = "check" if args.check else "remove" if args.remove else "add"
        return update(args.binary, args.dylib, action)
    except (OSError, ValueError, struct.error) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
