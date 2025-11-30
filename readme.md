# 📺 YouTube Streaming Dashboard

Lightweight YouTube streaming management dashboard built with **Go-React Monolith Architecture**.

## ✨ Features

- 🎥 Manage multiple YouTube streams
- ⚡ Super lightweight (~20MB RAM idle)
- 🗄️ SQLite database (single file, no external DB needed)
- 🚀 Single binary deployment
- 📊 Real-time stream status monitoring
- 🔐 Production-ready with systemd auto-restart

## 🏗️ Architecture

- **Backend**: Go + Fiber v2 + SQLite3
- **Frontend**: React 18 + Vite + Tailwind CSS
- **Deployment**: Single binary with embedded static files
- **Memory**: ~20MB idle (vs ~100MB+ for Node.js apps)

## 📦 Quick Install

### One-Line Install (from GitHub)

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/REPO_NAME/main/install.sh | sudo bash
```

Or clone and run:

```bash
git clone https://github.com/YOUR_USERNAME/REPO_NAME.git
cd REPO_NAME
sudo bash install.sh
```

### Manual Install

1. Download the script:
```bash
wget https://raw.githubusercontent.com/YOUR_USERNAME/REPO_NAME/main/install.sh
chmod +x install.sh
```

2. Run as root:
```bash
sudo bash install.sh
```

Installation takes ~5-10 minutes depending on your server speed.

## 🎯 Quick Start

After installation:

1. **Access Dashboard**
   ```
   http://YOUR_SERVER_IP:55001
   ```

2. **Create a Stream**
   - Click "New Stream"
   - Enter title and stream key
   - Click "Create Stream"

3. **Start Streaming**
   - Click the ▶️ Play button to go live
   - Click the ⏹️ Stop button to end stream

## 🔧 Management Commands

```bash
# Check status
systemctl status yt-streaming-dashboard

# View logs (live)
journalctl -u yt-streaming-dashboard -f

# Restart service
systemctl restart yt-streaming-dashboard

# Stop service
systemctl stop yt-streaming-dashboard

# Start service
systemctl start yt-streaming-dashboard
```

## 🔄 Update

To rebuild after code changes:

```bash
sudo bash update.sh
```

## 🗑️ Uninstall

```bash
sudo bash uninstall.sh
```

This removes:
- Application files
- Systemd service
- Database

**Note**: Go and Node.js are kept on your system.

## 📁 File Structure

```
/opt/yt-streaming-dashboard/
├── yt-streaming-dashboard    # Binary executable
├── yt-streaming.db           # SQLite database
├── backend/
│   ├── main.go
│   └── go.mod
└── frontend/
    ├── dist/                 # Built static files
    ├── src/
    └── package.json
```

## 🔌 API Endpoints

### Get All Streams
```bash
GET /api/streams
```

### Create Stream
```bash
POST /api/streams
Content-Type: application/json

{
  "title": "My Stream",
  "stream_key": "xxxx-xxxx-xxxx-xxxx"
}
```

### Update Stream Status
```bash
PUT /api/streams/:id/status
Content-Type: application/json

{
  "status": "live"  # or "idle"
}
```

### Delete Stream
```bash
DELETE /api/streams/:id
```

### Health Check
```bash
GET /api/health
```

## 🛡️ Security Notes

- Default port: `55001`
- No authentication included (add JWT/OAuth if needed)
- Database: SQLite with WAL mode enabled
- Service runs as root (change user in systemd if needed)

## 🚀 Performance

- **RAM Usage**: ~20MB idle
- **Binary Size**: ~15MB
- **Database**: Single file, no external dependencies
- **Startup Time**: <100ms

## 🐛 Troubleshooting

### Service won't start
```bash
journalctl -u yt-streaming-dashboard -n 50
```

### Port already in use
Edit `/etc/systemd/system/yt-streaming-dashboard.service` and change port in the binary.

### Database locked
SQLite uses WAL mode to prevent locking. If issues persist:
```bash
rm /opt/yt-streaming-dashboard/yt-streaming.db
systemctl restart yt-streaming-dashboard
```

## 📝 Requirements

- Ubuntu/Debian Linux (tested on 20.04+)
- Root access
- 1GB RAM minimum
- 500MB disk space

## 🤝 Contributing

1. Fork the repo
2. Make changes
3. Test with `update.sh`
4. Submit PR

## 📄 License

MIT License - Use freely!

## 🙏 Credits

Built with the **Go-React Monolith Architecture** for maximum performance and minimal resource usage.

---

**Need help?** Open an issue on GitHub!
