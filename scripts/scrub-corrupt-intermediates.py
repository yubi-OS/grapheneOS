#!/usr/bin/env python3
import os
import sys
import time
import zipfile

VALID_OBJ_MAGICS = (b"\x7fELF", b"BC\xc0\xde", b"\xde\xc0\x17\x0b", b"go o")
VALID_ZIP_MAGICS = (b"PK\x03\x04", b"PK\x05\x06", b"PK\x07\x08")

def is_valid_ar(path: str, file_size: int) -> bool:
    if file_size < 8:
        return False
    try:
        with open(path, "rb") as f:
            if f.read(8) != b"!<arch>\n":
                return False
            pos = 8
            while pos < file_size:
                if pos + 60 > file_size:
                    return False
                f.seek(pos)
                hdr = f.read(60)
                if len(hdr) < 60 or hdr[58:60] != b"`\n":
                    return False
                name = hdr[0:16].strip()
                try:
                    size = int(hdr[48:58].strip())
                except ValueError:
                    return False
                payload_start = pos + 60
                payload_end = payload_start + size
                if payload_end > file_size:
                    return False
                obj_start = payload_start
                if name.startswith(b"#1/"):
                    try:
                        ext_len = int(name[3:])
                        obj_start += ext_len
                    except ValueError:
                        return False
                if name not in (b"/", b"//", b"/SYM64/", b"__.SYMDEF", b"__.SYMDEF SORTED", b"__.PKGDEF"):
                    if obj_start + 4 > payload_end:
                        return False
                    f.seek(obj_start)
                    magic = f.read(4)
                    if magic not in VALID_OBJ_MAGICS:
                        return False
                pos = payload_end
                if pos % 2 == 1:
                    pos += 1
    except OSError:
        return False
    return True

def check_one_file(fp: str) -> int:
    if not os.path.isfile(fp) or os.path.islink(fp):
        return 0
    fn = os.path.basename(fp)
    try:
        st = os.stat(fp)
    except OSError:
        return 0
    if st.st_size == 0 and not fn.endswith((".toc", ".d", ".rsp", ".txt", ".stamp", ".lock", ".list")):
        print(f"Removing 0-byte recent output: {fp}", flush=True)
        try:
            os.remove(fp)
            return 1
        except OSError:
            return 0
    if fn.endswith(".o"):
        try:
            with open(fp, "rb") as f:
                hdr = f.read(4)
            if len(hdr) < 4 or hdr not in VALID_OBJ_MAGICS:
                print(f"Removing corrupt .o: {fp}", flush=True)
                os.remove(fp)
                return 1
        except OSError:
            pass
    elif fn.endswith(".so") or ".so." in fn:
        if not fn.endswith((".toc", ".d", ".rsp", ".txt", ".json", ".map", ".sym")):
            try:
                with open(fp, "rb") as f:
                    hdr = f.read(4)
                if len(hdr) < 4 or hdr != b"\x7fELF":
                    print(f"Removing corrupt .so: {fp}", flush=True)
                    os.remove(fp)
                    toc_fp = fp + ".toc"
                    if os.path.exists(toc_fp):
                        os.remove(toc_fp)
                    return 1
            except OSError:
                pass
    elif fn.endswith(".a"):
        if not is_valid_ar(fp, st.st_size):
            print(f"Removing corrupt .a archive: {fp}", flush=True)
            try:
                os.remove(fp)
                return 1
            except OSError:
                pass
    elif fn.endswith((".jar", ".srcjar", ".apk", ".zip")):
        try:
            with open(fp, "rb") as f:
                hdr = f.read(4)
            if len(hdr) < 4 or hdr not in VALID_ZIP_MAGICS or not zipfile.is_zipfile(fp):
                print(f"Removing corrupt zip/jar: {fp}", flush=True)
                os.remove(fp)
                return 1
        except OSError:
            pass
    elif fn.endswith(".dex"):
        try:
            with open(fp, "rb") as f:
                hdr = f.read(4)
            if len(hdr) < 4 or hdr != b"dex\n":
                print(f"Removing corrupt .dex: {fp}", flush=True)
                os.remove(fp)
                return 1
        except OSError:
            pass
    elif st.st_size >= 8 and not fn.endswith((".raw", ".img", ".bin", ".dat", ".prof", ".art", ".vdex", ".odex", ".pc_state")):
        try:
            with open(fp, "rb") as rf:
                hdr = rf.read(8)
            if hdr == b"\x00" * 8:
                print(f"Removing NUL-header recent output: {fp}", flush=True)
                os.remove(fp)
                return 1
        except OSError:
            pass
    return 0

def main() -> int:
    # Paced, zero-os.walk scrubber: inspects ONLY the tail of .ninja_log and flat host/linux-x86/bin
    # so we never issue a full-tree os.walk metadata storm against mmcblk0 on cold cache after reboot.
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "/mnt/extended/grapheneos/out_adevtool_deps"
    if not os.path.isdir(out_dir):
        return 0
    ws_dir = os.path.dirname(os.path.abspath(out_dir))
    removed = 0
    checked = 0
    ninja_log = os.path.join(out_dir, ".ninja_log")
    if os.path.isfile(ninja_log):
        try:
            with open(ninja_log, "rb") as f:
                f.seek(0, os.SEEK_END)
                size = f.tell()
                f.seek(max(0, size - 262144), os.SEEK_SET)
                lines = f.read().decode("utf-8", errors="replace").splitlines()[-300:]
        except OSError:
            lines = []
        seen = set()
        for line in reversed(lines):
            if line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 4:
                continue
            rel = parts[3].strip()
            if not rel or rel in seen:
                continue
            seen.add(rel)
            fp = os.path.join(ws_dir, rel) if not os.path.isabs(rel) else rel
            if not os.path.exists(fp) and not rel.startswith(os.path.basename(out_dir) + "/"):
                fp = os.path.join(out_dir, rel)
            checked += 1
            removed += check_one_file(fp)
            time.sleep(0.01)
    host_bin = os.path.join(out_dir, "host", "linux-x86", "bin")
    if os.path.isdir(host_bin):
        try:
            for fn in os.listdir(host_bin):
                fp = os.path.join(host_bin, fn)
                checked += 1
                removed += check_one_file(fp)
                time.sleep(0.005)
        except OSError:
            pass
    print(f"Paced scrub complete (no os.walk): checked {checked} recent target(s), removed {removed} corrupt artifact(s) under {out_dir}", flush=True)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
