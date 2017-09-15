#!/bin/bash

if [ "$1" == "" -o "$2" == "" ]; then
    echo "ERROR: please imput port and parameter's name"
    exit 1
fi

PORT=$1
PARAMETER=$2

SOCKET=`get_socket.sh ${PORT}`
if [ `echo ${SOCKET} | grep ERROR | wc -l` -gt 0 ]; then
    echo "ERRO: no running instance"
    exit 2
fi

VALUE=`mysql -udbadmin -palipswxx -S${SOCKET} -e"show global variables like '${PARAMETER}'" | awk 'NR==2 {print $2}' | tr -d "\n"`
if [ "${VALUE}" == "" ]; then
    echo "ERROR: cannot get value of ${PORT}:${PARAMETER}"
    exit 3
else
    printf "%s" "${VALUE}"
fi
