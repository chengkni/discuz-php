# discuz-php

给 **Discuz! X3.5** 用的 PHP-FPM 镜像。基于官方 `php:<version>-fpm-alpine`，预装 Discuz 必需的扩展，并把 `www-data` 对齐到 uid/gid 1000。

## 为什么需要这个

官方 `php:8.x-fpm-alpine` 镜像里**没有** Discuz 需要的这几个扩展：

```
gd  mysqli  pdo_mysql  zip  bcmath
```

而 Alpine 上从源码编译它们需要先装 gcc/binutils 整套工具链（200MB+），在慢网络环境下要十几分钟。

**这个仓库把编译结果固化成镜像，一次构建、到处拉取。**

> 工作流里的镜像名是**动态推导**的（取自 `github.repository`），代码里不写死账号名。

## 用法

```bash
docker pull ghcr.io/chengkni/discuz-php:php-8.5.12
```

```yaml
services:
  php:
    image: ghcr.io/chengkni/discuz-php:php-8.5.12
    restart: unless-stopped
    volumes:
      - ./site:/var/www/html
```

## 用法二：下载归档（docker pull 慢时用）

每个版本在 [Releases](../../releases) 里挂了镜像 tar 包，可以直接下载后 `docker load`，**绕过 registry**：

```bash
# 1. 下载（以 8.5.12 / amd64 为例）
curl -fLO https://github.com/chengkni/discuz-php/releases/download/php-8.5.12/discuz-php_8.5.12_linux_amd64.tar.gz
curl -fLO https://github.com/chengkni/discuz-php/releases/download/php-8.5.12/discuz-php_8.5.12_linux_amd64.tar.gz.sha256

# 2. 校验
sha256sum -c discuz-php_8.5.12_linux_amd64.tar.gz.sha256

# 3. 加载
gunzip -c discuz-php_8.5.12_linux_amd64.tar.gz | docker load
```

加载出来的镜像名**和 GHCR 上完全一致**（`ghcr.io/chengkni/discuz-php:php-8.5.12`），
所以 compose 里的 `image:` 一个字都不用改。

arm64 把文件名里的 `amd64` 换成 `arm64` 即可。

> 归档是**按架构单独构建**的（多架构 manifest list 没法直接 `docker save`）。
> 构建复用 GHCR 那份的 buildx 缓存，所以不会明显拖慢 CI。

## 可用标签

| 标签 | 说明 |
|---|---|
| `php-8.5.12` | 精确版本（推荐，可复现） |
| `php-8.5` | 跟随该分支最新补丁，上游发新版自动更新 |
| `php-8.4.27` / `php-8.4` | |
| `php-7.4.33` / `php-7.4` | 已 EOL，仅供旧环境对照 |
| `fp-<hash>` | 构建指纹标签，CI 用它判断是否需要重编 |
| `latest` | 跟随 `LATEST_BRANCH`（默认 8.5） |
| `sha-<commit>` | 对应 commit |

## 镜像内容

| 项 | 值 |
|---|---|
| 基础镜像 | `php:<version>-fpm-alpine` |
| PHP 扩展 | `gd` `mysqli` `pdo_mysql` `zip` `bcmath` |
| gd 支持 | freetype + jpeg + png + **webp** |
| `www-data` | **保持官方原样（82:82）**，镜像不做任何 uid 改写 |
| `expose_php` | `Off`（不暴露 `X-Powered-By`） |
| 错误日志 | 输出到 stderr（`docker logs` 可见） |

### 关于文件权限

镜像**不修改** `www-data` 的 uid/gid，保持和官方镜像一致。

- **生产**：站点文件如果属于 `www-data`（82），天然一致，什么都不用做
- **本地/其他 uid**：用 compose 的 `user:` 指定，不要改镜像

```yaml
services:
  php:
    image: ghcr.io/chengkni/discuz-php:php-8.5.12
    user: "1000:1000"
    # FPM 以非 root 启动时会忽略 pool 里的 user 指令，
    # 工作进程直接以该 uid 运行（日志会提示 'user' directive is ignored）
```

**为什么不在镜像里改 uid**：那会让镜像和官方镜像产生意外差异。别人挂载属于 82 的文件时反而会坏掉。

## 构建

### 本地

```bash
docker build -t discuz-php:8.5 --build-arg PHP_VERSION=8.5.12 .
```

### CI

推送到 `main` 或手动触发即自动构建。

**要加新分支**，只改 `PHP_BRANCHES` 一处：

```yaml
env:
  PHP_BRANCHES: "7.4 8.4 8.5"     # 写分支，不写精确版本号
  LATEST_BRANCH: "8.5"            # 这个分支的最新版额外打上 :latest
```

### 版本自动跟踪

`check` job 会查 Docker Hub API，解析每个分支当前的**最新补丁版本**：

```
PHP_BRANCHES: "7.4 8.4 8.5"
        ↓ 解析
7.4.33-fpm-alpine  8.4.27-fpm-alpine  8.5.12-fpm-alpine
```

**上游一发新版（8.5.13），解析结果就变 → digest 变 → 指纹变 → 自动重编。**
你不需要改任何代码。

### ⚠️ 定时工作流会被 GitHub 停用 —— 已加保活

GitHub 会在仓库**连续 60 天无活动**后自动停用 `schedule` 触发。**对安全补丁来说这是致命的**——你会悄悄失去自动更新。

本仓库的 `keepalive` job 会在每次定时运行时检查 `.keepalive` 的时间戳，**超过 50 天就写一次**，让仓库保持活跃：

```
定时运行 → 距上次保活 ≥50 天? → 是 → 提交 .keepalive（带 [skip ci]）
                                    → 否 → 跳过
```

- 提交带 `[skip ci]`，**不会反过来触发构建**
- 约每 50 天一次，一年 7 次左右
- `.keepalive` 在 `.dockerignore` 里，**不影响镜像构建**

> 手动触发（Actions → Run workflow）随时可用，不受停用影响。

### 构建指纹机制

`check` job 会为每个版本算一个指纹：

```
指纹 = sha256( PHP版本 + 上游镜像digest + Dockerfile哈希 )
```

- **上游发新版**（如 `php:8.5-fpm-alpine` 更新到 8.5.13）→ digest 变 → 指纹变 → 自动重编
- **Dockerfile 改动** → 哈希变 → 指纹变 → 自动重编
- 指纹没变则跳过编译

**定时探测（每 6 小时）和 PR 会走指纹闸门；push 和手动触发总是构建。**

> 这个机制正好能帮你盯住 PHP 的安全补丁——上游一放新版本，CI 就会自动产出新镜像。

## 目录结构

```
.
├── .github/workflows/build.yml    # CI：解析版本 → 指纹判断 → 多架构构建 → 推 GHCR → 挂 Release
├── Dockerfile                     # ARG PHP_VERSION，矩阵构建
├── docker-compose.example.yml     # 用法示例
├── .keepalive                     # 保活时间戳（CI 自动维护）
├── .dockerignore
├── .gitignore
└── README.md
```

## ⚠️ 踩过的坑

### 1. 运行时库必须永久安装

```dockerfile
# ❌ 错误：只装 -dev 再 apk del，会把运行时库一起删掉
RUN apk add --no-cache --virtual .build-deps freetype-dev libpng-dev ...; \
    docker-php-ext-install gd; \
    apk del --no-network .build-deps
# → gd.so 加载失败：libpng16.so.16: No such file or directory

# ✅ 正确：运行时库单独永久安装
RUN apk add --no-cache freetype libjpeg-turbo libpng libwebp libzip; \
    apk add --no-cache --virtual .build-deps freetype-dev libjpeg-turbo-dev ...; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install gd mysqli pdo_mysql zip bcmath; \
    apk del --no-network .build-deps
```

`-dev` 包会**拉入**运行时库，删掉 `-dev` 时运行时库也一起没了。必须显式永久安装。

### 2. 不要改镜像里的 `www-data` uid

曾经想在镜像里把 `www-data` 改成 uid 1000（对齐宿主机用户），**这是错的方向**：

- 官方 alpine 镜像里是 `82:82`，**生产环境站点文件通常就是 82**，天然一致
- 改掉之后，别人挂载属于 82 的文件反而会坏
- 需要别的 uid 时，用 compose 的 `user:` 即可，一行搞定

**镜像应该保持和官方一致，把差异留给使用方声明。**

### 3. 本地构建慢 ≠ 有问题

Alpine 上编译这些扩展需要先装 gcc/binutils 工具链。**网络慢的话（实测 246 KB/s）光下载就要 15 分钟以上。**

这是选择用 CI 构建的主要原因——GitHub Actions 的机器网络是千兆的。

## 相关

- [PHP: Supported Versions](https://www.php.net/supported-versions.php) — PHP 维护时间表
