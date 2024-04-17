#!/bin/bash
#
#
make run

while true; do
  fswatch -1 "src/" >/dev/null 
  make run
done
