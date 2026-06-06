#!/bin/bash

# 同步PC和iOS数据库脚本
# 合并两个数据库，完全一样的记录只保留一份，然后同步回两个数据库

PC_DB="./prparking.db"
IOS_DB="../CityDriveRide/prparking.db"
BACKUP_DIR="./backups"
TEMP_DB="./temp_merged.db"

echo "🔄 开始同步PC和iOS数据库..."

# 创建备份目录
mkdir -p "$BACKUP_DIR"
BACKUP_DATE=$(date +"%Y%m%d_%H%M%S")

# 检查数据库文件是否存在
if [ ! -f "$PC_DB" ]; then
    echo "❌ PC数据库不存在: $PC_DB"
    exit 1
fi

if [ ! -f "$IOS_DB" ]; then
    echo "❌ iOS数据库不存在: $IOS_DB"
    exit 1
fi

# 备份两个数据库
echo "📦 备份数据库..."
cp "$PC_DB" "$BACKUP_DIR/prparking_pc_${BACKUP_DATE}.db"
cp "$IOS_DB" "$BACKUP_DIR/prparking_ios_${BACKUP_DATE}.db"
echo "✅ 备份完成"

# 删除临时数据库（如果存在）
rm -f "$TEMP_DB"

# 创建临时合并数据库
echo "🔀 合并数据库并去重..."

sqlite3 "$TEMP_DB" <<EOF
-- 创建表结构
CREATE TABLE PRParkings (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    address TEXT NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    totalSpaces INTEGER NOT NULL DEFAULT 0,
    pricePerHour REAL DEFAULT NULL,
    city TEXT NOT NULL,
    facilities TEXT DEFAULT '',
    operatingHours TEXT DEFAULT '',
    contactPhone TEXT DEFAULT '',
    isActive INTEGER DEFAULT 1,
    createdAt TEXT DEFAULT CURRENT_TIMESTAMP,
    updatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
    CHECK (totalSpaces >= 0),
    CHECK (pricePerHour IS NULL OR pricePerHour >= 0),
    CHECK (latitude >= -90 AND latitude <= 90),
    CHECK (longitude >= -180 AND longitude <= 180)
);

CREATE INDEX idx_prparkings_city ON PRParkings(city);
CREATE INDEX idx_prparkings_coordinates ON PRParkings(latitude, longitude);
CREATE INDEX idx_prparkings_active ON PRParkings(isActive);
CREATE INDEX idx_prparkings_city_active ON PRParkings(city, isActive);

CREATE TABLE IF NOT EXISTS DatabaseStats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    statName TEXT UNIQUE NOT NULL,
    statValue TEXT NOT NULL,
    updatedAt TEXT DEFAULT CURRENT_TIMESTAMP
);
EOF

# 合并两个数据库并去重
sqlite3 "$TEMP_DB" <<EOF
-- 附加两个源数据库
ATTACH DATABASE '$PC_DB' AS pc_db;
ATTACH DATABASE '$IOS_DB' AS ios_db;

-- 统计原始数据
SELECT '📊 原始数据统计:' as info;
SELECT 'PC数据库记录数: ' || COUNT(*) FROM pc_db.PRParkings;
SELECT 'iOS数据库记录数: ' || COUNT(*) FROM ios_db.PRParkings;

-- 合并PC数据库的数据（去重）
INSERT INTO PRParkings (
    name, address, latitude, longitude, totalSpaces, 
    pricePerHour, city, facilities, operatingHours, 
    contactPhone, isActive, createdAt, updatedAt
)
SELECT 
    name, address, latitude, longitude, totalSpaces, 
    pricePerHour, city, facilities, operatingHours, 
    contactPhone, isActive, createdAt, updatedAt
FROM pc_db.PRParkings
WHERE NOT EXISTS (
    SELECT 1 FROM PRParkings t 
    WHERE (t.name = pc_db.PRParkings.name AND t.address = pc_db.PRParkings.address)
       OR (t.name = pc_db.PRParkings.name 
           AND ABS(t.latitude - pc_db.PRParkings.latitude) < 0.0001 
           AND ABS(t.longitude - pc_db.PRParkings.longitude) < 0.0001)
);

-- 合并iOS数据库的数据（去重）
INSERT INTO PRParkings (
    name, address, latitude, longitude, totalSpaces, 
    pricePerHour, city, facilities, operatingHours, 
    contactPhone, isActive, createdAt, updatedAt
)
SELECT 
    name, address, latitude, longitude, totalSpaces, 
    pricePerHour, city, facilities, operatingHours, 
    contactPhone, isActive, createdAt, updatedAt
FROM ios_db.PRParkings
WHERE NOT EXISTS (
    SELECT 1 FROM PRParkings t 
    WHERE (t.name = ios_db.PRParkings.name AND t.address = ios_db.PRParkings.address)
       OR (t.name = ios_db.PRParkings.name 
           AND ABS(t.latitude - ios_db.PRParkings.latitude) < 0.0001 
           AND ABS(t.longitude - ios_db.PRParkings.longitude) < 0.0001)
);

-- 同步DatabaseStats表（如果存在）
-- 优先使用iOS数据库的统计信息，如果不存在则使用PC数据库的
INSERT OR REPLACE INTO DatabaseStats (statName, statValue, updatedAt)
SELECT statName, statValue, updatedAt
FROM ios_db.DatabaseStats
WHERE EXISTS (SELECT 1 FROM ios_db.sqlite_master WHERE type='table' AND name='DatabaseStats');

INSERT OR IGNORE INTO DatabaseStats (statName, statValue, updatedAt)
SELECT statName, statValue, updatedAt
FROM pc_db.DatabaseStats
WHERE EXISTS (SELECT 1 FROM pc_db.sqlite_master WHERE type='table' AND name='DatabaseStats');

-- 更新统计信息
UPDATE DatabaseStats SET statValue = (SELECT COUNT(*) FROM PRParkings), updatedAt = datetime('now') WHERE statName = 'totalRecords';

-- 显示合并结果
SELECT '✅ 合并完成！' as status;
SELECT '去重后总记录数: ' || COUNT(*) FROM PRParkings;

-- 分离数据库
DETACH DATABASE pc_db;
DETACH DATABASE ios_db;
EOF

if [ $? -ne 0 ]; then
    echo "❌ 合并失败"
    rm -f "$TEMP_DB"
    exit 1
fi

# 获取合并后的记录数
FINAL_COUNT=$(sqlite3 "$TEMP_DB" "SELECT COUNT(*) FROM PRParkings;")
echo "📊 去重后总记录数: $FINAL_COUNT"

# 同步回PC数据库
echo "💾 同步到PC数据库..."
rm -f "$PC_DB"
cp "$TEMP_DB" "$PC_DB"
echo "✅ PC数据库已更新"

# 同步回iOS数据库
echo "💾 同步到iOS数据库..."
rm -f "$IOS_DB"
cp "$TEMP_DB" "$IOS_DB"
echo "✅ iOS数据库已更新"

# 清理临时文件
rm -f "$TEMP_DB"

# 验证同步结果
echo ""
echo "🔍 验证同步结果..."
PC_COUNT=$(sqlite3 "$PC_DB" "SELECT COUNT(*) FROM PRParkings;")
IOS_COUNT=$(sqlite3 "$IOS_DB" "SELECT COUNT(*) FROM PRParkings;")

echo "PC数据库记录数: $PC_COUNT"
echo "iOS数据库记录数: $IOS_COUNT"

if [ "$PC_COUNT" -eq "$IOS_COUNT" ] && [ "$PC_COUNT" -eq "$FINAL_COUNT" ]; then
    echo ""
    echo "🎉 同步成功！"
    echo "✅ 两个数据库已完全同步"
    echo "✅ 完全一样的记录已去重，只保留一份"
    echo "💾 备份文件保存在: $BACKUP_DIR"
else
    echo "⚠️  警告：记录数不一致，请检查"
    exit 1
fi

