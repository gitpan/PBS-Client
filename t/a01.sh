#!/bin/sh

#PBS -N test1
#PBS -d /tmp
#PBS -e test1.err
#PBS -o test1.out
#PBS -q queue02@server01
#PBS -W x=PARTITION:cluster01
#PBS -A guest
#PBS -l nodes=1
#PBS -l host=node13.abc.com

pwd
