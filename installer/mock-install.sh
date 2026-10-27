#!/usr/bin/env bash
# Fake install.sh for clicking through the installer UI: GM_INSTALLER_SCRIPT=$PWD/mock-install.sh
for id in tools source xcode signing idevice; do
  echo "::step $id $id"; echo "doing ${id}…"; sleep 1; echo "::ok $id"
done
echo "::ask Which team ID should sign GPS Spoofer?	ABCDE12345" >&2
read -r -t 6 team; echo "team: $team"
echo "::step phone iPhone"
echo "::wait Plug your iPhone into this Mac with a cable, unlock it, and tap Trust if it asks."
read -r -t 6 _ || true
echo "::resume"
for id in build pair; do echo "::step $id $id"; sleep 1; done
[ "${MOCK_FAIL:-}" ] && { echo "::fail Couldn't reach your iPhone."; exit 1; }
echo "::done"
