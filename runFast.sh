#!/usr/bin/env bash
set -euxo pipefail

fast-chess -maxmoves 100 -concurrency 4 \
    -openings file=./test.pgn format=pgn order=random \
    -log file=./out level=info realtime=true \
    -engine cmd=./zig-out/bin/zigfish-uci name=new st=0.1 timemargin=100 \
    -engine cmd=$1 name=old st=0.1 timemargin=100