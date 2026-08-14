#!/usr/bin/env bash
# 下载并解压 llama.cpp 官方预编译 XCFramework 到 Frameworks/。
# XCFramework 约 855MB(含 iOS 真机+模拟器+macOS 等多平台 slice),已在 .gitignore 中排除,
# clone 仓库后运行本脚本即可让工程编译通过。
set -euo pipefail

VER="b10428"
URL="https://github.com/ggml-org/llama.cpp/releases/download/${VER}/llama-${VER}-xcframework.zip"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ZIP="/tmp/llama-${VER}-xcframework.zip"

if [ -d "$ROOT/Frameworks/build-apple/llama.xcframework" ]; then
  echo "已存在:$ROOT/Frameworks/build-apple/llama.xcframework(跳过)"
  exit 0
fi

echo "下载 $URL ..."
curl -L --fail -o "$ZIP" "$URL"
mkdir -p "$ROOT/Frameworks"
echo "解压到 $ROOT/Frameworks/ ..."
unzip -q -o "$ZIP" -d "$ROOT/Frameworks/"
rm -f "$ZIP"
echo "完成:$ROOT/Frameworks/build-apple/llama.xcframework"
