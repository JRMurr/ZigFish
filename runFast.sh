#!/usr/bin/env bash
set -euxo pipefail

#     -log file=./out level=info realtime=true \
mkdir -p ./fastchess-out
rm -f ./fastchess-out/log
rm -f ./fastchess-out/pgnout

zig build
OLD_ENGINE=$(buildAtCommit "3d62d81a61e891f606bf8ce457dd9e4f2a5387ab")


fast-chess -maxmoves 100 -concurrency 20 \
    -log file=./fastchess-out/log level=info realtime=true \
    -pgnout file=./fastchess-out/pgnout \
    -resign score=500000 \
    -rounds 100 \
    -draw movenumber=30 movecount=8 score=80 \
    -openings file=./test.pgn format=pgn order=random \
    -engine cmd=./zig-out/bin/zigfish-uci name=new st=0.1 timemargin=100 \
    -engine cmd="$OLD_ENGINE" name=old st=0.1 timemargin=100