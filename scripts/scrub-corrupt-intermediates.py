#!/usr/bin/env python3
import os
import sys

VALID_OBJ_MAGICS = (b"\x7fELF", b"BC\xc0\xde", b"\xde\xc0\x17\x0b")

def is_valid_ar(path: str) -> bool:
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return False
    if len(data) < 8 or data[:8] != b"!<arch>\n":
        return False
    pos = 8
    n = len(data)
    while pos < n:
        if pos + 60 > n:
            return False
        hdr = data[pos:pos+60]
        if hdr[58:60] != b"`\n":
            return False
        name = hdr[0:16].strip()
        try:
            size = int(hdr[48:58].strip())
        except ValueError:
            return False
        payload_start = pos + 60
        payload_end = payload_start + size
        if payload_end > n:
            return False
        obj_start = payload_start
        if name.startswith(b"#1/"):
            try:
                ext_len = int(name[3:])
                obj_start += ext_len
            except ValueError:
                return False
        if name not in (b"/", b"//", b"/SYM64/", b"__.SYMDEF", b"__.SYMDEF SORTED"):
            if obj_start + 4 > payload_end:
                return False
            magic = data[obj_start:obj_start+4]
            if magic not in VALID_OBJ_MAGICS:
                return False
        pos = payload_end
        if pos % 2 == 1:
            pos += 1
    return True

def main() -> int:
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "/mnt/extended/grapheneos/out_adevtool_deps"
    if not os.path.isdir(out_dir):
        return 0
    removed = 0
    for dirpath, _, filenames in os.walk(out_dir):
        for fn in filenames:
            fp = os.path.join(dirpath, fn)
            if os.path.islink(fp):
                continue
            try:
                st = os.stat(fp)
            except OSError:
                continue
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
                if fn.endswith(".toc") or fn.endswith(".d") or fn.endswith(".rsp") or fn.endswith(".txt") or fn.endswith(".json"):
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
                if not is_valid_ar(fp):
                    print(f"Removing corrupt .a archive: {fp}", flush=True)
                    try:
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
    print(f"Scrub complete: removed {removed} crash-corrupted artifact(s) under {out_dir}", flush=True)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
