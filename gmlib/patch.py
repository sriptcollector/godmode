"""IPA -> inject tweaks (cyan) -> new bundle id -> re-sign -> install on the phone."""
import json
import os
import plistlib
import shutil
import tempfile
import urllib.request

from . import config, device, sign
from .device import run, DeviceError

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.expanduser("~/.godmode/cache")


def load_mod(name):
    path = os.path.join(ROOT, "mods", f"{name}.json")
    if not os.path.exists(path):
        have = sorted(f[:-5] for f in os.listdir(os.path.join(ROOT, "mods")) if f.endswith(".json"))
        raise DeviceError(f"no mod recipe {name!r} (have: {', '.join(have)})")
    with open(path) as f:
        return json.load(f)


def fetch(url):
    os.makedirs(CACHE, exist_ok=True)
    dest = os.path.join(CACHE, url.rsplit("/", 1)[-1])
    if not os.path.exists(dest):
        print(f"  ↓ {url}")
        urllib.request.urlretrieve(url, dest + ".part")
        os.rename(dest + ".part", dest)
    return dest


def speedhack_dylib():
    dylib = os.path.join(ROOT, "tweaks", "speedhack", "SpeedHack.dylib")
    src = os.path.join(ROOT, "tweaks", "speedhack", "SpeedHack.m")
    if not os.path.exists(dylib) or os.path.getmtime(src) > os.path.getmtime(dylib):
        run([os.path.join(ROOT, "tweaks", "speedhack", "build.sh")])
    return dylib


def assert_decrypted(app_dir):
    """App Store binaries are FairPlay-encrypted; injected code can't run in them."""
    with open(os.path.join(app_dir, "Info.plist"), "rb") as f:
        info = plistlib.load(f)
    binary = os.path.join(app_dir, info["CFBundleExecutable"])
    out = run(["otool", "-l", binary]).stdout
    if "cryptid 1" in out:
        raise DeviceError("this IPA is still FairPlay-encrypted (cryptid 1). "
                          "You need a *decrypted* IPA — see README › Getting a decrypted IPA.")


def patch(mod_name, ipa, dev_id=None, speed=None, install=True, out_dir=None):
    if not shutil.which("cyan"):
        raise DeviceError("cyan missing — pipx install https://github.com/asdfzxcvbn/pyzule-rw/archive/main.zip")
    mod = load_mod(mod_name)
    work = tempfile.mkdtemp(prefix=f"gm-{mod_name}-")
    try:
        files = [fetch(t["url"]) for t in mod.get("tweaks", [])]
        if mod.get("speedhack", True):
            files.append(speedhack_dylib())

        injected = os.path.join(work, "injected.ipa")
        print(f"• injecting {', '.join(os.path.basename(f) for f in files)}")
        run(["cyan", "-i", ipa, "-o", injected, "-f", *files,
             "-b", mod["bundle_id"], "-n", mod["display_name"],
             "-u", "-w", "-e", "--overwrite"])

        app_dir = sign.unpack_ipa(injected, os.path.join(work, "x"))
        assert_decrypted(app_dir)
        if speed:
            sign.set_info(app_dir, GMSpeed=float(speed))

        dev = device.pick(dev_id)
        udid = dev["hardwareProperties"]["udid"]
        print(f"• minting dev profile for {mod['bundle_id']} (team {config.team()})")
        profile = sign.mint_profile(mod["bundle_id"], config.team(), udid)
        ident = sign.resign(app_dir, profile)
        print(f"• signed with {ident[:10]}…")

        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
            final = os.path.join(out_dir, os.path.basename(app_dir))
            shutil.rmtree(final, ignore_errors=True)
            shutil.copytree(app_dir, final, symlinks=True)
            print(f"• kept {final}")
        if install:
            print("• installing on phone…")
            device.install(dev["identifier"], app_dir)
            print(f"✓ {mod['display_name']} installed ({mod['bundle_id']})")
            if mod.get("settings_hint"):
                print(f"  next: {mod['settings_hint']}")
        return mod
    finally:
        shutil.rmtree(work, ignore_errors=True)


def push_speed(bundle_id, speed, dev_id=None):
    dev_id = dev_id or device.pick()["identifier"]
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump({"speed": float(speed)}, f)
        src = f.name
    try:
        device.push_to_container(dev_id, bundle_id, src, "Documents/godmode.json")
    finally:
        os.unlink(src)
