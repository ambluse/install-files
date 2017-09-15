#!/bin/sh
#****************************************************************#
# ScriptName: set_env_for_rds.sh
# Author: taofang@alipay.com
# Create Date: 2013-11-27 13:27
# Modify Author: $SHTERM_REAL_USER@alibaba-inc.com
# Modify Date: 2013-11-27 13:27
# Function: modify profile setting for RDS 
#***************************************************************#
sed -i "/source/d" /etc/profile.d/mysql_profile.sh

