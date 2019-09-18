#!/bin/sh

apt-get update
apt-get install -y eja
eja --update
eja --install https://raw.githubusercontent.com/zapelin-media/zmi/master/zmi.eja
eja --zmi-install --log-level 3
