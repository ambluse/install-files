#!/bin/bash

if [ "$1" == "" -o "$2" == "" ]; then
    echo "ERROR: please imput port and parameter's name"
    exit 1
fi

PORT=$1
PARAMETER=$2

FILE=`get_cnf.sh ${PORT}`
if [ `echo ${FILE} | grep ERROR | wc -l` -gt 0 ]; then
    echo "ERROR: no running instance" 
    exit 2
fi

VALUE=`cat ${FILE} | tr -d " " | grep "^${PARAMETER}=" | cut -d "=" -f 2 | cut -d "#" -f 1 | tr -d " "`
if [ "${VALUE}" == "" ]; then
    echo "ERROR: cannot get value of ${PORT}:${PARAMETER}"
    exit 3
else
    printf "%s" "${VALUE}"
fi
