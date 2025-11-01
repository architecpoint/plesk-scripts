#!/bin/sh
#
# MySQL Database Backup Script for Plesk Servers
# 
# This script backs up all MySQL databases on a Plesk server, excluding system databases.
# It uses a PID file to prevent multiple instances from running simultaneously.
#
# Features:
# - Prevents concurrent execution using PID file
# - Backs up all databases except system databases
# - Creates individual SQL dump files per database
# - Proper error handling and logging
#

# Configuration
HOME="/backup/mysql/"
FOLDER="${HOME}/data"
PID="${HOME}/mysql.pid"

# Create backup directory if it doesn't exist
/bin/mkdir -p "${FOLDER}"

# Check if another instance is already running
if [ -f "${PID}" ]; then
  KILL=$(cat "${PID}")
  echo "Another instance of script is running (PID: ${KILL}). Attempting to terminate..."
  kill -9 "${KILL}" 2>/dev/null || true
fi

# Write current PID to lock file
echo $$ > "${PID}"

# Set restrictive permissions for created files
umask 077

# Get list of databases, excluding system databases
IFS='
'
/usr/sbin/plesk db -e "show databases" | grep -v -E "^Database|information_schema|performance_schema|phpmyadmin" > "${FOLDER}/dbs.txt"

# Check if database connection was successful
if [ "$?" -ne 0 ]; then
  echo "ERROR: Cannot connect to MySQL database"
  rm -f "${PID}"
  exit 1
fi

echo "Starting MySQL database backup..."

# Backup each database
for i in $(cat "${FOLDER}/dbs.txt"); do
  echo "Backing up database: ${i}"
  
  # Remove old backup file if it exists
  /bin/rm -f "${FOLDER}/${i}.sql"
  
  # Dump database
  /usr/sbin/plesk db dump "${i}" > "${FOLDER}/${i}.sql"
  
  # Check if dump was successful
  if [ "$?" -ne 0 ]; then
    echo "ERROR: Dump failed for database: ${i}"
  else
    echo "Successfully backed up: ${i}"
  fi
done

echo "MySQL backup completed successfully"

# Clean up PID file
rm -f "${PID}"
exit 0
