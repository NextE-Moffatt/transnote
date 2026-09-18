#!/bin/bash
# 创建一个本地自签名代码签名身份（只需执行一次，可重复安全运行）。
#
# 为什么需要它：ad-hoc 签名的「指定要求」只绑 cdhash，
# 每次重新编译 cdhash 都会变，macOS 已经授予的「辅助功能」权限就会失效。
# 用一个固定的证书签名后，指定要求变成对证书根哈希的引用，授权可以长期保留。
#
# 注意：这个证书不加入系统信任列表，也不影响 Gatekeeper，只放在登录钥匙串里。

set -euo pipefail

IDENTITY="TransNote Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
WORK="$HOME/.transnote/signing"

if security find-identity -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  echo "签名身份已存在：$IDENTITY"
  exit 0
fi

mkdir -p "$WORK"

openssl req -x509 -new -nodes -newkey rsa:2048 -days 3650 \
  -keyout "$WORK/transnote.key" -out "$WORK/transnote.crt" \
  -subj "/CN=$IDENTITY/O=TransNote" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" >/dev/null 2>&1

# OpenSSL 3 默认的加密算法 macOS 的 security 读不了，必须用传统算法
openssl pkcs12 -export -out "$WORK/transnote.p12" \
  -inkey "$WORK/transnote.key" -in "$WORK/transnote.crt" \
  -name "$IDENTITY" -passout pass:transnote \
  -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1

security import "$WORK/transnote.p12" -k "$KEYCHAIN" \
  -P transnote -T /usr/bin/codesign -T /usr/bin/security -A >/dev/null

chmod 600 "$WORK/transnote.key" "$WORK/transnote.p12" 2>/dev/null || true
rm -f "$WORK/transnote.p12"

echo "已创建签名身份：$IDENTITY"
