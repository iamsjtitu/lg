# Host9x.com Looking Glass - PRD

## Original Problem Statement
Build a Looking Glass network diagnostic tool for host9x.com with:
- Network Tests: Ping, Traceroute, MTR, BGP Route Lookup
- Server Locations: Netherlands, Germany, Italy, Mumbai
- Theme: Light theme
- Additional Features: Download speed test, IP Geolocation lookup
- Access: Public (no authentication)

## Architecture
- **Frontend**: React with Tailwind CSS, Shadcn UI components
- **Backend**: FastAPI with MongoDB
- **Fonts**: Chivo (headings), Inter (body), JetBrains Mono (terminal)

## What's Been Implemented (Jan 2026)
- ✅ Network diagnostic tests (Ping, Traceroute, MTR, BGP) - SIMULATED
- ✅ 4 Server locations with interactive map
- ✅ Speed test with download/upload/latency gauges
- ✅ IP Geolocation lookup (using ip-api.com)
- ✅ Test history panel
- ✅ Professional terminal-style results display
- ✅ Light theme with professional hosting look

## User Personas
1. Hosting customers checking connectivity
2. Network administrators troubleshooting
3. Technical users testing network routes

## Core Requirements (Static)
- Fast, responsive UI
- Real-time test results
- Mobile-friendly design
- No authentication required

## Backlog
### P0 (Critical) - Done
- All network tests
- Speed test
- IP Geolocation

### P1 (High) - Future
- Real network commands (server-side execution)
- More server locations

### P2 (Medium) - Future
- Whois lookup
- DNS lookup
- Port checker

## Next Tasks
1. Add real network command execution (requires server permissions)
2. Add more server locations
3. Add Whois/DNS lookup tools
