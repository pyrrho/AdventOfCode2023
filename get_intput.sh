#!/usr/bin/env sh

curl https://adventofcode.com/2023/day/${1}/input -H "Cookie:session=$(cat .session_cookie)" > src/day${1}_input.txt
