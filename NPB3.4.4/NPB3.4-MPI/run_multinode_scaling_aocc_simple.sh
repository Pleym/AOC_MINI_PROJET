#!/usr/bin/env bash
#SBATCH --account="projet0041"
#SBATCH --time=0-00:20:00
#SBATCH --mem=2G
#SBATCH --constraint=x64cpu
#SBATCH --nodes=128
#SBATCH --cpus-per-task=1
#SBATCH --job-name="NPB_FT_C_scaling"
#SBATCH --error=job.%J.err
#SBATCH --output=job.%J.out

romeo_load_x64cpu_env
spack load openmpi@4.1.7%aocc

PPN=16
NODES_LIST="1 2 4 8 16 32 64 128"

EXE="$SLURM_SUBMIT_DIR/bin/ft.C.x"
OUT_CSV="$SLURM_SUBMIT_DIR/ft_C_scaling_$SLURM_JOB_ID.csv"

echo "nodes,ntasks,time_s,verification" > "$OUT_CSV"

for nodes in $NODES_LIST; do
    ntasks=$((nodes * PPN))
    srun -N "$nodes" -n "$ntasks" "$EXE" > run_N${nodes}.out

    time_s=$(awk '/Time in seconds/ {print $NF}' run_N${nodes}.out | tail -1)
    grep -q "Verification.*SUCCESSFUL" run_N${nodes}.out && verif="SUCCESS" || verif="FAIL"

    echo "$nodes,$ntasks,$time_s,$verif" >> "$OUT_CSV"
    echo "N=$nodes ntasks=$ntasks t=${time_s}s $verif"
done

echo "Resultats: $OUT_CSV"
