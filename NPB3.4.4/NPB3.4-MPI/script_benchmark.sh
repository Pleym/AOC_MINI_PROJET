#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------
# Campagne MAQAO OneView NPB-MPI (FT uniquement, CLASS=C)
# - Exécution chronologique des étapes d'optimisation
# - Un rapport OneView par étape
# - Export CSV de synthèse des métriques
# - Soumission unique Slurm (sans dépendances)
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
STAGES="${STAGES:-baseline,o3_native,ofast_native,lto_native,compiler_variant_mpifort}"

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUMMARY_CSV="${ROOT_DIR}/ft_C_campaign_summary.csv"

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

ensure_project_layout() {
	if [[ ! -f "${ROOT_DIR}/config/make.def.template" ]]; then
		echo "Erreur: script_benchmark.sh doit être lancé depuis NPB3.4-MPI."
		echo "Chemin actuel script: ${SCRIPT_PATH}"
		echo "Fichier manquant: ${ROOT_DIR}/config/make.def.template"
		exit 1
	fi
}

set_make_def_param() {
	local key="$1"
	local value="$2"
	sed -i -E "s|^${key}[[:space:]]*=.*$|${key} = ${value}|" config/make.def
}

configure_make_def_for_stage() {
	local stage="$1"
	STAGE_DESC=""
	cp config/make.def.template config/make.def

	case "${stage}" in
		baseline)
			STAGE_DESC="Référence stable pour profiler (O2 + debug symboles)."
			set_make_def_param MPIFC "mpif90"
			set_make_def_param FLINK '$(MPIFC)'
			set_make_def_param MPICC "mpicc"
			set_make_def_param CLINK '$(MPICC)'
			set_make_def_param FFLAGS "-O2 -g -fno-omit-frame-pointer"
			set_make_def_param CFLAGS "-O2 -g -fno-omit-frame-pointer"
			set_make_def_param FLINKFLAGS '$(FFLAGS)'
			set_make_def_param CLINKFLAGS '$(CFLAGS)'
			;;
		o3_native)
			STAGE_DESC="Optimisation classique HPC: O3 + arch native + unroll."
			set_make_def_param MPIFC "mpif90"
			set_make_def_param FLINK '$(MPIFC)'
			set_make_def_param MPICC "mpicc"
			set_make_def_param CLINK '$(MPICC)'
			set_make_def_param FFLAGS "-O3 -funroll-loops -march=native -g -fno-omit-frame-pointer"
			set_make_def_param CFLAGS "-O3 -funroll-loops -march=native -g -fno-omit-frame-pointer"
			set_make_def_param FLINKFLAGS '$(FFLAGS)'
			set_make_def_param CLINKFLAGS '$(CFLAGS)'
			;;
		ofast_native)
			STAGE_DESC="Version agressive calcul flottant: Ofast + fast-math + native."
			set_make_def_param MPIFC "mpif90"
			set_make_def_param FLINK '$(MPIFC)'
			set_make_def_param MPICC "mpicc"
			set_make_def_param CLINK '$(MPICC)'
			set_make_def_param FFLAGS "-Ofast -ffast-math -funroll-loops -march=native -g -fno-omit-frame-pointer"
			set_make_def_param CFLAGS "-Ofast -ffast-math -funroll-loops -march=native -g -fno-omit-frame-pointer"
			set_make_def_param FLINKFLAGS '$(FFLAGS)'
			set_make_def_param CLINKFLAGS '$(CFLAGS)'
			;;
		lto_native)
			STAGE_DESC="Ajout Link-Time Optimization pour optimiser inter-modules."
			set_make_def_param MPIFC "mpif90"
			set_make_def_param FLINK '$(MPIFC)'
			set_make_def_param MPICC "mpicc"
			set_make_def_param CLINK '$(MPICC)'
			set_make_def_param FFLAGS "-O3 -funroll-loops -march=native -flto -g -fno-omit-frame-pointer"
			set_make_def_param CFLAGS "-O3 -funroll-loops -march=native -flto -g -fno-omit-frame-pointer"
			set_make_def_param FLINKFLAGS '$(FFLAGS) -flto'
			set_make_def_param CLINKFLAGS '$(CFLAGS) -flto'
			;;
		compiler_variant_mpifort)
			STAGE_DESC="Comparaison wrapper compilateur MPI: mpifort au lieu de mpif90."
			set_make_def_param MPIFC "mpifort"
			set_make_def_param FLINK '$(MPIFC)'
			set_make_def_param MPICC "mpicc"
			set_make_def_param CLINK '$(MPICC)'
			set_make_def_param FFLAGS "-O3 -g -fno-omit-frame-pointer"
			set_make_def_param CFLAGS "-O3 -g -fno-omit-frame-pointer"
			set_make_def_param FLINKFLAGS '$(FFLAGS)'
			set_make_def_param CLINKFLAGS '$(CFLAGS)'
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

extract_metric() {
	local csv_file="$1"
	local metric="$2"
	awk -F';' -v m="${metric}" '$1 == m {gsub(/^"+|"+$/, "", $3); print $3; exit}' "${csv_file}"
}

init_summary_csv() {
	if [[ ! -f "${SUMMARY_CSV}" ]]; then
		echo "stage,status,description,profiled_time,application_time,user_time,loops_time,speedup_if_fully_vectorised,speedup_if_fp_vect,compilation_options,xp_dir" > "${SUMMARY_CSV}"
	fi
}

append_summary_csv() {
	local stage="$1"
	local status="$2"
	local desc="$3"
	local xp_dir="$4"
	local metrics_file="${xp_dir}/shared/run_0/global_metrics.csv"

	local profiled_time="NA"
	local application_time="NA"
	local user_time="NA"
	local loops_time="NA"
	local speedup_fully_vect="NA"
	local speedup_fp_vect="NA"
	local compilation_options="NA"

	if [[ -f "${metrics_file}" ]]; then
		profiled_time="$(extract_metric "${metrics_file}" "profiled_time")"
		application_time="$(extract_metric "${metrics_file}" "application_time")"
		user_time="$(extract_metric "${metrics_file}" "user_time")"
		loops_time="$(extract_metric "${metrics_file}" "loops_time")"
		speedup_fully_vect="$(extract_metric "${metrics_file}" "speedup_if_fully_vectorised")"
		speedup_fp_vect="$(extract_metric "${metrics_file}" "speedup_if_fp_vect")"
		compilation_options="$(extract_metric "${metrics_file}" "compilation_options")"
	fi

	echo "${stage},${status},\"${desc}\",${profiled_time},${application_time},${user_time},${loops_time},${speedup_fully_vect},${speedup_fp_vect},${compilation_options},${xp_dir}" >> "${SUMMARY_CSV}"
}

run_stage() {
	local stage="$1"
	local nprocs="$2"

	cd "${ROOT_DIR}"
	ensure_project_layout
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

	if maqao oneview -R1 xp="${xp}" --mpi-command="${launcher}" -- "${exe}"; then
		append_summary_csv "${stage}" "OK" "${STAGE_DESC}" "${ROOT_DIR}/${xp}"
		return 0
	fi

	append_summary_csv "${stage}" "FAIL" "${STAGE_DESC}" "${ROOT_DIR}/${xp}"
	return 1
}

run_all_stages() {
	local nprocs="$1"
	IFS=',' read -r -a stage_array <<< "${STAGES}"
	local failed=0

	init_summary_csv

	for stage in "${stage_array[@]}"; do
		echo "=== Stage: ${stage} (FT CLASS=C) ==="
		if ! run_stage "${stage}" "${nprocs}"; then
			echo "Stage ${stage} en échec: on poursuit la campagne." >&2
			failed=$((failed + 1))
		fi
	done

	echo "Résumé campagne: ${SUMMARY_CSV}"
	if [[ ${failed} -gt 0 ]]; then
		echo "${failed} étape(s) en échec." >&2
		return 1
	fi
}

submit_campaign() {
	cd "${ROOT_DIR}"

	unset SBATCH_DEPENDENCY || true
	ensure_project_layout

	local job_name="npb_${BENCHMARK}_${CLASS}_campaign"
	local output_file="${BENCHMARK}_${CLASS}_campaign.%j.out"
	local error_file="${BENCHMARK}_${CLASS}_campaign.%j.err"

	local job_id
	job_id=$(sbatch --parsable \
		--account="${ACCOUNT}" \
		--time="${WALLTIME}" \
		--mem="${MEM}" \
		--nodes="${NODES}" \
		--constraint="${CONSTRAINT}" \
		--ntasks="${NTASKS}" \
		--cpus-per-task="${CPUS_PER_TASK}" \
		--job-name="${job_name}" \
		--output="${output_file}" \
		--error="${error_file}" \
		--export=ALL,RUN_ALL_STAGES=1,STAGES="${STAGES}",NTASKS_REQ="${NTASKS}" \
		"${SCRIPT_PATH}")

	echo "Soumis ${job_name} -> job ${job_id}"
	echo "Campagne soumise."
}

if [[ "${RUN_ALL_STAGES:-0}" == "1" ]]; then
	run_all_stages "${NTASKS_REQ:-${SLURM_NTASKS:-${NTASKS}}}"
elif [[ "${RUN_STAGE:-0}" == "1" ]]; then
	run_stage "${STAGE}" "${NTASKS_REQ:-${SLURM_NTASKS:-${NTASKS}}}"
elif [[ -n "${SLURM_JOB_ID:-}" ]]; then
	run_all_stages "${SLURM_NTASKS:-${NTASKS}}"
else
	submit_campaign
fi

