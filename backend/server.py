from fastapi import FastAPI, APIRouter, HTTPException
from dotenv import load_dotenv
from starlette.middleware.cors import CORSMiddleware
from motor.motor_asyncio import AsyncIOMotorClient
import os
import logging
from pathlib import Path
from pydantic import BaseModel, Field, ConfigDict
from typing import List, Optional
import uuid
from datetime import datetime, timezone
import random
import asyncio
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

# Server Locations
SERVER_LOCATIONS = [
    {"id": "nl", "name": "Netherlands", "city": "Amsterdam", "country": "NL", "ip": "185.107.56.1", "lat": 52.3676, "lon": 4.9041},
    {"id": "de", "name": "Germany", "city": "Frankfurt", "country": "DE", "ip": "195.201.42.1", "lat": 50.1109, "lon": 8.6821},
    {"id": "it", "name": "Italy", "city": "Milan", "country": "IT", "ip": "185.94.188.1", "lat": 45.4642, "lon": 9.1900},
    {"id": "in", "name": "Mumbai", "city": "Mumbai", "country": "IN", "ip": "103.21.124.1", "lat": 19.0760, "lon": 72.8777},
]

# Models
class NetworkTestRequest(BaseModel):
    target: str
    source_location: str

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

class SpeedTestRequest(BaseModel):
    location: str

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

# Helper functions
def get_location_by_id(location_id: str):
    for loc in SERVER_LOCATIONS:
        if loc["id"] == location_id:
            return loc
    return None

def simulate_ping(target: str, hops: int = 4):
    """Simulate ping results"""
    lines = [f"PING {target} ({target}) 56(84) bytes of data."]
    for i in range(hops):
        latency = round(random.uniform(1, 50) + (i * 5), 3)
        lines.append(f"64 bytes from {target}: icmp_seq={i+1} ttl={64-i} time={latency} ms")
    
    avg_latency = round(random.uniform(10, 40), 3)
    min_lat = round(avg_latency * 0.8, 3)
    max_lat = round(avg_latency * 1.4, 3)
    lines.append(f"\n--- {target} ping statistics ---")
    lines.append(f"{hops} packets transmitted, {hops} received, 0% packet loss")
    lines.append(f"rtt min/avg/max/mdev = {min_lat}/{avg_latency}/{max_lat}/{round(max_lat-min_lat, 3)} ms")
    return "\n".join(lines)

def simulate_traceroute(target: str):
    """Simulate traceroute results"""
    lines = [f"traceroute to {target} ({target}), 30 hops max, 60 byte packets"]
    hops = random.randint(8, 15)
    
    for i in range(1, hops + 1):
        ip = f"{random.randint(1,254)}.{random.randint(0,254)}.{random.randint(0,254)}.{random.randint(1,254)}"
        lat1 = round(random.uniform(1, 20) + (i * 3), 3)
        lat2 = round(lat1 + random.uniform(-2, 5), 3)
        lat3 = round(lat1 + random.uniform(-2, 5), 3)
        hostname = f"hop-{i}.router.net" if random.random() > 0.3 else ip
        lines.append(f" {i:2}  {hostname} ({ip})  {lat1} ms  {lat2} ms  {lat3} ms")
    
    lines.append(f" {hops+1}  {target} ({target})  {round(random.uniform(20, 80), 3)} ms")
    return "\n".join(lines)

def simulate_mtr(target: str):
    """Simulate MTR results"""
    lines = [
        f"Start: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')}",
        f"HOST: host9x-{random.choice(['nl', 'de', 'it', 'in'])}                Loss%   Snt   Last   Avg  Best  Wrst StDev",
        ""
    ]
    hops = random.randint(8, 12)
    
    for i in range(1, hops + 1):
        ip = f"{random.randint(1,254)}.{random.randint(0,254)}.{random.randint(0,254)}.{random.randint(1,254)}"
        loss = random.choice([0, 0, 0, 0, 0, round(random.uniform(0, 5), 1)])
        snt = 10
        last = round(random.uniform(5, 30) + (i * 2), 1)
        avg = round(last + random.uniform(-3, 3), 1)
        best = round(avg * 0.7, 1)
        wrst = round(avg * 1.5, 1)
        stdev = round(random.uniform(0.5, 5), 1)
        hostname = f"hop-{i}.network.net"
        lines.append(f" {i:2}.|-- {hostname:30} {loss:5.1f}%  {snt:4}  {last:5.1f}  {avg:5.1f}  {best:5.1f}  {wrst:5.1f}  {stdev:5.1f}")
    
    lines.append(f" {hops+1}.|-- {target:30}   0.0%  {10:4}  {round(random.uniform(20, 50), 1):5.1f}  {round(random.uniform(25, 55), 1):5.1f}  {round(random.uniform(15, 25), 1):5.1f}  {round(random.uniform(60, 90), 1):5.1f}  {round(random.uniform(5, 15), 1):5.1f}")
    return "\n".join(lines)

def simulate_bgp(target: str):
    """Simulate BGP route lookup"""
    asn = random.randint(1000, 65000)
    prefix = f"{target.split('.')[0]}.{target.split('.')[1]}.0.0/16" if '.' in target else f"{target}/24"
    
    lines = [
        f"BGP routing table entry for {prefix}",
        f"Paths: (3 available, best #1)",
        f"  Advertised to non peer-group peers:",
        f"",
        f"  AS Path: {asn} {random.randint(1000, 65000)} {random.randint(1000, 65000)} i",
        f"    Origin: IGP, metric: 100, localpref: 100, weight: 0, valid, external, best",
        f"    Community: {asn}:100 {asn}:200",
        f"    Last update: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC",
        f"",
        f"  AS Path: {random.randint(1000, 65000)} {asn} i",
        f"    Origin: IGP, metric: 200, localpref: 90, weight: 0, valid, external",
        f"    Last update: {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S')} UTC",
    ]
    return "\n".join(lines)

# Routes
@api_router.get("/")
async def root():
    return {"message": "Host9x Looking Glass API", "version": "1.0.0"}

@api_router.get("/locations")
async def get_locations():
    return {"locations": SERVER_LOCATIONS}

@api_router.post("/network/ping", response_model=NetworkTestResult)
async def run_ping(request: NetworkTestRequest):
    location = get_location_by_id(request.source_location)
    if not location:
        raise HTTPException(status_code=400, detail="Invalid source location")
    
    # Simulate delay
    await asyncio.sleep(random.uniform(0.5, 1.5))
    
    result = simulate_ping(request.target)
    test_result = NetworkTestResult(
        test_type="ping",
        target=request.target,
        source_location=request.source_location,
        source_name=f"{location['name']} ({location['city']})",
        result=result
    )
    
    # Save to DB
    doc = test_result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.test_history.insert_one(doc)
    
    return test_result

@api_router.post("/network/traceroute", response_model=NetworkTestResult)
async def run_traceroute(request: NetworkTestRequest):
    location = get_location_by_id(request.source_location)
    if not location:
        raise HTTPException(status_code=400, detail="Invalid source location")
    
    await asyncio.sleep(random.uniform(1, 2))
    
    result = simulate_traceroute(request.target)
    test_result = NetworkTestResult(
        test_type="traceroute",
        target=request.target,
        source_location=request.source_location,
        source_name=f"{location['name']} ({location['city']})",
        result=result
    )
    
    doc = test_result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.test_history.insert_one(doc)
    
    return test_result

@api_router.post("/network/mtr", response_model=NetworkTestResult)
async def run_mtr(request: NetworkTestRequest):
    location = get_location_by_id(request.source_location)
    if not location:
        raise HTTPException(status_code=400, detail="Invalid source location")
    
    await asyncio.sleep(random.uniform(1.5, 2.5))
    
    result = simulate_mtr(request.target)
    test_result = NetworkTestResult(
        test_type="mtr",
        target=request.target,
        source_location=request.source_location,
        source_name=f"{location['name']} ({location['city']})",
        result=result
    )
    
    doc = test_result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.test_history.insert_one(doc)
    
    return test_result

@api_router.post("/network/bgp", response_model=NetworkTestResult)
async def run_bgp(request: NetworkTestRequest):
    location = get_location_by_id(request.source_location)
    if not location:
        raise HTTPException(status_code=400, detail="Invalid source location")
    
    await asyncio.sleep(random.uniform(0.5, 1))
    
    result = simulate_bgp(request.target)
    test_result = NetworkTestResult(
        test_type="bgp",
        target=request.target,
        source_location=request.source_location,
        source_name=f"{location['name']} ({location['city']})",
        result=result
    )
    
    doc = test_result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.test_history.insert_one(doc)
    
    return test_result

@api_router.post("/speed-test", response_model=SpeedTestResult)
async def run_speed_test(request: SpeedTestRequest):
    location = get_location_by_id(request.location)
    if not location:
        raise HTTPException(status_code=400, detail="Invalid location")
    
    await asyncio.sleep(random.uniform(2, 4))
    
    result = SpeedTestResult(
        location=request.location,
        location_name=f"{location['name']} ({location['city']})",
        download_speed=round(random.uniform(500, 1000), 2),
        upload_speed=round(random.uniform(200, 500), 2),
        latency=round(random.uniform(5, 50), 2)
    )
    
    doc = result.model_dump()
    doc['timestamp'] = doc['timestamp'].isoformat()
    await db.speed_tests.insert_one(doc)
    
    return result

@api_router.get("/geolocation/{ip}")
async def get_geolocation(ip: str):
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(f"http://ip-api.com/json/{ip}?fields=status,message,country,countryCode,region,regionName,city,lat,lon,timezone,isp,org,query", timeout=10.0)
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
    except httpx.RequestError:
        raise HTTPException(status_code=500, detail="Failed to fetch geolocation data")

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
