"""Local, uncommitted settings in ~/.godmode/config.json (team id + App Store Connect API key)."""
import json
import os

PATH = os.path.expanduser("~/.godmode/config.json")


def load():
    try:
        with open(PATH) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def team():
    return os.environ.get("GM_TEAM") or load().get("team") or "482FP5Y9AN"


def xcode_auth_args():
    """xcodebuild flags so signing works even when Xcode has no Apple ID logged in."""
    c = load()
    if not c.get("asc_key_id"):
        return ["-allowProvisioningUpdates"]
    return ["-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration",
            "-authenticationKeyPath", os.path.expanduser(c["asc_key_path"]),
            "-authenticationKeyID", c["asc_key_id"],
            "-authenticationKeyIssuerID", c["asc_issuer_id"]]
