#!/bin/sh

apt-get update
apt-get install -y eja
eja --update
eja --install http://get.zapelin.com/zapelin.eja
eja --zmi-install --log-level 3
