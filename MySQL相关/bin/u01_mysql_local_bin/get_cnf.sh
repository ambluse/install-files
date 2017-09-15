#!/bin/bash

if [ "$1" == "" ]; then
    echo "ERROR: input port please!"
    exit 1
else
    PORT=$1
fi

FILE=""
for i in `ps -ef|grep mysqld | grep -v safe | grep ${PORT}`;
do
    if [ `echo ${i} | grep defaults-file | grep -v extra | wc -l` -eq 1 ]; then
         FILE=`echo ${i} | cut -d "=" -f 2 | tr -d " " | tr -d "\n"`
         break
    fi
done

if [ "${FILE}" == "" ]; then
    #echo "cannot get my.cnf location from running process"
    if [ -f /u01/my${PORT}/my.cnf ]; then
        FILE="/u01/my${PORT}/my.cnf"
    elif [ -f /data/mysql${PORT}/my.cnf ]; then
        FILE="/data/mysql${PORT}/my.cnf"
    elif [ -f /etc/my.cnf ]; then
        FILE="/etc/my.cnf"
    fi
fi

if [ "${FILE}" == "" ]; then
    echo "ERROR: my.cnf doesn't exist!"
    exit 2
else
    printf "%s" "${FILE}"
fi
