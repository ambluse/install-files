#!/bin/bash
#****************************************************************#
# ScriptName: dbrole.sh
# Author: taofang@alipay.com
# Create Date: 2013-03-28 15:32
# Modify Author: $SHTERM_REAL_USER@alibaba-inc.com
# Modify Date: 2014-04-11 18:00
# Function: set bash prompt for mysql host
#***************************************************************#

#Get Port List and Instance Number##################################
PORTS_INITED=`ls /u01/ | grep -e "my[0-9][0-9]*" | sed 's#my# #g' | tr -d '\n' | sed 's#^ ##g'`
PORTS_RUNNING=`ps -elf | grep mysqld | perl -wn -e 'BEGIN{my @arr;}{ m/datadir=(\S+) .*log-error=(\S+) .*socket=(\S+) .*port=(\S+)/ and push @arr,$4;}END{my @sa = sort @arr; print "@sa"; }'`
NUM_INST=`echo ${PORTS_RUNNING} | awk '{print NF}'`


#Get Value to Show in Promt#########################################
PORT=`echo ${MYSQL_HOME} | sed 's#u01##g' | sed 's#my##g' | tr -d '/'`
RW=`mysql -udbadmin -palipswxx --batch  -e"show global variables like 'read_only'" 2>&1 | tail -1 | awk '{print $2}'`
if [ "${RW}" == "OFF" ]; then
    RW="RW"
elif [ "${RW}" == "ON" ]; then
    RW="RO"
else
    RW="Down"
fi
MYSQL_STATUS="${PORT}-${RW}-${NUM_INST}Inst"


#Alias##############################################################
alias alert="tail -80f $MYSQL_HOME/log/alert.log"
alias a-alert="tail -80f $MYSQL_HOME/log/alert.log"
alias a-logdir="cd $MYSQL_HOME/log"
alias a-datadir="cd $MYSQL_HOME/data"
alias check_hardware="sudo /usr/alisys/dragoon/libexec/monitor/hardware/get_server_hardware.sh"
#alias sql="mysql -udbadmin -palipswxx -P$PORT -A"
alias dbasql="dbasql -P$PORT "
alias a-dbasql="dbasql -P$PORT "
#alias rdsql="rdsql -P$PORT "
alias a-sql="rdsql -P$PORT "
alias a-mysqldump="a-mysqldump -P$PORT "
alias a-mysqladmin="a-mysqladmin -P$PORT "
alias a-dbs="dbs"
alias a-check-hardware="sudo /usr/alisys/dragoon/libexec/monitor/hardware/get_server_hardware.sh"
alias a-raid="sudo tbraid"
alias a-hwconfig="sudo /opt/satools/hwconfig"
alias a-checkssd="sudo /opt/satools/check_ssd.py"
alias a-tbsql="/usr/local/bin/tbsql"
alias a-orzdba="/usr/local/bin/orzdba"
alias a-orztop="/usr/local/bin/orztop"
alias a-relayfetch="/usr/local/bin/relayfetch"
alias a-relayfetch55="/usr/local/bin/relayfetch55"
#ln -sf /usr/local/bin/a-myadm /etc/init.d/mysql
for PORT in ${PORTS_INITED}
do
    alias my${PORT}="export MYSQL_HOME=/u01/my${PORT} && source dbrole.sh"
    #alias a-my${PORT}="export MYSQL_HOME=/u01/my${PORT} && source dbrole.sh"
done


#Show Key Infomation and Define Promt###############################
RED="\e[1;31m"
GREEN="\e[1;32m"
NC="\e[0m"

if [ "${PORTS_INITED}" == "" ]; then
    if [[ $- =~ "i" ]] ;then
        echo "No MySQL has been initiated"
    fi
else
    if [[ $- =~ "i" ]] ;then
        echo "There are $NUM_INST MySQL instance(s) running"
    fi
    if [[ $- =~ "i" ]] ;then
      printf "["
    fi
    for PORT_INITED in ${PORTS_INITED}
    do
        MATCHED=0
        for PORT_RUNNING in ${PORTS_RUNNING}
        do
            if [ "${PORT_INITED}" == "${PORT_RUNNING}" ]; then
                MATCHED=1
                break
            fi
        done

        if [ ${MATCHED} -eq 1 ]; then
            if [[ $- =~ "i" ]] ;then
              printf " ${GREEN}%s${NC}" "${PORT_INITED}"
           fi
        else
            if [[ $- =~ "i" ]] ;then
              printf " ${RED}%s${NC}" "${PORT_INITED}"
            fi
        fi
    done
    if [[ $- =~ "i" ]] ;then
      printf " ]\n"
    fi
fi

if [ "${PORTS_RUNNING}" == "" ]; then
    export PS1="\n\e[1;37m[\e[m\e[1;34mNoMySQL\e[m\e[1;35m@\e[m\e[1;32m\H\e[m \w\e[m\e[1;37m]\e[m\e[1;36m\e[m\n\$"
else
    export PS1="\n\e[1;37m[\e[m\e[1;34m$MYSQL_STATUS\e[m\e[1;35m@\e[m\e[1;32m\H\e[m \w\e[m\e[1;37m]\e[m\e[1;36m\e[m\n\$"
fi
export LD_LIBRARY_PATH=/usr/lib/mysql/:$LD_LIBRARY_PATH
if [[ $- =~ "i" ]] ;then
    echo "Current MySQL Home: $MYSQL_HOME"
fi
