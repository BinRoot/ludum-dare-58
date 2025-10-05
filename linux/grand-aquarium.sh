#!/bin/sh
printf '\033c\033]0;%s\a' ludum-dare-58
base_path="$(dirname "$(realpath "$0")")"
"$base_path/grand-aquarium.x86_64" "$@"
