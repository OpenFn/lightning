#!/usr/bin/env bash

mix deps.get

cd ../lightning
mix deps.get
mix test test/lightning_web/live/workflow_live/editor_test.exs:1183
