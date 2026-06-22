# OpenCode Container

[English](README.md) | 简体中文

容器化 OpenCode 与 OpenChamber 部署方案

## 什么是 OpenCode / OpenChamber

**[OpenCode](https://opencode.ai)** 是一个开源的 AI 编程智能体 (coding agent)，支持在终端、IDE 或桌面应用中使用。它可以接入 75+ 模型供应商（Claude、GPT、Gemini 等），内置 LSP 支持，支持多会话并行、会话分享。在本项目中 OpenCode 以无头服务器的形式运行，允许通过浏览器访问 OpenCode 内置的 Web UI，或通过其他客户端（如 TUI、桌面客户端等）连接到该服务器。

**[OpenChamber](https://openchamber.dev)** 是一个基于 OpenCode SDK 构建的智能体开发环境，提供桌面应用、浏览器、移动端和 VS Code 插件等多种交互方式。它让你可以直接从代码仓库、Issue 或 PR 开始工作，实时查看代码变更 (diff)，检查输出，并在就绪后提交或发起 PR。OpenChamber 同样开源且注重隐私，代码和会话数据都保留在本地。

本项目为这两款工具提供 Docker 容器化封装，方便在服务器或私有环境中快速部署与使用。

## 镜像概览

本项目提供两个主要的 Docker 镜像：

- **OpenCode 镜像** ([`ghcr.io/jks15satoshi/opencode`](https://ghcr.io/jks15satoshi/opencode))  
  - 该镜像运行一个无头 OpenCode 服务器，允许通过浏览器访问 OpenCode 内置的 Web UI，或通过其他客户端（如 TUI、桌面客户端等）连接到该服务器。
- **OpenChamber 镜像** ([`ghcr.io/jks15satoshi/openchamber`](https://ghcr.io/jks15satoshi/openchamber))  
  - 该镜像运行 OpenChamber 网页界面，默认由 OpenChamber 自己管理一个不可对外访问的 OpenCode 实例，允许配置为连接到外部 OpenCode 服务器。

两个镜像应用相同的标签定义：
- `latest`：指向最新构建版本。
- `vX.Y.Z`：指向上游特定发布版本的构建。
- `vX.Y.Z-rev.N`：在上游版本基础上进行的修订构建，通常用于修复镜像侧的问题或功能改进。

镜像基于 `node:26-trixie-slim` 构建，内置常用的 shell 工具（如 `curl`、`git`、`jq` 等），核心程序都基于官方分发的 OpenCode / OpenChamber 版本构建，维持原版功能不加修改。所有镜像都支持 `linux/amd64` 和 `linux/arm64` 架构。

镜像默认运行一个非 root 用户（`opencode` 或 `openchamber`，取决于部署镜像），UID 和 GID 默认均为 1000，但启动时会根据挂载的工作区目录权限自动调整为匹配该目录的所有者，以避免权限问题。

## 快速开始

**OpenCode**

```bash
docker run -d --name opencode \
  -p 4096:4096 \
  -e OPENCODE_SERVER_PASSWORD=your_password \
  -v opencode_config:/home/opencode/.config/opencode \
  -v opencode_data:/home/opencode/.local/share/opencode \
  -v /path/to/your/project:/workspace \
  ghcr.io/jks15satoshi/opencode:latest
```

访问 `http://localhost:4096`

**OpenChamber**

```bash
docker run -d --name openchamber \
  -p 3000:3000 \
  -e OPENCHAMBER_UI_PASSWORD=your_password \
  -v openchamber_config:/home/openchamber/.config/openchamber \
  -v opencode_config:/home/openchamber/.config/opencode \
  -v opencode_data:/home/openchamber/.local/share/opencode \
  -v /path/to/your/project:/workspace \
  ghcr.io/jks15satoshi/openchamber:latest
```

访问 `http://localhost:3000`

详细配置和组合部署方案见下方[部署方式](#部署方式)章节。

## 部署方式

> [!CAUTION]
> **重要安全警示**：  
> 切勿在无任何安全防护的环境中暴露 OpenCode / OpenChamber 环境。未经授权的访问可能会导致敏感信息泄露（如 API 密钥、环境变量、项目代码等）、模型请求滥用、远程代码执行等安全风险。
>
> 如果你确有需求远程访问到服务，请至少采取以下安全措施：
> - 配置强访问密码（`OPENCODE_SERVER_PASSWORD` 或 `OPENCHAMBER_UI_PASSWORD` 环境变量）；
> - 透过安全隧道（如 SSH 隧道、VPN 等）建立受信任的网络环境；
> - 通过反向代理（如 Nginx 等）配置 HTTPS 和访问控制。

> [!TIP]
> 我们推荐使用 [Docker Compose](https://docs.docker.com/compose/) 来管理这些容器。

按实际场景需要，可以选择以下部署方式：

### 单独部署 OpenCode

你可以选择仅部署 OpenCode 服务端，允许其他客户端（如 OpenChamber、桌面客户端、TUI 等）连接到该服务端。

- Docker CLI:
  
  ```bash
  docker run -d \
    --name opencode \
    -p 4096:4096 \
    -e OPENCODE_SERVER_PASSWORD=your_secure_password \
    -v opencode_config:/home/opencode/.config/opencode \
    -v opencode_data:/home/opencode/.local/share/opencode \
    -v /path/to/your/project:/workspace \
    ghcr.io/jks15satoshi/opencode:latest
  ```

- Docker Compose：

  ```yaml
  services:
    opencode:
      image: ghcr.io/jks15satoshi/opencode:latest
      container_name: opencode
      ports:
        - "4096:4096"
      environment:
        - OPENCODE_SERVER_PASSWORD=your_secure_password
      volumes:
        - opencode_config:/home/opencode/.config/opencode
        - opencode_data:/home/opencode/.local/share/opencode
        - workspace:/workspace
      healthcheck:
        test: ["CMD", "curl", "-fsS", "http://localhost:4096/global/health"]
        interval: 30s
        timeout: 5s
        retries: 3
        start_period: 15s
      restart: unless-stopped

  volumes:
    opencode_config:
    opencode_data:
    workspace:  # 挂载你的项目工作区代码目录
  ```

### 单独部署 OpenChamber

如果你只需要使用 OpenChamber 的网页界面，不关心 OpenCode 服务端如何管理，你可以选择仅部署 OpenChamber。

- Docker CLI:

  ```bash
  docker run -d \
    --name openchamber \
    -p 3000:3000 \
    -e OPENCHAMBER_UI_PASSWORD=your_secure_password \
    -v openchamber_config:/home/openchamber/.config/openchamber \
    -v opencode_config:/home/openchamber/.config/opencode \
    -v opencode_data:/home/openchamber/.local/share/opencode \
    -v /path/to/your/project:/workspace \
    ghcr.io/jks15satoshi/openchamber:latest
  ```

- Docker Compose：

  ```yaml
  services:
    openchamber:
      image: ghcr.io/jks15satoshi/openchamber:latest
      container_name: openchamber
      ports:
        - "3000:3000"
      environment:
        - OPENCHAMBER_UI_PASSWORD=your_secure_password
      volumes:
        - openchamber_config:/home/openchamber/.config/openchamber
        - opencode_config:/home/openchamber/.config/opencode
        - opencode_data:/home/openchamber/.local/share/opencode
        - workspace:/workspace
      healthcheck:
        test: ["CMD", "curl", "-fsS", "http://localhost:3000/global/health"]
        interval: 30s
        timeout: 5s
        retries: 3
        start_period: 15s
      restart: unless-stopped

  volumes:
    openchamber_config:
    opencode_config:
    opencode_data:
    workspace:  # 挂载你的项目工作区代码目录
  ```

需要注意，OpenChamber 默认必须通过 `OPENCHAMBER_UI_PASSWORD` 环境变量指定访问密码，否则会拒绝启动。可以通过指定 `OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN=true` 环境变量允许未认证的局域网访问。

> [!WARNING]
> 启用 `OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN=true` 将允许局域网内任何设备访问 OpenChamber 界面，请确保网络环境已做好隔离和访问控制。

### OpenCode + OpenChamber 组合部署

如果你有以下需求，可以选择组合部署：
- 需要独立控制 OpenCode 服务端的版本；
- 需要在使用 OpenChamber 的同时，确保 OpenCode 可被外部工具访问。

> [!NOTE]
> 组合部署涉及到多容器编排，因此只提供 Docker Compose 示例。

- Docker Compose：

  ```yaml
  services:
    opencode:
      image: ghcr.io/jks15satoshi/opencode:latest
      container_name: opencode
      ports:
        - "4096:4096"
      environment:
        - OPENCODE_SERVER_PASSWORD=your_secure_password
      volumes:
        - opencode_config:/home/opencode/.config/opencode
        - opencode_data:/home/opencode/.local/share/opencode
        - workspace:/workspace
      healthcheck:
        test: ["CMD", "curl", "-fsS", "http://localhost:4096/global/health"]
        interval: 30s
        timeout: 5s
        retries: 3
        start_period: 15s
      restart: unless-stopped

    openchamber:
      image: ghcr.io/jks15satoshi/openchamber:latest
      container_name: openchamber
      ports:
        - "3000:3000"
      environment:
        - OPENCHAMBER_UI_PASSWORD=your_secure_password
        - OPENCODE_SKIP_START=true
        - OPENCODE_HOST=http://opencode:4096
      volumes:
        - openchamber_config:/home/openchamber/.config/openchamber
        - workspace:/workspace
      depends_on:
        - opencode
      healthcheck:
        test: ["CMD", "curl", "-fsS", "http://localhost:3000/global/health"]
        interval: 30s
        timeout: 5s
        retries: 3
        start_period: 15s
      restart: unless-stopped

  volumes:
    openchamber_config:
    opencode_config:
    opencode_data:
    workspace:  # 挂载你的项目工作区代码目录
  ```

需要注意，在组合部署场景下，OpenCode 与 OpenChamber 必须访问到相同的工作区目录（`workspace`），以确保 OpenChamber 能正确加载和操作代码文件。

此外，OpenChamber 需要通过环境变量 `OPENCODE_SKIP_START=true` 指示不要启动内置的 OpenCode 实例，而是连接到外部的 OpenCode 服务端（通过 `OPENCODE_HOST=http://opencode:4096` 指定地址）。

## 配置参考

### 环境变量

OpenCode / OpenChamber 镜像支持通过环境变量进行配置，以下是一些常用的环境变量：

**OpenCode**

| 环境变量                   | 说明                                                   | 默认值     |
| -------------------------- | ------------------------------------------------------ | ---------- |
| `OPENCODE_SERVER_PASSWORD` | 设置访问 OpenCode 基本认证密码，为空时允许无密码访问。 |            |
| `OPENCODE_SERVER_USERNAME` | 设置访问 OpenCode 基本认证用户名。                     | `opencode` |

**OpenChamber**

| 环境变量                                | 说明                                                                                                                          | 默认值  |
| --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ------- |
| `OPENCHAMBER_UI_PASSWORD`               | 设置访问 OpenChamber 网页界面基本认证密码。<br/> 除非指定 `OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN` 为 `true`，否则不允许为空。 |         |
| `OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN` | 允许局域网内未认证访问 OpenChamber 网页界面。<br/> **建议只在受信任的网络环境中启用。**                                       | `false` |
| `OPENCODE_SKIP_START`                   | 在 OpenChamber 中跳过启动内置的 OpenCode 实例，改为连接到外部 OpenCode 服务端。需要同时指定 `OPENCODE_HOST`。                 | `false` |
| `OPENCODE_HOST`                         | 指定外部 OpenCode 服务端的地址（如 `http://opencode:4096`）。                                                                 |         |

以下环境变量不属于上游支持的配置选项，而是镜像侧提供的功能选项，对所有镜像有效：

| 环境变量            | 说明                                         | 默认值 |
|---------------------|----------------------------------------------| ------ |
| `PUID`              | 设置容器内用户的 UID，以匹配宿主机用户权限。 | `1000` |
| `PGID`              | 设置容器内用户的 GID，以匹配宿主机用户权限。 | `1000` |

### 挂载数据卷

**OpenCode**

| 路径                                   | 说明                                                  |
| -------------------------------------- | ----------------------------------------------------- |
| `/home/opencode/.config/opencode`      | OpenCode 配置目录。存放用户配置文件与插件文件。       |
| `/home/opencode/.local/share/opencode` | OpenCode 数据目录。存放模型认证信息、会话数据和日志。 |

**OpenChamber**

| 路径                                      | 说明                                                                                                                                                |
| ----------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/home/openchamber/.config/openchamber`   | OpenChamber 配置目录。存放用户配置信息、会话数据、Git 凭证配置、日志等。                                                                            |
| `/home/openchamber/.config/opencode`      | OpenCode 配置目录。存放用户配置文件与插件文件。<br/> 仅单独部署时需要挂载。                                                                         |
| `/home/openchamber/.local/share/opencode` | OpenCode 数据目录。存放模型认证信息、会话数据和日志。<br/> 仅单独部署时需要挂载。                                                                   |
| `/home/openchamber/.ssh/id_ed25519`       | SSH 私钥文件。用于 Git 操作的 SSH 认证。<br/> 当需要在 OpenChamber 中使用 Git 操作时，且配置 Git 认证方式为 SSH 时，需要挂载你的 SSH 私钥文件。     |
| `/home/openchamber/.git-credentials`      | Git 凭证文件。用于 Git 操作的 HTTPS 认证。<br/> 当需要在 OpenChamber 中使用 Git 操作时，且配置 Git 认证方式为 token 时，需要挂载你的 Git 凭证文件。 |

### 工作区目录与权限

OpenCode 和 OpenChamber 镜像都预留了 `/workspace` 目录用于挂载你的项目工作区代码目录。

在[镜像概览](#镜像概览)一节中提到，镜像启动时会自动检测挂载的工作区目录权限，并调整容器内用户的 UID 和 GID 以匹配该目录的所有者，从而避免权限问题。具体机制如下：

1. 镜像启动时会首先检查是否指定了 `PUID` 和 `PGID` 环境变量，如果指定了则遵循环境变量值；
2. 否则，检查是否从外部挂载了 `/workspace` 目录，如是则获取该目录的所有者 UID 和 GID，并将容器内用户的 UID 和 GID 调整为匹配该目录的所有者；
    - 特别地，如果挂载目录所有者为 1000:1000，由于默认 UID 和 GID 与容器内用户一致，则会跳过调整步骤；
    - 如果挂载目录所有者为 root（0:0），出于安全考虑，则会阻止运行容器，避免提权风险；
3. 否则，使用默认的 UID 和 GID（1000:1000）。

每个镜像也同时创建了指向 `/workspace` 的符号链接 `~/workspace`，方便在容器中访问。

### 接入 LLM 模型供应商

OpenCode / OpenChamber 各自提供了配置 LLM 模型供应商的方式，详见 [OpenCode 文档](https://opencode.ai/docs/zh-cn/providers/) 与 [OpenChamber 文档](https://docs.openchamber.dev/zh-cn/providers/)。

此外，环境变量也可以用来启用对应的 LLM 提供商：

> 以下仅列举部分常见的模型提供商。参阅 [AI SDK 文档](https://ai-sdk.dev/providers/ai-sdk-providers) 了解更多提供商环境变量配置选项。

| 环境变量            | 说明                       |
|---------------------|----------------------------|
| `OPENAI_API_KEY`    | OpenAI API 密钥            |
| `ANTHROPIC_API_KEY` | Anthropic API 密钥         |
| `GOOGLE_API_KEY`    | Google API 密钥            |
| `GROQ_API_KEY`      | Groq API 密钥              |
| `MISTRAL_API_KEY`   | Mistral API 密钥           |
| `DEEPSEEK_API_KEY`  | DeepSeek API 密钥          |
| `MOONSHOT_API_KEY`  | Moonshot（国际站）API 密钥 |


## 许可协议与声明

本项目使用 [MIT 协议](../LICENSE) 授权。

本项目遵循原始许可协议二次分发 OpenCode / OpenChamber，原始许可协议请参见：
- OpenCode: [MIT 协议](https://github.com/anomalyco/opencode/blob/dev/LICENSE)
- OpenChamber: [MIT 协议](https://github.com/openchamber/openchamber/blob/main/LICENSE)

本项目不由 OpenCode 与 OpenChamber 官方维护，也与这些团队无任何关联。
