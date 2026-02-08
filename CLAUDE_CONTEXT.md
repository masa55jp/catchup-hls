# Claude Code 引き継ぎドキュメント

このドキュメントを読んで、作業の続きを行ってください。

## プロジェクト概要

**catchup-hls** - 録画中のTSファイルからHLSを自動生成し、追っかけ再生を可能にするシステム

### システム構成

```
┌─────────────────────────────────────────────────────────────┐
│  Jetson Nano (100.83.73.68)                                 │
│  ├─ EPGStation (:8888) - 録画管理                           │
│  ├─ Mirakurun (:40772) - チューナー                         │
│  └─ TS録画 → NASに保存                                      │
└─────────────────────────────────────────────────────────────┘
         │ NFS
         ▼
┌─────────────────────────────────────────────────────────────┐
│  UGREEN NAS DXP2800 (100.86.102.37)                         │
│  ├─ /volume1/jetsonTV/record/ - TS保存先                    │
│  ├─ /volume1/jetsonTV/hls/ - HLS出力先                      │
│  └─ catchup-hls (Docker) (:8080)                            │
│      ├─ TS監視 → Intel QSV で HLS生成                       │
│      └─ Nginx で Web UI + HLS配信                           │
└─────────────────────────────────────────────────────────────┘
```

## 現在の状態

### 完了済み
- [x] Jetson Nano 石川県仕様のバックアップ（/mnt/nas/backup/に保存済み）
- [x] catchup-hls の設計・実装
- [x] GitHub リポジトリ: https://github.com/masa55jp/catchup-hls
- [x] GHCR にイメージ公開: ghcr.io/masa55jp/catchup-hls:latest
- [x] NAS で Docker コンテナ起動

### 問題発生中
**NAS の catchup-hls から Jetson の EPGStation に接続できない**

Web UI (http://100.86.102.37:8080/) で「EPGStationに接続できません」と表示される

### 原因の可能性
1. NAS が Tailscale ネットワークに入っていない
2. Jetson のローカル IP を使う必要がある

## 次にやるべきこと

### 1. NAS から Jetson への接続確認

```bash
# NAS のターミナルで実行
docker exec catchup-hls curl -s http://100.83.73.68:8888/api/version

# または Jetson のローカル IP で試す
docker exec catchup-hls curl -s http://192.168.x.x:8888/api/version
```

### 2. EPGSTATION_URL の修正

接続できる IP がわかったら、docker-compose.yml を更新:

```yaml
environment:
  - EPGSTATION_URL=http://正しいIP:8888
```

### 3. コンテナ再起動

```bash
docker-compose down && docker-compose up -d
```

### 4. 動作テスト

1. EPGStation で短い番組を録画開始
2. Web UI (http://100.86.102.37:8080/) で録画中として表示されるか確認
3. HLS リンクをタップして再生できるか確認

## ファイル構成

```
/volume1/jetsonTV/
├── record/          # TS録画ファイル（Jetsonから書き込み）
├── hls/             # HLS出力先（catchup-hlsが書き込み）
└── docker/catchup-hls/
    └── docker-compose.yml
```

## docker-compose.yml の内容

```yaml
version: '3.8'
services:
  catchup-hls:
    image: ghcr.io/masa55jp/catchup-hls:latest
    container_name: catchup-hls
    restart: unless-stopped
    devices:
      - /dev/dri:/dev/dri
    volumes:
      - /volume1/jetsonTV/record:/record:ro
      - /volume1/jetsonTV/hls:/hls
    environment:
      - EPGSTATION_URL=http://100.83.73.68:8888  # ← ここを修正する可能性
      - TZ=Asia/Tokyo
    ports:
      - "8080:80"
```

## 関連情報

| 項目 | 値 |
|------|-----|
| Jetson Nano IP (Tailscale) | 100.83.73.68 |
| NAS IP (Tailscale) | 100.86.102.37 |
| Jetson SSH | masashi@100.83.73.68 |
| GitHub リポジトリ | https://github.com/masa55jp/catchup-hls |
| Docker イメージ | ghcr.io/masa55jp/catchup-hls:latest |

## HLS 仕様

| パラメータ | 値 |
|-----------|-----|
| 解像度 | 480p (854x480) |
| 映像ビットレート | 600kbps |
| 音声ビットレート | 128kbps (AAC) |
| 合計 | 約730kbps |
| セグメント長 | 4秒 |
| 自動削除 | 24時間後 |
