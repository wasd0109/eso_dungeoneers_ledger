"""Runs the Dungeoneer's Ledger suite on lupa's real Lua 5.1 (run as: python -I run_tests.py [name-filter])."""
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

import lupa.lua51 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON_NAME = "DungeoneersLedger"


def find_addon_root():
    env = os.environ.get("ESO_ADDON_ROOT")
    if env:
        return os.path.abspath(env)
    cur = HERE
    for _ in range(8):
        if os.path.isfile(os.path.join(cur, ADDON_NAME + ".addon")):
            return cur
        sub = os.path.join(cur, ADDON_NAME)
        if os.path.isfile(os.path.join(sub, ADDON_NAME + ".addon")):
            return sub
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        cur = parent
    return None


def find_package_script(addon_root):
    env = os.environ.get("ESO_PACKAGE_SCRIPT")
    if env:
        return env if os.path.isfile(env) else None
    starts = [HERE]
    if addon_root:
        starts.append(addon_root)
    for start in starts:
        cur = start
        for _ in range(8):
            cand = os.path.join(cur, "tools", "package.ps1")
            if os.path.isfile(cand):
                return cand
            parent = os.path.dirname(cur)
            if parent == cur:
                break
            cur = parent
    return None


def default_libsets():
    return os.environ.get("ESO_LIBSETS_PATH") or os.path.join(
        os.path.expanduser("~"), "Documents", "Elder Scrolls Online", "live", "AddOns", "LibSets")


def default_esoui():
    env = os.environ.get("ESO_UI_SRC")
    if env:
        return env
    # convenience fallback: the extracted game source used while the suite was written (skipped when absent)
    cand = os.path.join(tempfile.gettempdir(), "claude", "C--Users-kenx4-Documents-src-eso-quest",
                        "aac288bb-0c01-47cb-987d-ce0b87503628", "scratchpad", "esoui_src", "esoui")
    return cand if os.path.isdir(cand) else None


def stage_and_package(lua, addon_root, script):
    """Copies the addon (plus decoy tests/.git/.bak files) into a temp layout identical to the repo layout the
    script expects, runs a copy of package.ps1 there and returns the zip's entry names."""
    tmp = tempfile.mkdtemp(prefix="dl_pkg_")
    try:
        dst = os.path.join(tmp, ADDON_NAME)
        ignore = shutil.ignore_patterns(".venv", "__pycache__", ".git", "tests", "dist", "tools")
        shutil.copytree(addon_root, dst, ignore=ignore)
        os.makedirs(os.path.join(tmp, "tools"))
        shutil.copy(script, os.path.join(tmp, "tools", "package.ps1"))
        os.makedirs(os.path.join(dst, "tests", "stubs"))
        os.makedirs(os.path.join(dst, ".git"))
        for rel in ("tests/test.lua", "tests/stubs/x.lua", ".git/config", "src/Core.lua.bak", "Overrides.lua.bak",
                    "lang/en.lua.bak2", "notes.txt", "src/Scratch.txt"):
            with open(os.path.join(dst, rel), "w") as f:
                f.write("decoy")
        proc = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                               os.path.join(tmp, "tools", "package.ps1")], capture_output=True, text=True)
        out = {"exit": proc.returncode, "output": (proc.stdout or "") + (proc.stderr or "")}
        zips = [n for n in os.listdir(os.path.join(tmp, "dist"))] if os.path.isdir(os.path.join(tmp, "dist")) else []
        out["zips"] = lua.table_from(zips)
        if zips:
            with zipfile.ZipFile(os.path.join(tmp, "dist", zips[0])) as z:
                out["entries"] = lua.table_from(z.namelist())
            out["zipname"] = zips[0]
        return lua.table_from(out)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    version = lua.eval("_VERSION")
    addon_root = find_addon_root()
    script = find_package_script(addon_root)

    def read(path):
        try:
            with open(path, "rb") as f:
                return f.read().decode("utf-8", errors="replace")
        except OSError:
            return None

    def exists(path):
        return os.path.exists(path)

    def listdir(path):
        try:
            return lua.table_from(sorted(os.listdir(path)))
        except OSError:
            return None

    def isdir(path):
        return os.path.isdir(path)

    def walk_files(path, exts):
        exts = tuple(exts.values()) if exts else ()
        found = []
        for base, _dirs, files in os.walk(path):
            for name in files:
                if not exts or name.lower().endswith(exts):
                    found.append(os.path.join(base, name))
        return lua.table_from(found)

    def real_stage(*_):
        return stage_and_package(lua, addon_root, script)

    host = lua.table(read=read, exists=exists, listdir=listdir, isdir=isdir, walk_files=walk_files,
                     stage_and_package=real_stage)
    cfg = lua.table(
        here=HERE, addonRoot=addon_root, packageScript=script, libsetsPath=default_libsets(),
        esoSrc=default_esoui(), luaVersion=version, filter=sys.argv[1] if len(sys.argv) > 1 else None)
    g = lua.globals()
    g.host = host
    g.CFG = cfg
    g.RUNNER_VERSION = version
    if not addon_root:
        print("ERROR: addon root not found (set ESO_ADDON_ROOT)")
        return 1

    def load(rel):
        src = read(os.path.join(HERE, rel))
        loader = lua.eval("function(s, n) local f, e = loadstring(s, n) if not f then error(e, 0) end return f end")
        try:
            return loader(src, "@" + rel)
        except lupa.LuaError as exc:
            print("syntax error in %s: %s" % (rel, exc))
            sys.exit(1)

    load("framework.lua")()
    load(os.path.join("stubs", "eso_world.lua"))()
    load(os.path.join("stubs", "libsets_real.lua"))()
    load("data_helpers.lua")()
    for name in sorted(os.listdir(os.path.join(HERE, "suites"))):
        if name.endswith(".lua"):
            load(os.path.join("suites", name))()
    return lua.eval("function() return T.run(CFG.filter) end")()


if __name__ == "__main__":
    sys.exit(main())
