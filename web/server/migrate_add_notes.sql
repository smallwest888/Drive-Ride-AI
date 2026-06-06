-- 数据库迁移脚本：添加 notes 列
-- 版本: 3.2
-- 创建时间: 2024-12-28
-- 说明: 为 PRParkings 表添加 notes 列用于存储备注信息

-- 检查并添加 notes 列
-- SQLite 的 ALTER TABLE 只支持添加列，不支持条件判断
-- 如果列已存在，此命令会失败，但不会影响现有数据

ALTER TABLE PRParkings ADD COLUMN notes TEXT DEFAULT '';

-- 更新数据库版本信息（如果 DatabaseStats 表存在）
UPDATE DatabaseStats 
SET statValue = '3.2', updatedAt = CURRENT_TIMESTAMP 
WHERE statName = 'schema_version';

-- 如果版本记录不存在，则插入
INSERT OR IGNORE INTO DatabaseStats (statName, statValue, updatedAt) 
VALUES ('schema_version', '3.2', CURRENT_TIMESTAMP);

-- 迁移完成提示
SELECT 'Migration completed: notes column added to PRParkings table' as result;

