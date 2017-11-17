#!/bin/bash

wget -qO- https://get.haskellstack.org/ | sh && stack setup && stack build
