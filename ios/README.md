# Drive-Ride-AI · iOS App

SwiftUI 构建的 AI 出行助手，ChatBot 风格交互。用户用自然语言描述出行需求，
App 会解析出发地/目的地/偏好，比较多种出行方式的**成本**与**时间**，并给出几种方案卡片。

## 运行要求

- Xcode 16 或更高版本
- iOS 18.0+（部署目标，可在工程设置中调整）
- 无第三方依赖，纯 SwiftUI / Foundation

## 如何运行

1. 用 Xcode 打开 `DriveRideAI/DriveRideAI.xcodeproj`
2. 选择一个 iOS 18 模拟器（如 iPhone 16）
3. `Cmd + R` 运行

> 工程采用 Xcode 16 的「同步文件夹」（File System Synchronized Group）格式，
> `DriveRideAI/` 目录下的所有 `.swift` 文件会被自动纳入编译，无需手动管理引用。

## 试一试

直接在输入框描述需求，或点击引导气泡，例如：

- 「我想从北京去上海，预算有限，周五出发」
- 「成都到重庆，两个人，想快点到」
- 「杭州到南京，最环保的方式」

## 架构（MVVM）

```
DriveRideAI/
├── DriveRideAIApp.swift        # App 入口
├── Models/                     # 数据模型
│   ├── TravelMode.swift        # 出行方式 + 估算参数（速度/单价/碳排放…）
│   ├── TripRequest.swift       # 解析后的出行需求与偏好
│   ├── TravelPlan.swift        # 单条出行方案（成本/时间/舒适度/碳排放）
│   └── ChatMessage.swift       # 聊天消息（可携带方案卡片）
├── Services/
│   ├── RouteData.swift         # 内置城市坐标 + 距离估算（Haversine）
│   ├── TripPlanning.swift      # 规划服务协议
│   ├── LocalTripPlanner.swift  # 离线启发式引擎 + 自然语言解析
│   └── AITripPlanner.swift     # 可选 LLM 增强（OpenAI 兼容接口）
├── ViewModels/
│   └── ChatViewModel.swift     # 聊天状态管理
└── Views/
    ├── ChatView.swift          # 主界面
    ├── MessageBubbleView.swift # 聊天气泡
    ├── PlanCardView.swift      # 方案卡片
    ├── InputBarView.swift      # 底部输入栏
    └── TypingIndicatorView.swift
```

## 规划引擎说明

- **默认离线可用**：`LocalTripPlanner` 在本地完成需求解析、距离估算、各出行方式的成本与时间计算，
  并标注「最快 / 最省钱 / 最舒适 / 最环保」，再按用户偏好排序。无需联网或 API Key。
- **可选 LLM 增强**：`AITripPlanner` 在结构化方案的基础上，用大语言模型生成更自然的中文建议。
  结构化数据始终由本地引擎计算，保证可靠、不编造。

### 接入大语言模型（可选）

设置以下任意一种配置即可启用（未配置则自动回退到纯本地文案）：

- 环境变量：`OPENAI_API_KEY`、`OPENAI_BASE_URL`（默认 OpenAI）、`OPENAI_MODEL`（默认 `gpt-4o-mini`）
- 或在 App 的 Info 配置中加入对应键值

> 注意：不要把真实 API Key 提交到仓库。`.gitignore` 已忽略 `Secrets.plist` 与 `.env`。

## 说明

- 城市距离与各出行方式的成本/时间为**工程估算**，用于方案对比演示；
  接入真实票价 / 地图 API 后可替换 `RouteData` 与 `LocalTripPlanner` 中的估算逻辑获得更精确结果。
