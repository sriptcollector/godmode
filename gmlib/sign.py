"""Mint a dev provisioning profile for any bundle id and re-sign an .app with it.

Minting trick: build a throwaway Xcode project with that bundle id and automatic signing.
Xcode registers the App ID + creates a profile that includes every registered device,
and the built .app carries it as embedded.mobileprovision — we lift it from there.
"""
import os
import plistlib
import shutil
import tempfile

from . import config
from .device import run, DeviceError

CACHE = os.path.expanduser("~/.godmode/profiles")

STUB_YML = """name: Stub
options: {{bundleIdPrefix: gm}}
targets:
  Stub:
    type: application
    platform: iOS
    deploymentTarget: "16.0"
    sources: [Stub]
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: {bundle}
      DEVELOPMENT_TEAM: {team}
      CODE_SIGN_STYLE: Automatic
      GENERATE_INFOPLIST_FILE: YES
"""


def read_profile(path):
    out = run(["security", "cms", "-D", "-i", path]).stdout
    return plistlib.loads(out.encode())


def mint_profile(bundle_id, team, udid):
    """Return a path to a development .mobileprovision for bundle_id (cached)."""
    os.makedirs(CACHE, exist_ok=True)
    cached = os.path.join(CACHE, f"{bundle_id}.mobileprovision")
    if os.path.exists(cached):
        import datetime
        prof = read_profile(cached)
        if udid in prof.get("ProvisionedDevices", []) and \
                prof["ExpirationDate"] > datetime.datetime.now() + datetime.timedelta(days=2):
            return cached
    work = tempfile.mkdtemp(prefix="gm-stub-")
    try:
        os.makedirs(os.path.join(work, "Stub"))
        with open(os.path.join(work, "Stub", "App.swift"), "w") as f:
            f.write("import SwiftUI\n@main struct S: App { var body: some Scene { WindowGroup { Text(\"stub\") } } }\n")
        with open(os.path.join(work, "project.yml"), "w") as f:
            f.write(STUB_YML.format(bundle=bundle_id, team=team))
        run(["xcodegen", "generate", "--spec", os.path.join(work, "project.yml"), "--project", work])
        run(["xcodebuild", "-project", os.path.join(work, "Stub.xcodeproj"), "-scheme", "Stub",
             "-destination", f"id={udid}", "-derivedDataPath", os.path.join(work, "dd"),
             *config.xcode_auth_args(), "build", "-quiet"])
        built = os.path.join(work, "dd", "Build", "Products", "Debug-iphoneos", "Stub.app",
                             "embedded.mobileprovision")
        if not os.path.exists(built):
            raise DeviceError("xcodebuild finished but produced no embedded.mobileprovision")
        shutil.copy(built, cached)
        return cached
    finally:
        shutil.rmtree(work, ignore_errors=True)


def identity_for(profile):
    """Pick the keychain signing identity whose cert is inside the profile."""
    import hashlib
    hashes = {hashlib.sha1(c).hexdigest().upper() for c in profile["DeveloperCertificates"]}
    out = run(["security", "find-identity", "-v", "-p", "codesigning"]).stdout
    for line in out.splitlines():
        parts = line.split()
        if len(parts) > 1 and parts[1] in hashes:
            return parts[1]
    raise DeviceError("no keychain identity matches the profile's certificates")


def resign(app_dir, profile_path):
    """Re-sign an unpacked .app (inside-out) with profile_path. Returns the identity used."""
    profile = read_profile(profile_path)
    ident = identity_for(profile)
    ents = dict(profile["Entitlements"])
    ents["get-task-allow"] = True  # lets devicectl push config into the app container

    shutil.copy(profile_path, os.path.join(app_dir, "embedded.mobileprovision"))
    # Anything whose bundle id the profile can't cover would fail install — drop it.
    for junk in ("PlugIns", "Extensions", "Watch", "com.apple.WatchPlaceholder", "SC_Info"):
        shutil.rmtree(os.path.join(app_dir, junk), ignore_errors=True)

    nested = []
    for root, dirs, files in os.walk(app_dir):
        for d in dirs:
            if d.endswith((".framework", ".appex")):
                nested.append(os.path.join(root, d))
        for f in files:
            if f.endswith(".dylib"):
                nested.append(os.path.join(root, f))
    # deepest first so outer seals cover already-signed inner code
    for path in sorted(nested, key=lambda p: p.count(os.sep), reverse=True):
        run(["codesign", "-f", "-s", ident, "--generate-entitlement-der", path])

    with tempfile.NamedTemporaryFile(suffix=".plist", delete=False) as f:
        plistlib.dump(ents, f)
        ent_path = f.name
    try:
        run(["codesign", "-f", "-s", ident, "--entitlements", ent_path,
             "--generate-entitlement-der", app_dir])
    finally:
        os.unlink(ent_path)
    run(["codesign", "--verify", "--deep", "--strict", app_dir])
    return ident


def unpack_ipa(ipa, dest):
    run(["ditto", "-x", "-k", ipa, dest])
    payload = os.path.join(dest, "Payload")
    apps = [a for a in os.listdir(payload) if a.endswith(".app")]
    if not apps:
        raise DeviceError(f"{ipa}: no .app inside Payload/")
    return os.path.join(payload, apps[0])


def set_info(app_dir, **keys):
    p = os.path.join(app_dir, "Info.plist")
    with open(p, "rb") as f:
        info = plistlib.load(f)
    info.update(keys)
    with open(p, "wb") as f:
        plistlib.dump(info, f)
    return info

