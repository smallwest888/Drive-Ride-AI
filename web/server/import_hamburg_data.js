// 导入汉堡停车数据到数据库
const sqlite3 = require('sqlite3').verbose();
const XLSX = require('xlsx');
const path = require('path');

// 数据库路径
const dbPath = path.join(__dirname, '..', 'CityDriveRide', 'prparking.db');
const excelPath = path.join(__dirname, '..', 'parking_data_hamburg01.xlsx');

console.log('🔍 数据库路径:', dbPath);
console.log('📊 Excel文件路径:', excelPath);

// 读取Excel文件
let workbook;
try {
    workbook = XLSX.readFile(excelPath);
    console.log('✅ Excel文件读取成功');
} catch (err) {
    console.error('❌ 无法读取Excel文件:', err.message);
    process.exit(1);
}

// 获取第一个工作表
const sheetName = workbook.SheetNames[0];
const worksheet = workbook.Sheets[sheetName];
const data = XLSX.utils.sheet_to_json(worksheet);

console.log(`📋 工作表名称: ${sheetName}`);
console.log(`📊 数据行数: ${data.length}`);

if (data.length > 0) {
    console.log('📝 数据列名:', Object.keys(data[0]));
    console.log('🔍 第一行数据示例:', data[0]);
}

// 连接数据库
const db = new sqlite3.Database(dbPath, (err) => {
    if (err) {
        console.error('❌ 无法连接数据库:', err.message);
        process.exit(1);
    }
    
    console.log('✅ 数据库连接成功');
    
    // 开始导入数据
    importData();
});

function importData() {
    // 准备插入语句
    const insertSQL = `
        INSERT INTO PRParkings (
            name, address, latitude, longitude, 
            totalSpaces, pricePerHour, city, 
            facilities, operatingHours, contactPhone, 
            isActive, createdAt, updatedAt
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `;
    
    let successCount = 0;
    let errorCount = 0;
    
    // 开始事务
    db.serialize(() => {
        db.run("BEGIN TRANSACTION");
        
        const stmt = db.prepare(insertSQL);
        
        data.forEach((row, index) => {
            try {
                // 根据Excel列名映射数据
                const name = row['停车场名称'] || `汉堡停车场${index + 1}`;
                const address = row['地址'] || '';
                const latitude = parseFloat(row['纬度'] || 0);
                const longitude = parseFloat(row['经度'] || 0);
                const totalSpaces = parseInt(row['总车位数'] || 0);
                const pricePerHour = row['每小时价格(€)'] ? parseFloat(row['每小时价格(€)']) : null;
                const city = row['城市'] || 'Hamburg';
                const facilities = row['设施'] || 'P+R服务';
                const publicTransport = row['公共交通'] || '';
                const operatingHours = row['营业时间'] || '24h';
                const contactPhone = row['联系电话'] || '';
                const notes = row['备注'] || '';
                const isActive = (row['是否活跃'] === 'Ja' || row['是否活跃'] === '是') ? 1 : 1; // 默认激活
                const createdAt = new Date().toISOString();
                const updatedAt = new Date().toISOString();
                
                // 组合设施信息
                let facilitiesText = facilities;
                if (publicTransport) {
                    facilitiesText += `, 公共交通: ${publicTransport}`;
                }
                if (notes) {
                    facilitiesText += `, ${notes}`;
                }
                
                // 验证必要字段
                if (!name || latitude === 0 || longitude === 0) {
                    console.warn(`⚠️  跳过第${index + 1}行：缺少必要数据`, { name, latitude, longitude });
                    errorCount++;
                    return;
                }
                
                stmt.run([
                    name, address, latitude, longitude,
                    totalSpaces, pricePerHour, city,
                    facilitiesText, operatingHours, contactPhone,
                    isActive, createdAt, updatedAt
                ], function(err) {
                    if (err) {
                        console.error(`❌ 插入第${index + 1}行失败:`, err.message);
                        errorCount++;
                    } else {
                        successCount++;
                        console.log(`✅ 插入成功: ${name} (ID: ${this.lastID})`);
                    }
                });
                
            } catch (err) {
                console.error(`❌ 处理第${index + 1}行数据失败:`, err.message);
                errorCount++;
            }
        });
        
        stmt.finalize((err) => {
            if (err) {
                console.error('❌ 语句执行失败:', err.message);
                db.run("ROLLBACK");
            } else {
                db.run("COMMIT", (err) => {
                    if (err) {
                        console.error('❌ 提交事务失败:', err.message);
                    } else {
                        console.log('\n📊 导入完成统计:');
                        console.log(`✅ 成功导入: ${successCount} 条记录`);
                        console.log(`❌ 失败记录: ${errorCount} 条记录`);
                        
                        // 验证导入结果
                        verifyImport();
                    }
                });
            }
        });
    });
}

function verifyImport() {
    console.log('\n🔍 验证导入结果...');
    
    // 查询汉堡停车场数量
    db.get("SELECT COUNT(*) as count FROM PRParkings WHERE city = 'Hamburg'", [], (err, row) => {
        if (err) {
            console.error('❌ 验证查询失败:', err.message);
        } else {
            const hamburgCount = row ? row.count : 0;
            console.log(`🏙️ 汉堡停车场总数: ${hamburgCount} 个`);
            
            // 显示汉堡停车场列表
            db.all("SELECT id, name, address, totalSpaces, pricePerHour FROM PRParkings WHERE city = 'Hamburg' ORDER BY id", [], (err, rows) => {
                if (err) {
                    console.error('❌ 查询汉堡停车场失败:', err.message);
                } else {
                    console.log('\n📋 汉堡停车场列表:');
                    rows.forEach((row, index) => {
                        const price = row.pricePerHour ? `€${row.pricePerHour}/小时` : '免费';
                        console.log(`   ${index + 1}. [${row.id}] ${row.name} - ${row.totalSpaces}车位 - ${price}`);
                        if (row.address) {
                            console.log(`      地址: ${row.address}`);
                        }
                    });
                }
                
                // 关闭数据库连接
                db.close((err) => {
                    if (err) {
                        console.error('❌ 关闭数据库失败:', err.message);
                    } else {
                        console.log('\n✅ 数据库连接已关闭');
                    }
                });
            });
        }
    });
}