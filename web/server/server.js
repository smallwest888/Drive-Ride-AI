const express = require('express');
const cors = require('cors');
const bodyParser = require('body-parser');
const sqlite3 = require('sqlite3').verbose();
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = 3000;

// 中间件
app.use(cors());
app.use(bodyParser.json());
app.use(bodyParser.urlencoded({ extended: true }));

// 数据库文件路径配置
// 优先级1: 生产环境数据目录（推荐用于服务器部署）
const DB_PATH_1 = path.join(__dirname, '..', 'data', 'prparking.db');
// 优先级2: 项目目录下的数据库文件（与iOS应用共享，用于本地开发）
const DB_PATH_2 = path.join(__dirname, '..', 'CityDriveRide', 'prparking.db');
// 优先级3: 服务器目录下的数据库文件（备用）
const DB_PATH_3 = path.join(__dirname, 'prparking.db');

// 根据环境变量或文件存在性选择数据库路径
let dbPath;
if (process.env.DB_PATH) {
    // 如果设置了环境变量，优先使用
    dbPath = process.env.DB_PATH;
    console.log(`📁 使用环境变量指定的数据库路径: ${dbPath}`);
} else if (fs.existsSync(DB_PATH_1)) {
    dbPath = DB_PATH_1;
    console.log(`📁 使用生产环境数据库路径: ${dbPath}`);
} else if (fs.existsSync(DB_PATH_2)) {
    dbPath = DB_PATH_2;
    console.log(`📁 使用本地开发数据库路径: ${dbPath}`);
} else {
    dbPath = DB_PATH_3;
    console.log(`⚠️  数据库文件不存在于前两个路径，使用备用路径: ${dbPath}`);
}

// 初始化数据库连接
let db;
function initDatabase() {
    return new Promise((resolve, reject) => {
        // 如果数据库文件不存在，先创建
        if (!fs.existsSync(dbPath)) {
            console.log(`📁 数据库文件不存在，创建新数据库: ${dbPath}`);
            db = new sqlite3.Database(dbPath, (err) => {
                if (err) {
                    console.error('❌ 创建数据库失败:', err);
                    reject(err);
                } else {
                    console.log('✅ 数据库创建成功');
                    createTables().then(resolve).catch(reject);
                }
            });
        } else {
            db = new sqlite3.Database(dbPath, (err) => {
                if (err) {
                    console.error('❌ 打开数据库失败:', err);
                    reject(err);
                } else {
                    console.log(`✅ 数据库连接成功: ${dbPath}`);
                    // 检查表是否存在
                    checkAndCreateTables().then(resolve).catch(reject);
                }
            });
        }
    });
}

// 检查表是否存在，如果不存在则创建
function checkAndCreateTables() {
    return new Promise((resolve, reject) => {
        // 检查PRParkings表是否存在
        db.get("SELECT name FROM sqlite_master WHERE type='table' AND name='PRParkings'", [], (err, row) => {
            if (err) {
                console.error('❌ 检查表失败:', err);
                reject(err);
            } else if (!row) {
                console.log('⚠️  表不存在，开始创建表...');
                createTables().then(resolve).catch(reject);
            } else {
                console.log('✅ 表已存在，跳过创建');
                // 检查并添加publicTransport列（如果不存在）
                migrateAddPublicTransportColumn()
                    .then(() => migrateAddNotesColumn())
                    .then(resolve)
                    .catch(resolve);
            }
        });
    });
}

// 数据库迁移：添加publicTransport列（如果不存在）
function migrateAddPublicTransportColumn() {
    return new Promise((resolve, reject) => {
        // 检查列是否存在
        db.all("PRAGMA table_info(PRParkings)", [], (err, columns) => {
            if (err) {
                console.error('❌ 检查列失败:', err);
                reject(err);
                return;
            }
            
            const hasPublicTransport = columns.some(col => col.name === 'publicTransport');
            
            if (!hasPublicTransport) {
                console.log('🔄 添加publicTransport列...');
                db.run("ALTER TABLE PRParkings ADD COLUMN publicTransport TEXT DEFAULT ''", (err) => {
                    if (err) {
                        console.error('❌ 添加publicTransport列失败:', err);
                        reject(err);
                    } else {
                        console.log('✅ publicTransport列添加成功');
                        // 从facilities列提取公共交通信息
                        extractPublicTransportFromFacilities().then(resolve).catch(resolve);
                    }
                });
            } else {
                console.log('ℹ️  publicTransport列已存在');
                resolve();
            }
        });
    });
}

// 数据库迁移：添加notes列（如果不存在）
function migrateAddNotesColumn() {
    return new Promise((resolve, reject) => {
        // 检查列是否存在
        db.all("PRAGMA table_info(PRParkings)", [], (err, columns) => {
            if (err) {
                console.error('❌ 检查列失败:', err);
                reject(err);
                return;
            }
            
            const hasNotes = columns.some(col => col.name === 'notes');
            
            if (!hasNotes) {
                console.log('🔄 添加notes列...');
                db.run("ALTER TABLE PRParkings ADD COLUMN notes TEXT DEFAULT ''", (err) => {
                    if (err) {
                        console.error('❌ 添加notes列失败:', err);
                        reject(err);
                    } else {
                        console.log('✅ notes列添加成功');
                        resolve();
                    }
                });
            } else {
                console.log('ℹ️  notes列已存在');
                resolve();
            }
        });
    });
}

// 从facilities列提取公共交通信息到publicTransport列
function extractPublicTransportFromFacilities() {
    return new Promise((resolve, reject) => {
        db.all("SELECT id, facilities, publicTransport FROM PRParkings WHERE facilities IS NOT NULL AND facilities != ''", [], (err, rows) => {
            if (err) {
                console.error('❌ 查询失败:', err);
                reject(err);
                return;
            }
            
            let updateCount = 0;
            const updatePromises = rows.map(row => {
                return new Promise((resolveUpdate) => {
                    // 如果publicTransport已有值，跳过
                    if (row.publicTransport) {
                        resolveUpdate();
                        return;
                    }
                    
                    const facilities = row.facilities || '';
                    let publicTransport = '';
                    
                    // 第一步：检查是否有"ÖPNV-Anbindung:"格式
                    if (facilities.includes('ÖPNV-Anbindung:')) {
                        // 提取"ÖPNV-Anbindung:"之后的内容
                        const opnvMatch = facilities.match(/ÖPNV-Anbindung:\s*([^,]+(?:,\s*[^,]+)*)/);
                        if (opnvMatch && opnvMatch[1]) {
                            let opnvContent = opnvMatch[1].trim();
                            
                            // 移除常见的非公交线路关键词
                            const nonTransportKeywords = [
                                'Behindertenstellplätze', 'Fahrradstellplätze', 'Frauenstellplätze',
                                'Familienstellplätze', 'Elektroladesäulen', 'Bahnhof Kiosk',
                                'Toiletten', 'Telefon', 'Videokontrollsystem', 'Packstation',
                                'Kiosk', 'Lift', 'Motorradstellplätze', 'Elektroluftpumpe',
                                'Batterieladestation'
                            ];
                            
                            nonTransportKeywords.forEach(keyword => {
                                opnvContent = opnvContent.replace(new RegExp(keyword, 'gi'), '');
                            });
                            
                            // 清理多余的空格和逗号
                            opnvContent = opnvContent.replace(/\s+/g, ' ').replace(/,\s*,/g, ',').trim();
                            
                            if (opnvContent) {
                                publicTransport = opnvContent;
                            }
                        }
                    }
                    
                    // 第二步：如果没有从ÖPNV格式提取到，尝试正则表达式匹配
                    if (!publicTransport) {
                        // 匹配 S/U/RE/ICE/RB/BRB + 数字，或单独的RE/RB/BRB
                        const transportMatch = facilities.match(/\b([SU]\d+|RE\d*|RB\d*|BRB|ICE\d*)\b/gi);
                        
                        if (transportMatch && transportMatch.length > 0) {
                            publicTransport = transportMatch.map(m => m.trim()).filter(m => m).join(', ');
                        }
                    }
                    
                    // 如果提取到了公交信息，更新数据库
                    if (publicTransport) {
                        // 最终清理：统一格式
                        publicTransport = publicTransport.replace(/\s*,\s*/g, ', ').trim();
                        
                        db.run("UPDATE PRParkings SET publicTransport = ? WHERE id = ?", [publicTransport, row.id], (err) => {
                            if (!err) {
                                updateCount++;
                            }
                            resolveUpdate();
                        });
                    } else {
                        resolveUpdate();
                    }
                });
            });
            
            Promise.all(updatePromises).then(() => {
                if (updateCount > 0) {
                    console.log(`✅ 从facilities提取了 ${updateCount} 条公共交通信息`);
                }
                resolve();
            }).catch(reject);
        });
    });
}

// 创建表结构
function createTables() {
    return new Promise((resolve, reject) => {
        // 优先查找SQL文件，支持多个位置
        let sqlPath = path.join(__dirname, 'database_schema_unified.sql');
        if (!fs.existsSync(sqlPath)) {
            sqlPath = path.join(__dirname, '..', 'CityDriveRide', 'database_schema_unified.sql');
        }
        if (!fs.existsSync(sqlPath)) {
            sqlPath = path.join(__dirname, '..', 'database_schema_unified.sql');
        }
        
        if (!fs.existsSync(sqlPath)) {
            console.log('⚠️  SQL文件不存在，使用内联SQL创建表');
            // 如果SQL文件不存在，使用内联SQL
            const createTableSQL = `
                CREATE TABLE IF NOT EXISTS PRParkings (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    address TEXT NOT NULL,
                    latitude REAL NOT NULL,
                    longitude REAL NOT NULL,
                    availableSpaces INTEGER NOT NULL DEFAULT 0,
                    totalSpaces INTEGER NOT NULL DEFAULT 0,
                    pricePerHour REAL DEFAULT NULL,
                    city TEXT NOT NULL,
                    facilities TEXT DEFAULT '',
                    publicTransport TEXT DEFAULT '',
                    operatingHours TEXT DEFAULT '',
                    contactPhone TEXT DEFAULT '',
                    notes TEXT DEFAULT '',
                    isActive INTEGER DEFAULT 1,
                    createdAt TEXT DEFAULT CURRENT_TIMESTAMP,
                    updatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
                    CHECK (availableSpaces >= 0),
                    CHECK (totalSpaces >= 0),
                    CHECK (availableSpaces <= totalSpaces),
                    CHECK (pricePerHour IS NULL OR pricePerHour >= 0),
                    CHECK (latitude >= -90 AND latitude <= 90),
                    CHECK (longitude >= -180 AND longitude <= 180)
                );
                    operatingHours TEXT DEFAULT '',
                    contactPhone TEXT DEFAULT '',
                    notes TEXT DEFAULT '',
                    isActive INTEGER DEFAULT 1,
                    createdAt TEXT DEFAULT CURRENT_TIMESTAMP,
                    updatedAt TEXT DEFAULT CURRENT_TIMESTAMP,
                    CHECK (totalSpaces >= 0),
                    CHECK (pricePerHour IS NULL OR pricePerHour >= 0),
                    CHECK (latitude >= -90 AND latitude <= 90),
                    CHECK (longitude >= -180 AND longitude <= 180)
                );
                
                CREATE TABLE IF NOT EXISTS DatabaseStats (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    statName TEXT UNIQUE NOT NULL,
                    statValue TEXT NOT NULL,
                    updatedAt TEXT DEFAULT CURRENT_TIMESTAMP
                );
            `;
            
            db.exec(createTableSQL, (err) => {
                if (err) {
                    console.error('❌ 创建表失败:', err);
                    reject(err);
                } else {
                    console.log('✅ 表创建成功');
                    resolve();
                }
            });
        } else {
            // 读取并执行SQL文件
            const sqlContent = fs.readFileSync(sqlPath, 'utf8');
            
            // 改进的SQL解析：正确处理BEGIN...END块和多行语句
            const lines = sqlContent.split('\n');
            let statements = [];
            let currentStatement = '';
            let inMultiLineComment = false;
            let beginDepth = 0; // 跟踪BEGIN的嵌套深度
            
            for (let i = 0; i < lines.length; i++) {
                let line = lines[i].trim();
                
                // 跳过空行
                if (line.length === 0) {
                    continue;
                }
                
                // 处理多行注释 /* ... */
                if (line.includes('/*')) {
                    inMultiLineComment = true;
                    const commentStart = line.indexOf('/*');
                    line = line.substring(0, commentStart).trim();
                }
                if (line.includes('*/')) {
                    inMultiLineComment = false;
                    const commentEnd = line.indexOf('*/');
                    line = line.substring(commentEnd + 2).trim();
                }
                if (inMultiLineComment) {
                    continue;
                }
                
                // 移除单行注释
                const commentIndex = line.indexOf('--');
                if (commentIndex >= 0) {
                    line = line.substring(0, commentIndex).trim();
                }
                
                // 跳过纯注释行
                if (line.length === 0) {
                    continue;
                }
                
                // 检查BEGIN和END（不区分大小写）
                const upperLine = line.toUpperCase();
                if (upperLine.includes('BEGIN')) {
                    // 计算BEGIN的数量（可能一行有多个BEGIN）
                    const beginMatches = upperLine.match(/\bBEGIN\b/g);
                    if (beginMatches) {
                        beginDepth += beginMatches.length;
                    }
                }
                if (upperLine.includes('END')) {
                    // 计算END的数量
                    const endMatches = upperLine.match(/\bEND\b/g);
                    if (endMatches) {
                        beginDepth -= endMatches.length;
                        beginDepth = Math.max(0, beginDepth); // 防止负数
                    }
                }
                
                // 累积到当前语句
                currentStatement += (currentStatement ? ' ' : '') + line;
                
                // 只有在没有未闭合的BEGIN块且行以分号结尾时，才完成一个语句
                if (beginDepth === 0 && line.endsWith(';')) {
                    const statement = currentStatement.slice(0, -1).trim(); // 移除末尾的分号
                    if (statement.length > 0) {
                        statements.push(statement);
                    }
                    currentStatement = '';
                }
            }
            
            // 处理最后一个语句（如果没有以分号结尾）
            if (currentStatement.trim().length > 0) {
                statements.push(currentStatement.trim());
            }
            
            console.log(`📝 准备执行 ${statements.length} 条SQL语句`);
            
            // 显示前几条语句用于调试
            if (statements.length > 0) {
                console.log(`   前3条语句预览:`);
                statements.slice(0, 3).forEach((stmt, idx) => {
                    console.log(`   ${idx + 1}. ${stmt.substring(0, 80).replace(/\s+/g, ' ')}...`);
                });
            }
            
            // 使用串行执行确保顺序
            let currentIndex = 0;
            let successCount = 0;
            let skipCount = 0;
            
            function executeNext() {
                if (currentIndex >= statements.length) {
                    console.log(`✅ SQL文件执行完成 (成功: ${successCount}, 跳过: ${skipCount})`);
                    // 验证表是否创建成功
                    db.get("SELECT name FROM sqlite_master WHERE type='table' AND name='PRParkings'", [], (err, row) => {
                        if (err) {
                            console.error('❌ 验证表创建失败:', err);
                            resolve();
                        } else if (row) {
                            console.log('✅ 验证: PRParkings表已成功创建');
                            // 检查数据数量
                            db.get("SELECT COUNT(*) as count FROM PRParkings", [], (countErr, countRow) => {
                                if (countErr) {
                                    console.error('❌ 检查数据数量失败:', countErr);
                                } else {
                                    const count = countRow ? countRow.count : 0;
                                    if (count > 0) {
                                        console.log(`✅ 验证: 数据库中有 ${count} 条停车场数据`);
                                    } else {
                                        console.log(`⚠️  警告: 数据库中没有数据，可能需要手动插入初始数据`);
                                    }
                                }
                                resolve();
                            });
                        } else {
                            console.error('❌ 验证失败: PRParkings表未创建');
                            resolve();
                        }
                    });
                    return;
                }
                
                const statement = statements[currentIndex];
                const statementNum = currentIndex + 1;
                currentIndex++;
                
                // 跳过空语句
                if (!statement || statement.trim().length === 0) {
                    executeNext();
                    return;
                }
                
                // 记录重要语句的执行
                const upperStatement = statement.toUpperCase();
                if (upperStatement.includes('CREATE TABLE')) {
                    console.log(`📋 执行语句 ${statementNum}: CREATE TABLE...`);
                } else if (upperStatement.includes('INSERT')) {
                    console.log(`📥 执行语句 ${statementNum}: INSERT...`);
                }
                
                db.run(statement, function(err) {
                    if (err) {
                        // 忽略"already exists"错误（表/索引已存在）
                        if (err.message.includes('already exists') || 
                            err.message.includes('duplicate') ||
                            err.message.includes('UNIQUE constraint')) {
                            skipCount++;
                            executeNext();
                        } else {
                            console.error(`❌ SQL语句 ${statementNum} 执行失败:`, err.message);
                            console.error(`   语句预览: ${statement.substring(0, 150).replace(/\s+/g, ' ')}...`);
                            reject(err);
                        }
                    } else {
                        successCount++;
                        // 如果是CREATE TABLE语句，记录成功
                        if (upperStatement.includes('CREATE TABLE')) {
                            console.log(`   ✅ CREATE TABLE语句执行成功`);
                        } else if (upperStatement.includes('INSERT')) {
                            // INSERT语句可能插入多行，this.changes显示受影响的行数
                            const rowsAffected = this.changes || 0;
                            if (rowsAffected > 0) {
                                console.log(`   ✅ INSERT语句执行成功，插入了 ${rowsAffected} 行数据`);
                            } else {
                                console.log(`   ⚠️  INSERT语句执行但未插入数据（可能已存在）`);
                            }
                        }
                        executeNext();
                    }
                });
            }
            
            executeNext();
        }
    });
}

// API路由

// 获取所有停车场
app.get('/api/parkings', (req, res) => {
    // 确保数据库已初始化
    if (!db) {
        return res.status(503).json({ error: '数据库未初始化' });
    }
    
    // 先查询所有数据（包括isActive=0的），用于调试
    const queryAll = 'SELECT * FROM PRParkings ORDER BY city, name';
    const query = 'SELECT * FROM PRParkings WHERE isActive = 1 ORDER BY city, name';
    
    // 先检查是否有数据
    db.get('SELECT COUNT(*) as count FROM PRParkings', [], (countErr, countRow) => {
        if (countErr) {
            console.error('❌ 查询数据数量失败:', countErr);
            return res.status(500).json({ error: '查询失败', message: countErr.message });
        }
        
        const totalCount = countRow ? countRow.count : 0;
        console.log(`📊 数据库中共有 ${totalCount} 条数据`);
        
        if (totalCount === 0) {
            console.log('⚠️  数据库为空，返回空数组');
            return res.json([]);
        }
        
        // 查询活跃的停车场
        db.all(query, [], (err, rows) => {
            if (err) {
                console.error('❌ 查询失败:', err);
                // 如果是表不存在错误，尝试重新创建表
                if (err.message.includes('no such table')) {
                    console.log('⚠️  检测到表不存在，尝试重新创建...');
                    checkAndCreateTables().then(() => {
                        // 重试查询
                        db.all(query, [], (retryErr, retryRows) => {
                            if (retryErr) {
                                res.status(500).json({ error: '查询失败', message: retryErr.message });
                            } else {
                                const parkings = retryRows.map(row => ({
                                    id: row.id,
                                    name: row.name,
                                    address: row.address,
                                    latitude: row.latitude,
                                    longitude: row.longitude,
                                    totalSpaces: row.totalSpaces,
                                    pricePerHour: row.pricePerHour,
                                    city: row.city,
                                    facilities: row.facilities || '',
                                    publicTransport: row.publicTransport || '',
                                    operatingHours: row.operatingHours || '',
                                    contactPhone: row.contactPhone || '',
                                    notes: row.notes || '',
                                    isActive: row.isActive === 1,
                                    createdAt: row.createdAt,
                                    updatedAt: row.updatedAt
                                }));
                                res.json(parkings);
                            }
                        });
                    }).catch(createErr => {
                        res.status(500).json({ error: '创建表失败', message: createErr.message });
                    });
                } else {
                    res.status(500).json({ error: '查询失败', message: err.message });
                }
            } else {
                const parkings = rows.map(row => ({
                    id: row.id,
                    name: row.name,
                    address: row.address,
                    latitude: row.latitude,
                    longitude: row.longitude,
                    totalSpaces: row.totalSpaces,
                    pricePerHour: row.pricePerHour,
                    city: row.city,
                    facilities: row.facilities || '',
                    publicTransport: row.publicTransport || '',
                    operatingHours: row.operatingHours || '',
                    contactPhone: row.contactPhone || '',
                    notes: row.notes || '',
                    isActive: row.isActive === 1,
                    createdAt: row.createdAt,
                    updatedAt: row.updatedAt
                }));
                console.log(`✅ 返回 ${parkings.length} 条活跃停车场数据`);
                res.json(parkings);
            }
        });
    });
});

// 获取单个停车场
app.get('/api/parkings/:id', (req, res) => {
    const id = parseInt(req.params.id);
    const query = 'SELECT * FROM PRParkings WHERE id = ?';
    
    db.get(query, [id], (err, row) => {
        if (err) {
            console.error('❌ 查询失败:', err);
            res.status(500).json({ error: '查询失败', message: err.message });
        } else if (!row) {
            res.status(404).json({ error: '停车场不存在' });
        } else {
            res.json({
                id: row.id,
                name: row.name,
                address: row.address,
                latitude: row.latitude,
                longitude: row.longitude,
                totalSpaces: row.totalSpaces,
                pricePerHour: row.pricePerHour,
                city: row.city,
                facilities: row.facilities || '',
                publicTransport: row.publicTransport || '',
                operatingHours: row.operatingHours || '',
                contactPhone: row.contactPhone || '',
                notes: row.notes || '',
                isActive: row.isActive === 1,
                createdAt: row.createdAt,
                updatedAt: row.updatedAt
            });
        }
    });
});

// 添加停车场
app.post('/api/parkings', (req, res) => {
    const { name, address, latitude, longitude, totalSpaces, pricePerHour, city, facilities, publicTransport, operatingHours, contactPhone, notes } = req.body;
    
    // 验证必填字段
    if (!name || !address || !city || latitude === undefined || longitude === undefined || totalSpaces === undefined) {
        return res.status(400).json({ error: '缺少必填字段' });
    }
    
    const query = `
        INSERT INTO PRParkings (name, address, latitude, longitude, totalSpaces, pricePerHour, city, facilities, publicTransport, operatingHours, contactPhone, notes, isActive, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, datetime('now'), datetime('now'))
    `;
    
    db.run(query, [
        name,
        address,
        latitude,
        longitude,
        totalSpaces,
        pricePerHour || null,
        city,
        facilities || '',
        publicTransport || '',
        operatingHours || '',
        contactPhone || '',
        notes || ''
    ], function(err) {
        if (err) {
            console.error('❌ 插入失败:', err);
            res.status(500).json({ error: '插入失败', message: err.message });
        } else {
            res.json({
                id: this.lastID,
                message: '添加成功',
                success: true
            });
        }
    });
});

// 批量添加停车场
app.post('/api/parkings/batch', (req, res) => {
    const parkings = req.body;
    
    if (!Array.isArray(parkings) || parkings.length === 0) {
        return res.status(400).json({ error: '数据格式错误，需要数组格式' });
    }
    
    const query = `
        INSERT INTO PRParkings (name, address, latitude, longitude, totalSpaces, pricePerHour, city, facilities, publicTransport, operatingHours, contactPhone, notes, isActive, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, datetime('now'), datetime('now'))
    `;
    
    let successCount = 0;
    let failCount = 0;
    const errors = [];
    
    db.serialize(() => {
        db.run('BEGIN TRANSACTION');
        
        const stmt = db.prepare(query);
        
        // 使用 Promise 来确保所有插入完成后再 finalize
        const insertPromises = parkings.map((parking, index) => {
            return new Promise((resolve) => {
                // 验证必填字段
                if (!parking.name || !parking.address || !parking.city || 
                    parking.latitude === undefined || parking.longitude === undefined ||
                    parking.totalSpaces === undefined) {
                    failCount++;
                    errors.push(`第 ${index + 1} 条数据缺少必填字段`);
                    resolve();
                    return;
                }
                
                stmt.run([
                    parking.name,
                    parking.address,
                    parking.latitude,
                    parking.longitude,
                    parking.totalSpaces,
                    parking.pricePerHour || null,
                    parking.city,
                    parking.facilities || '',
                    parking.publicTransport || '',
                    parking.operatingHours || '',
                    parking.contactPhone || '',
                    parking.notes || ''
                ], (err) => {
                    if (err) {
                        failCount++;
                        errors.push(`第 ${index + 1} 条数据插入失败: ${err.message}`);
                    } else {
                        successCount++;
                    }
                    resolve();
                });
            });
        });
        
        // 等待所有插入完成后再 finalize
        Promise.all(insertPromises).then(() => {
            stmt.finalize((err) => {
                if (err) {
                    db.run('ROLLBACK');
                    console.error('❌ 批量插入 finalize 失败:', err);
                    res.status(500).json({ error: '批量插入失败', message: err.message });
                } else {
                    db.run('COMMIT', (err) => {
                        if (err) {
                            console.error('❌ 批量插入提交失败:', err);
                            res.status(500).json({ error: '提交事务失败', message: err.message });
                        } else {
                            console.log(`✅ 批量添加完成: 成功 ${successCount} 条，失败 ${failCount} 条`);
                            res.json({
                                success: true,
                                successCount,
                                failCount,
                                errors: errors.length > 0 ? errors : undefined,
                                message: `批量添加完成！成功: ${successCount} 条，失败: ${failCount} 条`
                            });
                        }
                    });
                }
            });
        });
    });
});

// 更新停车场
app.put('/api/parkings/:id', (req, res) => {
    const id = parseInt(req.params.id);
    const { name, address, latitude, longitude, totalSpaces, pricePerHour, city, facilities, publicTransport, operatingHours, contactPhone, notes, isActive } = req.body;
    
    const query = `
        UPDATE PRParkings 
        SET name = ?, address = ?, latitude = ?, longitude = ?, totalSpaces = ?, pricePerHour = ?, 
            city = ?, facilities = ?, publicTransport = ?, operatingHours = ?, contactPhone = ?, notes = ?, isActive = ?, updatedAt = datetime('now')
        WHERE id = ?
    `;
    
    db.run(query, [
        name,
        address,
        latitude,
        longitude,
        totalSpaces,
        pricePerHour || null,
        city,
        facilities || '',
        publicTransport || '',
        operatingHours || '',
        contactPhone || '',
        notes || '',
        isActive ? 1 : 0,
        id
    ], function(err) {
        if (err) {
            console.error('❌ 更新失败:', err);
            res.status(500).json({ error: '更新失败', message: err.message });
        } else if (this.changes === 0) {
            res.status(404).json({ error: '停车场不存在' });
        } else {
            res.json({ success: true, message: '更新成功' });
        }
    });
});

// 删除停车场
app.delete('/api/parkings/:id', (req, res) => {
    const id = parseInt(req.params.id);
    const query = 'DELETE FROM PRParkings WHERE id = ?';
    
    db.run(query, [id], function(err) {
        if (err) {
            console.error('❌ 删除失败:', err);
            res.status(500).json({ error: '删除失败', message: err.message });
        } else if (this.changes === 0) {
            res.status(404).json({ error: '停车场不存在' });
        } else {
            res.json({ success: true, message: '删除成功' });
        }
    });
});

// 获取统计信息
app.get('/api/stats', (req, res) => {
    const queries = {
        total: 'SELECT COUNT(*) as count FROM PRParkings WHERE isActive = 1',
        active: 'SELECT COUNT(*) as count FROM PRParkings WHERE isActive = 1',
        totalSpaces: 'SELECT SUM(totalSpaces) as total FROM PRParkings WHERE isActive = 1'
    };
    
    Promise.all([
        new Promise((resolve, reject) => {
            db.get(queries.total, [], (err, row) => {
                if (err) reject(err);
                else resolve(row.count);
            });
        }),
        new Promise((resolve, reject) => {
            db.get(queries.active, [], (err, row) => {
                if (err) reject(err);
                else resolve(row.count);
            });
        }),
        new Promise((resolve, reject) => {
            db.get(queries.totalSpaces, [], (err, row) => {
                if (err) reject(err);
                else resolve(row.total || 0);
            });
        })
    ]).then(([total, active, totalSpaces]) => {
        res.json({ total, active, totalSpaces });
    }).catch(err => {
        console.error('❌ 获取统计失败:', err);
        res.status(500).json({ error: '获取统计失败', message: err.message });
    });
});

// 初始化数据（插入7个默认停车场）
app.post('/api/init-data', (req, res) => {
    if (!db) {
        return res.status(503).json({ error: '数据库未初始化' });
    }
    
    const initialData = [
        {
            name: 'P+R Westfriedhof',
            address: 'Vaalser Straße 340, Laurensberg, 52074 Aachen, Deutschland',
            latitude: 50.7753,
            longitude: 6.0839,
            totalSpaces: 200,
            pricePerHour: null,
            city: 'Aachen',
            facilities: 'P+R服务,公交连接',
            operatingHours: '24小时',
            contactPhone: '+49-241-234567'
        },
        {
            name: 'FU Berlin',
            address: 'Otto-von-Simson-Straße 12, Dahlem, 14195 Berlin, Deutschland',
            latitude: 52.454143,
            longitude: 13.289695,
            totalSpaces: 0,
            pricePerHour: null,
            city: 'Berlin',
            facilities: 'P+R服务,公交连接',
            operatingHours: '24小时',
            contactPhone: ''
        },
        {
            name: 'P+R Hangeweiher',
            address: 'Hermann-Löns-Allee, 52074 Aachen',
            latitude: 50.7613056,
            longitude: 6.0709167,
            totalSpaces: 120,
            pricePerHour: null,
            city: 'Aachen',
            facilities: 'P+R服务,公交连接',
            operatingHours: '24小时',
            contactPhone: ''
        },
        {
            name: 'P+R Jülicher Straße/Berliner Ring',
            address: 'Jülicher Str. 376, 52070 Aachen',
            latitude: 50.7908056,
            longitude: 6.1184167,
            totalSpaces: 80,
            pricePerHour: null,
            city: 'Aachen',
            facilities: 'P+R服务,公交连接',
            operatingHours: '24小时',
            contactPhone: ''
        },
        {
            name: 'P+R Waldfriedhof',
            address: 'Monschauer Str., 52076 Aachen',
            latitude: 50.7453056,
            longitude: 6.1080000,
            totalSpaces: 99,
            pricePerHour: null,
            city: 'Aachen',
            facilities: 'P+R服务,公交连接',
            operatingHours: '24小时',
            contactPhone: ''
        },
        {
            name: 'P+R Autobahnabfahrt Aachen Zentrum',
            address: 'Krefelder Str. 201, 52070 Aachen',
            latitude: 50.7937500,
            longitude: 6.0954167,
            totalSpaces: 1200,
            pricePerHour: null,
            city: 'Aachen',
            facilities: 'P+R服务,公交连接',
            operatingHours: '24小时',
            contactPhone: ''
        },
        {
            name: 'P+R Vaalser Straße',
            address: 'Vaalser Str., 52074 Aachen',
            latitude: 50.7696667,
            longitude: 6.0489167,
            totalSpaces: 179,
            pricePerHour: null,
            city: 'Aachen',
            facilities: 'P+R服务,公交连接',
            operatingHours: '24小时',
            contactPhone: ''
        }
    ];
    
    const query = `
        INSERT OR REPLACE INTO PRParkings 
        (name, address, latitude, longitude, totalSpaces, pricePerHour, city, facilities, publicTransport, operatingHours, contactPhone, notes, isActive, createdAt, updatedAt)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, datetime('now'), datetime('now'))
    `;
    
    let successCount = 0;
    let failCount = 0;
    
    db.serialize(() => {
        db.run('BEGIN TRANSACTION');
        
        const stmt = db.prepare(query);
        
        initialData.forEach((parking) => {
            stmt.run([
                parking.name,
                parking.address,
                parking.latitude,
                parking.longitude,
                parking.totalSpaces,
                parking.pricePerHour || null,
                parking.city,
                parking.facilities || '',
                parking.publicTransport || '',
                parking.operatingHours || '',
                parking.contactPhone || '',
                parking.notes || ''
            ], (err) => {
                if (err) {
                    console.error('插入失败:', err);
                    failCount++;
                } else {
                    successCount++;
                }
            });
        });
        
        stmt.finalize((err) => {
            if (err) {
                db.run('ROLLBACK');
                res.status(500).json({ error: '初始化失败', message: err.message });
            } else {
                db.run('COMMIT', (err) => {
                    if (err) {
                        res.status(500).json({ error: '提交事务失败', message: err.message });
                    } else {
                        console.log(`✅ 初始化数据完成: 成功 ${successCount} 条，失败 ${failCount} 条`);
                        res.json({
                            success: true,
                            message: `初始化完成！成功: ${successCount} 条，失败: ${failCount} 条`,
                            successCount,
                            failCount
                        });
                    }
                });
            }
        });
    });
});

// 健康检查
// 同步端点：返回所有停车场数据（供iOS App同步使用）
app.get('/api/sync', (req, res) => {
    console.log('📥 收到同步请求');
    
    db.all('SELECT * FROM PRParkings WHERE isActive = 1 ORDER BY city, name', [], (err, rows) => {
        if (err) {
            console.error('❌ 同步查询失败:', err);
            res.status(500).json({ 
                error: true, 
                message: '查询失败: ' + err.message 
            });
            return;
        }
        
        // 获取数据库版本号（如果有）
        db.get("SELECT statValue FROM DatabaseStats WHERE statName = 'schema_version'", [], (err, versionRow) => {
            const version = versionRow ? versionRow.statValue : null;
            const timestamp = new Date().toISOString();
            
            console.log(`✅ 同步成功: 返回 ${rows.length} 条记录，版本: ${version || '未知'}`);
            
            res.json({
                success: true,
                version: version,
                timestamp: timestamp,
                count: rows.length,
                data: rows
            });
        });
    });
});

// 获取同步版本号（用于检查是否有更新）
app.get('/api/sync/version', (req, res) => {
    db.get("SELECT statValue FROM DatabaseStats WHERE statName = 'schema_version'", [], (err, row) => {
        if (err) {
            res.status(500).json({ error: true, message: err.message });
            return;
        }
        
        const version = row ? row.statValue : null;
        const timestamp = new Date().toISOString();
        
        // 获取记录数
        db.get('SELECT COUNT(*) as count FROM PRParkings WHERE isActive = 1', [], (err, countRow) => {
            res.json({
                success: true,
                version: version,
                timestamp: timestamp,
                count: countRow ? countRow.count : 0
            });
        });
    });
});

app.get('/api/health', (req, res) => {
    if (!db) {
        return res.status(503).json({ 
            status: 'error', 
            message: '数据库未初始化',
            database: dbPath
        });
    }
    
    // 检查数据数量
    db.get('SELECT COUNT(*) as count FROM PRParkings', [], (err, row) => {
        const count = err ? 0 : (row ? row.count : 0);
        res.json({ 
            status: 'ok', 
            database: dbPath,
            dataCount: count,
            timestamp: new Date().toISOString()
        });
    });
});

// 启动服务器
initDatabase().then(() => {
    app.listen(PORT, () => {
        console.log(`🚀 API服务器启动成功！`);
        console.log(`📡 服务地址: http://localhost:${PORT}`);
        console.log(`📊 数据库路径: ${dbPath}`);
        console.log(`\n可用API端点:`);
        console.log(`  GET    /api/parkings        - 获取所有停车场`);
        console.log(`  GET    /api/parkings/:id   - 获取单个停车场`);
        console.log(`  POST   /api/parkings        - 添加停车场`);
        console.log(`  POST   /api/parkings/batch - 批量添加停车场`);
        console.log(`  PUT    /api/parkings/:id   - 更新停车场`);
        console.log(`  DELETE /api/parkings/:id  - 删除停车场`);
        console.log(`  GET    /api/stats          - 获取统计信息`);
        console.log(`  GET    /api/health         - 健康检查\n`);
    });
}).catch(err => {
    console.error('❌ 服务器启动失败:', err);
    process.exit(1);
});

// 优雅关闭
process.on('SIGINT', () => {
    console.log('\n正在关闭服务器...');
    if (db) {
        db.close((err) => {
            if (err) {
                console.error('关闭数据库失败:', err);
            } else {
                console.log('✅ 数据库连接已关闭');
            }
            process.exit(0);
        });
    } else {
        process.exit(0);
    }
});

