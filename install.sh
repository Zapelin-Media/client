#!/bin/sh

apt-get update
apt-get install -y eja
eja --update
eja --install https://raw.githubusercontent.com/Zapelin-Media/client/master/zapelin.eja
eja --zmi-install --log-level 3
