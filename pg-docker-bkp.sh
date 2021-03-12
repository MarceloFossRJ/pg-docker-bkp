#!/bin/bash

#USAGE:
# PATH_TO/pg_backup_rotated.sh -c PATH_TO/config.ini

# Schedule to cron on a daily basis:
# Execute $crontab -e and insert the line below
# 00 00 * * 1 cd /opt/docker-compose; PATH_TO/pg_backup_rotated.sh -c PATH_TO/config.ini

# Restore the backup
# gzip -d FILENAME.sql.gz

# single command
# docker exec -t CONTAINER_ID pg_dumpall -c -U postgres > peppery_dump_`date +%d-%m-%Y"_"%H_%M_%S`.sql

# load config
# -C is the option for the path to config file 

while [ $# -gt 0 ]; do
    case $1 in
        -c)
            CONFIG_FILE_PATH="$2"
            shift 2
            ;;
        *)
            ${ECHO} "Unknown Option \"$1\"" 1>&2
            exit 2
            ;;
    esac
done

if [ -z $CONFIG_FILE_PATH ] ; then
        SCRIPTPATH=$(cd ${0%/*} && pwd -P)
        CONFIG_FILE_PATH="${SCRIPTPATH}/config.ini"
fi

if [ ! -r ${CONFIG_FILE_PATH} ] ; then
        echo "Could not load config file from ${CONFIG_FILE_PATH}" 1>&2
        exit 1
fi

source "${CONFIG_FILE_PATH}"

# check if backup user is informed in config file
if [ "$BACKUP_USER" != "" -a "$(id -un)" != "$BACKUP_USER" ] ; then
    echo "This script must be run as $BACKUP_USER. Exiting." 1>&2
    exit 1
fi

# backup routine
function bkp_exec()
{
    # Suffix is the parameter for the bkp type (monthly, weekly, hourly )
    SUFFIX=$1
    FINAL_BACKUP_DIR=$BACKUP_DIR"`date +\%Y-\%m-\%d`$SUFFIX/"

    # Create backup dir
    echo "Creating the backup directory in $FINAL_BACKUP_DIR"
    if ! mkdir -p $FINAL_BACKUP_DIR; then
            echo "Could not create backup directory in $FINAL_BACKUP_DIR. Check out permissions !" 1>&2
            exit 1;
    fi;

    echo -e "\n\n Starting the Backup"
    echo -e "--------------------------------------------\n"    
    # retrieve docker container id
    QUERYCONTAINER=`docker ps -f name=peppery_db  --format '{{.Names}}'`
    
    # Execute backup
    if [ "$QUERYCONTAINER" ]; then
        for DBCONTAINER in $QUERYCONTAINER;
        do
            echo "CHECK-IN $DBCONTAINER"
            docker exec -t $DBCONTAINER pg_dumpall -c -U "$BACKUP_USER" | gzip > $FINAL_BACKUP_DIR"/$FILENAME".sql.gz;
        done
        echo -e "\nAll postgres databases backup have been completed successfully!"
    fi;
}

# Monthly backups
DAY_OF_MONTH=`date +%d`
if [ $DAY_OF_MONTH -eq 1 ];
then
    # Delete all expired monthly directories
    find $BACKUP_DIR -maxdepth 1 -name "*-monthly" -exec rm -rf '{}' ';'
            
    echo -e "\n\nPerforming Monthly backup"
    echo -e "--------------------------------------------\n"
    bkp_exec "-monthly"
    exit 0;
fi

# Weekly backups
DAY_OF_WEEK=`date +%u` #1-7 (Monday-Sunday)
EXPIRED_DAYS=`expr $((($WEEKS_TO_KEEP * 7) + 1))`
if [ $DAY_OF_WEEK = $DAY_OF_WEEK_TO_KEEP ];
then
    # Delete all expired weekly directories
    find $BACKUP_DIR -maxdepth 1 -mtime +$EXPIRED_DAYS -name "*-weekly" -exec rm -rf '{}' ';'
    
    echo -e "\n\nPerforming Weekly backup"
    echo -e "--------------------------------------------\n"
    bkp_exec "-weekly"
    exit 0;
fi

# Daily backups
echo -e "\n\nPerforming Daily backup"
echo -e "--------------------------------------------\n"
#find $BACKUP_DIR -maxdepth 1 -mtime +$DAYS_TO_KEEP -name "*-daily" -exec rm -rf '{}' ';'
bkp_exec "-daily"