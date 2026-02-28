#!/bin/bash




#SBATCH --account="r250142"
#SBATCH --time=10:00
#SBATCH --mem=10G
#SBATCH --nodes=1
#SBATCH --constraint=x64cpu
#SBATCH --ntasks=16
#SBATCH --cpus-per-task=1
#SBATCH --error=ft.%J.err
#SBATCH --output=ft.%J.out

romeo_load_x64cpu_env

spack load openmpi@4.1.7%aocc || spack load openmpi || true
spack load maqao@2025.1.4%aocc || spack load maqao || true

make clean
mkdir -p bin
make ft CLASS=C

MPI_LAUNCHER=""
if command -v mpirun >/dev/null 2>&1; then
	MPI_LAUNCHER="mpirun -np ${SLURM_NTASKS}"
elif command -v mpiexec >/dev/null 2>&1; then
	MPI_LAUNCHER="mpiexec -n ${SLURM_NTASKS}"
elif command -v srun >/dev/null 2>&1; then
	MPI_LAUNCHER="srun -n ${SLURM_NTASKS}"
else
	echo "Erreur: aucun lanceur MPI trouvé (mpirun/mpiexec/srun)."
	exit 1
fi

maqao oneview -R1 xp=maqao_oneview_xp_ft_C --mpi-command="${MPI_LAUNCHER}" -- ./bin/ft.C.x

# mpirun -np "${SLURM_NTASKS}" ./bin/ft.C.x

