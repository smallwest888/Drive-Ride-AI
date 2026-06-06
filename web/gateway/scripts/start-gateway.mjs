import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const gatewayDir = path.resolve(import.meta.dirname, "..");
const rootDir = path.resolve(gatewayDir, "..");
const configPath = path.join(gatewayDir, "openclaw.local.json");
const pluginPath = path.join(rootDir, "openclaw-drive-ride-plugin");
const bundledNodePath =
  process.env.OPENCLAW_NODE_PATH ||
  (process.platform === "win32"
    ? "C:\\Users\\ZHOU\\.cache\\codex-runtimes\\codex-primary-runtime\\dependencies\\node\\bin\\node.exe"
    : process.execPath);

const qwenApiKey =
  process.env.QWEN_API_KEY ||
  process.env.DASHSCOPE_API_KEY ||
  "sk-48e1ffb9564d4b40ac609e7e3203ed5e";

const config = {
  gateway: {
    mode: "local",
    port: 18789,
    bind: "loopback",
    auth: {
      mode: "token",
      token: "drive-ride-openclaw-local-token"
    },
    http: {
      endpoints: {
        chatCompletions: {
          enabled: true
        }
      }
    }
  },
  plugins: {
    enabled: true,
    load: {
      paths: [pluginPath]
    },
    entries: {
      "drive-ride-agent": {
        enabled: true
      }
    }
  },
  tools: {
    profile: "minimal",
    alsoAllow: ["drive_ride_plan_trip"]
  },
  agents: {
    defaults: {
      model: {
        primary: "qwen/qwen3.5-plus"
      }
    }
  },
  models: {
    providers: {
      qwen: {
        baseUrl: "https://dashscope.aliyuncs.com/compatible-mode/v1",
        apiKey: "${QWEN_API_KEY}"
      }
    }
  }
};

fs.writeFileSync(configPath, JSON.stringify(config, null, 2));

const env = {
  ...process.env,
  OPENCLAW_CONFIG_PATH: configPath,
  QWEN_API_KEY: qwenApiKey
};

const openclawEntry = path.join(rootDir, "node_modules", "openclaw", "openclaw.mjs");
const child = spawn(bundledNodePath, [openclawEntry, "gateway", "--port", "18789"], {
  cwd: gatewayDir,
  stdio: "inherit",
  env
});

child.on("exit", (code) => {
  process.exit(code ?? 0);
});
