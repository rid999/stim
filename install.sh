#!/bin/bash

# ============================================
# YouTube Streaming Dashboard Installer
# Full-Featured with Google Authenticator
# One-Command Installation - Zero Hassle
# ============================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 YouTube Streaming Dashboard - Full Installer${NC}"
echo "===================================================="

if [ "$EUID" -ne 0 ]; then 
   echo -e "${RED}⚠️  Please run as root: sudo bash install.sh${NC}"
   exit 1
fi

APP_NAME="yt-streaming-dashboard"
INSTALL_DIR="/opt/$APP_NAME"
PORT=55001

echo ""
echo -e "${YELLOW}📋 Configuration:${NC}"
echo "   App Name: $APP_NAME"
echo "   Install Directory: $INSTALL_DIR"
echo "   Port: $PORT"
echo ""

# Cleanup any previous failed installation
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}🗑️  Cleaning up previous installation...${NC}"
    systemctl stop $APP_NAME 2>/dev/null || true
    rm -rf $INSTALL_DIR
fi

echo -e "${GREEN}📦 [1/7] Installing system dependencies...${NC}"
apt update -qq
apt install -y build-essential sqlite3 curl wget git qrencode

echo -e "${GREEN}🐹 [2/7] Installing Go 1.21...${NC}"
if ! command -v go &> /dev/null; then
    wget -q https://go.dev/dl/go1.21.5.linux-amd64.tar.gz
    rm -rf /usr/local/go
    tar -C /usr/local -xzf go1.21.5.linux-amd64.tar.gz
    rm go1.21.5.linux-amd64.tar.gz
    export PATH=$PATH:/usr/local/go/bin
    echo 'export PATH=$PATH:/usr/local/go/bin' >> /root/.bashrc
    echo -e "${GREEN}✅ Go installed${NC}"
else
    echo -e "${GREEN}✅ Go already installed ($(go version))${NC}"
fi

export PATH=$PATH:/usr/local/go/bin

echo -e "${GREEN}📗 [3/7] Installing Node.js 18...${NC}"
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt install -y nodejs
    echo -e "${GREEN}✅ Node.js installed${NC}"
else
    echo -e "${GREEN}✅ Node.js already installed ($(node -v))${NC}"
fi

echo -e "${GREEN}📁 [4/7] Creating project structure...${NC}"
mkdir -p $INSTALL_DIR/{backend,frontend/src}
cd $INSTALL_DIR

cat > backend/main.go << 'GOEOF'
package main

import (
	"crypto/rand"
	"database/sql"
	"encoding/base32"
	"fmt"
	"log"
	"time"

	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/gofiber/fiber/v2/middleware/logger"
	"github.com/golang-jwt/jwt/v4"
	_ "github.com/mattn/go-sqlite3"
	"github.com/pquerna/otp/totp"
	"golang.org/x/crypto/bcrypt"
)

type User struct {
	ID        int    `json:"id"`
	Username  string `json:"username"`
	Password  string `json:"-"`
	OTPSecret string `json:"-"`
	CreatedAt time.Time `json:"created_at"`
}

type Stream struct {
	ID          int        `json:"id"`
	Title       string     `json:"title"`
	StreamKey   string     `json:"stream_key"`
	Status      string     `json:"status"`
	Viewers     int        `json:"viewers"`
	StartTime   time.Time  `json:"start_time"`
	EndTime     *time.Time `json:"end_time"`
}

var db *sql.DB
var jwtSecret = []byte("your-super-secret-jwt-key-change-this-in-production")

func initDB() error {
	var err error
	db, err = sql.Open("sqlite3", "./yt-streaming.db?_journal_mode=WAL")
	if err != nil {
		return err
	}

	schema := `
	CREATE TABLE IF NOT EXISTS users (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		username TEXT UNIQUE NOT NULL,
		password TEXT NOT NULL,
		otp_secret TEXT NOT NULL,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	);
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

func generateOTPSecret() string {
	secret := make([]byte, 20)
	rand.Read(secret)
	return base32.StdEncoding.EncodeToString(secret)
}

func createDefaultUser() error {
	var count int
	err := db.QueryRow("SELECT COUNT(*) FROM users").Scan(&count)
	if err != nil {
		return err
	}

	if count == 0 {
		hashedPassword, _ := bcrypt.GenerateFromPassword([]byte("admin"), bcrypt.DefaultCost)
		otpSecret := generateOTPSecret()
		
		_, err = db.Exec(
			"INSERT INTO users (username, password, otp_secret) VALUES (?, ?, ?)",
			"admin", string(hashedPassword), otpSecret,
		)
		if err != nil {
			return err
		}
		
		log.Println("✅ Default user created: admin / admin")
		log.Println("⚠️  Please change password after first login!")
	}
	
	return nil
}

func generateJWT(username string) (string, error) {
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, jwt.MapClaims{
		"username": username,
		"exp":      time.Now().Add(time.Hour * 24).Unix(),
	})
	return token.SignedString(jwtSecret)
}

func authMiddleware(c *fiber.Ctx) error {
	authHeader := c.Get("Authorization")
	if authHeader == "" {
		return c.Status(401).JSON(fiber.Map{"error": "Missing authorization header"})
	}

	tokenString := authHeader[7:] // Remove "Bearer "
	token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
		return jwtSecret, nil
	})

	if err != nil || !token.Valid {
		return c.Status(401).JSON(fiber.Map{"error": "Invalid token"})
	}

	return c.Next()
}

func main() {
	app := fiber.New(fiber.Config{
		AppName: "YouTube Streaming Dashboard",
	})

	app.Use(cors.New(cors.Config{
		AllowOrigins: "*",
		AllowHeaders: "Origin, Content-Type, Accept, Authorization",
	}))
	app.Use(logger.New())

	if err := initDB(); err != nil {
		log.Fatal("Failed to initialize database:", err)
	}
	defer db.Close()

	if err := createDefaultUser(); err != nil {
		log.Fatal("Failed to create default user:", err)
	}

	app.Static("/", "./frontend/dist")

	api := app.Group("/api")

	// Auth Routes
	api.Post("/setup-check", func(c *fiber.Ctx) error {
		var count int
		db.QueryRow("SELECT COUNT(*) FROM users").Scan(&count)
		return c.JSON(fiber.Map{"needs_setup": count == 0})
	})

	api.Post("/setup", func(c *fiber.Ctx) error {
		var input struct {
			Username string `json:"username"`
			Password string `json:"password"`
		}
		if err := c.BodyParser(&input); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid input"})
		}

		var count int
		db.QueryRow("SELECT COUNT(*) FROM users").Scan(&count)
		if count > 0 {
			return c.Status(400).JSON(fiber.Map{"error": "Setup already completed"})
		}

		hashedPassword, _ := bcrypt.GenerateFromPassword([]byte(input.Password), bcrypt.DefaultCost)
		otpSecret := generateOTPSecret()

		_, err := db.Exec(
			"INSERT INTO users (username, password, otp_secret) VALUES (?, ?, ?)",
			input.Username, string(hashedPassword), otpSecret,
		)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": err.Error()})
		}

		otpURL := fmt.Sprintf("otpauth://totp/YT-Dashboard:%s?secret=%s&issuer=YT-Dashboard",
			input.Username, otpSecret)

		return c.JSON(fiber.Map{
			"message": "Setup complete",
			"otp_url": otpURL,
			"secret":  otpSecret,
		})
	})

	api.Post("/login", func(c *fiber.Ctx) error {
		var input struct {
			Username string `json:"username"`
			Password string `json:"password"`
			OTP      string `json:"otp"`
		}
		if err := c.BodyParser(&input); err != nil {
			return c.Status(400).JSON(fiber.Map{"error": "Invalid input"})
		}

		var user User
		err := db.QueryRow(
			"SELECT id, username, password, otp_secret FROM users WHERE username = ?",
			input.Username,
		).Scan(&user.ID, &user.Username, &user.Password, &user.OTPSecret)

		if err != nil {
			return c.Status(401).JSON(fiber.Map{"error": "Invalid credentials"})
		}

		if err := bcrypt.CompareHashAndPassword([]byte(user.Password), []byte(input.Password)); err != nil {
			return c.Status(401).JSON(fiber.Map{"error": "Invalid credentials"})
		}

		if !totp.Validate(input.OTP, user.OTPSecret) {
			return c.Status(401).JSON(fiber.Map{"error": "Invalid OTP"})
		}

		token, err := generateJWT(user.Username)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": "Failed to generate token"})
		}

		return c.JSON(fiber.Map{
			"token":    token,
			"username": user.Username,
		})
	})

	api.Get("/qr-code", func(c *fiber.Ctx) error {
		username := c.Query("username", "admin")
		
		var otpSecret string
		err := db.QueryRow("SELECT otp_secret FROM users WHERE username = ?", username).Scan(&otpSecret)
		if err != nil {
			return c.Status(404).JSON(fiber.Map{"error": "User not found"})
		}

		otpURL := fmt.Sprintf("otpauth://totp/YT-Dashboard:%s?secret=%s&issuer=YT-Dashboard",
			username, otpSecret)

		return c.JSON(fiber.Map{
			"otp_url": otpURL,
			"secret":  otpSecret,
		})
	})

	// Protected Routes
	protected := api.Group("/", authMiddleware)

	protected.Get("/streams", func(c *fiber.Ctx) error {
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

	protected.Post("/streams", func(c *fiber.Ctx) error {
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

	protected.Put("/streams/:id/status", func(c *fiber.Ctx) error {
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

	protected.Delete("/streams/:id", func(c *fiber.Ctx) error {
		id := c.Params("id")
		_, err := db.Exec("DELETE FROM streams WHERE id = ?", id)
		if err != nil {
			return c.Status(500).JSON(fiber.Map{"error": err.Error()})
		}
		return c.JSON(fiber.Map{"message": "Stream deleted"})
	})

	protected.Get("/health", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{"status": "ok", "time": time.Now()})
	})

	app.Get("*", func(c *fiber.Ctx) error {
		return c.SendFile("./frontend/dist/index.html")
	})

	log.Printf("🚀 Server starting on port 55001...")
	log.Fatal(app.Listen(":55001"))
}
GOEOF

cat > backend/go.mod << 'MODEOF'
module yt-streaming-dashboard

go 1.21

require (
	github.com/gofiber/fiber/v2 v2.52.0
	github.com/golang-jwt/jwt/v4 v4.5.0
	github.com/mattn/go-sqlite3 v1.14.19
	github.com/pquerna/otp v1.4.0
	golang.org/x/crypto v0.18.0
)
MODEOF

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
    "lucide-react": "^0.263.1",
    "qrcode.react": "^3.1.0"
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
import { Play, Square, Trash2, Plus, Radio, LogOut, Key } from 'lucide-react';
import { QRCodeSVG } from 'qrcode.react';

function LoginPage({ onLogin }) {
  const [username, setUsername] = useState('admin');
  const [password, setPassword] = useState('');
  const [otp, setOtp] = useState('');
  const [showQR, setShowQR] = useState(false);
  const [qrData, setQrData] = useState(null);
  const [error, setError] = useState('');

  const handleLogin = async (e) => {
    e.preventDefault();
    setError('');

    try {
      const res = await fetch('/api/login', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password, otp })
      });

      const data = await res.json();
      
      if (!res.ok) {
        setError(data.error || 'Login failed');
        return;
      }

      localStorage.setItem('token', data.token);
      localStorage.setItem('username', data.username);
      onLogin(data.token);
    } catch (err) {
      setError('Connection error');
    }
  };

  const showQRCode = async () => {
    try {
      const res = await fetch(`/api/qr-code?username=${username}`);
      const data = await res.json();
      setQrData(data);
      setShowQR(true);
    } catch (err) {
      setError('Failed to load QR code');
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 to-gray-800 flex items-center justify-center p-4">
      <div className="bg-gray-800 p-8 rounded-lg shadow-2xl w-full max-w-md">
        <div className="text-center mb-8">
          <Radio className="mx-auto text-red-500 mb-4" size={64} />
          <h1 className="text-3xl font-bold text-white">YT Streaming Dashboard</h1>
          <p className="text-gray-400 mt-2">Secure Login with Google Authenticator</p>
        </div>

        {showQR && qrData ? (
          <div className="text-center">
            <h2 className="text-xl font-semibold text-white mb-4">Scan QR Code</h2>
            <div className="bg-white p-4 rounded-lg inline-block mb-4">
              <QRCodeSVG value={qrData.otp_url} size={200} />
            </div>
            <div className="bg-gray-700 p-4 rounded-lg mb-4">
              <p className="text-gray-300 text-sm mb-2">Manual Entry:</p>
              <code className="text-green-400 break-all text-xs">{qrData.secret}</code>
            </div>
            <button
              onClick={() => setShowQR(false)}
              className="bg-blue-600 hover:bg-blue-700 px-6 py-2 rounded-lg text-white transition"
            >
              Back to Login
            </button>
          </div>
        ) : (
          <form onSubmit={handleLogin} className="space-y-4">
            {error && (
              <div className="bg-red-600 text-white p-3 rounded-lg text-sm">
                {error}
              </div>
            )}

            <div>
              <label className="block text-gray-300 mb-2 text-sm">Username</label>
              <input
                type="text"
                value={username}
                onChange={(e) => setUsername(e.target.value)}
                className="w-full bg-gray-700 text-white px-4 py-3 rounded-lg focus:outline-none focus:ring-2 focus:ring-red-500"
                required
              />
            </div>

            <div>
              <label className="block text-gray-300 mb-2 text-sm">Password</label>
              <input
                type="password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                className="w-full bg-gray-700 text-white px-4 py-3 rounded-lg focus:outline-none focus:ring-2 focus:ring-red-500"
                required
              />
            </div>

            <div>
              <label className="block text-gray-300 mb-2 text-sm">Google Authenticator Code</label>
              <input
                type="text"
                value={otp}
                onChange={(e) => setOtp(e.target.value.replace(/\D/g, '').slice(0, 6))}
                placeholder="000000"
                className="w-full bg-gray-700 text-white px-4 py-3 rounded-lg focus:outline-none focus:ring-2 focus:ring-red-500 text-center text-2xl tracking-widest"
                maxLength={6}
                required
              />
            </div>

            <button
              type="submit"
              className="w-full bg-red-600 hover:bg-red-700 text-white py-3 rounded-lg font-semibold transition"
            >
              Login
            </button>

            <button
              type="button"
              onClick={showQRCode}
              className="w-full bg-gray-700 hover:bg-gray-600 text-white py-3 rounded-lg font-semibold transition flex items-center justify-center gap-2"
            >
              <Key size={20} />
              Show QR Code
            </button>

            <p className="text-gray-400 text-xs text-center mt-4">
              Default: admin / admin
            </p>
          </form>
        )}
      </div>
    </div>
  );
}

function Dashboard({ onLogout }) {
  const [streams, setStreams] = useState([]);
  const [showForm, setShowForm] = useState(false);
  const [formData, setFormData] = useState({ title: '', stream_key: '' });
  const username = localStorage.getItem('username');

  useEffect(() => {
    fetchStreams();
    const interval = setInterval(fetchStreams, 5000);
    return () => clearInterval(interval);
  }, []);

  const fetchStreams = async () => {
    try {
      const token = localStorage.getItem('token');
      const res = await fetch('/api/streams', {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      
      if (res.status === 401) {
        onLogout();
        return;
      }
      
      const data = await res.json();
      setStreams(data || []);
    } catch (err) {
      console.error('Failed to fetch streams:', err);
    }
  };

  const createStream = async (e) => {
    e.preventDefault();
    try {
      const token = localStorage.getItem('token');
      await fetch('/api/streams', {
        method: 'POST',
        headers: { 
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
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
      const token = localStorage.getItem('token');
      await fetch(`/api/streams/${id}/status`, {
        method: 'PUT',
        headers: { 
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
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
      const token = localStorage.getItem('token');
      await fetch(`/api/streams/${id}`, { 
        method: 'DELETE',
        headers: { 'Authorization': `Bearer ${token}` }
      });
      fetchStreams();
    } catch (err) {
      console.error('Failed to delete stream:', err);
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-gray-900 to-gray-800 text-white">
      <div className="container mx-auto px-4 py-8">
        <div className="flex justify-between items-center mb-8">
          <div>
            <h1 className="text-4xl font-bold flex items-center gap-3">
              <Radio className="text-red-500" size={40} />
              YouTube Streaming Dashboard
            </h1>
            <p className="text-gray-400 mt-2">Welcome, {username}</p>
          </div>
          <div className="flex gap-3">
            <button
              onClick={() => setShowForm(!showForm)}
              className="bg-red-600 hover:bg-red-700 px-6 py-3 rounded-lg flex items-center gap-2 transition"
            >
              <Plus size={20} />
              New Stream
            </button>
            <button
              onClick={onLogout}
              className="bg-gray-700 hover:bg-gray-600 px-6 py-3 rounded-lg flex items-center gap-2 transition"
            >
              <LogOut size={20} />
              Logout
            </button>
          </div>
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

export default function App() {
  const [isAuthenticated, setIsAuthenticated] = useState(false);

  useEffect(() => {
    const token = localStorage.getItem('token');
    if (token) {
      setIsAuthenticated(true);
    }
  }, []);

  const handleLogin = (token) => {
    setIsAuthenticated(true);
  };

  const handleLogout = () => {
    localStorage.removeItem('token');
    localStorage.removeItem('username');
    setIsAuthenticated(false);
  };

  return isAuthenticated ? (
    <Dashboard onLogout={handleLogout} />
  ) : (
    <LoginPage onLogin={handleLogin} />
  );
}
APPEOF

echo -e "${GREEN}✅ Project structure created${NC}"

echo -e "${GREEN}🔨 [5/7] Building application...${NC}"

cd $INSTALL_DIR/frontend
echo "   Installing frontend dependencies..."
npm install --silent

echo "   Building frontend..."
npm run build

cd $INSTALL_DIR/backend
echo "   Downloading Go dependencies..."
go mod tidy
go mod download

echo "   Building backend binary..."
CGO_ENABLED=1 go build -ldflags="-s -w" -o $INSTALL_DIR/$APP_NAME main.go

echo -e "${GREEN}✅ Build completed${NC}"

echo -e "${GREEN}⚙️  [6/7] Creating systemd service...${NC}"

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
Environment="PATH=/usr/local/go/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
SERVICEEOF

systemctl daemon-reload
systemctl enable $APP_NAME
systemctl start $APP_NAME

echo -e "${GREEN}✅ Service created and started${NC}"

echo -e "${GREEN}📱 [7/7] Generating initial QR code...${NC}"

sleep 2

SERVER_IP=$(hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}✅ Installation Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "${YELLOW}📍 Application Details:${NC}"
echo "   Location: $INSTALL_DIR"
echo "   Binary: $INSTALL_DIR/$APP_NAME"
echo "   Database: $INSTALL_DIR/yt-streaming.db"
echo "   Port: $PORT"
echo ""
echo -e "${YELLOW}🌐 Access your dashboard at:${NC}"
echo -e "   ${BLUE}http://$SERVER_IP:$PORT${NC}"
echo ""
echo -e "${YELLOW}🔐 Default Credentials:${NC}"
echo "   Username: admin"
echo "   Password: admin"
echo ""
echo -e "${YELLOW}📱 Setup Google Authenticator:${NC}"
echo "   1. Login with username & password"
echo "   2. Click 'Show QR Code' button"
echo "   3. Scan QR with Google Authenticator app"
echo "   4. Enter 6-digit code to complete login"
echo ""
echo -e "${YELLOW}🔧 Useful Commands:${NC}"
echo "   Status:  systemctl status $APP_NAME"
echo "   Logs:    journalctl -u $APP_NAME -f"
echo "   Restart: systemctl restart $APP_NAME"
echo "   Stop:    systemctl stop $APP_NAME"
echo ""
echo -e "${GREEN}🚀 Your YouTube Streaming Dashboard is now running!${NC}"
echo -e "${GREEN}============================================${NC}"
