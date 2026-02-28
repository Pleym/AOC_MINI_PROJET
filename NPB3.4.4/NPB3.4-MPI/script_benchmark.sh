#!/bin/bash
set -euo pipefail

# ------------------------------------------------------------
# Campagne FT CLASS=C (version simplifiée)
# Objectif: garder UNIQUEMENT la meilleure optimisation observée
#           et comparer proprement seq/par + modes MAQAO + 2 compilateurs.
# ------------------------------------------------------------

ACCOUNT="${ACCOUNT:-r250142}"
PARTITION="${PARTITION:-}"
WALLTIME="${WALLTIME:-00:30:00}"
MEM="${MEM:-10G}"
NODES="${NODES:-1}"
CONSTRAINT="${CONSTRAINT:-x64cpu}"
NTASKS="${NTASKS:-16}"
CPUS_PER_TASK="${CPUS_PER_TASK:-1}"

BENCHMARK="ft"
CLASS="C"

# Profils de flags à comparer (un OneView par profil)
FLAG_PROFILES="${FLAG_PROFILES:-best_o2_profiled,o3_native,ofast_native,lto_native}"

# Essai d'au moins deux wrappers compilateur MPI
COMPILERS="${COMPILERS:-mpif90,mpifort}"

# Conseils prof: seq puis par + modes R1/S1/R1-WS
PROFILES="${PROFILES:-seq,par}"
SEQ_NTASKS="${SEQ_NTASKS:-1}"
PAR_NTASKS="${PAR_NTASKS:-${NTASKS}}"
MAQAO_MODES="${MAQAO_MODES:-normal,stability,scalability}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPT_PATH="${SCRIPT_DIR}/$(basename "$0")"
ROOT_DIR="${SCRIPT_DIR}"

if [[ -n "${SLURM_SUBMIT_DIR:-}" && -f "${SLURM_SUBMIT_DIR}/config/make.def.template" ]]; then
	ROOT_DIR="${SLURM_SUBMIT_DIR}"
fi

if [[ -f "${ROOT_DIR}/script_benchmark.sh" ]]; then
	SCRIPT_PATH="${ROOT_DIR}/script_benchmark.sh"
fi

SUMMARY_CSV="${ROOT_DIR}/ft_C_campaign_summary.csv"
RUNTIME_CSV="${ROOT_DIR}/ft_C_runtime_memory.csv"
RUNTIME_DIR="${ROOT_DIR}/runtime_logs"

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

resolve_flags_profile() {
	local flag_profile="$1"
	case "${flag_profile}" in
		best_o2_profiled)
			PROFILE_FFLAGS="-O2 -g -fno-omit-frame-pointer"
			PROFILE_CFLAGS="-O2 -g -fno-omit-frame-pointer"
			PROFILE_FLINKFLAGS='$(FFLAGS)'
			PROFILE_CLINKFLAGS='$(CFLAGS)'
			;;
		o3_native)
			PROFILE_FFLAGS="-O3 -march=native -funroll-loops -g -fno-omit-frame-pointer"
			PROFILE_CFLAGS="-O3 -march=native -funroll-loops -g -fno-omit-frame-pointer"
			PROFILE_FLINKFLAGS='$(FFLAGS)'
			PROFILE_CLINKFLAGS='$(CFLAGS)'
			;;
		ofast_native)
			PROFILE_FFLAGS="-Ofast -ffast-math -march=native -funroll-loops -g -fno-omit-frame-pointer"
			PROFILE_CFLAGS="-Ofast -ffast-math -march=native -funroll-loops -g -fno-omit-frame-pointer"
			PROFILE_FLINKFLAGS='$(FFLAGS)'
			PROFILE_CLINKFLAGS='$(CFLAGS)'
			;;
		lto_native)
			PROFILE_FFLAGS="-O3 -march=native -funroll-loops -flto -g -fno-omit-frame-pointer"
			PROFILE_CFLAGS="-O3 -march=native -funroll-loops -flto -g -fno-omit-frame-pointer"
			PROFILE_FLINKFLAGS='$(FFLAGS) -flto'
			PROFILE_CLINKFLAGS='$(CFLAGS) -flto'
			;;
		*)
			echo "Profil de flags inconnu: ${flag_profile}" >&2
			return 1
			;;
	esac
	return 0
}

configure_make_def_for_compiler() {
	local compiler="$1"
	local flag_profile="$2"

	resolve_flags_profile "${flag_profile}"
	cp config/make.def.template config/make.def

	set_make_def_param MPIFC "${compiler}"
	set_make_def_param FLINK '$(MPIFC)'
	set_make_def_param MPICC "mpicc"
	set_make_def_param CLINK '$(MPICC)'
	set_make_def_param FFLAGS "${PROFILE_FFLAGS}"
	set_make_def_param CFLAGS "${PROFILE_CFLAGS}"
	set_make_def_param FLINKFLAGS "${PROFILE_FLINKFLAGS}"
	set_make_def_param CLINKFLAGS "${PROFILE_CLINKFLAGS}"
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

maqao_mode_args() {
	local mode="$1"
	case "${mode}" in
		normal)
			echo "-R1"
			;;
		stability)
			echo "-S1"
			;;
		scalability)
			echo "-R1 -WS"
			;;
		*)
			echo ""
			;;
	esac
}

extract_metric() {
	local csv_file="$1"
	local metric="$2"
	awk -F';' -v m="${metric}" '$1 == m {gsub(/^"+|"+$/, "", $3); print $3; exit}' "${csv_file}"
}

init_summary_csv() {
	if [[ ! -f "${SUMMARY_CSV}" ]]; then
		echo "label,compiler,profile,mode,nprocs,status,profiled_time,application_time,user_time,loops_time,speedup_if_fully_vectorised,speedup_if_fp_vect,array_access_efficiency,compilation_options,xp_dir" > "${SUMMARY_CSV}"
	fi

	if [[ ! -f "${RUNTIME_CSV}" ]]; then
		echo "label,compiler,profile,nprocs,status,elapsed_wall,max_rss_kb,stdout_log,stderr_log" > "${RUNTIME_CSV}"
	fi

	mkdir -p "${RUNTIME_DIR}"
}

append_summary_csv() {
	local label="$1"
	local compiler="$2"
	local profile="$3"
	local mode="$4"
	local nprocs="$5"
	local status="$6"
	local xp_dir="$7"
	local metrics_file="${xp_dir}/shared/run_0/global_metrics.csv"

	local profiled_time="NA"
	local application_time="NA"
	local user_time="NA"
	local loops_time="NA"
	local speedup_fully_vect="NA"
	local speedup_fp_vect="NA"
	local array_access_efficiency="NA"
	local compilation_options="NA"

	if [[ -f "${metrics_file}" ]]; then
		profiled_time="$(extract_metric "${metrics_file}" "profiled_time")"
		application_time="$(extract_metric "${metrics_file}" "application_time")"
		user_time="$(extract_metric "${metrics_file}" "user_time")"
		loops_time="$(extract_metric "${metrics_file}" "loops_time")"
		speedup_fully_vect="$(extract_metric "${metrics_file}" "speedup_if_fully_vectorised")"
		speedup_fp_vect="$(extract_metric "${metrics_file}" "speedup_if_fp_vect")"
		array_access_efficiency="$(extract_metric "${metrics_file}" "array_access_efficiency")"
		compilation_options="$(extract_metric "${metrics_file}" "compilation_options")"
	fi

	echo "${label},${compiler},${profile},${mode},${nprocs},${status},${profiled_time},${application_time},${user_time},${loops_time},${speedup_fully_vect},${speedup_fp_vect},${array_access_efficiency},${compilation_options},${xp_dir}" >> "${SUMMARY_CSV}"
}

append_runtime_csv() {
	local label="$1"
	local compiler="$2"
	local profile="$3"
	local nprocs="$4"
	local status="$5"
	local elapsed="$6"
	local max_rss="$7"
	local out_log="$8"
	local err_log="$9"

	echo "${label},${compiler},${profile},${nprocs},${status},\"${elapsed}\",${max_rss},${out_log},${err_log}" >> "${RUNTIME_CSV}"
}

run_plain_timing() {
	local label="$1"
	local compiler="$2"
	local profile="$3"
	local nprocs="$4"
	local exe="$5"

	local launcher
	launcher="$(resolve_mpi_launcher "${nprocs}")"
	if [[ -z "${launcher}" ]]; then
		append_runtime_csv "${label}" "${compiler}" "${profile}" "${nprocs}" "FAIL" "NA" "NA" "NA" "NA"
		return 1
	fi

	local out_log="${RUNTIME_DIR}/run_${label}_${compiler}_${profile}.out"
	local err_log="${RUNTIME_DIR}/run_${label}_${compiler}_${profile}.err"

	if /usr/bin/time -v bash -lc "${launcher} ${exe}" >"${out_log}" 2>"${err_log}"; then
		local elapsed
		local max_rss
		elapsed=$(awk -F': ' '/Elapsed \(wall clock\) time/ {print $2; exit}' "${err_log}")
		max_rss=$(awk -F': ' '/Maximum resident set size/ {print $2; exit}' "${err_log}")
		append_runtime_csv "${label}" "${compiler}" "${profile}" "${nprocs}" "OK" "${elapsed:-NA}" "${max_rss:-NA}" "${out_log}" "${err_log}"
		return 0
	fi

	local elapsed
	local max_rss
	elapsed=$(awk -F': ' '/Elapsed \(wall clock\) time/ {print $2; exit}' "${err_log}")
	max_rss=$(awk -F': ' '/Maximum resident set size/ {print $2; exit}' "${err_log}")
	append_runtime_csv "${label}" "${compiler}" "${profile}" "${nprocs}" "FAIL" "${elapsed:-NA}" "${max_rss:-NA}" "${out_log}" "${err_log}"
	return 1
}

run_oneview() {
	local label="$1"
	local compiler="$2"
	local profile="$3"
	local mode="$4"
	local nprocs="$5"
	local exe="$6"

	local launcher
	launcher="$(resolve_mpi_launcher "${nprocs}")"
	if [[ -z "${launcher}" ]]; then
		append_summary_csv "${label}" "${compiler}" "${profile}" "${mode}" "${nprocs}" "FAIL" "NA"
		return 1
	fi

	local mode_args
	mode_args="$(maqao_mode_args "${mode}")"
	if [[ -z "${mode_args}" ]]; then
		append_summary_csv "${label}" "${compiler}" "${profile}" "${mode}" "${nprocs}" "FAIL" "NA"
		return 1
	fi

	local xp="maqao_oneview_xp_${BENCHMARK}_${CLASS}_${label}_${compiler}_${profile}_${mode}"
	rm -rf "${xp}"

	if maqao oneview ${mode_args} xp="${xp}" --mpi-command="${launcher}" -- "${exe}"; then
		append_summary_csv "${label}" "${compiler}" "${profile}" "${mode}" "${nprocs}" "OK" "${ROOT_DIR}/${xp}"
		return 0
	fi

	append_summary_csv "${label}" "${compiler}" "${profile}" "${mode}" "${nprocs}" "FAIL" "${ROOT_DIR}/${xp}"
	return 1
}

run_campaign() {
	cd "${ROOT_DIR}"
	ensure_project_layout
	load_tools
	init_summary_csv

	local failed=0
	IFS=',' read -r -a flag_array <<< "${FLAG_PROFILES}"
	IFS=',' read -r -a compiler_array <<< "${COMPILERS}"
	IFS=',' read -r -a profile_array <<< "${PROFILES}"
	IFS=',' read -r -a mode_array <<< "${MAQAO_MODES}"

	for flag_profile in "${flag_array[@]}"; do
		for compiler in "${compiler_array[@]}"; do
			if ! command -v "${compiler}" >/dev/null 2>&1; then
				echo "Compilateur indisponible: ${compiler} (skip)"
				continue
			fi

			echo "=== Compilation ${BENCHMARK}.${CLASS} avec ${compiler} (${flag_profile}) ==="
			if ! configure_make_def_for_compiler "${compiler}" "${flag_profile}"; then
				failed=$((failed + 1))
				continue
			fi

			make clean
			mkdir -p bin
			if ! make "${BENCHMARK}" "CLASS=${CLASS}" F08=def; then
				echo "Echec compilation avec ${compiler} (${flag_profile})" >&2
				failed=$((failed + 1))
				continue
			fi

			local exe="./bin/${BENCHMARK}.${CLASS}.x"
			if [[ ! -x "${exe}" ]]; then
				echo "Binaire introuvable après compilation ${compiler}/${flag_profile}: ${exe}" >&2
				failed=$((failed + 1))
				continue
			fi

			for profile in "${profile_array[@]}"; do
				local nprocs="${PAR_NTASKS}"
				if [[ "${profile}" == "seq" ]]; then
					nprocs="${SEQ_NTASKS}"
				fi

				if ! run_plain_timing "${flag_profile}" "${compiler}" "${profile}" "${nprocs}" "${exe}"; then
					failed=$((failed + 1))
				fi

				for mode in "${mode_array[@]}"; do
					if ! run_oneview "${flag_profile}" "${compiler}" "${profile}" "${mode}" "${nprocs}" "${exe}"; then
						failed=$((failed + 1))
					fi
				done
			done
		done
	done

	echo "Résumé MAQAO: ${SUMMARY_CSV}"
	echo "Résumé temps/RAM: ${RUNTIME_CSV}"

	if [[ ${failed} -gt 0 ]]; then
		echo "${failed} exécution(s) en échec (voir logs)." >&2
		return 1
	fi
}

submit_campaign() {
	cd "${ROOT_DIR}"
	ensure_project_layout
	unset SBATCH_DEPENDENCY || true

	local job_name="npb_${BENCHMARK}_${CLASS}_flags_campaign"
	local output_file="${BENCHMARK}_${CLASS}_flags_campaign.%j.out"
	local error_file="${BENCHMARK}_${CLASS}_flags_campaign.%j.err"

	local -a sbatch_cmd
	sbatch_cmd=(sbatch --parsable
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
		--export=ALL,RUN_CAMPAIGN=1
		"${SCRIPT_PATH}")

	if [[ -n "${PARTITION}" ]]; then
		sbatch_cmd=(sbatch --parsable
			--account="${ACCOUNT}"
			--partition="${PARTITION}"
			--time="${WALLTIME}"
			--mem="${MEM}"
			--nodes="${NODES}"
			--constraint="${CONSTRAINT}"
			--ntasks="${NTASKS}"
			--cpus-per-task="${CPUS_PER_TASK}"
			--job-name="${job_name}"
			--output="${output_file}"
			--error="${error_file}"
			--export=ALL,RUN_CAMPAIGN=1
			"${SCRIPT_PATH}")
	fi

	local job_id
	job_id=$("${sbatch_cmd[@]}")
	echo "Soumis ${job_name} -> job ${job_id}"
	echo "Campagne soumise."
}

if [[ "${RUN_CAMPAIGN:-0}" == "1" ]]; then
	run_campaign
elif [[ -n "${SLURM_JOB_ID:-}" ]]; then
	run_campaign
else
	submit_campaign
fi

