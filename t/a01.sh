#!/bin/sh

#PBS -N test1
#PBS -d /tmp/test
#PBS -e test1.err
#PBS -o test1.out
#PBS -q delta@clc
#PBS -W x=PARTITION:dell
#PBS -A guest
#PBS -l nodes=1
#PBS -l host=delta01.clustertech.com

pwd
