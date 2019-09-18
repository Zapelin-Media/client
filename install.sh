#!/bin/sh

apt-get update
apt-get install -y eja
eja --update
eja --install https://github.com/zapelin-media/zmi/raw/zmi.eja
eja --zmi-install --log-level 3
