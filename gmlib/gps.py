"""GPS spoofing for a plugged-in iPhone via pymobiledevice3 (iOS 17+ needs the userspace tunnel)."""
import shutil
import subprocess

from .device import DeviceError

PLACES = {
    "sf": (37.7749, -122.4194), "la": (34.0522, -118.2437), "nyc": (40.7128, -74.0060),
    "london": (51.5074, -0.1278), "tokyo": (35.6762, 139.6503), "paris": (48.8566, 2.3522),
    "vegas": (36.1699, -115.1398), "miami": (25.7617, -80.1918),
}


def _run(args):
    if not shutil.which("pymobiledevice3"):
        raise DeviceError("pymobiledevice3 missing — pipx install pymobiledevice3")
    p = subprocess.run(["pymobiledevice3", "developer", "dvt", "simulate-location", *args],
                       capture_output=True, text=True)
    if p.returncode != 0:
        raise DeviceError((p.stderr or p.stdout).strip())


def set_location(where):
    if where in PLACES:
        lat, lon = PLACES[where]
    else:
        try:
            lat, lon = (float(x) for x in where.replace(" ", "").split(","))
        except ValueError:
            raise DeviceError(f"give a place ({', '.join(PLACES)}) or lat,lon — got {where!r}")
    _run(["set", "--", str(lat), str(lon)])
    return lat, lon


def clear():
    _run(["clear"])
