#!/bin/bash
set -euo pipefail

WRAPPER_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_SCRIPT="${WRAPPER_DIR}/NPB3.4.4/NPB3.4-MPI/script_benchmark.sh"

if [[ ! -f "${TARGET_SCRIPT}" ]]; then
	echo "Erreur: script cible introuvable: ${TARGET_SCRIPT}"
	exit 1
fi

exec bash "${TARGET_SCRIPT}" "$@"

