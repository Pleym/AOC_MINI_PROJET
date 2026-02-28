#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------
# Campagne MAQAO OneView NPB-MPI (FT uniquement, CLASS=C)
# - Exécution chronologique des étapes d'optimisation
# - Un rapport OneView par étape
# ------------------------------------------------------------

ACCOUNT="${ACCOUNT:-r250142}"
WALLTIME="${WALLTIME:-00:20:00}"
MEM="${MEM:-10G}"
NODES="${NODES:-1}"
CONSTRAINT="${CONSTRAINT:-x64cpu}"
NTASKS="${NTASKS:-16}"
CPUS_PER_TASK="${CPUS_PER_TASK:-1}"

BENCHMARK="ft"
CLASS="C"
STAGES="${STAGES:-baseline,aggressive_flags,compiler_variant}"

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

load_tools() {
	romeo_load_x64cpu_env

	spack load openmpi@4.1.7%aocc || spack load openmpi

	local maqao_hash
	maqao_hash=$(spack find --format '{name}@{version} /{hash:7}' maqao 2>/dev/null | awk '/^maqao@2025\.1\.4 / {print $2; exit}')
	if [[ -n "${maqao_hash}" ]]; then
		spack load "${maqao_hash}"
		return
	fi

	maqao_hash=$(spack find --format '{name}@{version} /{hash:7}' maqao 2>/dev/null | awk '/^maqao@/ {print $2; exit}')
	if [[ -n "${maqao_hash}" ]]; then
		spack load "${maqao_hash}"
		return
	fi

	echo "Erreur: aucun package maqao disponible via Spack."
	exit 1
}

set_make_def_param() {
	local key="$1"
	local value="$2"
	sed -i -E "s|^${key}[[:space:]]*=.*$|${key} = ${value}|" config/make.def
}

configure_make_def_for_stage() {
	local stage="$1"
	cp config/make.def.template config/make.def

	case "${stage}" in
		baseline)
			set_make_def_param MPIFC "mpif90"
			set_make_def_param FLINK '$(MPIFC)'
			set_make_def_param MPICC "mpicc"
			set_make_def_param CLINK '$(MPICC)'
			set_make_def_param FFLAGS "-O2 -g -fno-omit-frame-pointer"
			set_make_def_param CFLAGS "-O2 -g -fno-omit-frame-pointer"
			;;
		aggressive_flags)
			set_make_def_param MPIFC "mpif90"
			set_make_def_param FLINK '$(MPIFC)'
			set_make_def_param MPICC "mpicc"
			set_make_def_param CLINK '$(MPICC)'
			set_make_def_param FFLAGS "-O3 -funroll-loops -march=native -g -fno-omit-frame-pointer"
			set_make_def_param CFLAGS "-O3 -funroll-loops -march=native -g -fno-omit-frame-pointer"
			;;
		compiler_variant)
			set_make_def_param MPIFC "mpifort"
			set_make_def_param FLINK '$(MPIFC)'
			set_make_def_param MPICC "mpicc"
			set_make_def_param CLINK '$(MPICC)'
			set_make_def_param FFLAGS "-O3 -g -fno-omit-frame-pointer"
			set_make_def_param CFLAGS "-O3 -g -fno-omit-frame-pointer"
			;;
		*)
			echo "Erreur: étape inconnue '${stage}'."
			exit 1
			;;
	esac
}

resolve_mpi_launcher() {
	local nprocs="$1"

	if command -v mpirun >/dev/null 2>&1; then
		echo "mpirun -np ${nprocs}"
		return
	fi
	if command -v mpiexec >/dev/null 2>&1; then
		echo "mpiexec -n ${nprocs}"
		return
	fi
	if command -v srun >/dev/null 2>&1; then
		echo "srun -n ${nprocs}"
		return
	fi

	echo ""
}

run_stage() {
	local stage="$1"
	local nprocs="$2"

	cd "${ROOT_DIR}"
	load_tools
	configure_make_def_for_stage "${stage}"

	make clean
	mkdir -p bin
	make "${BENCHMARK}" "CLASS=${CLASS}" F08=def

	local exe="./bin/${BENCHMARK}.${CLASS}.x"
	if [[ ! -x "${exe}" ]]; then
		echo "Erreur: binaire introuvable ${exe}"
		exit 1
	fi

	local launcher
	launcher="$(resolve_mpi_launcher "${nprocs}")"
	if [[ -z "${launcher}" ]]; then
		echo "Erreur: aucun lanceur MPI trouvé (mpirun/mpiexec/srun)."
		exit 1
	fi

	local xp="maqao_oneview_xp_${BENCHMARK}_${CLASS}_${stage}"
	rm -rf "${xp}"

	maqao oneview -R1 xp="${xp}" --mpi-command="${launcher}" -- "${exe}"
}

submit_campaign() {
	cd "${ROOT_DIR}"

	IFS=',' read -r -a stage_array <<< "${STAGES}"
	local previous_job=""

	for stage in "${stage_array[@]}"; do
		local job_name="npb_${BENCHMARK}_${CLASS}_${stage}"
		local output_file="${BENCHMARK}_${CLASS}_${stage}.%j.out"
		local error_file="${BENCHMARK}_${CLASS}_${stage}.%j.err"

		local -a cmd
		cmd=(sbatch --parsable
			--account="${ACCOUNT}"
			--time="${WALLTIME}"
			--mem="${MEM}"
			--nodes="${NODES}"
			--constraint="${CONSTRAINT}"
			--ntasks="${NTASKS}"
			--cpus-per-task="${CPUS_PER_TASK}"
			--job-name="${job_name}"
			--output="${output_file}"
			--error="${error_file}"
			--export=ALL,RUN_STAGE=1,STAGE="${stage}",NTASKS_REQ="${NTASKS}"
		)

		if [[ -n "${previous_job}" ]]; then
			cmd+=(--dependency="afterok:${previous_job}")
		fi

		cmd+=("${SCRIPT_PATH}")

		local job_id
		job_id=$("${cmd[@]}")
		echo "Soumis ${job_name} -> job ${job_id}"

		previous_job="${job_id}"
	done

	echo "Campagne soumise."
}

if [[ "${RUN_STAGE:-0}" == "1" ]]; then
	run_stage "${STAGE}" "${NTASKS_REQ:-${SLURM_NTASKS:-${NTASKS}}}"
else
	submit_campaign
fi

