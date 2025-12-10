#!/usr/bin/env bash

IMAGE="mwader/static-ffmpeg:7.1.1"
DEST="/usr/local/bin"

# 拉取镜像
docker pull $IMAGE

# 用 Docker 临时容器输出 /ffmpeg 和 /ffprobe
docker run --rm $IMAGE tar cf - /ffmpeg /ffprobe | sudo tar xf - -C $DEST

# 设置可执行权限
sudo chmod +x $DEST/ffmpeg $DEST/ffprobe

# 验证
$DEST/ffmpeg -version
$DEST/ffprobe -version

echo "ffmpeg and ffprobe installed to $DEST"
