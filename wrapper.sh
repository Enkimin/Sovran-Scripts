#!/bin/bash

# Check if the user is root. If not, execute the actual script with sudo.
if [ "$(id -u)" -ne 0 ]; then
    sudo /media/enki/Data/GitHub/SovranScripts/Sovran-Scripts/nodeinstall.sh "$@"
else
    /media/enki/Data/GitHub/SovranScripts/Sovran-Scripts/nodeinstall.sh "$@"
fi