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

def scrub_recent_ninja_log(out_dir: str) -> int:
    ninja_log = os.path.join(out_dir, ".ninja_log")
    if not os.path.isfile(ninja_log):
        return 0
    ws_dir = os.path.dirname(os.path.abspath(out_dir))
    removed = 0
    try:
        with open(ninja_log, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(max(0, size - 262144), os.SEEK_SET)
            lines = f.read().decode("utf-8", errors="replace").splitlines()[-500:]
    except OSError:
        return 0
    seen = set()
    for line in lines:
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
        if not os.path.isfile(fp) or os.path.islink(fp):
            continue
        try:
            st = os.stat(fp)
            if st.st_size == 0 and not fp.endswith((".toc", ".d", ".rsp", ".txt", ".stamp", ".lock")):
                print(f"Removing 0-byte recent output: {fp}", flush=True)
                os.remove(fp)
                removed += 1
                continue
            if fp.endswith((".jar", ".srcjar", ".apk", ".zip")):
                if not zipfile.is_zipfile(fp):
                    print(f"Removing corrupt recent zip/jar: {fp}", flush=True)
                    os.remove(fp)
                    removed += 1
                    continue
            if st.st_size >= 8:
                with open(fp, "rb") as rf:
                    hdr = rf.read(8)
                if hdr == b"\x00" * 8 and not fp.endswith((".raw", ".img", ".bin", ".dat", ".prof", ".art", ".vdex", ".odex", ".pc_state")):
                    print(f"Removing NUL-header recent output: {fp}", flush=True)
                    os.remove(fp)
                    removed += 1
        except OSError:
            pass
    return removed

def main() -> int:
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "/mnt/extended/grapheneos/out_adevtool_deps"
    if not os.path.isdir(out_dir):
        return 0
    latest_mtime = time.time()
    for state_fn in (".siso_fs_state.journal", ".siso_deps", ".ninja_log"):
        sp = os.path.join(out_dir, state_fn)
        if os.path.exists(sp):
            try:
                latest_mtime = max(latest_mtime, os.stat(sp).st_mtime)
            except OSError:
                pass
    cutoff_mtime = latest_mtime - 7200.0
    removed = scrub_recent_ninja_log(out_dir)
    checked = 0
    for dirpath, _, filenames in os.walk(out_dir):
        for fn in filenames:
            if not (fn.endswith((".o", ".so", ".a", ".jar", ".srcjar", ".apk", ".dex")) or ".so." in fn or "/bin/" in dirpath):
                continue
            fp = os.path.join(dirpath, fn)
            if os.path.islink(fp):
                continue
            try:
                st = os.stat(fp)
            except OSError:
                continue
            if st.st_size > 0 and st.st_mtime < cutoff_mtime:
                continue
            checked += 1
            if fn.endswith(".o"):
                try:
                    with open(fp, "rb") as f:
                        hdr = f.read(4)
                    if len(hdr) < 4 or hdr not in VALID_OBJ_MAGICS:
                        print(f"Removing corrupt .o: {fp}", flush=True)
                        os.remove(fp)
                        removed += 1
                except OSError:
                    pass
            elif fn.endswith(".so") or ".so." in fn:
                if fn.endswith((".toc", ".d", ".rsp", ".txt", ".json", ".map", ".sym")):
                    continue
                try:
                    with open(fp, "rb") as f:
                        hdr = f.read(4)
                    if len(hdr) < 4 or hdr != b"\x7fELF":
                        print(f"Removing corrupt .so: {fp}", flush=True)
                        os.remove(fp)
                        removed += 1
                        toc_fp = fp + ".toc"
                        if os.path.exists(toc_fp):
                            os.remove(toc_fp)
                except OSError:
                    pass
            elif fn.endswith(".a"):
                if not is_valid_ar(fp, st.st_size):
                    print(f"Removing corrupt .a archive: {fp}", flush=True)
                    try:
                        os.remove(fp)
                        removed += 1
                    except OSError:
                        pass
            elif fn.endswith((".jar", ".srcjar", ".apk")):
                try:
                    with open(fp, "rb") as f:
                        hdr = f.read(4)
                    if len(hdr) < 4 or hdr not in VALID_ZIP_MAGICS:
                        print(f"Removing corrupt jar/apk: {fp}", flush=True)
                        os.remove(fp)
                        removed += 1
                except OSError:
                    pass
            elif fn.endswith(".dex"):
                try:
                    with open(fp, "rb") as f:
                        hdr = f.read(4)
                    if len(hdr) < 4 or hdr != b"dex\n":
                        print(f"Removing corrupt .dex: {fp}", flush=True)
                        os.remove(fp)
                        removed += 1
                except OSError:
                    pass
            elif "/bin/" in fp.replace("\\", "/") and st.st_size > 0:
                try:
                    with open(fp, "rb") as f:
                        hdr = f.read(4)
                    if hdr == b"\x00\x00\x00\x00":
                        print(f"Removing zero-filled binary: {fp}", flush=True)
                        os.remove(fp)
                        removed += 1
                except OSError:
                    pass
    print(f"Scrub complete: checked {checked} recent/0-byte file(s), removed {removed} crash-corrupted artifact(s) under {out_dir}", flush=True)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
