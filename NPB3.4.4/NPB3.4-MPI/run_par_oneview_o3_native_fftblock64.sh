#!/usr/bin/env bash
set -euo pipefail

# OneView MAQAO FT (MPI) en parallèle - O3 native + FFTBLOCK=64
# Config demandée:
# - 16 ranks MPI
# - OpenMPI construit avec %aocc
# - Profil de compilation: o3_native (=> -O3 -march=native ...)
# - NPB_FFTBLOCK=64
#
# Usage (sur ROMEO):
#   cd NPB3.4.4/NPB3.4-MPI
#   chmod +x run_par_oneview_o3_native_fftblock64.sh
#   ./run_par_oneview_o3_native_fftblock64.sh
#
# Variables optionnelles:
#   PAR_NTASKS=16 (sinon défaut 16)
#   OPENMPI_SPEC="openmpi@4.1.7%aocc" (ou OPENMPI_HASH)
#   ACCOUNT=... WALLTIME=... MEM=... CONSTRAINT=...
#   DIRECT=1 -> exécute directement (si déjà dans une allocation)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

export BENCHMARK="ft"
export CLASS="${CLASS:-C}"

export PROFILES="par"
export NTASKS="${NTASKS:-16}"
export PAR_NTASKS="${PAR_NTASKS:-${NTASKS}}"
export CPUS_PER_TASK="${CPUS_PER_TASK:-1}"
export MAQAO_MODES="${MAQAO_MODES:-normal}"

export FLAG_PROFILES="o3_native"
export NPB_FFTBLOCK="64"

export OPENMPI_SPEC="${OPENMPI_SPEC:-openmpi@4.1.7%aocc}"
export OPENMPI_TOOLCHAIN="${OPENMPI_TOOLCHAIN:-aocc}"

export ACCOUNT="${ACCOUNT:-r250142}"
export WALLTIME="${WALLTIME:-00:20:00}"
export MEM="${MEM:-10G}"
export NODES="${NODES:-1}"
export CONSTRAINT="${CONSTRAINT:-x64cpu}"

if [[ "${DIRECT:-0}" == "1" ]]; then
  echo "[INFO] Exécution directe (RUN_CAMPAIGN=1), PAR_NTASKS=${PAR_NTASKS}, FLAG_PROFILES=${FLAG_PROFILES}, NPB_FFTBLOCK=${NPB_FFTBLOCK}, OPENMPI_SPEC=${OPENMPI_SPEC}"
  RUN_CAMPAIGN=1 bash ./script_benchmark.sh
else
  echo "[INFO] Soumission Slurm via script_benchmark.sh, PAR_NTASKS=${PAR_NTASKS}, FLAG_PROFILES=${FLAG_PROFILES}, NPB_FFTBLOCK=${NPB_FFTBLOCK}, OPENMPI_SPEC=${OPENMPI_SPEC}"
  bash ./script_benchmark.sh
fi
