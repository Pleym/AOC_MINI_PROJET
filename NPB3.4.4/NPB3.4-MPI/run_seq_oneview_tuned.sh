#!/usr/bin/env bash
set -euo pipefail

# OneView MAQAO FT (MPI) en séquentiel (1 rang)
# - Compile FT CLASS=C
# - Applique un profil de flags (défaut: o3_avx2_fma)
# - Permet de régler le blocking FFT via NPB_FFTBLOCK (défaut: 64)
#
# Usage (sur ROMEO):
#   cd NPB3.4.4/NPB3.4-MPI
#   ./run_seq_oneview_tuned.sh
#
# Variables:
#   FLAG_PROFILE=o3_avx2_fma|o3_native|best_o2_profiled|ofast_native|lto_native
#   CLASS=C
#   NPB_FFTBLOCK=64
#   OPENMPI_SPEC="openmpi@4.1.7%gcc"  (ou OPENMPI_HASH)
#   ACCOUNT=... WALLTIME=... MEM=... CONSTRAINT=...
#   DIRECT=1   -> exécute directement (si déjà dans une allocation)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

export BENCHMARK="ft"
export CLASS="${CLASS:-C}"
export PROFILES="seq"
export SEQ_NTASKS="1"
export MAQAO_MODES="normal"

# Profil de flags à tester (un seul ici pour aller vite)
export FLAG_PROFILES="${FLAG_PROFILE:-o3_avx2_fma}"

# Bloque FFT: choix puissance de 2 (code arrondit vers le bas)
export NPB_FFTBLOCK="${NPB_FFTBLOCK:-64}"

# Environnement Spack / OpenMPI (ciblage GCC par défaut)
export OPENMPI_SPEC="${OPENMPI_SPEC:-openmpi@4.1.7%gcc}"
export OPENMPI_TOOLCHAIN="${OPENMPI_TOOLCHAIN:-gcc}"

# Ressources Slurm (si soumission)
export ACCOUNT="${ACCOUNT:-r250142}"
export WALLTIME="${WALLTIME:-00:20:00}"
export MEM="${MEM:-10G}"
export NODES="${NODES:-1}"
export CONSTRAINT="${CONSTRAINT:-x64cpu}"
export NTASKS="${NTASKS:-1}"
export CPUS_PER_TASK="${CPUS_PER_TASK:-1}"

if [[ "${DIRECT:-0}" == "1" ]]; then
  echo "[INFO] Exécution directe (RUN_CAMPAIGN=1), FLAG_PROFILES=${FLAG_PROFILES}, NPB_FFTBLOCK=${NPB_FFTBLOCK}"
  RUN_CAMPAIGN=1 bash ./script_benchmark.sh
else
  echo "[INFO] Soumission Slurm via script_benchmark.sh, FLAG_PROFILES=${FLAG_PROFILES}, NPB_FFTBLOCK=${NPB_FFTBLOCK}"
  bash ./script_benchmark.sh
fi
