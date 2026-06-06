// 快速检查数据库中的数据
const sqlite3 = require('sqlite3').verbose();
const path = require('path');

const dbPath = path.join(__dirname, '..', 'CityDriveRide', 'prparking.db');
console.log('🔍 数据库路径:', dbPath);

const db = new sqlite3.Database(dbPath, (err) => {
    if (err) {
        console.error('❌ 无法打开数据库:', err);
        process.exit(1);
    }
    
    console.log('✅ 数据库连接成功');
    
    // 检查表是否存在
    db.all("SELECT name FROM sqlite_master WHERE type='table'", [], (err, rows) => {
        if (err) {
            console.error('❌ 检查表失败:', err);
            db.close();
            process.exit(1);
        }
        
        console.log('📋 数据库中的表:', rows.map(r => r.name));
        
        const hasPRParkings = rows.some(r => r.name === 'PRParkings');
        
        if (!hasPRParkings) {
            console.log('❌ PRParkings表不存在');
            db.close();
            process.exit(1);
        }
        
        console.log('✅ 表存在');
        
        // 查询数据数量
        db.get("SELECT COUNT(*) as count FROM PRParkings", [], (err, row) => {
            if (err) {
                console.error('❌ 查询失败:', err);
                db.close();
                process.exit(1);
            }
            
            const count = row ? row.count : 0;
            console.log(`📊 数据库中有 ${count} 条数据`);
            
            if (count > 0) {
                // 统计柏林停车场
                db.get("SELECT COUNT(*) as berlinCount FROM PRParkings WHERE city = 'Berlin'", [], (err, berlinRow) => {
                    if (err) {
                        console.error('❌ 查询柏林数据失败:', err);
                    } else {
                        const berlinCount = berlinRow ? berlinRow.count : 0;
                        console.log(`🏙️ 柏林停车场数量: ${berlinCount} 个`);
                        
                        // 列出柏林的停车场
                        db.all("SELECT id, name, city, totalSpaces FROM PRParkings WHERE city = 'Berlin'", [], (err, berlinRows) => {
                            if (err) {
                                console.error('❌ 查询柏林停车场详情失败:', err);
                            } else {
                                console.log('\n📋 柏林停车场列表:');
                                berlinRows.forEach((row, index) => {
                                    console.log(`   ${index + 1}. [${row.id}] ${row.name} - ${row.totalSpaces}车位`);
                                });
                            }
                            
                            // 统计其他城市
                            db.all("SELECT city, COUNT(*) as count FROM PRParkings GROUP BY city ORDER BY count DESC", [], (err, cityRows) => {
                                if (err) {
                                    console.error('❌ 查询城市统计失败:', err);
                                } else {
                                    console.log('\n📊 各城市停车场统计:');
                                    cityRows.forEach((row) => {
                                        console.log(`   ${row.city}: ${row.count} 个停车场`);
                                    });
                                }
                                db.close();
                            });
                        });
                    }
                });
            } else {
                console.log('⚠️  数据库为空，需要插入初始数据');
                db.close();
            }
        });
    });
});

