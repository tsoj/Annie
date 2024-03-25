#!/bin/bash


nim c \
--define:ssl \
--mm:arc \
--define:useMalloc \
--passL:"-static" \
--cc:clang \
--threads:on \
--styleCheck:hint \
--passC:"-flto" \
--passL:"-flto" \
--panics:on \
--define:danger \
--passC:"-march=native" \
--passC:"-mtune=native" \
playLichessGame.nim && \
nim c --define:ssl lichessBot.nim && 
./lichessBot