#/bin/sh
#create by weixi@2013-04-22
#
#copy from taofang's safe_mysql_init.sh
set -e
innodb_buffer_pool_size=1G
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
my_context()
{    test -e /u01/mysql/lib/libjemalloc.so && sed -i  's%\(^##*\)\(.*malloc-lib=/u01/mysql/lib/libjemalloc.so\)%\2%' $1
    hostip=`hostname -i`
    a=`echo $hostip|cut -d\. -f1`
    b=`echo $hostip|cut -d\. -f2`
    c=`echo $hostip|cut -d\. -f3`
    d=`echo $hostip|cut -d\. -f4`
    server_id=`expr \( ${a} \* 256 \* 256 \* 256 + ${b} \* 256 \* 256 + ${c} \* 256 + ${d} \)`
    server_id=$((${server_id} << 6))
    server_id=`expr ${server_id} + \( 9833 % 64 \)`
    server_id=`expr ${server_id} % 4294967296`

    cat $1 | sed "s#PORT#${port}#g"                                                      > /tmp/my.cnf.temp1
    cat /tmp/my.cnf.temp1 | sed "s#INNODB_BUFFER_POOL_SIZE#${innodb_buffer_pool_size}#g" > /tmp/my.cnf.temp2
    cat /tmp/my.cnf.temp2 | sed "s#THREADBY4#16#g"             > /tmp/my.cnf.temp3
    cat /tmp/my.cnf.temp3 | sed "s#INNODB_IO_CAPACITY#600#g"           > /tmp/my.cnf.temp4
    cat /tmp/my.cnf.temp4 | sed "s#SERVER_ID#${server_id}#g"                             > /tmp/my.cnf.temp5 #if not a number?
    cat /tmp/my.cnf.temp5 | sed "s#THREAD#8#g"                                > /tmp/my.cnf.result
}


mybase_init()
{
    if [ -d /u01/mybase -o -d /u02/mybase ]; then
    echo "MySQL base folder has been initialized"
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
          num=`df -lh|grep u02|grep -v grep|wc -l`
          if [ $num -gt 0 ]; then
              mkdir -p /u02/mybase/log/
              ln -s /u02/mybase/log /u01/mybase/log
          else
              mkdir -p /u01/mybase/log/
          fi
          
          port="base"
          my_context /usr/mysqlmisc/support-files/mybase.cnf
          cat /tmp/my.cnf.result | sed "s#port=base#port=9833#g" > /u01/mybase/my.cnf
          cp -rpf /u01/mysql/mysqlmisc/support-files/ /u01/mysql/mysqlmisc/scripts/ /u01/mysql/
          /usr/mysqlmisc/scripts/mysql_install_db  --defaults-file=/u01/mybase/my.cnf  --basedir=/u01/mysql  --datadir=/u01/mybase/data/
          #/usr/mysqlmisc/scripts/mysql_install_db --defaults-file=/u01/mybase/my.cnf --basedir=/usr
      else
          echo "ERROR: please install MySQL first"
          exit 3 
      fi
  
      chown -R mysql:dba       /u01/mybase 
      [ -d /u02/mybase  ] &&   chown -R mysql:dba /u02/mybase
      echo | (mysqld_safe --defaults-file=/u01/mybase/my.cnf --user=mysql  &)
      num=`tail -n 5 /u01/mybase/log/alert.log|grep 'Source distribution'|grep -v grep |wc -l`
      while [ $num -lt 1 ];
      do
        num=`tail -n 5 /u01/mybase/log/alert.log|grep 'Source distribution'|grep -v grep |wc -l`
        sleep 5
      done
      chmod 744 /u01/mybase/log/alert.log

      #sleep 300 #we canmake it faster, use while to detect MySQL status
  
      #Add ali MySQL users#####################################################################
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select on *.* to 'tbsearch'@'172.23.105.1' IDENTIFIED BY PASSWORD '*8113659E2ED214D15F24FF2E2B38ED87EB7BED2A';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select on *.* to 'tbsearch'@'172.19.70.86' IDENTIFIED BY PASSWORD '*8113659E2ED214D15F24FF2E2B38ED87EB7BED2A';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select on *.* to 'tbsearch'@'172.22.2.91' IDENTIFIED BY PASSWORD '*8113659E2ED214D15F24FF2E2B38ED87EB7BED2A';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select on *.* to 'tbsearch'@'172.22.2.92' IDENTIFIED BY PASSWORD '*8113659E2ED214D15F24FF2E2B38ED87EB7BED2A';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"GRANT SELECT ON *.* TO 'idb_rnd'@'172.22.2.91' IDENTIFIED BY PASSWORD '*B56147DF2013D826EAB598FDFD5C45B34FA50F6E'"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"GRANT SELECT ON *.* TO 'idb_rnd'@'172.22.2.92' IDENTIFIED BY PASSWORD '*B56147DF2013D826EAB598FDFD5C45B34FA50F6E'"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select on *.* to 'tbsearch'@'172.23.100.17' IDENTIFIED BY PASSWORD '*8113659E2ED214D15F24FF2E2B38ED87EB7BED2A';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select on *.* to 'tbsearch'@'172.23.110.108' IDENTIFIED BY PASSWORD '*8113659E2ED214D15F24FF2E2B38ED87EB7BED2A';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select on *.* to 'tbsearch'@'172.19.70.108' IDENTIFIED BY PASSWORD '*8113659E2ED214D15F24FF2E2B38ED87EB7BED2A';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant process,show databases,replication client,select on *.* to monitor@'172.23.110.33' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant process,show databases,replication client,select on *.* to monitor@'172.19.70.68' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant super,process,show databases,replication client,select on *.* to monitor@'127.0.0.1' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot  -S /u01/mybase/run/mysql.sock -e"grant super,process,show databases,replication client,select on *.* to monitor@'172.24.102.70' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot  -S /u01/mybase/run/mysql.sock -e"grant super,process,show databases,replication client,select on *.* to monitor@'10.246.160.142' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot  -S /u01/mybase/run/mysql.sock -e"grant super,process,show databases,replication client,select on *.* to monitor@'172.23.100.117' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot  -S /u01/mybase/run/mysql.sock -e"grant super,process,show databases,replication client,select on *.* to monitor@'172.24.64.172' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot  -S /u01/mybase/run/mysql.sock -e"grant super,process,show databases,replication client,select on *.* to monitor@'172.23.110.75' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot  -S /u01/mybase/run/mysql.sock -e"grant super,process,show databases,replication client,select on *.* to monitor@'172.24.64.57' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot  -S /u01/mybase/run/mysql.sock -e"grant super,process,show databases,replication client,select on *.* to monitor@'172.23.110.172' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot  -S /u01/mybase/run/mysql.sock -e"grant super,process,show databases,replication client,select on *.* to monitor@'10.246.160.21' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot  -S /u01/mybase/run/mysql.sock -e"grant super,process,show databases,replication client,select on *.* to monitor@'10.246.160.50' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant super,process,show databases,replication client,select on *.* to monitor@'localhost' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant super,process,show databases,replication client,select on *.* to monitor@'172.23.110.200' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select on mysql.* to monitor@'172.23.110.200' IDENTIFIED BY PASSWORD '*865607513D6B8004B2C239C58FEB627832BD9F4E' ;"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"GRANT SELECT,Process,Show databases ON *.* TO 'dbaread'@'localhost' IDENTIFIED BY PASSWORD '*BABF041BF438C5E3595115B0D59BB1DB707F7985'"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"GRANT SELECT,Process,Show databases ON *.* TO 'dbaread'@'127.0.0.1' IDENTIFIED BY PASSWORD '*BABF041BF438C5E3595115B0D59BB1DB707F7985'"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant REPLICATION SLAVE,REPLICATION CLIENT,PROCESS, SHOW DATABASES on *.* to 'slave'@'%' IDENTIFIED BY  'slave';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant REPLICATION SLAVE,REPLICATION CLIENT,PROCESS, SHOW DATABASES on *.* to 'slave'@'127.0.0.1' IDENTIFIED BY  'slave';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"GRANT SELECT, REPLICATION SLAVE, REPLICATION CLIENT ON *.* TO 'tbdw'@'%' IDENTIFIED BY PASSWORD '*743E7A752733E988BEE879F23004F727AFAF5A12'"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"GRANT SELECT, SUPER, REPLICATION SLAVE, REPLICATION CLIENT, SHOW VIEW ON *.* TO 'drc'@'%' IDENTIFIED BY PASSWORD '*78AB260B4B8CE07F3B74DE91EBE4A9990F83FBD5';"
  
      #Add alipay MySQL users################################################################
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant all privileges on *.* to dbadmin@'localhost' IDENTIFIED BY PASSWORD '*0C3A6A26A43FECD19F8521DD56FEC2221B8A7609' WITH GRANT OPTION;"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant all privileges on *.* to dbadmin@'127.0.0.1' IDENTIFIED BY PASSWORD '*0C3A6A26A43FECD19F8521DD56FEC2221B8A7609' WITH GRANT OPTION;"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant REPLICATION SLAVE,REPLICATION CLIENT ON *.* TO 'repl'@'%' IDENTIFIED BY PASSWORD '*DE72B1A664B095CB45850A196F908CCD2B32FB03';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant SELECT,CREATE,DROP,PROCESS,FILE,INDEX,ALTER,SUPER,LOCK TABLES ON *.* TO 'maintain'@'10.225.36.187' IDENTIFIED BY PASSWORD '*C499CB77612AFE53B42B834EC9A00F0B5CD48747';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant SELECT,CREATE,DROP,PROCESS,FILE,INDEX,ALTER,SUPER,LOCK TABLES ON *.* TO 'maintain'@'10.228.86.27' IDENTIFIED BY PASSWORD '*C499CB77612AFE53B42B834EC9A00F0B5CD48747';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select on *.* to opsdba@'%' IDENTIFIED BY PASSWORD '*A17E627E4C1E1C140C67617478792A7625A8F0C0';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select,REPLICATION SLAVE,REPLICATION CLIENT on *.* to dwexp@'%' IDENTIFIED BY PASSWORD '*DBCE0907FBC167675EC61823F09C09F69A3E6B9A';"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"CREATE TABLE IF NOT EXISTS test.heartbeat (id smallint(6) NOT NULL,ts int(11) DEFAULT NULL,PRIMARY KEY (id) ) ENGINE=InnoDB DEFAULT CHARSET=gbk;"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"replace into test.heartbeat ( id ,ts) values (1,1);"
      #Delete useless users#################################################################
      host=`hostname`
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"delete from mysql.user where host='${host}'"
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"delete from mysql.user where user='';"
      if   hostname | grep "sqa" > /dev/null  ;then
        mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select,super,replication client,process on *.* to monitor@'10.232.31.167' identified by 'monitor';"
        mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select,super,replication client,process on *.* to monitor@'10.232.31.221' identified by 'monitor';"
        mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant select,super,replication client,process on *.* to monitor@'localhost' identified by 'monitor';"
        mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant super,process, show databases,replication client,select on *.* to monitor@'127.0.0.1' identified by 'monitor';"
        mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant replication slave on *.* to 'slave'@'%' identified by 'slave';"
        mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant all on *.* to dev_ddl@'10.232.31.94' IDENTIFIED BY 'tb4ddl';"
        mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant all on *.* to dev_ddl@'10.232.31.53' IDENTIFIED BY 'tb4ddl';"
        mysql -uroot -S /u01/mybase/run/mysql.sock -e"grant all on *.* to dev_ddl@'10.232.64.128' IDENTIFIED BY 'tb4ddl';"
        cp -f /u01/dbagent/conf/monitordb.cnf.sqa /u01/dbagent/conf/monitordb.cnf
        dbagent stop agent
        dbagent start agent
      fi
  


      #Make users available#################################################################
      mysql -uroot -S /u01/mybase/run/mysql.sock -e"flush privileges"
  
      #Make sure MySQL base folder is not able for running again############################
      mysqladmin shutdown -uroot -S /u01/mybase/run/mysql.sock 
      mv  /u01/mybase/my.cnf  /u01/mybase/bakmy.cnf
    fi
}

! grep -w oinstall /etc/group > /dev/null && /usr/sbin/groupadd -g 510 oinstall && echo "add user group:oinstall"
! grep -w dba /etc/group > /dev/null && /usr/sbin/groupadd -g 501 dba && echo "add user group:dba"
! grep -w admin /etc/group > /dev/null && /usr/sbin/groupadd -g 500 admin && echo "add user group:admin"
! grep -w mysql  /etc/shadow > /dev/null && /usr/sbin/useradd -n -u 502 -g 501 -d /home/mysql -s /bin/bash -p x -m mysql && chown -R mysql:dba /home/mysql && chmod 0755 /home/mysql &&echo "add user:mysql"

mem_check
test !  -L /usr/mysqlmisc &&  ln -s /u01/mysql/mysqlmisc/ /usr/
test -e /usr/local/bin/myadm &&  test ! -e /etc/init.d/mysqld && ln -s /usr/local/bin/myadm /etc/init.d/mysqld
test -e  /usr/local/bin/myadm && test ! -e /usr/local/bin/a-myadm  && ln -s /usr/local/bin/myadm /usr/local/bin/a-myadm 
/sbin/chkconfig --add mysqld
test -e /usr/bin/gdb  &&  chmod +s /usr/bin/gdb 
test -e /usr/bin/tcprstat  && chmod +s /usr/bin/tcprstat
test -e /usr/sbin/tcpdump && chmod +s  /usr/sbin/tcpdump
mybase_init > /tmp/mybase.log
