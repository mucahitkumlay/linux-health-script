#!/bin/bash

FILENAME=$(hostname)-$(date +%d_%m_%Y).out 

func (){

S="************************************"
D="-------------------------------------"
COLOR="on"

CPU_S=$(mpstat |tail -n2| sed -re 's/[ ]+/\t/g' |cut -f4,6,7,13| sed '1d')
CPU_STATE_S=$(echo -e "$CPU_S"| awk '{ if ($1 > 90 || $2 > 90 || $3 > 90 || $4 < 10 ) { print "RED" } else { print "GREEN"} }')
SERVICE_S=$(systemctl --all --type service | grep -E 'couchbase|mongod|postgresql|ambari-server|ambari-agent' | awk -v pat="$SERVICE" '$0 ~ pat {sub(/[^\x01-\x7f]+/, ""); print}' | awk '{print $1,$4}' | column -t)
SVCTM_S=$(sar -d 2 5 | grep -i Average | sed -re 's/[ ]+/\t/g' |cut -f9 | sed '1d' | awk '{ if($1 >= 8){ print $1}}')
MOUNT=$(mount|egrep -iw "xfs|nfs"|grep -v "loop"|sort -u -t' ' -k1,2| column -t| grep -i 'BACKUP\|data\|backup' | sed -re 's/[ ]+/\t/g' |cut -f1,3,5)
FS_USAGE=$(df -PThl -x tmpfs -x iso9660 -x devtmpfs -x squashfs|awk '!seen[$1]++'|sort -k6n|tail -n +2)
IUSAGE=$(df -iPThl -x tmpfs -x iso9660 -x devtmpfs -x squashfs|awk '!seen[$1]++'|sort -k6n|tail -n +2)

clear='\033[0m'

if [ $COLOR == on ]; then
{
 GCOLOR="\e[33;32m ------ OK/HEALTHY \e[0m"
 WCOLOR="\e[33;33m ------ WARNING \e[0m"
 CCOLOR="\e[33;31m ------ CRITICAL \e[0m"
}
else
{
 GCOLOR=" ------ OK/HEALTHY "
 WCOLOR=" ------ WARNING "
 CCOLOR=" ------ CRITICAL "
}
fi

export TERM=ansi

function bold {
    tput bold
    echo -n "$@"
    # bold can't be turned off by itself so this
    # turns off all attributes
    tput sgr0
}

function ul {
    tput smul
    echo -n "$@"
    tput rmul
}

function rev {
    # standout mode really, but reverse mode for ansi
    tput smso
    echo -n "$@"
    tput rmso
}

function print_centered {
     [[ $# == 0 ]] && return 1

     declare -i TERM_COLS="$(tput cols)"
     declare -i str_len="${#1}"
     [[ $str_len -ge $TERM_COLS ]] && {
          echo "$1";
          return 0;
     }

     declare -i filler_len="$(( (TERM_COLS - str_len) / 2 ))"
     [[ $# -ge 2 ]] && ch="${2:0:1}" || ch=" "
     filler=""
     for (( i = 0; i < filler_len; i++ )); do
          filler="${filler}${ch}"
     done

     text=$(bold $1) 

     printf "%s%s%s" "$filler" "$text" "$filler"
     [[ $(( (TERM_COLS - str_len) % 2 )) -ne 0 ]] && printf "%s" "${ch}"
     printf "\n"

     return 0
}

function print_left {
  if [[ $# == 0 ]]; then
    echo "No parameter given" >&2
    echo "Usage: $0 \"<phrase to align left>\" \"<1 char to fill empty space>\" [<number of columns>] [<1 char to surround the whole result>" >&2
    return 1
  fi

  declare -i NB_COLS
  if [[ $# -ge 3 ]]; then
    NB_COLS=$3
  else
    NB_COLS="$(tput cols)"
  fi

  if [[ $# -ge 4 ]]; then
    SURROUNDING_CHAR=${4:0:1}
    NB_COLS=$((NB_COLS - 2))
  fi

  declare -i str_len="${#1}"

  # Simply displays the text if it exceeds the maximum length
  if [[ $str_len -ge $NB_COLS ]]; then
    echo "$1";
    return 0;
  fi

  # Build the chars to add before and after the given text
  declare -i filler_len="$((NB_COLS - str_len))"
  if [[ $# -ge 2 ]]; then
    ch="${2:0:1}"
  else
    ch=" "
  fi
  filler=""
  for (( i = 0; i < filler_len; i++ )); do
      filler="${filler}${ch}"
  done
   
  text=$(bold $1) 
 
  printf "%s%s%s%s\n" "$SURROUNDING_CHAR" "$text" "$filler" "$SURROUNDING_CHAR"
  return 0
}
echo -e "\n\n"
print_centered "System Health Information" " "
echo -e "\n"
print_left " Operating System Information" ' ' 80 ' '

##--------Print Operating System Details--------#
hostname -f &> /dev/null && printf "\nHostname : $(hostname -f)" || printf "Hostname : $(hostname -s)"

echo -en "\nOperating System : "
[ -f /etc/os-release ] && echo $(egrep -w "NAME|VERSION" /etc/os-release|awk -F= '{ print $2 }'|sed 's/"//g') || cat /etc/system-release

echo -e "Kernel Version :" $(uname -r)
printf "OS Architecture :"$(arch | grep x86_64 &> /dev/null) && printf " 64 Bit OS\n"  || printf " 32 Bit OS\n"

#--------Print system uptime-------#
UPTIME=$(uptime)
echo -en "System Uptime : "
echo $UPTIME|grep day &> /dev/null
if [ $? != 0 ]; then
  echo $UPTIME|grep -w min &> /dev/null && echo -en "$(echo $UPTIME|awk '{print $2" by "$3}'|sed -e 's/,.*//g') minutes" \
 || echo -en "$(echo $UPTIME|awk '{print $2" by "$3" "$4}'|sed -e 's/,.*//g') hours"
else
  echo -en $(echo $UPTIME|awk '{print $2" by "$3" "$4" "$5" hours"}'|sed -e 's/,//g')
fi
echo -e "\nCurrent System Date & Time : "$(date +%c)
echo " "  
##----------------------------------------------------------------------------------------------------------CPU---------------------------------------------------------#

print_left "CPU Information" ' ' 80 ' '

if [[ "$CPU_STATE_S" == "RED" ]];then
     
    echo -e "\nMachine CPU usage state \e[33;31m $CPU_STATE_S \e[0m\n"
else

    echo -e "\nMachine CPU usage state \e[33;32m $CPU_STATE_S \e[0m\n"
fi

#--------------------------------------------------------------------------------------------DISK-MEMORY-SWAP--------------------------------------------------------------------#

print_left "Disk Usage On Mounted File System[s] / 0-85% = OK/HEALTHY,  85-95% = WARNING,  95-100% = CRITICAL" ' ' 80 ' '
echo " " 
COL1=$(echo "$FS_USAGE"|awk '{print $1 " "$7}')
COL2=$(echo "$FS_USAGE"|awk '{print $6}'|sed -e 's/%//g')

for i in $(echo "$COL2"); do
{
  if [ $i -ge 95 ]; then
    COL3="$(echo -e $i"% $CCOLOR\n$COL3")"
  elif [[ $i -ge 85 && $i -lt 95 ]]; then
    COL3="$(echo -e $i"% $WCOLOR\n$COL3")"
  else
    COL3="$(echo -e $i"% $GCOLOR\n$COL3")"
  fi
}
done
COL3="$(echo "$COL3"|sort -k1n)"
paste  <(echo "$COL1") <(echo "$COL3") -d' '|column -t
echo " "
#--------Check for currently outsource mounted file systems--------#
print_left "Currently Outsource Mounted File System[s]" ' ' 80 ' '
echo -e "\n$MOUNT\n"

#--------Check for Disk Details--------#
print_left "DISK SVCTM" ' ' 80 ' '
if [ "${SVCTM_S:-0}" == null ]; then
   echo -e "\nValues are normal"
else
  for i in $(echo "$SVCTM_S"); do
    COL333="$(echo -e $i"$WCOLOR\n$COL333${clear}")"
  done
  COL333="$(echo "$COL333"|sort -k1n)"
  paste  <(echo "$SVCTM") <(echo "$COL333") -d' '|column -t
  COL333=""
fi
echo " "

#--------Check for Memory Utilization--------#
print_left "MEMORY Details" ' ' 80 ' '
echo -e "\n$(free -h|  sed -re 's/[ ]+/\t/g'| cut -f1-4,7)\n"

#-------------------------------------------------------------------------SERVICES--------------------------------------------------------------#
print_left "Checking For Services / RUNNING = OK/HEALTHY, FAILED = CRITICAL" ' ' 80 ' '
echo " "
COL111=$(echo "$SERVICE_S"|awk '{print $1}')
COL222=$(echo "$SERVICE_S"|awk '{print $2}')

for i in $(echo "$COL222"); do
{
  if [ $i == "failed" ]; then
    COL333="$(echo -e $i"$CCOLOR\n$COL333${clear}")"
  else
    COL333="$(echo -e $i"   $GCOLOR\n$COL333")"
  fi
}
done
COL333="$(echo "$COL333"|sort -k1n)"
paste  <(echo "$COL111") <(echo "$COL333") -d' '|column -t

#------Print most recent 3 reboot events if available----#
echo " "
print_left "Reboot Events" ' ' 80 ' '
echo " "
last -x 2> /dev/null|grep reboot 1> /dev/null && /usr/bin/last -x 2> /dev/null|grep reboot|head -3 || \
echo -e "No reboot events are recorded."

#------Print most recent 3 shutdown events if available-----#
echo " "
print_left "Shutdown Events" ' ' 80 ' '
echo " "
last -x 2> /dev/null|grep shutdown 1> /dev/null && /usr/bin/last -x 2> /dev/null|grep shutdown|head -3 || \
echo -e "No shutdown events are recorded."
}

func 2>&1 | tee /tmp/$FILENAME
