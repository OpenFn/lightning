#!/usr/bin/env bash

# NODE_PATH=$(realpath ./deps)

(cd assets && ../_build/esbuild-linux-x64 js/app.js \
  js/storybook.js \
  js/editor/Editor.tsx \
  fonts/inter.css \
  fonts/fira-code.css \
  --loader:.woff2=file \
  --format=esm --splitting --bundle \
  --target=es2020 \
  --outdir=../priv/static/assets \
  --external:/fonts/* \
  --external:/images/*)
