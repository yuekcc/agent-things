#!/bin/bash

INSTALL_DIRS=(
    ~/.agents/skills
    ~/.codebuddy/skills
    ~/.workbuddy/skills
)

for INSTALL_DIR in "${INSTALL_DIRS[@]}"; do
    mkdir -p "$INSTALL_DIR"

    # 列出 skills 目录的一级子目录并处理
    for dir in skills/*/; do
        # 跳过非目录项
        [ ! -d "$dir" ] && continue
        
        # 获取子目录名称
        dir_name=$(basename "$dir")
        target_dir="$INSTALL_DIR/$dir_name"
        
        # 如果目标目录已存在，则先删除
        if [ -d "$target_dir" ]; then
            echo "$dir_name 已存在，删除中..."
            rm -rf "$target_dir"
        fi
        
        # 复制到安装目录
        echo "安装 $dir_name 到 $INSTALL_DIR..."
        cp -rf "$dir" "$target_dir"
    done
done

echo "安装完成！"