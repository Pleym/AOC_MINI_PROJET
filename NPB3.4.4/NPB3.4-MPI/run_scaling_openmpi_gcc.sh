#!/usr/bin/env bash
set -euo pipefail

# Strong scaling FT CLASS=C avec OpenMPI %gcc, sans toucher au code.
# Objectif: montrer que le speedup plafonne (efficacité qui chute), typiquement à cause
# de coûts mémoire/transposition/communications.
#
# Usage (sur romeo):
#   cd NPB3.4.4/NPB3.4-MPI
#   ./run_scaling_openmpi_gcc.sh
#
# Variables utiles:
#   PROCS_LIST="1 2 4 8 16 32"    # liste de nombres de rangs
#   REPEATS=3                     # répétitions par point
#   FLAG_PROFILE=O2               # O2 ou O3
#   OPENMPI_SPEC="openmpi@4.1.7%gcc"  # modifier si besoin
#   ACCOUNT=... WALLTIME=... MEM=... CONSTRAINT=... NTASKS=...

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_PATH="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"
cd "${SCRIPT_DIR}"

# -------------------- Paramètres --------------------
BENCHMARK="ft"
CLASS="C"
OPENMPI_SPEC="${OPENMPI_SPEC:-openmpi@4.1.7%gcc}"

FLAG_PROFILE="${FLAG_PROFILE:-O2}" # O2 ou O3
PROCS_LIST="${PROCS_LIST:-1 2 4 8 16 32}"
REPEATS="${REPEATS:-3}"

# Slurm (soumission par défaut)
ACCOUNT="${ACCOUNT:-r250142}"
WALLTIME="${WALLTIME:-00:30:00}"
MEM="${MEM:-12G}"
CONSTRAINT="${CONSTRAINT:-x64cpu}"
# NTASKS doit couvrir le max de PROCS_LIST
NTASKS="${NTASKS:-32}"

OUT_CSV="ft_${CLASS}_scaling_openmpi_gcc_${FLAG_PROFILE}.csv"
SUMMARY_CSV="ft_${CLASS}_scaling_openmpi_gcc_${FLAG_PROFILE}_summary.csv"

# -------------------- Helpers --------------------
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Erreur: '$1' introuvable" >&2; exit 1; }
}

set_make_def_param() {
  local key="$1"; shift
  local value="$1"; shift
  sed -i -E "s|^${key}[[:space:]]*=.*$|${key} = ${value}|" config/make.def
}

configure_make_def() {
  cp config/make.def.template config/make.def

  # Wrapper MPI Fortran/C
  set_make_def_param MPIFC "mpif90"
  set_make_def_param FLINK '$(MPIFC)'
  set_make_def_param MPICC "mpicc"
  set_make_def_param CLINK '$(MPICC)'

  # Flags
  case "${FLAG_PROFILE}" in
    O2|o2)
      set_make_def_param FFLAGS "-O2"
      set_make_def_param CFLAGS "-O2"
      ;;
    O3|o3)
      set_make_def_param FFLAGS "-O3 -march=native -funroll-loops"
      set_make_def_param CFLAGS "-O3 -march=native -funroll-loops"
      ;;
    *)
      echo "FLAG_PROFILE invalide: '${FLAG_PROFILE}' (attendu: O2 ou O3)" >&2
      exit 1
      ;;
  esac

  set_make_def_param FLINKFLAGS '$(FFLAGS)'
  set_make_def_param CLINKFLAGS '$(CFLAGS)'
}

parse_npb_time() {
  # Extrait le temps NPB depuis stdout
  # Format typique: "Time in seconds =  12.345"
  awk '
    /Time in seconds/ {
      for (i=1; i<=NF; i++) {
        if ($i ~ /^[0-9]+(\.[0-9]+)?$/) t=$i
      }
    }
    END { if (t=="") print "NA"; else print t }
  '
}

median_from_stdin() {
  # Lit une colonne de nombres sur stdin, sort la médiane (NA si vide)
  awk 'NF && $1!="NA"{a[n++]=$1}
       END{
         if(n==0){print "NA"; exit}
         # tri simple (n petit)
         for(i=0;i<n;i++) for(j=i+1;j<n;j++) if(a[j]<a[i]){tmp=a[i];a[i]=a[j];a[j]=tmp}
         if(n%2==1) print a[int(n/2)]; else print (a[n/2-1]+a[n/2])/2.0
       }'
}

compute_summary() {
  # Construit SUMMARY_CSV: median_time, speedup_vs_1, efficiency
  echo "nprocs,median_time_s,speedup,efficiency" > "${SUMMARY_CSV}"

  local t1
  t1=$(awk -F',' '$1=="1" {print $4}' "${OUT_CSV}" | median_from_stdin)

  while read -r p; do
    local tp
    tp=$(awk -F',' -v pp="${p}" '$1==pp {print $4}' "${OUT_CSV}" | median_from_stdin)

    local speedup="NA"
    local eff="NA"
    if [[ "${t1}" != "NA" && "${tp}" != "NA" ]]; then
      speedup=$(awk -v a="${t1}" -v b="${tp}" 'BEGIN{printf "%.4f", a/b}')
      eff=$(awk -v s="${speedup}" -v p="${p}" 'BEGIN{printf "%.4f", s/p}')
    fi

    echo "${p},${tp},${speedup},${eff}" >> "${SUMMARY_CSV}"
  done <<< "$(echo "${PROCS_LIST}")"
}

run_scaling() {
  # En batch Slurm, l'environnement (spack, modules) n'est pas toujours initialisé.
  # Sur romeo, la fonction romeo_load_x64cpu_env prépare Spack + toolchain.
  if command -v romeo_load_x64cpu_env >/dev/null 2>&1; then
    romeo_load_x64cpu_env >/dev/null 2>&1 || true
  fi

  need_cmd spack
  need_cmd make

  if [[ ! -f config/make.def.template ]]; then
    echo "Erreur: lance ce script depuis NPB3.4.4/NPB3.4-MPI" >&2
    exit 1
  fi

  # Charge OpenMPI %gcc
  spack unload openmpi >/dev/null 2>&1 || true
  spack load "${OPENMPI_SPEC}"

  need_cmd mpif90
  need_cmd mpicc

  configure_make_def

  echo "[INFO] Compilation FT CLASS=${CLASS} avec FLAG_PROFILE=${FLAG_PROFILE} (OpenMPI: ${OPENMPI_SPEC})"
  make clean
  mkdir -p bin
  make "${BENCHMARK}" "CLASS=${CLASS}" F08=def

  local exe="./bin/${BENCHMARK}.${CLASS}.x"
  if [[ ! -x "${exe}" ]]; then
    echo "Erreur: binaire introuvable: ${exe}" >&2
    exit 1
  fi

  # CSV brut: nprocs,repeat,launcher,npb_time_s,stdout_file
  echo "nprocs,repeat,launcher,npb_time_s,stdout_file" > "${OUT_CSV}"

  export OMP_NUM_THREADS=1

  for p in ${PROCS_LIST}; do
    for r in $(seq 1 "${REPEATS}"); do
      local out="scaling_${BENCHMARK}.${CLASS}_${FLAG_PROFILE}_p${p}_r${r}.out"

      if [[ -n "${SLURM_JOB_ID:-}" ]] && command -v srun >/dev/null 2>&1; then
        srun -n "${p}" --cpu-bind=cores "${exe}" > "${out}"
        local launcher="srun"
      else
        mpirun -np "${p}" "${exe}" > "${out}"
        local launcher="mpirun"
      fi

      local t
      t=$(parse_npb_time < "${out}")
      echo "${p},${r},${launcher},${t},${out}" >> "${OUT_CSV}"

      echo "[INFO] p=${p} r=${r} time=${t}s"
    done
  done

  compute_summary

  echo "[OK] CSV brut: ${OUT_CSV}"
  echo "[OK] Synthèse: ${SUMMARY_CSV}"
}

submit_self() {
  need_cmd sbatch

  # Si on n'est pas dans un job, on soumet un job qui fait tout d'un coup (compile + boucle)
  local job_name="ft_${CLASS}_scaling_gcc_${FLAG_PROFILE}"
  local job_id
  job_id=$(sbatch --parsable \
    --account="${ACCOUNT}" \
    --time="${WALLTIME}" \
    --mem="${MEM}" \
    --nodes=1 \
    --ntasks="${NTASKS}" \
    --constraint="${CONSTRAINT}" \
    --job-name="${job_name}" \
    --output="${job_name}.%j.out" \
    --error="${job_name}.%j.err" \
    --export=ALL,RUN_SCALING=1 \
    "${SELF_PATH}")

  echo "Soumis jobid=${job_id}"
  echo "Logs: ${job_name}.${job_id}.out / ${job_name}.${job_id}.err"
  echo "Suivi: squeue -j ${job_id}"
}

if [[ "${RUN_SCALING:-0}" == "1" || -n "${SLURM_JOB_ID:-}" ]]; then
  run_scaling
else
  submit_self
fi
