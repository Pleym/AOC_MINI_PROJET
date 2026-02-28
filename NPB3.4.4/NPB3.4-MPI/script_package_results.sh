#!/bin/bash
set -euo pipefail

# Utilisation:
#   bash script_package_results.sh [nom_archive.tar.gz]
#
# Si aucun nom n'est fourni, le script génère:
#   npb_ftC_maqao_results_YYYYmmdd_HHMMSS.tar.gz

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${ROOT_DIR}"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
ARCHIVE_NAME="${1:-npb_ftC_maqao_results_${TIMESTAMP}.tar.gz}"

if [[ "${ARCHIVE_NAME}" != *.tar.gz ]]; then
  ARCHIVE_NAME="${ARCHIVE_NAME}.tar.gz"
fi

items=()

add_matches() {
  local pattern="$1"
  local matched=0
  shopt -s nullglob
  for p in ${pattern}; do
    items+=("${p}")
    matched=1
  done
  shopt -u nullglob
  return ${matched}
}

# Résultats OneView FT/C (nouvelle et ancienne convention)
add_matches "maqao_oneview_xp_ft_C*" || true

# Logs de jobs et sorties associées
add_matches "ft*.out" || true
add_matches "ft*.err" || true
add_matches "ft_C_*.out" || true
add_matches "ft_C_*.err" || true
add_matches "slurm-*.out" || true

# Artefacts utiles pour rejouer/diagnostiquer
add_matches "config/make.def" || true
add_matches "script_benchmark.sh" || true

if [[ ${#items[@]} -eq 0 ]]; then
  echo "Aucun résultat à archiver dans ${ROOT_DIR}."
  echo "Vérifie que les dossiers maqao_oneview_xp_ft_C* existent."
  exit 1
fi

# Dé-duplication simple (préserve l'ordre)
unique_items=()
for it in "${items[@]}"; do
  skip=0
  for seen in "${unique_items[@]:-}"; do
    if [[ "${seen}" == "${it}" ]]; then
      skip=1
      break
    fi
  done
  if [[ ${skip} -eq 0 ]]; then
    unique_items+=("${it}")
  fi
done

echo "Création de l'archive: ${ARCHIVE_NAME}"
tar -czf "${ARCHIVE_NAME}" "${unique_items[@]}"

echo "Archive créée: ${ROOT_DIR}/${ARCHIVE_NAME}"
echo "Contenu archivé (${#unique_items[@]} entrées):"
printf ' - %s\n' "${unique_items[@]}"

echo
echo "Exemple SCP vers ta machine locale:"
echo "scp doabaul@romeo1:${ROOT_DIR}/${ARCHIVE_NAME} ."
