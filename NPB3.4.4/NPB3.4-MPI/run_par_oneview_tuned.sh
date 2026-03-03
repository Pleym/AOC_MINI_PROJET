#!/usr/bin/env bash
set -euo pipefail

# OneView MAQAO FT (MPI) en parallèle - TUNED (16 ranks par défaut)
# - Compile FT CLASS=C
# - Applique un profil de flags (défaut: o3_avx2_fma)
# - Permet de régler le blocking FFT via NPB_FFTBLOCK (défaut: 64)
# - Cible AOCC via OpenMPI construit avec %aocc
#
# Usage (sur ROMEO):
#   cd NPB3.4.4/NPB3.4-MPI
#   ./run_par_oneview_tuned.sh
#
# Variables:
#   PAR_NTASKS=16 (ou NTASKS=16)
#   FLAG_PROFILE=o3_avx2_fma|o3_native|best_o2_profiled|ofast_native|lto_native
#   NPB_FFTBLOCK=64
#   NPB_FFTBLOCK=default (ou 0) -> désactive l'override et laisse le défaut NPB (fftblock=16)
#   OPENMPI_SPEC="openmpi@4.1.7%aocc" (ou OPENMPI_HASH)
#   ACCOUNT=... WALLTIME=... MEM=... CONSTRAINT=...
#   DIRECT=1   -> exécute directement (si déjà dans une allocation)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

export BENCHMARK="ft"
export CLASS="${CLASS:-C}"

export PROFILES="par"
export NTASKS="${NTASKS:-16}"
export PAR_NTASKS="${PAR_NTASKS:-${NTASKS}}"
export CPUS_PER_TASK="${CPUS_PER_TASK:-1}"

export MAQAO_MODES="${MAQAO_MODES:-normal}"

# Profil de flags à tester (un seul ici)
export FLAG_PROFILES="${FLAG_PROFILE:-o3_avx2_fma}"

# Bloque FFT: choix puissance de 2 (code arrondit vers le bas)
case "${NPB_FFTBLOCK:-64}" in
  0|default|DEFAULT)
    unset NPB_FFTBLOCK || true
    ;;
  *)
    export NPB_FFTBLOCK="${NPB_FFTBLOCK:-64}"
    ;;
esac

# Environnement Spack / OpenMPI (ciblage AOCC par défaut)
export OPENMPI_SPEC="${OPENMPI_SPEC:-openmpi@4.1.7%aocc}"
export OPENMPI_TOOLCHAIN="${OPENMPI_TOOLCHAIN:-aocc}"

# Ressources Slurm (si soumission)
export ACCOUNT="${ACCOUNT:-r250142}"
export WALLTIME="${WALLTIME:-00:20:00}"
export MEM="${MEM:-10G}"
export NODES="${NODES:-1}"
export CONSTRAINT="${CONSTRAINT:-x64cpu}"

if [[ "${DIRECT:-0}" == "1" ]]; then
  echo "[INFO] Exécution directe (RUN_CAMPAIGN=1), PAR_NTASKS=${PAR_NTASKS}, FLAG_PROFILES=${FLAG_PROFILES}, NPB_FFTBLOCK=${NPB_FFTBLOCK:-default}"
  RUN_CAMPAIGN=1 bash ./script_benchmark.sh
else
  echo "[INFO] Soumission Slurm via script_benchmark.sh, PAR_NTASKS=${PAR_NTASKS}, FLAG_PROFILES=${FLAG_PROFILES}, NPB_FFTBLOCK=${NPB_FFTBLOCK:-default}"
  bash ./script_benchmark.sh
fi
