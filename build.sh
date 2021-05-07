#!/bin/bash
cp image.xml .image.xml
elbe chg_archive .image.xml archive
elbe initvm submit .image.xml --skip-build-bin  --skip-build-sources
