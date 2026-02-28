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

spack load ^openmpi@4.1.7  %aocc

make clean
mkdir -p bin
make ft CLASS=C

mpirun -np "${SLURM_NTASKS}" ./bin/ft.C.x