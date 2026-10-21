"""GPS spoofing for a plugged-in iPhone via pymobiledevice3.

iOS 17+ needs a RemoteXPC tunnel for developer commands. We use the no-root
`remote start-tunnel --native` tunnel (piggybacks Apple's own tunnel on macOS, up in ~2s),
then hold the location with a `simulate-location set` process that blocks until killed.
`gm gps off` kills both, and the phone reverts to its real GPS.
"""
import os
import re
import signal
import shutil
import subprocess
import time

from .device import DeviceError

PLACES = {
    "sf": (37.7749, -122.4194), "la": (34.0522, -118.2437), "nyc": (40.7128, -74.0060),
    "london": (51.5074, -0.1278), "tokyo": (35.6762, 139.6503), "paris": (48.8566, 2.3522),
    "vegas": (36.1699, -115.1398), "miami": (25.7617, -80.1918), "pyongyang": (39.0392, 125.7625),
}

STATE = os.path.expanduser("~/.godmode")
PIDFILE = os.path.join(STATE, "gps.pids")
TUNLOG = os.path.join(STATE, "gps_tunnel.log")


def _pmd3():
    if not shutil.which("pymobiledevice3"):
        raise DeviceError("pymobiledevice3 missing — pipx install pymobiledevice3")
    return "pymobiledevice3"


def _start_tunnel():
    """Bring up a no-root native RemoteXPC tunnel; return (rsd_addr, rsd_port, pid)."""
    os.makedirs(STATE, exist_ok=True)
    log = open(TUNLOG, "w")
    proc = subprocess.Popen([_pmd3(), "remote", "start-tunnel", "--native"],
                            stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    rsd = port = None
    for _ in range(40):  # ~20s; native tunnel is usually up in ~2s
        if proc.poll() is not None:
            raise DeviceError("tunnel exited early — is the phone plugged in, unlocked and trusted?\n"
                              + _tail(TUNLOG))
        txt = _read(TUNLOG)
        m_addr = re.search(r"RSD Address:\s*([0-9a-fA-F:]+)", txt)
        m_port = re.search(r"RSD Port:\s*(\d+)", txt)
        if m_addr and m_port:
            rsd, port = m_addr.group(1), m_port.group(1)
            break
        time.sleep(0.5)
    if not rsd:
        _kill(proc.pid)
        raise DeviceError("tunnel never reported an RSD address:\n" + _tail(TUNLOG))
    return rsd, port, proc.pid


def set_location(where):
    if where in PLACES:
        lat, lon = PLACES[where]
    else:
        try:
            lat, lon = (float(x) for x in where.replace(" ", "").split(","))
        except ValueError:
            raise DeviceError(f"give a place ({', '.join(PLACES)}) or lat,lon — got {where!r}")

    clear()  # drop any location we're already holding
    rsd, port, tun_pid = _start_tunnel()
    # `set` blocks to hold the location; let it run detached and keep feeding until `gm gps off`.
    sim = subprocess.Popen([_pmd3(), "developer", "dvt", "simulate-location", "set",
                            "--rsd", rsd, port, "--", str(lat), str(lon)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    time.sleep(2)
    if sim.poll() is not None:
        _kill(tun_pid)
        raise DeviceError("couldn't set the location (the hold process exited immediately)")
    with open(PIDFILE, "w") as f:
        f.write(f"{sim.pid}\n{tun_pid}\n")
    return lat, lon


def clear():
    """Kill the holding + tunnel processes; the phone reverts to its real GPS."""
    if not os.path.exists(PIDFILE):
        return
    with open(PIDFILE) as f:
        pids = [int(x) for x in f.read().split() if x.strip().isdigit()]
    for pid in pids:
        _kill(pid, signal.SIGTERM)
    # give them a moment to release the location, then make sure they're really gone
    for _ in range(10):
        if not any(_alive(p) for p in pids):
            break
        time.sleep(0.2)
    for pid in pids:
        if _alive(pid):
            _kill(pid, signal.SIGKILL)
    os.remove(PIDFILE)


def status():
    """Is a spoof currently held? Returns the pids or None."""
    if not os.path.exists(PIDFILE):
        return None
    with open(PIDFILE) as f:
        pids = [int(x) for x in f.read().split() if x.strip().isdigit()]
    return pids if any(_alive(p) for p in pids) else None


def _kill(pid, sig=signal.SIGTERM):
    try:
        os.killpg(os.getpgid(pid), sig)
    except (ProcessLookupError, PermissionError):
        try:
            os.kill(pid, sig)
        except ProcessLookupError:
            pass


def _alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def _read(path):
    try:
        with open(path) as f:
            return f.read()
    except OSError:
        return ""


def _tail(path, n=6):
    return "\n".join(_read(path).splitlines()[-n:])
