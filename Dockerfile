ARG PHP_VERSION=8.5.12
FROM php:${PHP_VERSION}-fpm-alpine

# 供 LABEL 和调试用
ARG PHP_VERSION
ARG FINGERPRINT=dev
# 仓库地址。CI 会传入实际值，本地构建留空即可 —— 不硬编码任何账号名。
ARG REPO_URL=""

LABEL org.opencontainers.image.title="discuz-php" \
      org.opencontainers.image.description="PHP-FPM for Discuz! X3.5 — gd/mysqli/pdo_mysql/zip/bcmath on the official php-fpm-alpine base" \
      org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.base.name="docker.io/library/php:${PHP_VERSION}-fpm-alpine" \
      io.discuz-php.php.version="${PHP_VERSION}" \
      io.discuz-php.build.fingerprint="${FINGERPRINT}"

# ─────────────────────────────────────────────────────────────
# PHP 扩展
#
# ⚠️ 运行时库必须永久安装。
#    只装 -dev 包再 `apk del`，会把 .so 依赖的运行时库(libpng16/libzip 等)
#    一起删掉，结果是 gd.so / zip.so 加载失败：
#        Error loading shared library libpng16.so.16: No such file or directory
# ─────────────────────────────────────────────────────────────
RUN set -eux; \
    apk add --no-cache \
        freetype \
        libjpeg-turbo \
        libpng \
        libwebp \
        libzip; \
    apk add --no-cache --virtual .build-deps \
        freetype-dev \
        libjpeg-turbo-dev \
        libpng-dev \
        libwebp-dev \
        libzip-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    docker-php-ext-install -j"$(nproc)" gd mysqli pdo_mysql zip bcmath; \
    apk del --no-network .build-deps

# ─────────────────────────────────────────────────────────────
# 不修改 www-data 的 uid/gid —— 保持官方镜像原样(82:82)
#
# 生产环境如果站点文件属于 www-data(82)，天然一致，什么都不用做。
# 如果挂载进来的文件属于别的 uid，用 compose 的 user: 指定即可：
#
#     services:
#       php:
#         image: ghcr.io/chengkni/discuz-php:php-8.5.12
#         user: "1000:1000"      # FPM 非 root 启动时会忽略 pool 里的 user 指令，
#                                # 工作进程直接以该 uid 运行
#
# 改镜像里的 uid 会让它和官方镜像产生意外差异，不值得。
# ─────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────
# 调试友好的默认配置
# 生产环境如需关闭 display_errors，挂载自己的 conf.d 覆盖即可。
# ─────────────────────────────────────────────────────────────
RUN { \
        echo 'display_errors = On'; \
        echo 'display_startup_errors = On'; \
        echo 'error_reporting = E_ALL'; \
        echo 'log_errors = On'; \
        echo 'error_log = /dev/stderr'; \
        echo 'expose_php = Off'; \
    } > /usr/local/etc/php/conf.d/zz-discuz.ini

# 健康检查：确认 FPM 在监听
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD php-fpm -t || exit 1

CMD ["php-fpm"]
