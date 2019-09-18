#!/bin/sh

apt-get update
apt-get install -y eja
eja --update
eja --install https://zapelin-media.github.io/client/zapelin.eja
eja --zmi-install --log-level 3
