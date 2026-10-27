"""Local, uncommitted settings in ~/.godmode/config.json (team id, bundle prefix, App Store Connect API key)."""
import json
import os

PATH = os.path.expanduser("~/.godmode/config.json")


def load():
    try:
        with open(PATH) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


OWNER_TEAM = "482FP5Y9AN"
OWNER_PREFIX = "com.orionjones.godmode"


def team():
    t = os.environ.get("GM_TEAM") or load().get("team")
    if not t:
        from .device import DeviceError
        raise DeviceError("no Apple team id — run install.sh, or put {\"team\": \"XXXXXXXXXX\"} in ~/.godmode/config.json")
    return t


def bundle_prefix():
    """Bundle ids are unique across all Apple teams, so everyone else gets their own prefix."""
    c = load()
    if c.get("bundle_prefix"):
        return c["bundle_prefix"]
    return OWNER_PREFIX if team() == OWNER_TEAM else f"com.godmode.t{team().lower()}"


def bundle_id(recipe_id):
    """Map a recipe's com.orionjones.godmode[.app] id onto this user's prefix."""
    if recipe_id == OWNER_PREFIX or recipe_id.startswith(OWNER_PREFIX + "."):
        return bundle_prefix() + recipe_id[len(OWNER_PREFIX):]
    return recipe_id


def xcode_auth_args():
    """xcodebuild flags so signing works even when Xcode has no Apple ID logged in."""
    c = load()
    if not c.get("asc_key_id"):
        return ["-allowProvisioningUpdates"]
    return ["-allowProvisioningUpdates", "-allowProvisioningDeviceRegistration",
            "-authenticationKeyPath", os.path.expanduser(c["asc_key_path"]),
            "-authenticationKeyID", c["asc_key_id"],
            "-authenticationKeyIssuerID", c["asc_issuer_id"]]
