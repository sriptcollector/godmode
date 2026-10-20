"""Thin wrappers around `xcrun devicectl` / libimobiledevice for a USB-attached iPhone."""
import json
import os
import shutil
import subprocess
import tempfile


class DeviceError(RuntimeError):
    pass


def run(cmd, check=True, capture=True):
    p = subprocess.run(cmd, capture_output=capture, text=True)
    if check and p.returncode != 0:
        raise DeviceError(f"{' '.join(cmd)}\n{(p.stderr or p.stdout or '').strip()}")
    return p


def devicectl(*args):
    """Run a devicectl command and return its parsed JSON `result`."""
    with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
        out = f.name
    try:
        run(["xcrun", "devicectl", *args, "--quiet", "--json-output", out])
        with open(out) as fh:
            return json.load(fh).get("result", {})
    finally:
        os.unlink(out)


def devices():
    return devicectl("list", "devices").get("devices", [])


def pick(name_or_id=None):
    """Return the target device: explicit id/name, else the first paired, connected iPhone."""
    devs = devices()
    if name_or_id:
        for d in devs:
            props = d.get("deviceProperties", {})
            hw = d.get("hardwareProperties", {})
            if name_or_id in (d.get("identifier"), props.get("name"), hw.get("udid")):
                return d
        raise DeviceError(f"no device matching {name_or_id!r}")
    for d in devs:
        hw = d.get("hardwareProperties", {})
        conn = d.get("connectionProperties", {})
        if hw.get("platform") == "iOS" and conn.get("pairingState") == "paired" \
                and conn.get("tunnelState") != "unavailable":
            return d
    raise DeviceError("no paired iPhone found — plug it in, unlock it, and tap Trust")


def details(dev_id):
    return devicectl("device", "info", "details", "--device", dev_id)


def apps(dev_id, include_system=False):
    args = ["device", "info", "apps", "--device", dev_id]
    if include_system:
        args += ["--include-all-apps"]
    return devicectl(*args).get("apps", [])


def install(dev_id, app_path):
    return devicectl("device", "install", "app", "--device", dev_id, app_path)


def uninstall(dev_id, bundle_id):
    return devicectl("device", "uninstall", "app", "--device", dev_id, bundle_id)


def launch(dev_id, bundle_id):
    return devicectl("device", "process", "launch", "--terminate-existing",
                     "--device", dev_id, bundle_id)


def push_to_container(dev_id, bundle_id, src, dest_rel):
    """Copy a local file into a dev-signed app's data container (e.g. Documents/godmode.json)."""
    return devicectl("device", "copy", "to", "--device", dev_id,
                     "--domain-type", "appDataContainer", "--domain-identifier", bundle_id,
                     "--source", src, "--destination", dest_rel)


def reveal_developer_mode(udid):
    """Make the Developer Mode toggle appear in Settings > Privacy & Security."""
    if not shutil.which("idevicedevmodectl"):
        raise DeviceError("idevicedevmodectl missing — brew install libimobiledevice")
    return run(["idevicedevmodectl", "-u", udid, "reveal"], check=False)
