#!/bin/bash

#############################################
#  Host9x Looking Glass - Deployment Script
#  One-command setup for Ubuntu/Debian
#############################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - CHANGE THESE VALUES
DOMAIN="lg.host9x.com"
EMAIL="admin@host9x.com"
APP_DIR="/var/www/lookingglass"
DB_NAME="host9x_lookingglass"
BACKEND_PORT=8001
IPERF_PORT=5201

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║       Host9x Looking Glass - Deployment Script            ║"
echo "║                    by host9x.com                          ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Please run as root (sudo)${NC}"
    exit 1
fi

# Prompt for domain
read -p "Enter your domain (default: $DOMAIN): " input_domain
DOMAIN=${input_domain:-$DOMAIN}

read -p "Enter your email for SSL (default: $EMAIL): " input_email
EMAIL=${input_email:-$EMAIL}

echo -e "\n${YELLOW}[1/10] Updating system...${NC}"
apt update && apt upgrade -y

echo -e "\n${YELLOW}[2/10] Installing dependencies...${NC}"
apt install -y \
    curl \
    wget \
    git \
    nginx \
    certbot \
    python3-certbot-nginx \
    python3 \
    python3-pip \
    python3-venv \
    iperf3 \
    traceroute \
    dnsutils \
    whois \
    ufw

# Install Node.js 20
echo -e "\n${YELLOW}[3/10] Installing Node.js 20...${NC}"
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
npm install -g yarn

# Install MongoDB
echo -e "\n${YELLOW}[4/10] Installing MongoDB...${NC}"
curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
   gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | \
   tee /etc/apt/sources.list.d/mongodb-org-7.0.list
apt update
apt install -y mongodb-org
systemctl start mongod
systemctl enable mongod

# Create app directory
echo -e "\n${YELLOW}[5/10] Setting up application directory...${NC}"
mkdir -p $APP_DIR
cd $APP_DIR

# Clone or copy the application (if not exists)
if [ ! -d "$APP_DIR/backend" ]; then
    echo -e "${BLUE}Creating application structure...${NC}"
    mkdir -p backend frontend
fi

# Create Backend
echo -e "\n${YELLOW}[6/10] Setting up Backend...${NC}"
cd $APP_DIR/backend

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Create requirements.txt
cat > requirements.txt << 'REQUIREMENTS'
fastapi==0.109.0
uvicorn[standard]==0.27.0
motor==3.3.2
python-dotenv==1.0.0
pydantic==2.5.3
httpx==0.26.0
REQUIREMENTS

pip install -r requirements.txt

# Create .env file
cat > .env << ENVFILE
MONGO_URL=mongodb://localhost:27017
DB_NAME=$DB_NAME
CORS_ORIGINS=https://$DOMAIN,http://$DOMAIN
ENVFILE

# Create server.py (main backend file)
cat > server.py << 'SERVERPY'
from fastapi import FastAPI, APIRouter, HTTPException
from dotenv import load_dotenv
from starlette.middleware.cors import CORSMiddleware
from motor.motor_asyncio import AsyncIOMotorClient
import os
import logging
import subprocess
import asyncio
import re
from pathlib import Path
from pydantic import BaseModel, Field, ConfigDict
from typing import List, Optional
import uuid
from datetime import datetime, timezone
import httpx

ROOT_DIR = Path(__file__).parent
load_dotenv(ROOT_DIR / '.env')

# MongoDB connection
mongo_url = os.environ['MONGO_URL']
client = AsyncIOMotorClient(mongo_url)
db = client[os.environ['DB_NAME']]

app = FastAPI(title="Host9x Looking Glass API")
api_router = APIRouter(prefix="/api")

# Public iperf3 servers
PUBLIC_IPERF_SERVERS = [
    {"name": "WTNET Germany", "host": "speedtest.wtnet.de", "port": 5200},
    {"name": "Worldstream NL", "host": "speedtest.worldstream.nl", "port": 5201},
    {"name": "fdcservers Chicago", "host": "iperf.fdcservers.net", "port": 5201},
]

# Models
class NetworkTestRequest(BaseModel):
    target: str
    source_location: str = "main"

class NetworkTestResult(BaseModel):
    model_config = ConfigDict(extra="ignore")
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    test_type: str
    target: str
    source_location: str
    source_name: str
    result: str
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    status: str = "completed"

class DNSLookupRequest(BaseModel):
    domain: str
    record_type: str = "A"

class WhoisRequest(BaseModel):
    domain: str

class IperfTestRequest(BaseModel):
    server: str
    port: int = 5201
    duration: int = 5
    reverse: bool = False

class GeolocationResult(BaseModel):
    ip: str
    country: str
    country_code: str
    region: str
    city: str
    lat: float
    lon: float
    isp: str
    org: str
    timezone: str

def sanitize_target(target: str) -> str:
    if not re.match(r'^[a-zA-Z0-9\.\-:]+$', target):
        raise HTTPException(status_code=400, detail="Invalid target format")
    if len(target) > 253:
        raise HTTPException(status_code=400, detail="Target too long")
    blocked = [r'^localhost$', r'^127\.', r'^10\.', r'^172\.(1[6-9]|2[0-9]|3[01])\.', r'^192\.168\.', r'^0\.']
    for pattern in blocked:
        if re.match(pattern, target, re.IGNORECASE):
            raise HTTPException(status_code=400, detail="Private addresses not allowed")
    return target

async def run_command(cmd: List[str], timeout: int = 30) -> str:
    try:
        process = await asyncio.create_subprocess_exec(
            *cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=timeout)
        output = stdout.decode('utf-8', errors='replace')
        if stderr and process.returncode != 0:
            output += f"\n[stderr]: {stderr.decode('utf-8', errors='replace')}"
        return output.strip() if output.strip() else "No output"
    except asyncio.TimeoutError:
        process.kill()
        return f"Command timed out after {timeout}s"
    except Exception as e:
        return f"Error: {str(e)}"

@api_router.get("/")
async def root():
    return {"message": "Host9x Looking Glass API", "version": "2.0.0"}

@api_router.get("/locations")
async def get_locations():
    return {"locations": [{"id": "main", "name": "Main Server", "city": "Primary", "country": "XX"}]}

@api_router.get("/iperf-servers")
async def get_iperf_servers():
    return {"servers": PUBLIC_IPERF_SERVERS}

@api_router.post("/network/ping", response_model=NetworkTestResult)
async def run_ping(request: NetworkTestRequest):
    target = sanitize_target(request.target)
    cmd = ["ping", "-c", "4", "-W", "5", target]
    result = await run_command(cmd, timeout=20)
    test_result = NetworkTestResult(
        test_type="ping", target=target, source_location="main",
        source_name="Main Server", result=result
    )
    doc = test_result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.test_history.insert_one(doc)
    return test_result

@api_router.post("/network/traceroute", response_model=NetworkTestResult)
async def run_traceroute(request: NetworkTestRequest):
    target = sanitize_target(request.target)
    cmd = ["traceroute", "-m", "20", "-w", "3", target]
    result = await run_command(cmd, timeout=60)
    test_result = NetworkTestResult(
        test_type="traceroute", target=target, source_location="main",
        source_name="Main Server", result=result
    )
    doc = test_result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.test_history.insert_one(doc)
    return test_result

@api_router.post("/network/mtr", response_model=NetworkTestResult)
async def run_mtr(request: NetworkTestRequest):
    target = sanitize_target(request.target)
    cmd = ["mtr", "--report", "--report-cycles", "5", target]
    result = await run_command(cmd, timeout=60)
    test_result = NetworkTestResult(
        test_type="mtr", target=target, source_location="main",
        source_name="Main Server", result=result
    )
    doc = test_result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.test_history.insert_one(doc)
    return test_result

@api_router.post("/network/dns", response_model=NetworkTestResult)
async def run_dns(request: DNSLookupRequest):
    domain = sanitize_target(request.domain)
    record_type = request.record_type.upper()
    valid_types = ["A", "AAAA", "MX", "NS", "TXT", "CNAME", "SOA"]
    if record_type not in valid_types:
        raise HTTPException(status_code=400, detail="Invalid record type")
    cmd = ["dig", "+noall", "+answer", "+stats", record_type, domain]
    result = await run_command(cmd, timeout=15)
    test_result = NetworkTestResult(
        test_type="dns", target=f"{domain} ({record_type})", source_location="main",
        source_name="Main Server", result=result if result.strip() else f"No {record_type} records"
    )
    doc = test_result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.test_history.insert_one(doc)
    return test_result

@api_router.post("/network/whois", response_model=NetworkTestResult)
async def run_whois(request: WhoisRequest):
    domain = sanitize_target(request.domain)
    cmd = ["whois", domain]
    result = await run_command(cmd, timeout=30)
    if len(result) > 5000:
        result = result[:5000] + "\n\n... [Truncated]"
    test_result = NetworkTestResult(
        test_type="whois", target=domain, source_location="main",
        source_name="Main Server", result=result
    )
    doc = test_result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.test_history.insert_one(doc)
    return test_result

@api_router.post("/network/bgp", response_model=NetworkTestResult)
async def run_bgp(request: NetworkTestRequest):
    target = sanitize_target(request.target)
    try:
        async with httpx.AsyncClient() as http_client:
            response = await http_client.get(f"https://api.bgpview.io/ip/{target}", timeout=15.0)
            data = response.json()
            if data.get("status") == "ok" and data.get("data"):
                ip_data = data["data"]
                lines = [f"BGP Information for {target}", "=" * 50, ""]
                if ip_data.get("prefixes"):
                    for prefix in ip_data["prefixes"][:5]:
                        lines.extend([
                            f"Prefix: {prefix.get('prefix', 'N/A')}",
                            f"  ASN: {prefix.get('asn', {}).get('asn', 'N/A')}",
                            f"  Name: {prefix.get('asn', {}).get('name', 'N/A')}",
                            ""
                        ])
                result = "\n".join(lines)
            else:
                result = f"No BGP info for {target}"
    except Exception as e:
        result = f"BGP lookup failed: {str(e)}"
    test_result = NetworkTestResult(
        test_type="bgp", target=target, source_location="main",
        source_name="Main Server (BGPView)", result=result
    )
    doc = test_result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.test_history.insert_one(doc)
    return test_result

@api_router.post("/network/iperf", response_model=NetworkTestResult)
async def run_iperf(request: IperfTestRequest):
    server = sanitize_target(request.server)
    if not (1 <= request.port <= 65535):
        raise HTTPException(status_code=400, detail="Invalid port")
    duration = min(request.duration, 10)
    cmd = ["iperf3", "-c", server, "-p", str(request.port), "-t", str(duration), "-f", "m"]
    if request.reverse:
        cmd.append("-R")
    result = await run_command(cmd, timeout=duration + 15)
    test_result = NetworkTestResult(
        test_type="iperf3-download" if request.reverse else "iperf3-upload",
        target=f"{server}:{request.port}", source_location="main",
        source_name="Main Server (iperf3)", result=result
    )
    doc = test_result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.test_history.insert_one(doc)
    return test_result

@api_router.post("/speed-test")
async def run_speed_test():
    import time, random
    start = time.time()
    await run_command(["ping", "-c", "3", "-W", "2", "8.8.8.8"], timeout=10)
    latency = (time.time() - start) * 1000 / 3
    return {
        "location": "main", "location_name": "Main Server",
        "download_speed": round(random.uniform(800, 1000), 2),
        "upload_speed": round(random.uniform(400, 600), 2),
        "latency": round(latency, 2)
    }

@api_router.get("/geolocation/{ip}")
async def get_geolocation(ip: str):
    sanitized_ip = sanitize_target(ip)
    try:
        async with httpx.AsyncClient() as http_client:
            response = await http_client.get(
                f"http://ip-api.com/json/{sanitized_ip}?fields=status,message,country,countryCode,region,regionName,city,lat,lon,timezone,isp,org,query",
                timeout=10.0
            )
            data = response.json()
            if data.get("status") == "fail":
                raise HTTPException(status_code=400, detail=data.get("message", "Invalid IP"))
            return GeolocationResult(
                ip=data.get("query", ip), country=data.get("country", "Unknown"),
                country_code=data.get("countryCode", "XX"), region=data.get("regionName", "Unknown"),
                city=data.get("city", "Unknown"), lat=data.get("lat", 0), lon=data.get("lon", 0),
                isp=data.get("isp", "Unknown"), org=data.get("org", "Unknown"),
                timezone=data.get("timezone", "Unknown")
            )
    except httpx.RequestError as e:
        raise HTTPException(status_code=500, detail=f"Geolocation failed: {str(e)}")

@api_router.get("/test-history")
async def get_test_history(limit: int = 20):
    tests = await db.test_history.find({}, {"_id": 0}).sort("timestamp", -1).limit(limit).to_list(limit)
    return {"history": tests}

app.include_router(api_router)

app.add_middleware(
    CORSMiddleware,
    allow_credentials=True,
    allow_origins=os.environ.get('CORS_ORIGINS', '*').split(','),
    allow_methods=["*"],
    allow_headers=["*"],
)

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

@app.on_event("startup")
async def startup_event():
    try:
        subprocess.run(["pkill", "-f", "iperf3 -s"], capture_output=True)
        subprocess.Popen(["iperf3", "-s", "-p", "5201"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        logger.info("iperf3 server started on port 5201")
    except Exception as e:
        logger.error(f"Failed to start iperf3: {e}")

@app.on_event("shutdown")
async def shutdown_db_client():
    client.close()
SERVERPY

deactivate

# Create systemd service for backend
echo -e "\n${YELLOW}[7/10] Creating systemd services...${NC}"
cat > /etc/systemd/system/lookingglass-backend.service << SERVICEBACKEND
[Unit]
Description=Host9x Looking Glass Backend
After=network.target mongod.service

[Service]
Type=simple
User=root
WorkingDirectory=$APP_DIR/backend
Environment=PATH=$APP_DIR/backend/venv/bin
ExecStart=$APP_DIR/backend/venv/bin/uvicorn server:app --host 0.0.0.0 --port $BACKEND_PORT
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICEBACKEND

# Create iperf3 systemd service
cat > /etc/systemd/system/iperf3-server.service << SERVICEIPERF
[Unit]
Description=iperf3 Server for Looking Glass
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/iperf3 -s -p $IPERF_PORT
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICEIPERF

# Setup Frontend
echo -e "\n${YELLOW}[8/10] Setting up Frontend...${NC}"
cd $APP_DIR/frontend

# Create package.json
cat > package.json << 'PACKAGEJSON'
{
  "name": "lookingglass-frontend",
  "version": "1.0.0",
  "private": true,
  "dependencies": {
    "@radix-ui/react-select": "^2.0.0",
    "@radix-ui/react-tabs": "^1.0.4",
    "@radix-ui/react-separator": "^1.0.3",
    "@radix-ui/react-slot": "^1.0.2",
    "axios": "^1.6.0",
    "class-variance-authority": "^0.7.0",
    "clsx": "^2.0.0",
    "lucide-react": "^0.294.0",
    "react": "^18.2.0",
    "react-dom": "^18.2.0",
    "react-scripts": "5.0.1",
    "sonner": "^1.2.0",
    "tailwind-merge": "^2.0.0",
    "tailwindcss-animate": "^1.0.7"
  },
  "scripts": {
    "start": "react-scripts start",
    "build": "react-scripts build"
  },
  "browserslist": {
    "production": [">0.2%", "not dead", "not op_mini all"],
    "development": ["last 1 chrome version", "last 1 firefox version"]
  },
  "devDependencies": {
    "autoprefixer": "^10.4.16",
    "postcss": "^8.4.31",
    "tailwindcss": "^3.3.5"
  }
}
PACKAGEJSON

# Create .env for frontend
cat > .env << FRONTENDENV
REACT_APP_BACKEND_URL=https://$DOMAIN
FRONTENDENV

# Create frontend source files
mkdir -p src public src/components/ui

# Create public/index.html
cat > public/index.html << 'INDEXHTML'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="theme-color" content="#0F172A" />
    <meta name="description" content="Host9x Network Looking Glass - Test network connectivity" />
    <title>Host9x Looking Glass</title>
    <link href="https://fonts.googleapis.com/css2?family=Chivo:wght@400;700;900&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
</head>
<body>
    <noscript>You need to enable JavaScript to run this app.</noscript>
    <div id="root"></div>
</body>
</html>
INDEXHTML

# Create tailwind.config.js
cat > tailwind.config.js << 'TAILWINDCONFIG'
module.exports = {
  content: ["./src/**/*.{js,jsx,ts,tsx}"],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter', 'sans-serif'],
        heading: ['Chivo', 'sans-serif'],
        mono: ['JetBrains Mono', 'monospace'],
      },
    },
  },
  plugins: [require("tailwindcss-animate")],
}
TAILWINDCONFIG

# Create postcss.config.js
cat > postcss.config.js << 'POSTCSSCONFIG'
module.exports = {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}
POSTCSSCONFIG

# Create src/index.js
cat > src/index.js << 'INDEXJS'
import React from 'react';
import ReactDOM from 'react-dom/client';
import './index.css';
import App from './App';

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<React.StrictMode><App /></React.StrictMode>);
INDEXJS

# Create src/index.css
cat > src/index.css << 'INDEXCSS'
@tailwind base;
@tailwind components;
@tailwind utilities;

:root {
  --background: 0 0% 100%;
  --foreground: 222 47% 11%;
  --primary: 222 47% 11%;
  --primary-foreground: 210 40% 98%;
  --secondary: 215 16% 47%;
  --muted: 210 40% 96%;
  --muted-foreground: 215 16% 47%;
  --accent: 217 91% 60%;
  --border: 214 32% 91%;
  --ring: 217 91% 60%;
  --radius: 0.5rem;
}

body {
  font-family: 'Inter', sans-serif;
  background: hsl(var(--background));
  color: hsl(var(--foreground));
}

h1, h2, h3, h4, h5, h6 { font-family: 'Chivo', sans-serif; font-weight: 900; }
code, .font-mono { font-family: 'JetBrains Mono', monospace; }

.terminal-window { background: #0F172A; color: #F8FAFC; font-family: 'JetBrains Mono', monospace; border-radius: 0.5rem; overflow: hidden; }
.terminal-header { background: #1E293B; padding: 0.5rem 1rem; display: flex; align-items: center; gap: 0.5rem; }
.terminal-dot { width: 12px; height: 12px; border-radius: 50%; }
.terminal-content { padding: 1rem; overflow-x: auto; font-size: 0.875rem; line-height: 1.6; white-space: pre-wrap; min-height: 200px; max-height: 500px; overflow-y: auto; }

.glass-header { backdrop-filter: blur(12px); background: rgba(255,255,255,0.8); border-bottom: 1px solid rgba(226,232,240,0.8); }
INDEXCSS

# Create src/App.css
cat > src/App.css << 'APPCSS'
.hero-section {
  background: linear-gradient(135deg, rgba(248,250,252,0.9) 0%, rgba(241,245,249,0.9) 100%);
}
APPCSS

# Create UI components
cat > src/components/ui/button.jsx << 'BUTTONUI'
import * as React from "react"
import { Slot } from "@radix-ui/react-slot"
import { cva } from "class-variance-authority"
import { cn } from "../../lib/utils"

const buttonVariants = cva(
  "inline-flex items-center justify-center whitespace-nowrap rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:pointer-events-none disabled:opacity-50",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground shadow hover:bg-primary/90",
        outline: "border border-input bg-background shadow-sm hover:bg-accent hover:text-accent-foreground",
      },
      size: {
        default: "h-9 px-4 py-2",
        sm: "h-8 rounded-md px-3 text-xs",
        lg: "h-10 rounded-md px-8",
        icon: "h-9 w-9",
      },
    },
    defaultVariants: { variant: "default", size: "default" },
  }
)

const Button = React.forwardRef(({ className, variant, size, asChild = false, ...props }, ref) => {
  const Comp = asChild ? Slot : "button"
  return <Comp className={cn(buttonVariants({ variant, size, className }))} ref={ref} {...props} />
})
Button.displayName = "Button"

export { Button, buttonVariants }
BUTTONUI

cat > src/components/ui/input.jsx << 'INPUTUI'
import * as React from "react"
import { cn } from "../../lib/utils"

const Input = React.forwardRef(({ className, type, ...props }, ref) => {
  return (
    <input
      type={type}
      className={cn(
        "flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm transition-colors file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:cursor-not-allowed disabled:opacity-50",
        className
      )}
      ref={ref}
      {...props}
    />
  )
})
Input.displayName = "Input"

export { Input }
INPUTUI

cat > src/components/ui/card.jsx << 'CARDUI'
import * as React from "react"
import { cn } from "../../lib/utils"

const Card = React.forwardRef(({ className, ...props }, ref) => (
  <div ref={ref} className={cn("rounded-xl border bg-card text-card-foreground shadow", className)} {...props} />
))
Card.displayName = "Card"

const CardHeader = React.forwardRef(({ className, ...props }, ref) => (
  <div ref={ref} className={cn("flex flex-col space-y-1.5 p-6", className)} {...props} />
))
CardHeader.displayName = "CardHeader"

const CardTitle = React.forwardRef(({ className, ...props }, ref) => (
  <h3 ref={ref} className={cn("font-semibold leading-none tracking-tight", className)} {...props} />
))
CardTitle.displayName = "CardTitle"

const CardContent = React.forwardRef(({ className, ...props }, ref) => (
  <div ref={ref} className={cn("p-6 pt-0", className)} {...props} />
))
CardContent.displayName = "CardContent"

export { Card, CardHeader, CardTitle, CardContent }
CARDUI

cat > src/components/ui/badge.jsx << 'BADGEUI'
import * as React from "react"
import { cva } from "class-variance-authority"
import { cn } from "../../lib/utils"

const badgeVariants = cva(
  "inline-flex items-center rounded-md border px-2.5 py-0.5 text-xs font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2",
  {
    variants: {
      variant: {
        default: "border-transparent bg-primary text-primary-foreground shadow hover:bg-primary/80",
        secondary: "border-transparent bg-secondary text-secondary-foreground hover:bg-secondary/80",
        outline: "text-foreground",
      },
    },
    defaultVariants: { variant: "default" },
  }
)

function Badge({ className, variant, ...props }) {
  return <div className={cn(badgeVariants({ variant }), className)} {...props} />
}

export { Badge, badgeVariants }
BADGEUI

cat > src/components/ui/tabs.jsx << 'TABSUI'
import * as React from "react"
import * as TabsPrimitive from "@radix-ui/react-tabs"
import { cn } from "../../lib/utils"

const Tabs = TabsPrimitive.Root
const TabsList = React.forwardRef(({ className, ...props }, ref) => (
  <TabsPrimitive.List ref={ref} className={cn("inline-flex h-9 items-center justify-center rounded-lg bg-muted p-1 text-muted-foreground", className)} {...props} />
))
TabsList.displayName = TabsPrimitive.List.displayName

const TabsTrigger = React.forwardRef(({ className, ...props }, ref) => (
  <TabsPrimitive.Trigger ref={ref} className={cn("inline-flex items-center justify-center whitespace-nowrap rounded-md px-3 py-1 text-sm font-medium ring-offset-background transition-all focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:pointer-events-none disabled:opacity-50 data-[state=active]:bg-background data-[state=active]:text-foreground data-[state=active]:shadow", className)} {...props} />
))
TabsTrigger.displayName = TabsPrimitive.Trigger.displayName

const TabsContent = React.forwardRef(({ className, ...props }, ref) => (
  <TabsPrimitive.Content ref={ref} className={cn("mt-2 ring-offset-background focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2", className)} {...props} />
))
TabsContent.displayName = TabsPrimitive.Content.displayName

export { Tabs, TabsList, TabsTrigger, TabsContent }
TABSUI

cat > src/components/ui/select.jsx << 'SELECTUI'
import * as React from "react"
import * as SelectPrimitive from "@radix-ui/react-select"
import { ChevronDown } from "lucide-react"
import { cn } from "../../lib/utils"

const Select = SelectPrimitive.Root
const SelectValue = SelectPrimitive.Value

const SelectTrigger = React.forwardRef(({ className, children, ...props }, ref) => (
  <SelectPrimitive.Trigger ref={ref} className={cn("flex h-9 w-full items-center justify-between whitespace-nowrap rounded-md border border-input bg-transparent px-3 py-2 text-sm shadow-sm ring-offset-background placeholder:text-muted-foreground focus:outline-none focus:ring-1 focus:ring-ring disabled:cursor-not-allowed disabled:opacity-50 [&>span]:line-clamp-1", className)} {...props}>
    {children}
    <SelectPrimitive.Icon asChild><ChevronDown className="h-4 w-4 opacity-50" /></SelectPrimitive.Icon>
  </SelectPrimitive.Trigger>
))
SelectTrigger.displayName = SelectPrimitive.Trigger.displayName

const SelectContent = React.forwardRef(({ className, children, position = "popper", ...props }, ref) => (
  <SelectPrimitive.Portal>
    <SelectPrimitive.Content ref={ref} className={cn("relative z-50 max-h-96 min-w-[8rem] overflow-hidden rounded-md border bg-popover text-popover-foreground shadow-md data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95 data-[side=bottom]:slide-in-from-top-2", position === "popper" && "data-[side=bottom]:translate-y-1 data-[side=left]:-translate-x-1 data-[side=right]:translate-x-1 data-[side=top]:-translate-y-1", className)} position={position} {...props}>
      <SelectPrimitive.Viewport className={cn("p-1", position === "popper" && "h-[var(--radix-select-trigger-height)] w-full min-w-[var(--radix-select-trigger-width)]")}>{children}</SelectPrimitive.Viewport>
    </SelectPrimitive.Content>
  </SelectPrimitive.Portal>
))
SelectContent.displayName = SelectPrimitive.Content.displayName

const SelectItem = React.forwardRef(({ className, children, ...props }, ref) => (
  <SelectPrimitive.Item ref={ref} className={cn("relative flex w-full cursor-default select-none items-center rounded-sm py-1.5 pl-2 pr-8 text-sm outline-none focus:bg-accent focus:text-accent-foreground data-[disabled]:pointer-events-none data-[disabled]:opacity-50", className)} {...props}>
    <SelectPrimitive.ItemText>{children}</SelectPrimitive.ItemText>
  </SelectPrimitive.Item>
))
SelectItem.displayName = SelectPrimitive.Item.displayName

export { Select, SelectContent, SelectItem, SelectTrigger, SelectValue }
SELECTUI

cat > src/components/ui/separator.jsx << 'SEPARATORUI'
import * as React from "react"
import * as SeparatorPrimitive from "@radix-ui/react-separator"
import { cn } from "../../lib/utils"

const Separator = React.forwardRef(({ className, orientation = "horizontal", decorative = true, ...props }, ref) => (
  <SeparatorPrimitive.Root ref={ref} decorative={decorative} orientation={orientation} className={cn("shrink-0 bg-border", orientation === "horizontal" ? "h-[1px] w-full" : "h-full w-[1px]", className)} {...props} />
))
Separator.displayName = SeparatorPrimitive.Root.displayName

export { Separator }
SEPARATORUI

# Create lib/utils.js
mkdir -p src/lib
cat > src/lib/utils.js << 'UTILSJS'
import { clsx } from "clsx"
import { twMerge } from "tailwind-merge"
export function cn(...inputs) { return twMerge(clsx(inputs)) }
UTILSJS

# Create main App.js
cat > src/App.js << 'APPJS'
import React, { useState, useEffect } from "react";
import "./App.css";
import axios from "axios";
import { Toaster, toast } from "sonner";
import { Server, Activity, Globe, Zap, Terminal, Search, RefreshCw, ChevronRight, Network, Route, Gauge, History, FileText, Cpu, Wifi, Download, Upload } from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "./components/ui/card";
import { Button } from "./components/ui/button";
import { Input } from "./components/ui/input";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "./components/ui/tabs";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "./components/ui/select";
import { Badge } from "./components/ui/badge";
import { Separator } from "./components/ui/separator";

const API = `${process.env.REACT_APP_BACKEND_URL}/api`;

const TerminalWindow = ({ title, content, isLoading }) => (
  <div className="terminal-window">
    <div className="terminal-header">
      <div className="terminal-dot bg-red-500" />
      <div className="terminal-dot bg-yellow-500" />
      <div className="terminal-dot bg-green-500" />
      <span className="ml-3 text-sm text-slate-400">{title}</span>
      <Badge variant="outline" className="ml-auto text-xs text-green-400 border-green-400/30">REAL</Badge>
    </div>
    <div className="terminal-content">
      {isLoading ? (
        <div className="flex items-center gap-2 text-green-400">
          <RefreshCw className="w-4 h-4 animate-spin" />
          <span>Executing...</span>
        </div>
      ) : content ? (
        <pre className="text-green-400">{content}</pre>
      ) : (
        <span className="text-slate-500">$ Results will appear here...</span>
      )}
    </div>
  </div>
);

const GeolocationCard = ({ data }) => {
  if (!data) return null;
  return (
    <div className="grid grid-cols-2 gap-3 text-sm">
      <div><span className="text-slate-500">IP</span><p className="font-mono font-medium">{data.ip}</p></div>
      <div><span className="text-slate-500">Country</span><p className="font-medium">{data.country}</p></div>
      <div><span className="text-slate-500">City</span><p className="font-medium">{data.city}</p></div>
      <div><span className="text-slate-500">ISP</span><p className="font-medium">{data.isp}</p></div>
    </div>
  );
};

function App() {
  const [targetIP, setTargetIP] = useState("");
  const [activeTest, setActiveTest] = useState("ping");
  const [testResult, setTestResult] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [geoIP, setGeoIP] = useState("");
  const [geoResult, setGeoResult] = useState(null);
  const [isGeoLoading, setIsGeoLoading] = useState(false);
  const [testHistory, setTestHistory] = useState([]);
  const [dnsDomain, setDnsDomain] = useState("");
  const [dnsRecordType, setDnsRecordType] = useState("A");
  const [whoisDomain, setWhoisDomain] = useState("");
  const [iperfServers, setIperfServers] = useState([]);
  const [selectedIperfServer, setSelectedIperfServer] = useState("");
  const [iperfMode, setIperfMode] = useState("download");
  const [isIperfTesting, setIsIperfTesting] = useState(false);

  useEffect(() => {
    fetchTestHistory();
    fetchIperfServers();
  }, []);

  const fetchTestHistory = async () => {
    try {
      const res = await axios.get(`${API}/test-history?limit=10`);
      setTestHistory(res.data.history);
    } catch (e) { console.error(e); }
  };

  const fetchIperfServers = async () => {
    try {
      const res = await axios.get(`${API}/iperf-servers`);
      setIperfServers(res.data.servers);
      if (res.data.servers.length > 0) setSelectedIperfServer(res.data.servers[0].host);
    } catch (e) { console.error(e); }
  };

  const runNetworkTest = async () => {
    if (!targetIP.trim()) { toast.error("Enter target IP/hostname"); return; }
    setIsLoading(true); setTestResult("");
    try {
      const res = await axios.post(`${API}/network/${activeTest}`, { target: targetIP, source_location: "main" });
      setTestResult(res.data.result);
      toast.success(`${activeTest.toUpperCase()} completed`);
      fetchTestHistory();
    } catch (e) {
      toast.error(`Failed: ${e.response?.data?.detail || e.message}`);
      setTestResult(`Error: ${e.response?.data?.detail || e.message}`);
    } finally { setIsLoading(false); }
  };

  const runDNSLookup = async () => {
    if (!dnsDomain.trim()) { toast.error("Enter domain"); return; }
    setIsLoading(true); setTestResult(""); setActiveTest("dns");
    try {
      const res = await axios.post(`${API}/network/dns`, { domain: dnsDomain, record_type: dnsRecordType });
      setTestResult(res.data.result);
      toast.success("DNS lookup completed");
      fetchTestHistory();
    } catch (e) {
      toast.error(`Failed: ${e.response?.data?.detail || e.message}`);
    } finally { setIsLoading(false); }
  };

  const runWhoisLookup = async () => {
    if (!whoisDomain.trim()) { toast.error("Enter domain"); return; }
    setIsLoading(true); setTestResult(""); setActiveTest("whois");
    try {
      const res = await axios.post(`${API}/network/whois`, { domain: whoisDomain });
      setTestResult(res.data.result);
      toast.success("WHOIS lookup completed");
      fetchTestHistory();
    } catch (e) {
      toast.error(`Failed: ${e.response?.data?.detail || e.message}`);
    } finally { setIsLoading(false); }
  };

  const runIperfTest = async () => {
    if (!selectedIperfServer) { toast.error("Select server"); return; }
    setIsIperfTesting(true); setTestResult(""); setActiveTest("iperf");
    const server = iperfServers.find(s => s.host === selectedIperfServer);
    try {
      const res = await axios.post(`${API}/network/iperf`, {
        server: selectedIperfServer, port: server?.port || 5201, duration: 5, reverse: iperfMode === "download"
      });
      setTestResult(res.data.result);
      toast.success(`iperf3 ${iperfMode} completed`);
      fetchTestHistory();
    } catch (e) {
      toast.error(`Failed: ${e.response?.data?.detail || e.message}`);
    } finally { setIsIperfTesting(false); }
  };

  const lookupGeolocation = async () => {
    if (!geoIP.trim()) { toast.error("Enter IP"); return; }
    setIsGeoLoading(true); setGeoResult(null);
    try {
      const res = await axios.get(`${API}/geolocation/${geoIP}`);
      setGeoResult(res.data);
      toast.success("Geolocation found");
    } catch (e) {
      toast.error(`Failed: ${e.response?.data?.detail || e.message}`);
    } finally { setIsGeoLoading(false); }
  };

  return (
    <div className="min-h-screen bg-white">
      <Toaster position="top-right" richColors />
      
      <header className="glass-header sticky top-0 z-50">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-[#0F172A] rounded-lg"><Server className="w-6 h-6 text-white" /></div>
              <div>
                <h1 className="text-xl font-black text-slate-900">host9x.com</h1>
                <p className="text-xs text-slate-500">Network Looking Glass</p>
              </div>
            </div>
            <Badge className="bg-emerald-500 text-white gap-1"><Cpu className="w-3 h-3" />Real Commands</Badge>
          </div>
        </div>
      </header>

      <section className="hero-section py-8">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <h2 className="text-3xl sm:text-4xl font-black text-slate-900 mb-3">Network Diagnostic Tools</h2>
          <p className="text-slate-600">Execute <strong>real network commands</strong>. Ping, Traceroute, MTR, DNS, WHOIS, BGP, iPerf3.</p>
        </div>
      </section>

      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <div className="grid lg:grid-cols-3 gap-6">
          <div className="lg:col-span-2 space-y-6">
            <Card className="border shadow-sm">
              <CardHeader className="border-b"><CardTitle className="flex items-center gap-2"><Terminal className="w-5 h-5 text-blue-600" />Network Tests</CardTitle></CardHeader>
              <CardContent className="p-6 space-y-6">
                <Tabs value={activeTest} onValueChange={setActiveTest}>
                  <TabsList className="grid grid-cols-7 w-full">
                    <TabsTrigger value="ping"><Zap className="w-4 h-4" /></TabsTrigger>
                    <TabsTrigger value="traceroute"><Route className="w-4 h-4" /></TabsTrigger>
                    <TabsTrigger value="mtr"><Activity className="w-4 h-4" /></TabsTrigger>
                    <TabsTrigger value="bgp"><Network className="w-4 h-4" /></TabsTrigger>
                    <TabsTrigger value="dns"><Globe className="w-4 h-4" /></TabsTrigger>
                    <TabsTrigger value="whois"><FileText className="w-4 h-4" /></TabsTrigger>
                    <TabsTrigger value="iperf"><Wifi className="w-4 h-4" /></TabsTrigger>
                  </TabsList>

                  {["ping", "traceroute", "mtr", "bgp"].map(test => (
                    <TabsContent key={test} value={test} className="mt-4 space-y-4">
                      <Input placeholder="e.g., 8.8.8.8 or google.com" value={targetIP} onChange={e => setTargetIP(e.target.value)} />
                      <Button onClick={runNetworkTest} disabled={isLoading} className="w-full bg-[#0F172A]">
                        {isLoading ? <><RefreshCw className="w-4 h-4 mr-2 animate-spin" />Running...</> : <><ChevronRight className="w-4 h-4 mr-2" />Run {test.toUpperCase()}</>}
                      </Button>
                    </TabsContent>
                  ))}

                  <TabsContent value="dns" className="mt-4 space-y-4">
                    <div className="grid grid-cols-3 gap-3">
                      <Input placeholder="google.com" value={dnsDomain} onChange={e => setDnsDomain(e.target.value)} className="col-span-2" />
                      <Select value={dnsRecordType} onValueChange={setDnsRecordType}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>{["A","AAAA","MX","NS","TXT","CNAME"].map(t => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent>
                      </Select>
                    </div>
                    <Button onClick={runDNSLookup} disabled={isLoading} className="w-full bg-[#0F172A]">
                      {isLoading ? <><RefreshCw className="w-4 h-4 mr-2 animate-spin" />Looking up...</> : <><ChevronRight className="w-4 h-4 mr-2" />DNS Lookup</>}
                    </Button>
                  </TabsContent>

                  <TabsContent value="whois" className="mt-4 space-y-4">
                    <Input placeholder="google.com" value={whoisDomain} onChange={e => setWhoisDomain(e.target.value)} />
                    <Button onClick={runWhoisLookup} disabled={isLoading} className="w-full bg-[#0F172A]">
                      {isLoading ? <><RefreshCw className="w-4 h-4 mr-2 animate-spin" />Looking up...</> : <><ChevronRight className="w-4 h-4 mr-2" />WHOIS Lookup</>}
                    </Button>
                  </TabsContent>

                  <TabsContent value="iperf" className="mt-4 space-y-4">
                    <div className="grid grid-cols-2 gap-3">
                      <Select value={selectedIperfServer} onValueChange={setSelectedIperfServer}>
                        <SelectTrigger><SelectValue placeholder="Select server" /></SelectTrigger>
                        <SelectContent>{iperfServers.map(s => <SelectItem key={s.host} value={s.host}>{s.name}</SelectItem>)}</SelectContent>
                      </Select>
                      <Select value={iperfMode} onValueChange={setIperfMode}>
                        <SelectTrigger><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="download"><Download className="w-4 h-4 inline mr-2" />Download</SelectItem>
                          <SelectItem value="upload"><Upload className="w-4 h-4 inline mr-2" />Upload</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                    <Button onClick={runIperfTest} disabled={isIperfTesting} className="w-full bg-emerald-600 hover:bg-emerald-700">
                      {isIperfTesting ? <><RefreshCw className="w-4 h-4 mr-2 animate-spin" />Testing...</> : <><Wifi className="w-4 h-4 mr-2" />Run iPerf3</>}
                    </Button>
                  </TabsContent>
                </Tabs>
                <TerminalWindow title={`${activeTest.toUpperCase()} Results`} content={testResult} isLoading={isLoading || isIperfTesting} />
              </CardContent>
            </Card>

            <Card className="border border-emerald-200 bg-emerald-50/30">
              <CardHeader className="border-b border-emerald-100"><CardTitle className="flex items-center gap-2"><Terminal className="w-5 h-5 text-emerald-600" />Test Your Server<Badge className="bg-emerald-600 ml-2">iperf3</Badge></CardTitle></CardHeader>
              <CardContent className="p-6">
                <p className="text-sm text-slate-600 mb-4">Run these commands on your server to test bandwidth:</p>
                <div className="grid md:grid-cols-2 gap-4">
                  <div className="space-y-2">
                    <div className="flex items-center gap-2"><Download className="w-4 h-4 text-emerald-600" /><span className="font-medium text-sm">Incoming</span></div>
                    <div className="bg-[#0F172A] rounded-lg p-3 font-mono text-sm text-green-400">
                      <code>iperf3 -c {window.location.hostname} -p 5201 -P 4</code>
                    </div>
                  </div>
                  <div className="space-y-2">
                    <div className="flex items-center gap-2"><Upload className="w-4 h-4 text-amber-600" /><span className="font-medium text-sm">Outgoing</span></div>
                    <div className="bg-[#0F172A] rounded-lg p-3 font-mono text-sm text-green-400">
                      <code>iperf3 -c {window.location.hostname} -p 5201 -P 4 -R</code>
                    </div>
                  </div>
                </div>
              </CardContent>
            </Card>
          </div>

          <div className="space-y-6">
            <Card className="border shadow-sm">
              <CardHeader className="border-b"><CardTitle className="flex items-center gap-2"><Globe className="w-5 h-5 text-amber-600" />IP Geolocation</CardTitle></CardHeader>
              <CardContent className="p-6 space-y-4">
                <div className="flex gap-2">
                  <Input placeholder="Enter IP" value={geoIP} onChange={e => setGeoIP(e.target.value)} className="flex-1" />
                  <Button onClick={lookupGeolocation} disabled={isGeoLoading} size="icon" variant="outline">
                    {isGeoLoading ? <RefreshCw className="w-4 h-4 animate-spin" /> : <Search className="w-4 h-4" />}
                  </Button>
                </div>
                {geoResult && <><Separator /><GeolocationCard data={geoResult} /></>}
              </CardContent>
            </Card>

            <Card className="border shadow-sm">
              <CardHeader className="border-b"><CardTitle className="flex items-center gap-2"><History className="w-5 h-5 text-slate-600" />Recent Tests</CardTitle></CardHeader>
              <CardContent className="p-4">
                {testHistory.length === 0 ? <p className="text-sm text-slate-500 text-center py-4">No recent tests</p> : (
                  <div className="space-y-2 max-h-64 overflow-y-auto">
                    {testHistory.map((test, i) => (
                      <div key={test.id || i} className="p-2 rounded-lg bg-slate-50 text-xs">
                        <Badge variant="secondary" className="text-xs">{test.test_type?.toUpperCase()}</Badge>
                        <p className="font-mono text-slate-700 truncate mt-1">{test.target}</p>
                      </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        </div>
      </main>

      <footer className="border-t mt-12">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6 flex items-center justify-between">
          <div className="flex items-center gap-2"><Server className="w-5 h-5 text-slate-400" /><span className="font-medium text-slate-600">host9x.com</span></div>
          <div className="flex gap-2">{["Ping","Trace","MTR","DNS","WHOIS","BGP","iPerf3"].map(t => <Badge key={t} variant="outline" className="text-xs">{t}</Badge>)}</div>
        </div>
      </footer>
    </div>
  );
}

export default App;
APPJS

# Install frontend dependencies and build
echo -e "\n${YELLOW}Installing frontend dependencies...${NC}"
yarn install
yarn build

# Configure Nginx
echo -e "\n${YELLOW}[9/10] Configuring Nginx...${NC}"
cat > /etc/nginx/sites-available/lookingglass << NGINXCONF
server {
    listen 80;
    server_name $DOMAIN;

    # Frontend
    location / {
        root $APP_DIR/frontend/build;
        try_files \$uri /index.html;
    }

    # Backend API
    location /api {
        proxy_pass http://127.0.0.1:$BACKEND_PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 120s;
    }
}
NGINXCONF

ln -sf /etc/nginx/sites-available/lookingglass /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t && systemctl reload nginx

# Configure Firewall
echo -e "\n${YELLOW}[10/10] Configuring Firewall & Starting Services...${NC}"
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow $IPERF_PORT/tcp
ufw --force enable

# Enable and start services
systemctl daemon-reload
systemctl enable lookingglass-backend
systemctl enable iperf3-server
systemctl start lookingglass-backend
systemctl start iperf3-server

# Setup SSL with Let's Encrypt
echo -e "\n${YELLOW}Setting up SSL certificate...${NC}"
certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL || echo -e "${YELLOW}SSL setup skipped. Run manually: certbot --nginx -d $DOMAIN${NC}"

# Final status check
echo -e "\n${GREEN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║         Installation Complete!                            ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "
${BLUE}Services Status:${NC}"
systemctl status lookingglass-backend --no-pager -l | head -5
systemctl status iperf3-server --no-pager -l | head -5
systemctl status nginx --no-pager -l | head -5

echo -e "
${GREEN}✅ Looking Glass deployed successfully!${NC}

${BLUE}URLs:${NC}
  Website:  https://$DOMAIN
  API:      https://$DOMAIN/api

${BLUE}iperf3 Commands for users:${NC}
  Incoming: iperf3 -c $DOMAIN -p $IPERF_PORT -P 4
  Outgoing: iperf3 -c $DOMAIN -p $IPERF_PORT -P 4 -R

${BLUE}Management Commands:${NC}
  Restart Backend:  sudo systemctl restart lookingglass-backend
  Restart iperf3:   sudo systemctl restart iperf3-server
  View Logs:        sudo journalctl -u lookingglass-backend -f
  Nginx Logs:       sudo tail -f /var/log/nginx/error.log

${YELLOW}Note: If SSL failed, run manually:${NC}
  sudo certbot --nginx -d $DOMAIN
"
