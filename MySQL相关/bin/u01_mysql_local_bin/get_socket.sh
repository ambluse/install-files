#!/bin/bash

if [ "$1" == "" ]; then
    echo "ERROR: input port please!"
    exit 1
else
    PORT=$1
fi

SOCKET=""
for i in `ps -ef|grep mysqld | grep -v safe | grep ${PORT}`;
do
    if [ `echo ${i} | grep socket | wc -l` -eq 1 ]; then
         SOCKET=`echo ${i} | cut -d "=" -f 2 | tr -d " " | tr -d "\n"`
         break
    fi
done

if [ "${SOCKET}" == "" ]; then
    echo "ERROR: socket doesn't exist!"
    exit 2
else
    printf "%s" "${SOCKET}"
fi
