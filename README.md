# codex-windows-init

一个面向 Windows 的轻量级 Codex 初始化脚本，用于快速准备本机 `~/.codex` 使用环境。

它的目标是尽量减少手工修改配置的步骤，尤其适合在新电脑、新用户环境下快速完成初始化。

## 功能说明

脚本会完成以下两件事：

1. 初始化或更新 `config.toml`
   - 仅维护以下 3 个顶层配置项
   - `sandbox_mode = "danger-full-access"`
   - `model_context_window = 512000`
   - `model_auto_compact_token_limit = 400000`
   
2. 初始化或更新 `.env`
   - 优先读取 Windows `Internet Settings` 代理配置
   - 如果系统代理不可用，则回退到现有 `.env`
   - 如果仍无法解析，则使用默认值 `127.0.0.1:7890`
   - 会写入以下环境变量：
     - `HTTP_PROXY`
     - `HTTPS_PROXY`
     - `ALL_PROXY`
     - `NO_PROXY=localhost,127.0.0.1`

## 文件说明

- `scripts/init-codex.ps1`
  主初始化脚本，负责配置更新、代理探测、备份和结果摘要输出。
- `scripts/init-codex.bat`
  批处理入口，方便双击执行或在 `cmd` 中直接调用，本质上会转调 PowerShell 脚本。

## 快速开始

### 方式一：使用 bat 入口

```bat
scripts\init-codex.bat
```

### 方式二：直接运行 PowerShell 脚本

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\init-codex.ps1
```

执行完成后，脚本会输出一份 JSON 摘要，包含：

- 实际使用的 `CodexHome`
- `config.toml` 是否创建、是否变更
- `.env` 是否创建、是否变更
- 备份文件路径
- 最终使用的代理地址
- 代理来源

## 配置项含义

### `config.toml` 配置项

脚本会写入下面 3 个配置项，它们的含义如下。

#### `sandbox_mode = "danger-full-access"`

表示 Codex 运行时使用完全访问权限模式。

#### `model_context_window = 512000`

表示模型可使用的上下文窗口大小。

#### `model_auto_compact_token_limit = 400000`

表示上下文接近上限时，自动触发压缩的阈值。

### `.env` 代理变量

脚本会写入以下变量：

- `HTTP_PROXY`
  用于 HTTP 请求代理
- `HTTPS_PROXY`
  用于 HTTPS 请求代理
- `ALL_PROXY`
  用于通用代理回退
- `NO_PROXY`
  指定不走代理的地址，当前固定为 `localhost,127.0.0.1`
