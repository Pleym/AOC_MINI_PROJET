#!/usr/bin/env bash
set -euo pipefail

# OneView MAQAO FT (MPI) en séquentiel (1 rang) - BASELINE
# - Compile FT CLASS=C
# - Utilise un profil de flags "baseline" (défaut: best_o2_profiled)
# - N'impose PAS de blocking FFT: on laisse le défaut NPB (fftblock=16)
#
# Usage (sur ROMEO):
#   cd NPB3.4.4/NPB3.4-MPI
#   ./run_seq_oneview_baseline.sh
#
# Variables:
#   FLAG_PROFILE=best_o2_profiled|o3_native|ofast_native|lto_native|o3_avx2_fma
#   CLASS=C
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
export FLAG_PROFILES="${FLAG_PROFILE:-best_o2_profiled}"

# Important: on ne force pas fftblock. Si tu as NPB_FFTBLOCK exporté dans ton shell,
# on l'enlève pour garantir une baseline strictement par défaut.
unset NPB_FFTBLOCK || true

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
  echo "[INFO] Exécution directe (RUN_CAMPAIGN=1), FLAG_PROFILES=${FLAG_PROFILES} (fftblock=defaut)"
  RUN_CAMPAIGN=1 bash ./script_benchmark.sh
else
  echo "[INFO] Soumission Slurm via script_benchmark.sh, FLAG_PROFILES=${FLAG_PROFILES} (fftblock=defaut)"
  bash ./script_benchmark.sh
fi
