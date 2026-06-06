# P+R停车场管理后台API服务器

## 📋 说明

这是管理后台的后端API服务器，用于连接真实的SQLite数据库。

## 🚀 快速开始

### 1. 安装依赖

```bash
cd server
npm install
```

### 2. 启动服务器

```bash
npm start
```

或者使用开发模式（自动重启）：

```bash
npm run dev
```

### 3. 访问API

服务器启动后，访问：`http://localhost:3000`

## 📡 API端点

### 获取所有停车场
```
GET /api/parkings
```

### 获取单个停车场
```
GET /api/parkings/:id
```

### 添加停车场
```
POST /api/parkings
Content-Type: application/json

{
  "name": "P+R Westfriedhof",
  "address": "Vaalser Straße 340, 52074 Aachen",
  "latitude": 50.7753,
  "longitude": 6.0839,
  "totalSpaces": 200,
  "city": "Aachen",
  "pricePerHour": null,
  "facilities": "P+R服务,公交连接",
  "operatingHours": "24小时",
  "contactPhone": "+49-241-234567"
}
```

### 批量添加停车场
```
POST /api/parkings/batch
Content-Type: application/json

[
  {
    "name": "P+R Westfriedhof",
    "address": "Vaalser Straße 340, 52074 Aachen",
    "latitude": 50.7753,
    "longitude": 6.0839,
    "totalSpaces": 200,
    "city": "Aachen"
  }
]
```

### 更新停车场
```
PUT /api/parkings/:id
Content-Type: application/json

{
  "name": "更新后的名称",
  ...
}
```

### 删除停车场
```
DELETE /api/parkings/:id
```

### 获取统计信息
```
GET /api/stats
```

### 健康检查
```
GET /api/health
```

## 📁 数据库配置

服务器会自动查找数据库文件，按以下优先级：

1. `../CityDriveRide/prparking.db`（项目目录）
2. `./prparking.db`（服务器目录）

如果数据库文件不存在，服务器会自动创建。

## 🔧 配置数据库路径

如果需要使用特定的数据库文件，可以修改 `server.js` 中的 `DB_PATH` 变量：

```javascript
const DB_PATH = '/path/to/your/database.db';
```

## 📝 注意事项

1. **数据库文件位置**：确保数据库文件路径正确
2. **端口冲突**：默认端口3000，如果被占用可以修改
3. **CORS**：已启用CORS，允许跨域请求
4. **数据验证**：API会验证必填字段

## 🛠️ 开发

### 安装开发依赖
```bash
npm install --save-dev nodemon
```

### 开发模式运行
```bash
npm run dev
```

## 🔒 生产环境

生产环境建议：
1. 添加身份验证
2. 使用HTTPS
3. 添加请求限流
4. 配置环境变量
5. 使用进程管理器（如PM2）

