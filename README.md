<div align="center">

# Tor Gateway 自動セットアップ

**教育目的の Tor 透過プロキシ構築ツール - ワンコマンドで展開可能**

![Bash](https://img.shields.io/badge/Bash-自動化-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Raspberry_Pi_%7C_Debian-A22846?style=for-the-badge&logo=raspberrypi&logoColor=white)
![License](https://img.shields.io/badge/License-Educational-FF8C00?style=for-the-badge)

</div>

---

## 📖 概要

Raspberry Pi または Debian ベースシステム上で Tor 透過プロキシゲートウェイを自動構築するスクリプトです。Ethernet 経由で接続されたすべてのデバイスの通信を自動的に Tor ネットワーク経由にルーティングし、プライバシーとセキュリティ研究のための教育環境を迅速に展開します。

---

## ✨ 主な機能

* 完全自動セットアッププロセス
* Ethernet 経由の透過プロキシ設定
* DHCP サーバー自動設定
* DNS 通信の Tor 経由ルーティング
* Kill Switch 機能（Tor 以外の通信を遮断）
* 冪等性のある実行（安全に再実行可能）
* 包括的なエラーハンドリング
* 再起動後の自動起動対応

---

## 📋 システム要件

* Raspberry Pi（推奨）または Debian 11/12
* root または sudo 権限
* Wi-Fi インターネット接続
* イーサネットポート（内蔵または USB）
* 最低 1GB の RAM
* 2GB の空きディスク容量

---

## 🚀 クイックスタート

セットアップスクリプトを実行:

```bash
sudo bash tor.sh
```

スクリプトは以下を自動的に実行します:

1. 必要なパッケージのインストール（Tor、dnsmasq、iptables）
2. ネットワークインターフェースの設定
3. Tor 透過プロキシの設定（0.0.0.0:9040、0.0.0.0:9053）
4. DHCP サーバーの設定
5. iptables ファイアウォールルールの適用
6. 全サービスの起動と有効化

セットアップは通常 2〜3 分で完了します。

---

## 💻 使用方法

### 初期セットアップ

```bash
# Wi-Fi 接続を設定（スクリプト実行前）
sudo raspi-config
# → System Options → Wireless LAN

# スクリプトをダウンロード
wget https://your-url/tor.sh

# 実行権限を付与
chmod +x tor.sh

# root 権限で実行
sudo bash tor.sh

# 再起動
sudo reboot
```

### ゲートウェイへの接続

再起動後、Mac や PC を Ethernet ケーブルでラズパイに接続:

1. デバイスが Ethernet 経由で接続
2. 自動的に IP アドレス（192.168.50.x）を取得
3. すべての通信が自動的に Tor 経由になる

### 動作確認

接続後、以下のコマンドで確認:

```bash
# Tor 経由確認
curl https://check.torproject.org/api/ip

# 期待される出力:
{"IsTor": true, "IP": "xxx.xxx.xxx.xxx"}
```

またはブラウザで確認:

```
https://check.torproject.org
```

---

## 🏗️ ネットワーク構成

```
デバイス (Mac/PC/スマホ)
        |
  Ethernet ケーブル
        |
        v
ラズパイ (192.168.50.1)
        |
    eth0 → DHCP 配布 (192.168.50.10-100)
        |
        v
      Tor
        |
    9040 (TransPort) - TCP 透過プロキシ
    9053 (DNSPort)   - DNS 解決
        |
        v
    wlan0 (Wi-Fi) → インターネット
```

---

## 🧩 技術アーキテクチャ

```
クライアントデバイス
        |
        v
  DHCP (192.168.50.x 取得)
        |
        v
    iptables NAT
        |
  DNS (port 53) → Tor DNSPort (9053)
  TCP (any)     → Tor TransPort (9040)
        |
        v
      Tor ネットワーク
        |
        v
    インターネット
```

### ファイアウォールルール

* **INPUT**: eth0 からの通信を許可、確立済み接続を許可
* **OUTPUT**: Tor プロセスの通信のみ許可（Kill Switch）
* **NAT PREROUTING**: DNS（53）→ Tor（9053）、TCP → Tor（9040）
* **NAT POSTROUTING**: wlan0 へのマスカレード

---

## 🔧 サービス管理

### サービスステータスの確認

```bash
# 全サービスの状態確認
sudo systemctl status tor
sudo systemctl status dnsmasq
sudo systemctl status systemd-networkd
```

### サービスの再起動

```bash
# Tor の再起動
sudo systemctl restart tor

# dnsmasq の再起動
sudo systemctl restart dnsmasq

# ネットワークの再起動
sudo systemctl restart systemd-networkd
```

### ログの確認

```bash
# Tor ログ
sudo journalctl -u tor -f
sudo tail -f /var/log/tor/notices.log

# dnsmasq ログ
sudo journalctl -u dnsmasq -f

# セットアップログ
sudo tail -f /var/log/tor-gateway/setup.log
```

### ポート確認

```bash
# Tor ポートの確認
sudo ss -tlnp | grep tor
sudo ss -ulnp | grep 9053

# 期待される出力:
# LISTEN 0.0.0.0:9040 (TransPort)
# LISTEN 0.0.0.0:9053 (DNSPort)
```

---

## ⚙️ カスタマイズ

### IP アドレス範囲の変更

スクリプト内の以下の行を編集:

```bash
LAN_IP="192.168.50.1"
LAN_NET="192.168.50.0/24"
```

dnsmasq 設定も変更:

```bash
sudo nano /etc/dnsmasq.d/tor-gateway.conf
# dhcp-range=192.168.50.10,192.168.50.100,12h
```

### インターフェースの変更

デフォルトでは eth0（LAN）と wlan0（WAN）を使用。変更する場合:

```bash
sudo nano tor.sh
# LAN_IF="eth0"
# WAN_IF="wlan0"
```

---

## 🔍 トラブルシューティング

### Tor ポートが 0.0.0.0 でリッスンしていない

Tor 設定を確認:

```bash
sudo cat /etc/tor/torrc

# 以下が含まれていることを確認:
# TransPort 0.0.0.0:9040
# DNSPort 0.0.0.0:9053
```

修正後、再起動:

```bash
sudo systemctl restart tor
```

### デバイスが IP アドレスを取得できない

dnsmasq の状態確認:

```bash
sudo systemctl status dnsmasq
sudo journalctl -u dnsmasq -n 50
```

eth0 の IP アドレス確認:

```bash
ip addr show eth0

# 192.168.50.1/24 が設定されているはず
```

### インターネット接続ができない

iptables ルールの確認:

```bash
sudo iptables -L -v -n
sudo iptables -t nat -L -v -n
```

Wi-Fi 接続の確認:

```bash
ip addr show wlan0
ping -c 3 8.8.8.8
```

### セットアップの再実行

スクリプトは冪等性があり、安全に再実行できます:

```bash
sudo bash tor.sh
sudo reboot
```

---

## 🖥️ システム要件（詳細）

### ハードウェア

* Raspberry Pi 3B 以降（推奨: Raspberry Pi 4 以降）
* 最低 1GB RAM（推奨: 2GB 以上）
* microSD カード（最低 8GB、推奨: 16GB 以上）
* イーサネットポート（内蔵または USB アダプタ）
* Wi-Fi アダプタ（内蔵または外付け）

### ソフトウェア

* Raspberry Pi OS（Debian 11/12 ベース）
* Tor（自動インストール）
* dnsmasq（自動インストール）
* iptables-persistent（自動インストール）

---

## 📊 パフォーマンスと制限

### 通信速度

* Tor ネットワークの速度に依存（通常 1〜10Mbps）
* 通常のインターネット接続より遅くなります
* ストリーミングやファイル共有には適していません

### 同時接続数

* DHCP プール: 90 デバイス（192.168.50.10-100）
* 推奨: 10 デバイス以下（パフォーマンス考慮）

### 制約事項

* UDP 通信は部分的にサポート（DNS 以外）
* P2P 通信は制限される可能性があります
* 一部のサービスは Tor 出口ノードをブロックする場合があります

---

## 🎓 教育への応用

このツールは以下の学習を促進します:

* Tor ネットワークアーキテクチャとプロトコル
* 透過プロキシの実装と運用
* iptables/netfilter ファイアウォール設定
* DHCP サーバーの設定と管理
* Linux ネットワーキング
* プライバシー保護技術
* システムセキュリティの強化

---

## ✅ 許可された使用範囲

本ソフトウェアは以下の目的でのみ使用可能です:

**許可される用途:**

* 教育研究と学習
* プライバシー技術の学習
* 管理された環境での個人実験
* ネットワークセキュリティの研究
* 学術的課題とプロジェクト

**禁止される用途:**

* あらゆる種類の違法行為
* 他者のネットワークへの不正アクセス
* サービス利用規約の違反
* 嫌がらせや他者への危害
* 著作権侵害

ユーザーは、使用が適用されるすべての法律および規制に準拠していることを確保する全責任を負います。Tor ネットワークの匿名性機能は、ユーザーを法的責任から免除するものではありません。

---

## 🔒 セキュリティに関する考慮事項

* Tor は匿名性を提供しますが、絶対的なセキュリティではありません
* Kill Switch 機能により、Tor 以外の通信は遮断されます
* ラズパイ自体のセキュリティを適切に保護してください
* 定期的なセキュリティアップデートを適用してください
* 機密性の高い用途には追加の強化が必要です
* 通信速度は Tor ネットワークに依存します

---

## 📚 参考資料

* Tor プロジェクトドキュメント: https://www.torproject.org/docs/
* Tor 透過プロキシガイド: https://gitlab.torproject.org/legacy/trac/-/wikis/doc/TransparentProxy
* iptables 詳細ガイド: https://www.netfilter.org/documentation/
* Raspberry Pi ドキュメント: https://www.raspberrypi.org/documentation/

---

## 💛 開発支援

このツールが教育目標の達成に役立った場合、継続的な開発への貢献をご検討ください:

**Bitcoin (BTC):**

```
151feG2x2pUqG97p9kSKL7E3LgpukNWozT
```

すべての寄付は、プライバシーとセキュリティ研究のための無料教育リソースの維持を支援します。

---

## 🌐 教育理念

本プロジェクトは、プライバシー技術におけるアクセス可能な教育への取り組みを維持しています。すべての機能は無料で提供され、ソフトウェアは教育利用のために常に自由に利用可能です。

---

## ⚠️ 免責事項

本ソフトウェアは教育目的でのみ提供されています。ユーザーは、使用が適用される法律、規制、倫理基準に準拠していることを確保する完全な責任を負います。作成者は本ソフトウェアの誤用に対する一切の責任を負いません。

---

<div align="center">

*プライバシー技術研究のための教育ツール*

</div>
