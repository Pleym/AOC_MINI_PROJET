#!/usr/bin/env bash
set -euo pipefail

# Script "tout fait" : OpenMPI %gcc + FT CLASS=C + O2/O3 + seq/par + MAQAO normal
# Utilise le script existant: NPB3.4-MPI/script_benchmark.sh
#
# Usage (sur romeo):
#   cd NPB3.4.4/NPB3.4-MPI
#   ./run_openmpi_gcc_o2_o3_fast.sh
#
# Par défaut, cela soumet un job Slurm (sbatch) via script_benchmark.sh.
# Pour exécuter directement (si tu es déjà dans une allocation Slurm):
#   DIRECT=1 ./run_openmpi_gcc_o2_o3_fast.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

if ! command -v spack >/dev/null 2>&1; then
  echo "Erreur: 'spack' introuvable. Lance ce script sur romeo avec l'environnement Spack initialisé." >&2
  exit 1
fi

# Vérifie qu'un OpenMPI %gcc est bien installé (sinon message clair)
if ! spack find "openmpi@4.1.7%gcc" >/dev/null 2>&1; then
  echo "Erreur: aucun OpenMPI 'openmpi@4.1.7%gcc' visible via Spack." >&2
  echo "Commande utile: spack find openmpi" >&2
  exit 1
fi

# Ressources Slurm (si submission via sbatch)
export ACCOUNT="${ACCOUNT:-r250142}"
export WALLTIME="${WALLTIME:-00:30:00}"
export MEM="${MEM:-12G}"
export NODES="${NODES:-1}"
export CONSTRAINT="${CONSTRAINT:-x64cpu}"

# Campagne réduite au strict nécessaire
export BENCHMARK="ft"
export CLASS="C"
export COMPILERS="${COMPILERS:-mpif90}"

# Sélection explicite OpenMPI %gcc
export OPENMPI_SPEC="openmpi@4.1.7%gcc"
export OPENMPI_TOOLCHAIN="gcc"
unset OPENMPI_HASH || true

# Deux niveaux de compilation + seulement MAQAO normal (plus rapide)
export FLAG_PROFILES="best_o2_profiled,o3_native"
export MAQAO_MODES="normal"

# Deux exécutions: séquentiel puis parallèle
export PROFILES="seq,par"
export SEQ_NTASKS="${SEQ_NTASKS:-1}"
export NTASKS="${NTASKS:-16}"
export PAR_NTASKS="${PAR_NTASKS:-${NTASKS}}"

if [[ "${DIRECT:-0}" == "1" ]]; then
  echo "[INFO] Exécution directe (RUN_CAMPAIGN=1)"
  RUN_CAMPAIGN=1 bash ./script_benchmark.sh
else
  echo "[INFO] Soumission Slurm via sbatch (par défaut)"
  bash ./script_benchmark.sh
fi

cat <<'EOF'

Résultats à lire ensuite:
- Temps + RAM (RSS): ft_C_runtime_memory.csv
- Résumé OneView (application_time, etc.): ft_C_campaign_summary.csv
EOF
