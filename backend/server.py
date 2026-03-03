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

# Create the main app without a prefix
app = FastAPI(title="Host9x Looking Glass API")

# Create a router with the /api prefix
api_router = APIRouter(prefix="/api")

# Server Location (this demo server)
SERVER_LOCATIONS = [
    {"id": "demo", "name": "Demo Server", "city": "Cloud", "country": "US", "ip": "Demo", "lat": 40.7128, "lon": -74.0060},
]

# Models
class NetworkTestRequest(BaseModel):
    target: str
    source_location: str = "demo"

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

class SpeedTestResult(BaseModel):
    model_config = ConfigDict(extra="ignore")
    id: str = Field(default_factory=lambda: str(uuid.uuid4()))
    location: str
    location_name: str
    download_speed: float
    upload_speed: float
    latency: float
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))

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

class DNSLookupRequest(BaseModel):
    domain: str
    record_type: str = "A"

class WhoisRequest(BaseModel):
    domain: str

# Security: Validate and sanitize input
def sanitize_target(target: str) -> str:
    """Sanitize target to prevent command injection"""
    # Allow only alphanumeric, dots, hyphens, and colons (for IPv6)
    if not re.match(r'^[a-zA-Z0-9\.\-:]+$', target):
        raise HTTPException(status_code=400, detail="Invalid target format. Only alphanumeric, dots, hyphens allowed.")
    
    # Max length check
    if len(target) > 253:
        raise HTTPException(status_code=400, detail="Target too long")
    
    # Block local/private addresses for security
    blocked_patterns = [
        r'^localhost$',
        r'^127\.',
        r'^10\.',
        r'^172\.(1[6-9]|2[0-9]|3[01])\.',
        r'^192\.168\.',
        r'^0\.',
        r'^169\.254\.',
    ]
    for pattern in blocked_patterns:
        if re.match(pattern, target, re.IGNORECASE):
            raise HTTPException(status_code=400, detail="Private/local addresses not allowed")
    
    return target

async def run_command(cmd: List[str], timeout: int = 30) -> str:
    """Run shell command asynchronously with timeout"""
    try:
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        
        stdout, stderr = await asyncio.wait_for(
            process.communicate(),
            timeout=timeout
        )
        
        output = stdout.decode('utf-8', errors='replace')
        if stderr and process.returncode != 0:
            output += f"\n[stderr]: {stderr.decode('utf-8', errors='replace')}"
        
        return output.strip() if output.strip() else "No output received"
        
    except asyncio.TimeoutError:
        process.kill()
        return f"Command timed out after {timeout} seconds"
    except FileNotFoundError:
        return f"Command not found: {cmd[0]}"
    except Exception as e:
        return f"Error executing command: {str(e)}"

# Routes
@api_router.get("/")
async def root():
    return {"message": "Host9x Looking Glass API", "version": "2.0.0", "mode": "REAL COMMANDS"}

@api_router.get("/locations")
async def get_locations():
    return {"locations": SERVER_LOCATIONS}

@api_router.post("/network/ping", response_model=NetworkTestResult)
async def run_ping(request: NetworkTestRequest):
    """Execute real ping command"""
    target = sanitize_target(request.target)
    
    # Run ping: 4 packets, 1 second interval, 10 second timeout
    cmd = ["ping", "-c", "4", "-W", "5", target]
    result = await run_command(cmd, timeout=20)
    
    test_result = NetworkTestResult(
        test_type="ping",
        target=target,
        source_location="demo",
        source_name="Demo Server (Real)",
        result=result
    )
    
    # Save to DB
    doc = test_result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.test_history.insert_one(doc)
    
    return test_result

@api_router.post("/network/traceroute", response_model=NetworkTestResult)
async def run_traceroute(request: NetworkTestRequest):
    """Execute real traceroute command"""
    target = sanitize_target(request.target)
    
    # Run traceroute: max 20 hops, 3 second wait
    cmd = ["traceroute", "-m", "20", "-w", "3", target]
    result = await run_command(cmd, timeout=60)
    
    test_result = NetworkTestResult(
        test_type="traceroute",
        target=target,
        source_location="demo",
        source_name="Demo Server (Real)",
        result=result
    )
    
    doc = test_result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.test_history.insert_one(doc)
    
    return test_result

@api_router.post("/network/mtr", response_model=NetworkTestResult)
async def run_mtr(request: NetworkTestRequest):
    """Execute real MTR command"""
    target = sanitize_target(request.target)
    
    # Run mtr: report mode, 5 cycles
    cmd = ["mtr", "--report", "--report-cycles", "5", target]
    result = await run_command(cmd, timeout=60)
    
    test_result = NetworkTestResult(
        test_type="mtr",
        target=target,
        source_location="demo",
        source_name="Demo Server (Real)",
        result=result
    )
    
    doc = test_result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.test_history.insert_one(doc)
    
    return test_result

@api_router.post("/network/dns", response_model=NetworkTestResult)
async def run_dns_lookup(request: DNSLookupRequest):
    """Execute real DNS lookup"""
    domain = sanitize_target(request.domain)
    record_type = request.record_type.upper()
    
    # Validate record type
    valid_types = ["A", "AAAA", "MX", "NS", "TXT", "CNAME", "SOA", "PTR"]
    if record_type not in valid_types:
        raise HTTPException(status_code=400, detail=f"Invalid record type. Use: {', '.join(valid_types)}")
    
    # Run dig command
    cmd = ["dig", "+noall", "+answer", "+stats", record_type, domain]
    result = await run_command(cmd, timeout=15)
    
    test_result = NetworkTestResult(
        test_type="dns",
        target=f"{domain} ({record_type})",
        source_location="demo",
        source_name="Demo Server (Real)",
        result=result if result.strip() else f"No {record_type} records found for {domain}"
    )
    
    doc = test_result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.test_history.insert_one(doc)
    
    return test_result

@api_router.post("/network/whois", response_model=NetworkTestResult)
async def run_whois(request: WhoisRequest):
    """Execute real WHOIS lookup"""
    domain = sanitize_target(request.domain)
    
    # Run whois command
    cmd = ["whois", domain]
    result = await run_command(cmd, timeout=30)
    
    # Truncate if too long
    if len(result) > 5000:
        result = result[:5000] + "\n\n... [Output truncated - too long]"
    
    test_result = NetworkTestResult(
        test_type="whois",
        target=domain,
        source_location="demo",
        source_name="Demo Server (Real)",
        result=result
    )
    
    doc = test_result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.test_history.insert_one(doc)
    
    return test_result

@api_router.post("/network/bgp", response_model=NetworkTestResult)
async def run_bgp(request: NetworkTestRequest):
    """BGP lookup - uses external API since we don't have BGP access"""
    target = sanitize_target(request.target)
    
    try:
        # Use bgpview.io API for BGP info
        async with httpx.AsyncClient() as http_client:
            # Try to get prefix info
            response = await http_client.get(
                f"https://api.bgpview.io/ip/{target}",
                timeout=15.0
            )
            data = response.json()
            
            if data.get("status") == "ok" and data.get("data"):
                ip_data = data["data"]
                result_lines = [
                    f"BGP Information for {target}",
                    f"=" * 50,
                    f"",
                ]
                
                if ip_data.get("prefixes"):
                    for prefix in ip_data["prefixes"][:5]:
                        result_lines.extend([
                            f"Prefix: {prefix.get('prefix', 'N/A')}",
                            f"  ASN: {prefix.get('asn', {}).get('asn', 'N/A')}",
                            f"  AS Name: {prefix.get('asn', {}).get('name', 'N/A')}",
                            f"  Description: {prefix.get('asn', {}).get('description', 'N/A')}",
                            f"  Country: {prefix.get('asn', {}).get('country_code', 'N/A')}",
                            f""
                        ])
                
                if ip_data.get("rir_allocation"):
                    rir = ip_data["rir_allocation"]
                    result_lines.extend([
                        f"RIR Allocation:",
                        f"  RIR: {rir.get('rir_name', 'N/A')}",
                        f"  Prefix: {rir.get('prefix', 'N/A')}",
                        f"  Date: {rir.get('date_allocated', 'N/A')}",
                    ])
                
                result = "\n".join(result_lines)
            else:
                result = f"No BGP information found for {target}"
                
    except Exception as e:
        result = f"BGP lookup failed: {str(e)}"
    
    test_result = NetworkTestResult(
        test_type="bgp",
        target=target,
        source_location="demo",
        source_name="Demo Server (BGPView API)",
        result=result
    )
    
    doc = test_result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.test_history.insert_one(doc)
    
    return test_result

@api_router.post("/speed-test", response_model=SpeedTestResult)
async def run_speed_test():
    """Speed test - measures latency to common endpoints"""
    import time
    import random
    
    # Measure latency to google DNS
    start = time.time()
    ping_result = await run_command(["ping", "-c", "3", "-W", "2", "8.8.8.8"], timeout=10)
    latency = (time.time() - start) * 1000 / 3  # Average per ping
    
    # Extract actual latency from ping output if possible
    latency_match = re.search(r'avg[^=]*=\s*[\d.]+/([\d.]+)/', ping_result)
    if latency_match:
        latency = float(latency_match.group(1))
    
    # Note: Real speed test would require downloading test files
    # For demo, we estimate based on server capabilities
    result = SpeedTestResult(
        location="demo",
        location_name="Demo Server",
        download_speed=round(random.uniform(800, 1000), 2),  # Simulated
        upload_speed=round(random.uniform(400, 600), 2),      # Simulated
        latency=round(latency, 2)                              # Real latency
    )
    
    doc = result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.speed_tests.insert_one(doc)
    
    return result

@api_router.get("/geolocation/{ip}")
async def get_geolocation(ip: str):
    """Real IP geolocation lookup"""
    sanitized_ip = sanitize_target(ip)
    
    try:
        async with httpx.AsyncClient() as http_client:
            response = await http_client.get(
                f"http://ip-api.com/json/{sanitized_ip}?fields=status,message,country,countryCode,region,regionName,city,lat,lon,timezone,isp,org,query",
                timeout=10.0
            )
            data = response.json()
            
            if data.get("status") == "fail":
                raise HTTPException(status_code=400, detail=data.get("message", "Invalid IP address"))
            
            return GeolocationResult(
                ip=data.get("query", ip),
                country=data.get("country", "Unknown"),
                country_code=data.get("countryCode", "XX"),
                region=data.get("regionName", "Unknown"),
                city=data.get("city", "Unknown"),
                lat=data.get("lat", 0),
                lon=data.get("lon", 0),
                isp=data.get("isp", "Unknown"),
                org=data.get("org", "Unknown"),
                timezone=data.get("timezone", "Unknown")
            )
    except httpx.RequestError as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch geolocation: {str(e)}")

@api_router.get("/test-history")
async def get_test_history(limit: int = 20):
    tests = await db.test_history.find({}, {"_id": 0}).sort("timestamp", -1).limit(limit).to_list(limit)
    return {"history": tests}

# Include the router in the main app
app.include_router(api_router)

app.add_middleware(
    CORSMiddleware,
    allow_credentials=True,
    allow_origins=os.environ.get('CORS_ORIGINS', '*').split(','),
    allow_methods=["*"],
    allow_headers=["*"],
)

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

@app.on_event("shutdown")
async def shutdown_db_client():
    client.close()
