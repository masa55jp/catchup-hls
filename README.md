# catchup-hls

録画中のTSファイルからHLSを自動生成し、追っかけ再生を可能にするDockerアプリケーション。

## 特徴

- **Intel QSV対応**: Intel N100などのCPU内蔵GPUでハードウェアエンコード
- **自動検知**: 新しいTSファイルを検知して自動でHLS生成開始
- **追っかけ再生**: 録画中の番組を最初から視聴可能
- **Web UI**: 録画中番組一覧と再生リンク
- **自動削除**: 24時間後にHLSを自動クリーンアップ

## システム構成

```
┌────────────────────────────────────────────────────────────┐
│  UGREEN NAS (Intel N100)                                   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ catchup-hls (Docker)                                │   │
│  │                                                     │   │
│  │  ┌──────────────┐  ┌──────────────┐                │   │
│  │  │ TS監視       │  │ Nginx        │                │   │
│  │  │ + HLS生成    │  │ (Web UI/HLS) │                │   │
│  │  │ (Intel QSV)  │  │              │                │   │
│  │  └──────────────┘  └──────────────┘                │   │
│  │         ↓                  ↓                        │   │
│  │    /record (入力)    :80 (出力)                    │   │
│  └─────────────────────────────────────────────────────┘   │
│         ↑                     ↓                            │
│  /volume1/jetsonTV/      http://nas-ip:8080/               │
│  ├─ record/*.m2ts            ├─ /live/ (Web UI)            │
│  └─ hls/{id}/                └─ /hls/{id}/index.m3u8       │
│                                                             │
└────────────────────────────────────────────────────────────┘
         ↑
    NFS マウント
         │
┌────────────────────┐
│ Jetson Nano        │
│ (EPGStation)       │
│ → TS録画           │
└────────────────────┘
```

## 動作環境

### ハードウェア
- Intel CPU (N100, N5105, etc.) + 内蔵GPU
- または VA-API対応GPU

### ソフトウェア
- Docker / Docker Compose
- UGOS Pro (UGREEN NAS) または Linux

## クイックスタート

### 1. UGOSでの使用

1. Docker → Compose → 新規作成
2. 以下の内容を貼り付け:

```yaml
version: '3.8'
services:
  catchup-hls:
    image: ghcr.io/your-username/catchup-hls:latest
    container_name: catchup-hls
    restart: unless-stopped
    devices:
      - /dev/dri:/dev/dri
    volumes:
      - /volume1/jetsonTV/record:/record:ro
      - /volume1/jetsonTV/hls:/hls
    environment:
      - EPGSTATION_URL=http://100.83.73.68:8888
      - TZ=Asia/Tokyo
    ports:
      - "8080:80"
```

3. パスを環境に合わせて編集
4. 起動

### 2. ローカルビルド

```bash
git clone https://github.com/your-username/catchup-hls.git
cd catchup-hls
docker-compose up -d --build
```

## 使い方

### Web UI

`http://nas-ip:8080/` にアクセス

- 録画中の番組一覧が表示される
- 「追っかけ再生」ボタンでHLS再生開始
- Safari / VLC / Infuse で再生可能

### HLS URL 直接アクセス

```
http://nas-ip:8080/hls/{recording-id}/index.m3u8
```

## 環境変数

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `EPGSTATION_URL` | `http://localhost:8888` | EPGStationのURL |
| `HLS_VIDEO_BITRATE` | `600k` | 映像ビットレート |
| `HLS_AUDIO_BITRATE` | `128k` | 音声ビットレート |
| `HLS_RESOLUTION` | `854x480` | 出力解像度 |
| `HLS_SEGMENT_TIME` | `4` | セグメント長（秒） |
| `HLS_CLEANUP_HOURS` | `24` | HLS保持時間 |
| `TZ` | `Asia/Tokyo` | タイムゾーン |

## ビットレート目安

| 用途 | 映像 | 音声 | 合計 |
|------|------|------|------|
| モバイル（低速） | 400k | 64k | ~470kbps |
| モバイル（標準） | 600k | 128k | ~730kbps |
| WiFi / 高速回線 | 1000k | 128k | ~1.1Mbps |

## トラブルシューティング

### HLSが生成されない

1. GPU認識を確認:
```bash
docker exec catchup-hls vainfo
```

2. ログを確認:
```bash
docker logs catchup-hls
```

### Web UIに録画が表示されない

1. EPGStation URLを確認
2. NASからJetsonにアクセスできるか確認:
```bash
docker exec catchup-hls curl -s http://EPGSTATION_URL/api/version
```

### 再生が途切れる

- `HLS_SEGMENT_TIME` を大きく（6-10秒）
- `HLS_VIDEO_BITRATE` を下げる

## ライセンス

MIT License

## 謝辞

- [FFmpeg](https://ffmpeg.org/)
- [EPGStation](https://github.com/l3tnun/EPGStation)
- [Intel Media Driver](https://github.com/intel/media-driver)
