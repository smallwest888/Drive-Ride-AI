#!/bin/bash

# 数据库备份脚本
# 使用方法: ./backup_db.sh

echo "📦 开始备份数据库文件..."

# 获取当前日期时间作为备份文件名后缀
BACKUP_DATE=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="./backups"

# 创建备份目录
mkdir -p "$BACKUP_DIR"

# 备份 server 目录下的数据库
if [ -f "./prparking.db" ]; then
    cp "./prparking.db" "$BACKUP_DIR/prparking_server_${BACKUP_DATE}.db"
    echo "✅ 已备份: ./prparking.db -> $BACKUP_DIR/prparking_server_${BACKUP_DATE}.db"
fi

# 备份 CityDriveRide 目录下的数据库
if [ -f "../CityDriveRide/prparking.db" ]; then
    cp "../CityDriveRide/prparking.db" "$BACKUP_DIR/prparking_citydriveride_${BACKUP_DATE}.db"
    echo "✅ 已备份: ../CityDriveRide/prparking.db -> $BACKUP_DIR/prparking_citydriveride_${BACKUP_DATE}.db"
fi

echo ""
echo "🎉 备份完成！备份文件保存在: $BACKUP_DIR"
echo "💡 现在可以安全地运行 npm install 了"

