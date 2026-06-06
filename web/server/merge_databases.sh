#!/bin/bash

# 合并数据库脚本
# 将 server/prparking.db 的数据合并到 CityDriveRide/prparking.db

SOURCE_DB="./prparking.db"
TARGET_DB="../CityDriveRide/prparking.db"
BACKUP_DIR="./backups"

echo "🔄 开始合并数据库..."

# 创建备份目录
mkdir -p "$BACKUP_DIR"
BACKUP_DATE=$(date +"%Y%m%d_%H%M%S")

# 备份目标数据库
if [ -f "$TARGET_DB" ]; then
    cp "$TARGET_DB" "$BACKUP_DIR/prparking_citydriveride_before_merge_${BACKUP_DATE}.db"
    echo "✅ 已备份目标数据库: $TARGET_DB"
fi

# 检查源数据库是否存在
if [ ! -f "$SOURCE_DB" ]; then
    echo "❌ 源数据库不存在: $SOURCE_DB"
    exit 1
fi

# 检查目标数据库是否存在
if [ ! -f "$TARGET_DB" ]; then
    echo "⚠️  目标数据库不存在，将创建新数据库"
fi

# 使用 SQLite 合并数据（智能去重）
sqlite3 "$TARGET_DB" <<EOF
-- 附加源数据库
ATTACH DATABASE '$SOURCE_DB' AS source_db;

-- 记录合并前的数量
CREATE TEMP TABLE merge_stats AS
SELECT 
    (SELECT COUNT(*) FROM PRParkings) as target_before,
    (SELECT COUNT(*) FROM source_db.PRParkings) as source_count,
    (SELECT COUNT(*) FROM source_db.PRParkings s
     WHERE EXISTS (
         SELECT 1 FROM PRParkings t 
         WHERE (t.name = s.name AND t.address = s.address)
            OR (t.name = s.name AND ABS(t.latitude - s.latitude) < 0.0001 AND ABS(t.longitude - s.longitude) < 0.0001)
     )) as duplicate_count;

-- 显示合并前统计
SELECT '📊 合并前统计:' as info;
SELECT '目标数据库记录数: ' || target_before FROM merge_stats;
SELECT '源数据库记录数: ' || source_count FROM merge_stats;
SELECT '检测到重复记录数: ' || duplicate_count FROM merge_stats;

-- 插入不重复的数据（基于 name+address 或 name+坐标 去重）
INSERT INTO PRParkings (
    name, address, latitude, longitude, totalSpaces, 
    pricePerHour, city, facilities, operatingHours, 
    contactPhone, isActive, createdAt, updatedAt
)
SELECT 
    s.name, s.address, s.latitude, s.longitude, s.totalSpaces, 
    s.pricePerHour, s.city, s.facilities, s.operatingHours, 
    s.contactPhone, s.isActive, s.createdAt, s.updatedAt
FROM source_db.PRParkings s
WHERE NOT EXISTS (
    SELECT 1 FROM PRParkings t 
    WHERE (t.name = s.name AND t.address = s.address)
       OR (t.name = s.name AND ABS(t.latitude - s.latitude) < 0.0001 AND ABS(t.longitude - s.longitude) < 0.0001)
);

-- 显示合并后统计
SELECT '✅ 合并完成！' as status;
SELECT '本次新增记录数: ' || ((SELECT COUNT(*) FROM PRParkings) - target_before) FROM merge_stats;
SELECT '目标数据库合并后总记录数: ' || COUNT(*) FROM PRParkings;

-- 清理临时表
DROP TABLE merge_stats;

-- 分离源数据库
DETACH DATABASE source_db;
EOF

if [ $? -eq 0 ]; then
    echo ""
    echo "🎉 数据库合并成功！"
    echo "📊 合并后的数据统计："
    sqlite3 "$TARGET_DB" "SELECT COUNT(*) as '总记录数' FROM PRParkings;"
    echo ""
    echo "💾 备份文件保存在: $BACKUP_DIR"
else
    echo "❌ 合并失败，请检查错误信息"
    exit 1
fi

