#!/bin/bash

# trap ctrl-c and call ctrl_c()
trap ctrl_c INT

function ctrl_c() {
       ./gq-gmc-control.py --power-off
        exit
}

./gq-gmc-control.py --power-on
./gq-gmc-control.py --set-date-and-time "`date +'%y/%m/%d %H:%M:%S'`"
./gq-gmc-control.py --heartbeat
