#!/bin/bash
#****************************************************************#
# ScriptName: safe_mysql_init.sh
# Author: taofang@alipay.com
# Create Date: 2013-02-11 09:11
# Modify Author: taofang@alipay.com
# Modify Date: 2013-03-28 13:23
# Function: Init MySQL data folders and start instances based on port range
#***************************************************************#

#Parameter input and check##################################################################
usage ()
{
cat <<EOF
Usage: $0 [OPTIONS]
  --port_start                Range of port which should be init from       
  --port_end                  Range of port which should be init to
  --innodb_buffer_pool_size   innodb_buffer_pool_size for each new instance    
  --ht_number                 Logical CPU cores assaigned to each new instance
  --innodb_io_capacity        iops assaigned each new instance
EOF

exit 1
}

ARGS=`getopt -o "s:e:b:c:i:x:h" -l "port_start:,port_end:,innodb_buffer_pool_size:,ht_number:,innodb_io_capacity:,binlog_name:,help" -- "$@"`
eval set -- "$ARGS";

while [ 1 ]; 
do
    case "${1}" in
        -s|--port_start)
            port_start=${2}
            shift
            ;;
        -e|--port_end)
            port_end=${2}
            shift
            ;;
        -b|--innodb_buffer_pool_size)
            innodb_buffer_pool_size="${2}"
            shift
            ;;
        -c|--ht_number)
            ht_number="${2}"
            shift
            ;;
        -i|--innodb_io_capacity)
            innodb_io_capacity=${2}
            shift
            ;;
        -x|--binlog_name)
            binlog_name=${2}
            shift
            ;;
        -h|--help)
            usage
            break
            ;;
        --)
            shift
            break
            ;;
    esac
    shift
done

if [ "${port_start}" == "" -o "${port_end}" == "" -o "${innodb_buffer_pool_size}" == "" -o "${ht_number}" == "" -o "${innodb_io_capacity}" == "" ]; then
    echo "ERROR: empty parameter"
    echo "ERROR: quit"
    usage
fi

if [ "${binlog_name}" == "" ]; then
    echo "INFO: default value for binlog name"
    binlog_name="mysql-bin"
fi
innodb_thread_concurrency=`echo "${ht_number}*4"|bc`

#Check OS Env#################################################################################
network_check()
{
   if [ `hostname -i 2>&1 | grep -i "Unknown" | wc -l` -gt 0 ]; then
       echo "ERROR: hostname isn't in /etc/hosts"
       exit 2
   fi
}


#Generate my.cnf##############################################################################
my_context()
{
    hostip=`hostname -i`
    a=`echo $hostip|cut -d\. -f1`
    b=`echo $hostip|cut -d\. -f2`
    c=`echo $hostip|cut -d\. -f3`
    d=`echo $hostip|cut -d\. -f4`
    server_id=`expr \( ${a} \* 256 \* 256 \* 256 + ${b} \* 256 \* 256 + ${c} \* 256 + ${d} \)`
    server_id=$((${server_id} << 6))
    server_id=`expr ${server_id} + \( ${port} % 64 \)`
    server_id=`expr ${server_id} % 4294967296`

    cat $1 | sed "s#log-bin=/u01/myPORT/log/mysql-bin#log-bin=/u01/myPORT/log/${binlog_name}#g"  > /tmp/my.cnf.temp0 
    cat /tmp/my.cnf.temp0 | sed "s#PORT#${port}#g"                                               > /tmp/my.cnf.temp1
    cat /tmp/my.cnf.temp1 | sed "s#INNODB_BUFFER_POOL_SIZE#${innodb_buffer_pool_size}#g"         > /tmp/my.cnf.temp2
    cat /tmp/my.cnf.temp2 | sed "s#THREADBY4#${innodb_thread_concurrency}#g"                     > /tmp/my.cnf.temp3
    cat /tmp/my.cnf.temp3 | sed "s#INNODB_IO_CAPACITY#${innodb_io_capacity}#g"                   > /tmp/my.cnf.temp4
    cat /tmp/my.cnf.temp4 | sed "s#SERVER_ID#${server_id}#g"                                     > /tmp/my.cnf.temp5 #if not a number?
    cat /tmp/my.cnf.temp5 | sed "s#THREAD#${ht_number}#g"                                        > /tmp/my.cnf.result
}

#Check MySQL memory usage###################################################################
mem_check()
{
    memsum=0 #MB
    pass=0
    for folder in `ls /u01 | grep my`
    do
        if [ -f /u01/${folder}/my.cnf ]; then
            mem=`grep -i "innodb_buffer_pool_size" /u01/${folder}/my.cnf | cut -d "#" -f 1 | cut -d "=" -f 2 | tr A-Z a-z | sed "s# ##g" | sed "s#b##g"`
            if [ `echo ${mem} | grep g | wc -l` -eq 1 ]; then
                mem=`echo ${mem} | cut -d "g" -f 1` #GB
                memsum=`echo ${memsum}+${mem}*1024 | bc`
            elif [ `echo ${mem} | grep m | wc -l` -eq 1 ]; then
                mem=`echo ${mem} | cut -d "m" -f 1` #MB
                memsum=`echo ${memsum}+${mem} | bc`
            else
                echo "ERROR: cannot parse innodb buffer pool size in /u01/${folder}/my.cnf"
                exit 4
            fi
        fi
    done
    
    mem=`echo ${innodb_buffer_pool_size} | cut -d "#" -f 1 | cut -d "=" -f 2 | tr A-Z a-z | sed "s# ##g" | sed "s#b##g"`
    if [ `echo ${mem} | grep g | wc -l` -eq 1 ]; then
        mem=`echo ${mem} | cut -d "g" -f 1` #GB
        memsum=`echo ${memsum}+${mem}*1024 | bc`
    elif [ `echo ${mem} | grep m | wc -l` -eq 1 ]; then
        mem=`echo ${mem} | cut -d "m" -f 1` #MB
        memsum=`echo ${memsum}+${mem} | bc`
    else
        echo "ERROR: cannot parse innodb buffer pool size in input parameter"
        exit 5
    fi

    memavail=`free -m | grep -i "Mem" | awk '{print $2}'`
    memavail=`echo "scale=0;${memavail}/1.25" | bc`
    if [ ${memsum} -gt ${memavail} ]; then
        echo "ERROR: memory (${memsum}/${memavail}) is not enough for new instance, quit"
        pass=0
    else
        pass=1
    fi
}


#Main#######################################################################################
network_check

#Init MySQL base folder if not exist########################################################
if [ -d /u01/mybase -o -d /u02/mybase ]; then
    echo "INFO: MySQL base folder has been initialized"
else
    #Init MySQL base folder#################################################################
    echo "Init MySQL base folder"
    if [ -f /usr/mysqlmisc/scripts/mysql_install_db ]; then
        #Init MySQL base folder
        echo "MySQL base folder doesn't exist, making one"
        mem_check
        if [ ${pass} -eq 0 ];then
            echo "ERROR: fail to init base folder, quit the whole script"
            exit 6
        fi

        mkdir -p /u01/mybase/data /u01/mybase/run /u01/mybase/tmp
        if [ -d /u02 ]; then
            mkdir -p /u02/mybase/log/iblog
            ln -s /u02/mybase/log /u01/mybase/log
        else
            mkdir -p /u01/mybase/log/iblog
        fi
        
        port="base"
        my_context /usr/mysqlmisc/support-files/mybase.cnf
        cat /tmp/my.cnf.result | sed "s#port=base#port=9833#g" > /u01/mybase/my.cnf
        /usr/mysqlmisc/scripts/mysql_install_db --defaults-file=/u01/mybase/my.cnf --basedir=/usr
    else
        echo "ERROR: please install MySQL first"
        exit 3 
    fi

    chown -R mysql:dba       /u01/mybase /u02/mybase
    echo | (mysqld_safe --defaults-file=/u01/mybase/my.cnf --user=mysql  --read_only &)

    #check mybase status
    while [ 1 ]
    do
        success=`mysql -uroot -S/u01/mybase/run/mysql.sock -e"select 'okay'" 2>&1 | grep 'okay' | wc -l`
        if [ ${success} -gt 0 ]; then
            echo "INFO: MySQL base folder has been initialized"
            break
        else
            echo "INFO: initializing MySQL base folder ......"
            sleep 5
        fi
    done

      #Add ali MySQL users#####################################################################
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select on *.* to 'tbsearch'@'172.23.105.1' IDENTIFIED BY PASSWORD '*8113659E2ED214D15F24FF2E2B38ED87EB7BED2A';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select on *.* to 'tbsearch'@'172.19.70.86' IDENTIFIED BY PASSWORD '*8113659E2ED214D15F24FF2E2B38ED87EB7BED2A';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant process,show databases,replication client,select on *.* to monitor@'172.23.110.33' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant process,show databases,replication client,select on *.* to monitor@'172.19.70.68' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant super,process,show databases,replication client,select on *.* to monitor@'127.0.0.1' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant super,process,show databases,replication client,select on *.* to monitor@'localhost' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant super,process,show databases,replication client,select on *.* to monitor@'172.23.110.200' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"GRANT SELECT,Process ON *.* TO 'dbaread'@'localhost' IDENTIFIED BY PASSWORD '*BABF041BF438C5E3595115B0D59BB1DB707F7985'"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select on mysql.* to monitor@'172.23.110.200' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"          
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant REPLICATION SLAVE,REPLICATION CLIENT,PROCESS, SHOW DATABASES on *.* to 'slave'@'%' IDENTIFIED BY PASSWORD '*51125B3597BEE0FC43E0BCBFEE002EF8641B44CF';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant REPLICATION SLAVE,REPLICATION CLIENT,PROCESS, SHOW DATABASES on *.* to 'slave'@'127.0.0.1' IDENTIFIED BY PASSWORD '*51125B3597BEE0FC43E0BCBFEE002EF8641B44CF';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select on *.* to 'tbsearch'@'172.22.2.91' IDENTIFIED BY PASSWORD '*8113659E2ED214D15F24FF2E2B38ED87EB7BED2A';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select on *.* to 'tbsearch'@'172.22.2.92' IDENTIFIED BY PASSWORD '*8113659E2ED214D15F24FF2E2B38ED87EB7BED2A';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"GRANT SELECT ON *.* TO 'idb_rnd'@'172.22.2.91' IDENTIFIED BY PASSWORD '*B56147DF2013D826EAB598FDFD5C45B34FA50F6E'"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"GRANT SELECT ON *.* TO 'idb_rnd'@'172.22.2.92' IDENTIFIED BY PASSWORD '*B56147DF2013D826EAB598FDFD5C45B34FA50F6E'"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select on *.* to 'tbsearch'@'172.23.100.17' IDENTIFIED BY PASSWORD '*8113659E2ED214D15F24FF2E2B38ED87EB7BED2A';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select on *.* to 'tbsearch'@'172.23.110.108' IDENTIFIED BY PASSWORD '*8113659E2ED214D15F24FF2E2B38ED87EB7BED2A';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select on *.* to 'tbsearch'@'172.19.70.108' IDENTIFIED BY PASSWORD '*8113659E2ED214D15F24FF2E2B38ED87EB7BED2A';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"GRANT SELECT, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'tbdw'@'%' IDENTIFIED BY PASSWORD '*743E7A752733E988BEE879F23004F727AFAF5A12'"
  
      #Add alipay MySQL users################################################################
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant all privileges on *.* to dbadmin@'localhost' IDENTIFIED BY PASSWORD '*0C3A6A26A43FECD19F8521DD56FEC2221B8A7609' WITH GRANT OPTION;"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant all privileges on *.* to dbadmin@'127.0.0.1' IDENTIFIED BY PASSWORD '*0C3A6A26A43FECD19F8521DD56FEC2221B8A7609' WITH GRANT OPTION;"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant REPLICATION SLAVE,REPLICATION CLIENT ON *.* TO 'repl'@'%' IDENTIFIED BY PASSWORD '*DE72B1A664B095CB45850A196F908CCD2B32FB03';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant SELECT,CREATE,DROP,PROCESS,FILE,INDEX,ALTER,SUPER,LOCK TABLES ON *.* TO 'maintain'@'10.225.36.187' IDENTIFIED BY PASSWORD '*C499CB77612AFE53B42B834EC9A00F0B5CD48747';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant SELECT,CREATE,DROP,PROCESS,FILE,INDEX,ALTER,SUPER,LOCK TABLES ON *.* TO 'maintain'@'10.228.86.27' IDENTIFIED BY PASSWORD '*C499CB77612AFE53B42B834EC9A00F0B5CD48747';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select on *.* to opsdba@'%' IDENTIFIED BY PASSWORD '*A17E627E4C1E1C140C67617478792A7625A8F0C0';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select,REPLICATION SLAVE,REPLICATION CLIENT on *.* to dwexp@'%' IDENTIFIED BY PASSWORD '*DBCE0907FBC167675EC61823F09C09F69A3E6B9A';"
  
      #Delete useless users#################################################################
      host=`hostname`
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"delete from mysql.user where host='${host}'"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"delete from mysql.user where user='';"
  
      #Make users available#################################################################
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"flush privileges"

    #Make sure MySQL base folder is not able for running again############################
    mysqladmin shutdown -uroot -S /u01/mybase/run/mysql.sock 
    rm -f /u01/mybase/my.cnf
    rm -f /u01/mybase/log/binlog*
fi


#Init MySQL folders if not exist##########################################################
for port in `seq ${port_start} 1 ${port_end}`
do
    #Init MySQL folder based on port######################################################
    echo "INFO: init port ${port}"
    rm -f /u01/mybase/my.cnf
    rm -f /u01/mybase/log/binlog*
    if [ -d /u01/my${port} -o -d /u02/my${port} ]; then
        echo "ERROR: port ${port} has been initialized already!"
        continue
    else
        mem_check
        if [ ${pass} -eq 0 ];then
            echo "ERROR: fail to init port ${port}, quit"
            exit 6
        fi
        cp --preserve -r /u01/mybase /u01/my${port}
        if [ -d /u02 ]; then
            mkdir -p /u02/my${port}
            cp -r /u02/mybase/log /u02/my${port}/log
            rm -rf /u01/my${port}/log
            ln -s /u02/my${port}/log /u01/my${port}/log
        fi
    fi

    #Generate my.cnf base on port########################################################
    my_context /usr/mysqlmisc/support-files/mybase.cnf
    cp /tmp/my.cnf.result /u01/my${port}/my.cnf

    #Change owner of new folder, and start MySQL#########################################
    chown -R mysql:dba       /u01/my${port} /u02/my${port}
    echo | (mysqld_safe --defaults-file=/u01/my${port}/my.cnf --user=mysql  --read-only=1 &)
    sleep 10
done


#Detect MySQL status here





