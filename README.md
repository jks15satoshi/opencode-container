# OpenCode Container

English | [简体中文](docs/README.zh-CN.md)

Containerized deployment solution for OpenCode and OpenChamber

## What are OpenCode / OpenChamber

**[OpenCode](https://opencode.ai)** is an open-source AI coding agent that runs in terminals, IDEs, or desktop applications. It supports 75+ model providers (Claude, GPT, Gemini, etc.), has built-in LSP support, and enables parallel multi-session work with session sharing. In this project, OpenCode runs as a headless server, allowing browser access to OpenCode's built-in Web UI, or connections from other clients (such as TUI, desktop clients, etc.) to the server.

**[OpenChamber](https://openchamber.dev)** is an agent development environment built on the OpenCode SDK, offering multiple interaction methods including a desktop app, browser, mobile, and VS Code extension. It lets you start directly from a code repository, Issue, or PR, view code changes (diffs) in real time, inspect outputs, and commit or create PRs when ready. OpenChamber is also open-source and privacy-focused — code and session data remain local.

This project provides Docker containerization for both tools, enabling quick deployment and use in server or private environments.

## Image Overview

This project provides two main Docker images:

- **OpenCode Image** ([`ghcr.io/jks15satoshi/opencode`](https://ghcr.io/jks15satoshi/opencode))  
  - This image runs a headless OpenCode server, allowing browser access to OpenCode's built-in Web UI, or connections from other clients (such as TUI, desktop clients, etc.) to the server.
- **OpenChamber Image** ([`ghcr.io/jks15satoshi/openchamber`](https://ghcr.io/jks15satoshi/openchamber))  
  - This image runs the OpenChamber web interface. By default, OpenChamber manages its own internal OpenCode instance (not externally accessible), but can be configured to connect to an external OpenCode server.

Both images share the same tag conventions:
- `latest`: Points to the latest build.
- `vX.Y.Z`: Points to a build of a specific upstream release version.
- `vX.Y.Z-rev.N`: A revision build on top of an upstream version, typically used for image-side fixes or feature improvements.

Images are built on `node:26-trixie-slim` and include common shell tools (such as `curl`, `git`, `jq`, etc.). The core programs are built from the officially distributed OpenCode / OpenChamber releases, maintaining original functionality without modification. All images support both `linux/amd64` and `linux/arm64` architectures.

Images run as a non-root user by default (`opencode` or `openchamber`, depending on the deployed image), with default UID and GID of 1000. At startup, the container will automatically detect the mounted workspace directory permissions and adjust the UID/GID to match the directory owner, avoiding permission issues.

> [!NOTE]
> The image is built as root and drops privileges to a non-root user at runtime. This means if you `docker exec` into the container or run commands inside it, you will be operating as root.

## Quick Start

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

Access `http://localhost:4096`

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

Access `http://localhost:3000`

See the [Deployment Methods](#deployment-methods) section below for detailed configuration and combined deployment setups.

## Deployment Methods

> [!CAUTION]
> **Important Security Warning**:  
> Never expose OpenCode / OpenChamber environments without any security measures. Unauthorized access may lead to sensitive information leakage (such as API keys, environment variables, project code, etc.), model request abuse, remote code execution, and other security risks.
>
> If you genuinely need remote access to the service, please at least take the following security measures:
> - Configure strong access passwords (`OPENCODE_SERVER_PASSWORD` or `OPENCHAMBER_UI_PASSWORD` environment variables);
> - Establish a trusted network environment through secure tunnels (such as SSH tunnels, VPNs, etc.);
> - Configure HTTPS and access control through a reverse proxy (such as Nginx, etc.).

> [!TIP]
> We recommend using [Docker Compose](https://docs.docker.com/compose/) to manage these containers.

Depending on your actual needs, you can choose from the following deployment methods:

### Standalone OpenCode Deployment

You can choose to deploy only the OpenCode server, allowing other clients (such as OpenChamber, desktop clients, TUI, etc.) to connect to this server.

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

- Docker Compose:

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
    workspace:  # Mount your project workspace code directory
  ```

### Standalone OpenChamber Deployment

If you only need the OpenChamber web interface and don't care how the OpenCode server is managed, you can choose to deploy only OpenChamber.

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

- Docker Compose:

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
    workspace:  # Mount your project workspace code directory
  ```

Note that OpenChamber requires an access password to be specified via the `OPENCHAMBER_UI_PASSWORD` environment variable by default; it will refuse to start otherwise. You can allow unauthenticated LAN access by setting `OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN=true`.

> [!WARNING]
> Enabling `OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN=true` will allow any device on the LAN to access the OpenChamber interface. Ensure your network environment has proper isolation and access controls in place.

### OpenCode + OpenChamber Combined Deployment

Choose combined deployment if you have the following needs:
- You need independent control over the OpenCode server version;
- You need OpenCode to be accessible by external tools while using OpenChamber.

> [!NOTE]
> Combined deployment involves multi-container orchestration, so only Docker Compose examples are provided.

- Docker Compose:

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
    workspace:  # Mount your project workspace code directory
  ```

Note that in a combined deployment scenario, OpenCode and OpenChamber must access the same workspace directory (`workspace`) to ensure OpenChamber can correctly load and operate on code files.

Additionally, OpenChamber needs to be instructed via the `OPENCODE_SKIP_START=true` environment variable not to start a built-in OpenCode instance, and instead connect to an external OpenCode server (specified via `OPENCODE_HOST=http://opencode:4096`).

## Configuration Reference

### Environment Variables

OpenCode / OpenChamber images support configuration through environment variables. Below are some commonly used environment variables:

**OpenCode**

| Environment Variable       | Description                                                                                 | Default    |
| -------------------------- | ------------------------------------------------------------------------------------------- | ---------- |
| `OPENCODE_SERVER_PASSWORD` | Sets the basic auth password for accessing OpenCode. Allows passwordless access when empty. |            |
| `OPENCODE_SERVER_USERNAME` | Sets the basic auth username for accessing OpenCode.                                        | `opencode` |

**OpenChamber**

| Environment Variable                    | Description                                                                                                                                                     | Default   |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------- |
| `OPENCHAMBER_UI_PASSWORD`               | Sets the basic auth password for accessing the OpenChamber web interface.<br/> Cannot be empty unless `OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN` is set to `true`. |           |
| `OPENCHAMBER_ALLOW_UNAUTHENTICATED_LAN` | Allows unauthenticated LAN access to the OpenChamber web interface.<br/> **Recommended only in trusted network environments.**                                  | `false`   |
| `OPENCODE_SKIP_START`                   | Skips starting the built-in OpenCode instance in OpenChamber, connecting to an external OpenCode server instead. Requires `OPENCODE_HOST` to be set as well.    | `false`   |
| `OPENCODE_HOST`                         | Specifies the address of an external OpenCode server (e.g., `http://opencode:4096`).                                                                            |           |

The following environment variables are not upstream-supported configuration options but are image-side features and apply to all images:

| Environment Variable | Description                                                        | Default |
|----------------------|--------------------------------------------------------------------|---------|
| `PUID`               | Sets the UID of the container user to match host user permissions. | `1000`  |
| `PGID`               | Sets the GID of the container user to match host user permissions. | `1000`  |

### Mounted Data Volumes

**OpenCode**

| Path                                   | Description                                                                                                                                   |
| -------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `/home/opencode/.config/opencode`      | OpenCode configuration directory. Stores user config files and plugin files.                                                                  |
| `/home/opencode/.local/share/opencode` | OpenCode data directory. Stores model authentication info, session data, and logs.                                                            |
| `/mise`                                | Mise data directory. Stores Mise config and installed development tools. <br/> See [Managing Development Tools](#managing-development-tools). |

**OpenChamber**

| Path                                      | Description                                                                                                                                                                           |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `/home/openchamber/.config/openchamber`   | OpenChamber configuration directory. Stores user configuration info, session data, Git credential config, logs, etc.                                                                  |
| `/home/openchamber/.config/opencode`      | OpenCode configuration directory. Stores user config files and plugin files.<br/> Only needs to be mounted in standalone deployment.                                                  |
| `/home/openchamber/.local/share/opencode` | OpenCode data directory. Stores model authentication info, session data, and logs.<br/> Only needs to be mounted in standalone deployment.                                            |
| `/home/openchamber/.ssh/id_ed25519`       | SSH private key file. Used for SSH authentication in Git operations.<br/> Mount your SSH private key when using Git operations in OpenChamber with SSH authentication.                |
| `/home/openchamber/.git-credentials`      | Git credentials file. Used for HTTPS authentication in Git operations.<br/> Mount your Git credentials file when using Git operations in OpenChamber with token-based authentication. |
| `/mise`                                   | Mise data directory. Stores Mise config and installed development tools. <br/> See [Managing Development Tools](#managing-development-tools).                                         |

### Workspace Directory and Permissions

Both the OpenCode and OpenChamber images reserve the `/workspace` directory for mounting your project workspace code directory.

As mentioned in the [Image Overview](#image-overview) section, at startup the image automatically detects the permissions of the mounted workspace directory and adjusts the container user's UID and GID to match that directory's owner, thereby avoiding permission issues. The specific mechanism is as follows:

1. At startup, the image first checks whether `PUID` and `PGID` environment variables are specified; if so, it follows the environment variable values;
2. Otherwise, it checks whether `/workspace` is mounted from an external source. If so, it retrieves the owner UID and GID of that directory and adjusts the container user's UID and GID to match the directory owner;
    - Specifically, if the mounted directory owner is 1000:1000, the adjustment step is skipped since it matches the default UID/GID of the container user;
    - If the mounted directory owner is root (0:0), the container will refuse to run for security reasons to prevent privilege escalation risks;
3. Otherwise, the default UID and GID (1000:1000) are used.

Each image also creates a symbolic link `~/workspace` pointing to `/workspace` for convenient access within the container.

### Configuring Language Runtimes and Development Tools

Both the OpenCode and OpenChamber images come with the following built-in runtime environments:

- Bash:
  - Built-in bash-language-server LSP.
- Dockerfile:
  - Built-in dockerfile-language-server-nodejs LSP.
- Node.js:
  - Built-in Node.js 26 runtime and npm package manager. Node.js versions and package managers (npm, Yarn, PNPM) can be managed through Corepack.
  - Built-in Prettier formatter.
- Python:
  - Built-in Python interpreter (version depends on the Debian Trixie distribution). pip and venv are not bundled.
- YAML:
  - Built-in yaml-language-server LSP.

The built-in tools are usually insufficient for various development scenarios, so the images also provide [Mise](https://mise.en.dev) integration for managing language runtimes and development tools. You can specify the tools and versions you need by mounting a configuration file at `/mise/config.toml`. For example, for the following development environment:

- Python 3.12 + uv + Ruff + ty
- Node.js 24 + PNPM + typescript-language-server

You can create a `config.toml` file as follows:

```toml
[tools]
# Python
python       = "3.12"
uv           = "latest"
ty           = "latest"
"pipx:ruff"  = { version = "latest", depends = ["python"] }

# Node
node                             = "24"
pnpm                             = "latest"
"npm:typescript-language-server" = { version = "latest", depends = ["node"] }

[settings]
python.uv_venv_auto = true
```

At startup, the image automatically detects the `/mise/config.toml` file and installs the required tools and versions according to the configuration, adding them to PATH. Once installed, you can use these tools directly inside the container. If you've correctly mounted the Mise data directory, the installed tools and configuration will persist across container restarts.

For specific Mise configuration options and usage, please refer to the [Mise documentation](https://mise.en.dev/getting-started.html).

### Connecting LLM Model Providers

OpenCode / OpenChamber each provide their own methods for configuring LLM model providers. See the [OpenCode documentation](https://opencode.ai/docs/providers/) and [OpenChamber documentation](https://docs.openchamber.dev/providers/) for details.

Additionally, environment variables can be used to enable the corresponding LLM providers:

> The following lists only some common model providers. Refer to the [AI SDK documentation](https://ai-sdk.dev/providers/ai-sdk-providers) for more provider environment variable configuration options.

| Environment Variable  | Description              |
|-----------------------|--------------------------|
| `OPENAI_API_KEY`      | OpenAI API key           |
| `ANTHROPIC_API_KEY`   | Anthropic API key        |
| `GOOGLE_API_KEY`      | Google API key           |
| `GROQ_API_KEY`        | Groq API key             |
| `MISTRAL_API_KEY`     | Mistral API key          |
| `DEEPSEEK_API_KEY`    | DeepSeek API key         |
| `MOONSHOT_API_KEY`    | Moonshot (global) API key |

## License and Disclaimers

This project is licensed under the [MIT License](../LICENSE).

This project redistributes OpenCode / OpenChamber in compliance with their original licenses. Please refer to the original licenses:
- OpenCode: [MIT License](https://github.com/anomalyco/opencode/blob/dev/LICENSE)
- OpenChamber: [MIT License](https://github.com/openchamber/openchamber/blob/main/LICENSE)

This project is not maintained by the official OpenCode or OpenChamber teams, and has no affiliation with those teams.
