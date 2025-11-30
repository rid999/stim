#!/bin/bash

# ============================================
# YouTube Streaming Dashboard Installer
# Lightweight Go-React Monolith Architecture
# ============================================

set -e  # Exit on error

echo "🚀 YouTube Streaming Dashboard - Automated Installer"
echo "===================================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
   echo "⚠️  Please run as root: sudo bash install.sh"
   exit 1
fi

# Configuration
APP_NAME="yt-streaming-dashboard"
INSTALL_DIR="/opt/$APP_NAME"
PORT=55001

echo ""
echo "📋 Configuration:"
echo "   App Name: $APP_NAME"
echo "   Install Directory: $INSTALL_DIR"
echo "   Port: $PORT"
echo ""

# Step 1: Install Dependencies
echo "📦 [1/6] Installing system dependencies..."
apt update -qq
apt install -y build-essential sqlite3 curl wget git

# Step 2: Install Go
echo "🐹 [2/6] Installing Go 1.21..."
if ! command -v go &> /dev/null; then
    wget -q https://go.dev/dl/go1.21.5.linux-amd64.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
    rm go1.21.5.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /root/.bashrc
    echo "✅ Go installed"
else
    echo "✅ Go already installed ($(go version))"
fi

# Step 3: Install Node.js
echo "📗 [3/6] Installing Node.js 18..."
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
    echo "✅ Node.js installed"
else
    echo "✅ Node.js already installed ($(node -v))"
fi

# Step 4: Create Project Structure
echo "📁 [4/6] Creating project structure..."
mkdir -p $INSTALL_DIR/{backend,frontend/src}
cd $INSTALL_DIR

# Create Go Backend
cat > backend/main.go << 'GOEOF'
package main

import (
	"database/sql"
	"log"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	_ "github.com/mattn/go-sqlite3"
)

type Stream struct {
	ID          int       `json:"id"`
	Title       string    `json:"title"`
	StreamKey   string    `json:"stream_key"`
	Status      string    `json:"status"`
	Viewers     int       `json:"viewers"`
	StartTime   time.Time `json:"start_time"`
	EndTime     *time.Time `json:"end_time"`
}

var db *sql.DB

func initDB() error {
	var err error
	db, err = sql.Open("sqlite3", "./yt-streaming.db?_journal_mode=WAL")
	if err != nil {
		return err
	}

	schema := `
	CREATE TABLE IF NOT EXISTS streams (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		title TEXT NOT NULL,
		stream_key TEXT UNIQUE NOT NULL,
		status TEXT DEFAULT 'idle',
		viewers INTEGER DEFAULT 0,
		start_time DATETIME,
		end_time DATETIME
	);
	CREATE INDEX IF NOT EXISTS idx_status ON streams(status);
	`
	_, err = db.Exec(schema)
	return err
}

func main() {
	app := fiber.New(fiber.Config{
		AppName: "YouTube Streaming Dashboard",
	})

	// Middleware
	app.Use(cors.New())
	app.Use(logger.New())

	// Initialize Database
	if err := initDB(); err != nil {
		log.Fatal("Failed to initialize database:", err)
	}
	defer db.Close()

	// Serve Frontend
	app.Static("/", "./frontend/dist")

	// API Routes
	api := app.Group("/api")

	// Get all streams
	api.Get("/streams", func(c *fiber.Ctx) error {
		rows, err := db.Query("SELECT id, title, stream_key, status, viewers, start_time, end_time FROM streams ORDER BY id DESC")
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": err.Error()})
		}
		defer rows.Close()

		streams := []Stream{}
		for rows.Next() {
			var s Stream
			var endTime sql.NullTime
			err := rows.Scan(&s.ID, &s.Title, &s.StreamKey, &s.Status, &s.Viewers, &s.StartTime, &endTime)
			if err != nil {
				continue
			}
			if endTime.Valid {
				s.EndTime = &endTime.Time
			}
			streams = append(streams, s)
		}
		return c.JSON(streams)
	})

	// Create new stream
	api.Post("/streams", func(c *fiber.Ctx) error {
		var input struct {
			Title     string `json:"title"`
			StreamKey string `json:"stream_key"`
		}
		if err := c.BodyParser(&input); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid input"})
		}

		result, err := db.Exec(
			"INSERT INTO streams (title, stream_key, status, start_time) VALUES (?, ?, 'idle', ?)",
			input.Title, input.StreamKey, time.Now(),
		)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": err.Error()})
		}

		id, _ := result.LastInsertId()
		return c.JSON(fiber.Map{"id": id, "message": "Stream created"})
	})

	// Update stream status
	api.Put("/streams/:id/status", func(c *fiber.Ctx) error {
		id := c.Params("id")
		var input struct {
			Status string `json:"status"`
		}
		if err := c.BodyParser(&input); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid input"})
		}

		_, err := db.Exec("UPDATE streams SET status = ? WHERE id = ?", input.Status, id)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": err.Error()})
		}

		return c.JSON(fiber.Map{"message": "Status updated"})
	})

	// Delete stream
	api.Delete("/streams/:id", func(c *fiber.Ctx) error {
		id := c.Params("id")
		_, err := db.Exec("DELETE FROM streams WHERE id = ?", id)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": err.Error()})
		}
		return c.JSON(fiber.Map{"message": "Stream deleted"})
	})

	// Health check
	api.Get("/health", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"status": "ok", "time": time.Now()})
	})

	// React Router Handler
	app.Get("*", func(c *fiber.Ctx) error {
		return c.SendFile("./frontend/dist/index.html")
	})

	log.Printf("🚀 Server starting on port 55001...")
	log.Fatal(app.Listen(":55001"))
}
GOEOF

# Create Go mod
cat > backend/go.mod << 'MODEOF'
module yt-streaming-dashboard

go 1.21

require (
	github.com/gofiber/fiber/v2 v2.52.0
	github.com/mattn/go-sqlite3 v1.14.19
)
MODEOF

# Create Frontend Package.json
cat > frontend/package.json << 'PKGEOF'
{
  "name": "yt-streaming-dashboard-frontend",
  "version": "1.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "lucide-react": "^0.263.1"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "^4.2.1",
    "autoprefixer": "^10.4.16",
    "postcss": "^8.4.32",
    "tailwindcss": "^3.4.0",
    "vite": "^5.0.8"
  }
}
PKGEOF

# Create Vite Config
cat > frontend/vite.config.js << 'VITEEOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      '/api': 'http://localhost:55001'
    }
  }
})
VITEEOF

# Create Tailwind Config
cat > frontend/tailwind.config.js << 'TAILEOF'
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,jsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
TAILEOF

cat > frontend/postcss.config.js << 'POSTEOF'
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}
POSTEOF

# Create Frontend Files
mkdir -p frontend/src

cat > frontend/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>YouTube Streaming Dashboard</title>
</head>
<body>
  <div id="root"></div>
  <script type="module" src="/src/main.jsx"></script>
</body>
</html>
HTMLEOF

cat > frontend/src/main.jsx << 'MAINEOF'
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
MAINEOF

cat > frontend/src/index.css << 'CSSEOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

body {
  margin: 0;
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen',
    'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue',
    sans-serif;
  -webkit-font-smoothing: antialiased;
  -moz-osx-font-smoothing: grayscale;
}
CSSEOF

cat > frontend/src/App.jsx << 'APPEOF'
import React, { useState, useEffect } from 'react';
import { Play, Square, Trash2, Plus, Radio } from 'lucide-react';

export default function App() {
  const [streams, setStreams] = useState([]);
  const [showForm, setShowForm] = useState(false);
  const [formData, setFormData] = useState({ title: '', stream_key: '' });

  useEffect(() => {
    fetchStreams();
    const interval = setInterval(fetchStreams, 5000);
    return () => clearInterval(interval);
  }, []);

  const fetchStreams = async () => {
    try {
      const res = await fetch('/api/streams');
      const data = await res.json();
      setStreams(data || []);
    } catch (err) {
      console.error('Failed to fetch streams:', err);
    }
  };

  const createStream = async (e) => {
    e.preventDefault();
    try {
      await fetch('/api/streams', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData)
      });
      setFormData({ title: '', stream_key: '' });
      setShowForm(false);
      fetchStreams();
    } catch (err) {
      console.error('Failed to create stream:', err);
    }
  };

  const updateStatus = async (id, status) => {
    try {
      await fetch(`/api/streams/${id}/status`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ status })
      });
      fetchStreams();
    } catch (err) {
      console.error('Failed to update status:', err);
    }
  };

  const deleteStream = async (id) => {
    if (!confirm('Delete this stream?')) return;
    try {
      await fetch(`/api/streams/${id}`, { method: 'DELETE' });
      fetchStreams();
    } catch (err) {
      console.error('Failed to delete stream:', err);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 to-gray-800 text-white">
      <div className="container mx-auto px-4 py-8">
        <div className="flex justify-between items-center mb-8">
          <h1 className="text-4xl font-bold flex items-center gap-3">
            <Radio className="text-red-500" size={40} />
            YouTube Streaming Dashboard
          </h1>
          <button
            onClick={() => setShowForm(!showForm)}
            className="bg-red-600 hover:bg-red-700 px-6 py-3 rounded-lg flex items-center gap-2 transition"
          >
            <Plus size={20} />
            New Stream
          </button>
        </div>

        {showForm && (
          <form onSubmit={createStream} className="bg-gray-800 p-6 rounded-lg mb-8 shadow-xl">
            <h2 className="text-2xl font-semibold mb-4">Create New Stream</h2>
            <div className="grid gap-4">
              <input
                type="text"
                placeholder="Stream Title"
                value={formData.title}
                onChange={(e) => setFormData({ ...formData, title: e.target.value })}
                className="bg-gray-700 px-4 py-3 rounded-lg focus:outline-none focus:ring-2 focus:ring-red-500"
                required
              />
              <input
                type="text"
                placeholder="Stream Key"
                value={formData.stream_key}
                onChange={(e) => setFormData({ ...formData, stream_key: e.target.value })}
                className="bg-gray-700 px-4 py-3 rounded-lg focus:outline-none focus:ring-2 focus:ring-red-500"
                required
              />
              <div className="flex gap-3">
                <button type="submit" className="bg-green-600 hover:bg-green-700 px-6 py-3 rounded-lg flex-1 transition">
                  Create Stream
                </button>
                <button
                  type="button"
                  onClick={() => setShowForm(false)}
                  className="bg-gray-600 hover:bg-gray-700 px-6 py-3 rounded-lg transition"
                >
                  Cancel
                </button>
              </div>
            </div>
          </form>
        )}

        <div className="grid gap-6">
          {streams.length === 0 ? (
            <div className="text-center py-20 text-gray-400">
              <Radio size={64} className="mx-auto mb-4 opacity-50" />
              <p className="text-xl">No streams yet. Create your first stream!</p>
            </div>
          ) : (
            streams.map((stream) => (
              <div key={stream.id} className="bg-gray-800 p-6 rounded-lg shadow-xl hover:shadow-2xl transition">
                <div className="flex justify-between items-start">
                  <div className="flex-1">
                    <h3 className="text-2xl font-semibold mb-2">{stream.title}</h3>
                    <p className="text-gray-400 mb-3">Stream Key: {stream.stream_key}</p>
                    <div className="flex items-center gap-4">
                      <span className={`px-4 py-2 rounded-full text-sm font-semibold ${
                        stream.status === 'live' ? 'bg-red-600' :
                        stream.status === 'starting' ? 'bg-yellow-600' :
                        'bg-gray-600'
                      }`}>
                        {stream.status.toUpperCase()}
                      </span>
                      {stream.status === 'live' && (
                        <span className="text-gray-300">👁️ {stream.viewers} viewers</span>
                      )}
                    </div>
                  </div>
                  <div className="flex gap-2">
                    {stream.status !== 'live' ? (
                      <button
                        onClick={() => updateStatus(stream.id, 'live')}
                        className="bg-green-600 hover:bg-green-700 p-3 rounded-lg transition"
                        title="Start Stream"
                      >
                        <Play size={20} />
                      </button>
                    ) : (
                      <button
                        onClick={() => updateStatus(stream.id, 'idle')}
                        className="bg-red-600 hover:bg-red-700 p-3 rounded-lg transition"
                        title="Stop Stream"
                      >
                        <Square size={20} />
                      </button>
                    )}
                    <button
                      onClick={() => deleteStream(stream.id)}
                      className="bg-gray-700 hover:bg-gray-600 p-3 rounded-lg transition"
                      title="Delete Stream"
                    >
                      <Trash2 size={20} />
                    </button>
                  </div>
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  );
}
APPEOF

echo "✅ Project structure created"

# Step 5: Build Application
echo "🔨 [5/6] Building application..."

# Build Frontend
cd $INSTALL_DIR/frontend
echo "   Building frontend..."
npm install --silent
npm run build

# Build Backend
cd $INSTALL_DIR/backend
echo "   Building backend..."
export PATH=$PATH:/usr/local/go/bin
go mod download
go build -o $INSTALL_DIR/$APP_NAME main.go

echo "✅ Build completed"

# Step 6: Create Systemd Service
echo "⚙️  [6/6] Creating systemd service..."

cat > /etc/systemd/system/$APP_NAME.service << SERVICEEOF
[Unit]
Description=YouTube Streaming Dashboard
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$APP_NAME
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable $APP_NAME
systemctl start $APP_NAME

echo "✅ Service created and started"

# Final Info
echo ""
echo "============================================"
echo "✅ Installation Complete!"
echo "============================================"
echo ""
echo "📍 Application Details:"
echo "   Location: $INSTALL_DIR"
echo "   Binary: $INSTALL_DIR/$APP_NAME"
echo "   Database: $INSTALL_DIR/yt-streaming.db"
echo "   Port: $PORT"
echo ""
echo "🌐 Access your dashboard at:"
echo "   http://$(hostname -I | awk '{print $1}'):$PORT"
echo ""
echo "🔧 Useful Commands:"
echo "   Status:  systemctl status $APP_NAME"
echo "   Logs:    journalctl -u $APP_NAME -f"
echo "   Restart: systemctl restart $APP_NAME"
echo "   Stop:    systemctl stop $APP_NAME"
echo ""
echo "🚀 Your YouTube Streaming Dashboard is now running!"
echo "============================================"
