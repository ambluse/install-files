#!/bin/sh
check_base()
{
    which mysql
    [ $? -ne 0 ] && msg="No mysql,please install mysql rpm" ; echo "$msg" ; 
    which mysqld_safe
    [ $? -ne 0 ] && msg="No mysqld_safe,please install mysql rpm" ; echo "$msg" ; 
    mynum=`ps -ef|grep mysqld|grep data|grep $port|grep -v grep |wc -l`
    [ $mynum -gt 0 ] && msg="have this port mysql pid" ; echo "$msg" ; 
    [ `hostname`=$hostname ] && msg="hostname not equal,?? run on wrong host?" ; echo "$msg" ; 
}

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
                 msg="ERROR: cannot parse innodb buffer pool size in /u01/${folder}/my.cnf"
                 echo "$msg" ; 
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
        msg="ERROR: cannot parse innodb buffer pool size in input parameter"
        echo "$msg" ; 
        exit 5
    fi

    memavail=`free -m | grep -i "Mem" | awk '{print $2}'`
    memavail=`echo "scale=0;${memavail}/1.25" | bc`
    if [ ${memsum} -gt ${memavail} ]; then
         msg="ERROR: memory (${memsum}/${memavail}) is not enough for new instance, quit"
         echo "$msg" ; 
        pass=0
    else
        pass=1
    fi
}
my_context()
{
    hostip=`hostname -i`
    a=`echo $hostip|cut -d\. -f1`
    b=`echo $hostip|cut -d\. -f2`
    c=`echo $hostip|cut -d\. -f3`
    d=`echo $hostip|cut -d\. -f4`
    server_id=`expr \( ${a} \* 256 \* 256 \* 256 + ${b} \* 256 \* 256 + ${c} \* 256 + ${d} \)`
    server_id=$((${server_id} << 6))
    server_id=`expr ${server_id} +  \( ${port} % 64 \)`
    server_id=`expr ${server_id} % 4294967296`

    cat $1 | sed "s#PORT#${port}#g"                                                      > /tmp/my${port}.cnf.temp1
    cat /tmp/my${port}.cnf.temp1 | sed "s#INNODB_BUFFER_POOL_SIZE#${innodb_buffer_pool_size}#g" > /tmp/my${port}.cnf.temp2
    cat /tmp/my${port}.cnf.temp2 | sed "s#THREADBY4#16#g"             > /tmp/my${port}.cnf.temp3
    cat /tmp/my${port}.cnf.temp3 | sed "s#INNODB_IO_CAPACITY#1000#g"           > /tmp/my${port}.cnf.temp4
    cat /tmp/my${port}.cnf.temp4 | sed "s#SERVER_ID#${server_id}#g"                             > /tmp/my${port}.cnf.temp5 #if not a number?
    cat /tmp/my${port}.cnf.temp5 | sed "s#THREAD#8#g"                                > /tmp/my${port}.cnf.result
}


check_db_test(){
    $MYSQL -P${port} -e "create database wx_test_d5;"
    dbsnum=`$MYSQL -P${port} -e "show databases like 'wx_test_d5';"|wc -l`
    $MYSQL -P${port} -e "drop database wx_test_d5;"
}


init_instance()
{
    #Init MySQL folder based on port######################################################
    msg="Init port ${port}" && echo "$msg"
    rm -f /u01/mybase/log/binlog*
    if [ -d /u01/my${port} -o -d /u02/my${port} ]; then
        msg="ERROR: port ${port} has been initialized already!"
        echo "$msg" ; 
    else
        mem_check
        if [ ${pass} -eq 0 ];then
            msg="ERROR: fail to init base folder, quit the whole script"
            echo "$msg" ; 
            exit 6
        fi
        msg="start copy mysql base file on u01"
        echo "$msg"
        cp --preserve -r /u01/mybase /u01/my${port}
        num=`df -lh|grep -i u02|grep -v grep |wc -l`
        if [ $num -gt 0 ]; then
            msg="start copy mysql base file on u02"
            echo "$msg"
            mkdir -p /u02/my${port}
            cp -r /u02/mybase/log /u02/my${port}/log
            rm -rf /u01/my${port}/log
            ln -s /u02/my${port}/log /u01/my${port}/log
        fi
        rm -f /u01/my${port}/log/mysql-bin.00000*
        cat /dev/null >  /u01/my${port}/log/mysql-bin.index 
    fi

    #Generate my.cnf base on port########################################################
    my_context /usr/mysqlmisc/support-files/mybase.cnf
    msg="gen my.cnf ok"
    echo "$msg"
    cp /tmp/my${port}.cnf.result /u01/my${port}/my.cnf
    chmod 644 /u01/my${port}/my.cnf
    chmod 644 /u01/my${port}/log/alert.log
    touch /u01/my${port}/log/slow.log
    chmod 644 /u01/my${port}/log/slow.log
    chown mysql:dba /u01/my${port}/log/slow.log

    #Change owner of new folder, and start MySQL#########################################
    chown -R mysql:dba       /u01/my${port} 
    [ -d /u02/my${port} ] &&   chown -R mysql:dba  /u02/my${port}
    echo | (mysqld_safe --defaults-file=/u01/my${port}/my.cnf --user=mysql --read_only=1  >/dev/null  2>/dev/null  & )
    msg="start mysql $port instance,please waiting"
    echo "$msg"
    sleep 10
    num=`/u01/mysql/bin/mysql -udbadmin -palipswxx -h127.0.0.1 -P${port} -Ns  -e "show databases;"|grep wx64|grep -v grep  |wc -l`
    for i in `seq 1 100`
    do
      /u01/mysql/bin/mysql -udbadmin -palipswxx -h127.0.0.1 -P${port} -Ns  -e "create database wx64"|wc -l
      num=`/u01/mysql/bin/mysql -udbadmin -palipswxx -h127.0.0.1 -P${port} -Ns  -e "show databases;"|grep wx64|grep -v grep  |wc -l`
     if   [ $num -gt 0 ] ;then
        msg="mysqld $port start success"
        echo "$msg" 
        msg="${hostname}:${port} is created"
        echo "$msg" 
        /u01/mysql/bin/mysql -udbadmin -palipswxx -h127.0.0.1 -P${port} -Ns  -e "drop database wx64"
        continue
      fi
      sleep 5
      [ $i -gt 199 ] && msg="mysqld $port can not start " &&  echo "$msg" 
    done
}
! grep -w oinstall /etc/group > /dev/null && /usr/sbin/groupadd -g 510 oinstall && echo "add user group:oinstall"
! grep -w dba /etc/group > /dev/null && /usr/sbin/groupadd -g 501 dba && echo "add user group:dba"
! grep -w admin /etc/group > /dev/null && /usr/sbin/groupadd -g 500 admin && echo "add user group:admin"
! grep -w mysql  /etc/shadow > /dev/null && /usr/sbin/useradd -n -u 502 -g 501 -d /home/mysql -s /bin/bash -p x -m mysql && chown -R mysql:dba /home/mysql && chmod 0755 /home/mysql &&echo "add user:mysql"


oldnum=$1
num=`ps -ef|grep mysqld|grep -v grep |wc -l`
[ $num -gt 0 ] && echo "Have mysql running" && exit 9
mem=`free -g | grep Mem | awk '{ print $2}'`
innodb_buffer_pool_size=`echo $mem*0.79/$oldnum| bc -l | awk -F "." '{ print $1 }'`
innodb_buffer_pool_size="${innodb_buffer_pool_size}G"


for i in `seq 1 $oldnum`
do
  ports=(3306 3406 3506 3606 3401 3402 3403 3404 3405 3407 3408 3409 3410 3411 3412 3412 3413)
  pt_len=${#ports[@]}
  i=0
  while [ $i -lt $pt_len ];
  do
      port=${ports[$i]}
      tag=`ps -ef|grep mysqld|grep $port|grep -v grep|wc -l`
      [ $tag -lt 1 -o  ! -d /u01/my$port ]   && break
      let i+=1
  done
echo $port $innodb_buffer_pool_size
init_instance
done
