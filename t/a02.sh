#!/bin/sh

#PBS -d /tmp/test
#PBS -q delta
#PBS -p 10
#PBS -l nodes=2:ppn=1
#PBS -l mem=600mb
#PBS -l vmem=1gb
#PBS -l pvmem=100mb
#PBS -l cput=01:30:00
#PBS -l pcput=00:10:00
#PBS -l walltime=00:30:00
#PBS -l nice=5

pwd
