import React, { useState, useEffect } from "react";
import "@/App.css";
import axios from "axios";
import { Toaster, toast } from "sonner";
import {
  Server,
  Activity,
  Globe,
  Zap,
  MapPin,
  Terminal,
  Search,
  RefreshCw,
  Download,
  Upload,
  Clock,
  ChevronRight,
  Network,
  Route,
  Gauge,
  History,
} from "lucide-react";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Progress } from "@/components/ui/progress";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";

const BACKEND_URL = process.env.REACT_APP_BACKEND_URL;
const API = `${BACKEND_URL}/api`;

// Location Map Component
const LocationMap = ({ locations, selectedLocation, onSelect }) => {
  const mapPositions = {
    nl: { top: "28%", left: "48%" },
    de: { top: "32%", left: "50%" },
    it: { top: "40%", left: "51%" },
    in: { top: "52%", left: "72%" },
  };

  return (
    <div
      className="server-location-map relative h-48 bg-gradient-to-br from-slate-50 to-slate-100 rounded-xl border border-slate-200"
      data-testid="location-map"
    >
      {/* Simple World Map Dots */}
      <div className="absolute inset-0 flex items-center justify-center opacity-20">
        <Globe className="w-32 h-32 text-slate-400" />
      </div>

      {locations.map((loc) => (
        <button
          key={loc.id}
          className={`location-dot ${selectedLocation === loc.id ? "active" : ""}`}
          style={mapPositions[loc.id]}
          onClick={() => onSelect(loc.id)}
          title={`${loc.name} - ${loc.city}`}
          data-testid={`location-dot-${loc.id}`}
        />
      ))}

      {/* Location Labels */}
      {locations.map((loc) => (
        <div
          key={`label-${loc.id}`}
          className="absolute text-xs font-medium text-slate-600 transform -translate-x-1/2"
          style={{
            top: `calc(${mapPositions[loc.id].top} + 20px)`,
            left: mapPositions[loc.id].left,
          }}
        >
          {loc.city}
        </div>
      ))}
    </div>
  );
};

// Terminal Window Component
const TerminalWindow = ({ title, content, isLoading }) => (
  <div className="terminal-window" data-testid="terminal-window">
    <div className="terminal-header">
      <div className="terminal-dot bg-red-500" />
      <div className="terminal-dot bg-yellow-500" />
      <div className="terminal-dot bg-green-500" />
      <span className="ml-3 text-sm text-slate-400">{title}</span>
    </div>
    <div className="terminal-content min-h-[200px] max-h-[400px] overflow-y-auto">
      {isLoading ? (
        <div className="flex items-center gap-2 text-green-400">
          <RefreshCw className="w-4 h-4 animate-spin" />
          <span>Running test...</span>
        </div>
      ) : content ? (
        <pre className="text-green-400">{content}</pre>
      ) : (
        <span className="text-slate-500">
          Results will appear here after running a test...
        </span>
      )}
    </div>
  </div>
);

// Speed Gauge Component
const SpeedGauge = ({ value, max, label, type }) => {
  const percentage = Math.min((value / max) * 100, 100);
  const colors = {
    download: "bg-emerald-500",
    upload: "bg-amber-500",
    latency: "bg-blue-500",
  };

  return (
    <div className="flex flex-col items-center gap-2" data-testid={`speed-gauge-${type}`}>
      <div className="relative w-full h-3 bg-slate-200 rounded-full overflow-hidden">
        <div
          className={`absolute left-0 top-0 h-full ${colors[type]} transition-all duration-1000 ease-out rounded-full`}
          style={{ width: `${percentage}%` }}
        />
      </div>
      <div className="flex items-center justify-between w-full">
        <span className="text-sm text-slate-600">{label}</span>
        <span className="font-mono font-semibold text-slate-900">
          {value.toFixed(2)} {type === "latency" ? "ms" : "Mbps"}
        </span>
      </div>
    </div>
  );
};

// Geolocation Card Component
const GeolocationCard = ({ data }) => {
  if (!data) return null;

  return (
    <div className="grid grid-cols-2 gap-4 text-sm" data-testid="geolocation-result">
      <div>
        <span className="text-slate-500">IP Address</span>
        <p className="font-mono font-medium">{data.ip}</p>
      </div>
      <div>
        <span className="text-slate-500">Country</span>
        <p className="font-medium">
          {data.country} ({data.country_code})
        </p>
      </div>
      <div>
        <span className="text-slate-500">City</span>
        <p className="font-medium">{data.city}</p>
      </div>
      <div>
        <span className="text-slate-500">Region</span>
        <p className="font-medium">{data.region}</p>
      </div>
      <div>
        <span className="text-slate-500">ISP</span>
        <p className="font-medium">{data.isp}</p>
      </div>
      <div>
        <span className="text-slate-500">Timezone</span>
        <p className="font-medium">{data.timezone}</p>
      </div>
      <div className="col-span-2">
        <span className="text-slate-500">Coordinates</span>
        <p className="font-mono font-medium">
          {data.lat.toFixed(4)}, {data.lon.toFixed(4)}
        </p>
      </div>
    </div>
  );
};

function App() {
  const [locations, setLocations] = useState([]);
  const [selectedLocation, setSelectedLocation] = useState("nl");
  const [targetIP, setTargetIP] = useState("");
  const [activeTest, setActiveTest] = useState("ping");
  const [testResult, setTestResult] = useState("");
  const [isLoading, setIsLoading] = useState(false);
  const [speedTestResult, setSpeedTestResult] = useState(null);
  const [isSpeedTesting, setIsSpeedTesting] = useState(false);
  const [geoIP, setGeoIP] = useState("");
  const [geoResult, setGeoResult] = useState(null);
  const [isGeoLoading, setIsGeoLoading] = useState(false);
  const [testHistory, setTestHistory] = useState([]);

  useEffect(() => {
    fetchLocations();
    fetchTestHistory();
  }, []);

  const fetchLocations = async () => {
    try {
      const response = await axios.get(`${API}/locations`);
      setLocations(response.data.locations);
    } catch (error) {
      toast.error("Failed to fetch server locations");
    }
  };

  const fetchTestHistory = async () => {
    try {
      const response = await axios.get(`${API}/test-history?limit=10`);
      setTestHistory(response.data.history);
    } catch (error) {
      console.error("Failed to fetch test history");
    }
  };

  const runNetworkTest = async () => {
    if (!targetIP.trim()) {
      toast.error("Please enter a target IP or hostname");
      return;
    }

    setIsLoading(true);
    setTestResult("");

    try {
      const response = await axios.post(`${API}/network/${activeTest}`, {
        target: targetIP,
        source_location: selectedLocation,
      });
      setTestResult(response.data.result);
      toast.success(`${activeTest.toUpperCase()} test completed`);
      fetchTestHistory();
    } catch (error) {
      toast.error(`Test failed: ${error.response?.data?.detail || error.message}`);
    } finally {
      setIsLoading(false);
    }
  };

  const runSpeedTest = async () => {
    setIsSpeedTesting(true);
    setSpeedTestResult(null);

    try {
      const response = await axios.post(`${API}/speed-test`, {
        location: selectedLocation,
      });
      setSpeedTestResult(response.data);
      toast.success("Speed test completed");
    } catch (error) {
      toast.error("Speed test failed");
    } finally {
      setIsSpeedTesting(false);
    }
  };

  const lookupGeolocation = async () => {
    if (!geoIP.trim()) {
      toast.error("Please enter an IP address");
      return;
    }

    setIsGeoLoading(true);
    setGeoResult(null);

    try {
      const response = await axios.get(`${API}/geolocation/${geoIP}`);
      setGeoResult(response.data);
      toast.success("Geolocation lookup successful");
    } catch (error) {
      toast.error(
        `Lookup failed: ${error.response?.data?.detail || error.message}`
      );
    } finally {
      setIsGeoLoading(false);
    }
  };

  const selectedLocationData = locations.find((l) => l.id === selectedLocation);

  return (
    <div className="min-h-screen bg-white">
      <Toaster position="top-right" richColors />

      {/* Header */}
      <header className="glass-header sticky top-0 z-50" data-testid="header">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div className="p-2 bg-[#0F172A] rounded-lg">
                <Server className="w-6 h-6 text-white" />
              </div>
              <div>
                <h1 className="text-xl font-black text-slate-900">host9x.com</h1>
                <p className="text-xs text-slate-500">Network Looking Glass</p>
              </div>
            </div>
            <Badge variant="outline" className="hidden sm:flex gap-1">
              <Activity className="w-3 h-3 text-emerald-500" />
              All Systems Operational
            </Badge>
          </div>
        </div>
      </header>

      {/* Hero Section */}
      <section className="hero-section relative py-12" data-testid="hero-section">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
          <div className="text-center mb-8">
            <h2 className="text-3xl sm:text-4xl lg:text-5xl font-black text-slate-900 mb-3">
              Network Diagnostic Tools
            </h2>
            <p className="text-slate-600 max-w-2xl mx-auto">
              Test network connectivity from our global server locations.
              Ping, Traceroute, MTR, BGP lookups, Speed tests and more.
            </p>
          </div>

          {/* Location Map */}
          <div className="max-w-2xl mx-auto">
            <LocationMap
              locations={locations}
              selectedLocation={selectedLocation}
              onSelect={setSelectedLocation}
            />
            {selectedLocationData && (
              <div className="mt-4 text-center">
                <Badge className="bg-blue-600">
                  <MapPin className="w-3 h-3 mr-1" />
                  {selectedLocationData.name} - {selectedLocationData.city}
                </Badge>
              </div>
            )}
          </div>
        </div>
      </section>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div className="grid lg:grid-cols-3 gap-6">
          {/* Network Tests Panel */}
          <div className="lg:col-span-2 space-y-6">
            <Card className="bento-card" data-testid="network-tests-panel">
              <CardHeader className="border-b border-slate-100">
                <CardTitle className="flex items-center gap-2 text-lg">
                  <Terminal className="w-5 h-5 text-blue-600" />
                  Network Tests
                </CardTitle>
              </CardHeader>
              <CardContent className="p-6 space-y-6">
                {/* Location & Target Selection */}
                <div className="grid sm:grid-cols-2 gap-4">
                  <div>
                    <label className="text-sm font-medium text-slate-700 mb-2 block">
                      Source Location
                    </label>
                    <Select
                      value={selectedLocation}
                      onValueChange={setSelectedLocation}
                    >
                      <SelectTrigger data-testid="location-select">
                        <SelectValue placeholder="Select location" />
                      </SelectTrigger>
                      <SelectContent>
                        {locations.map((loc) => (
                          <SelectItem key={loc.id} value={loc.id}>
                            <div className="flex items-center gap-2">
                              <MapPin className="w-4 h-4" />
                              {loc.name} ({loc.city})
                            </div>
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div>
                    <label className="text-sm font-medium text-slate-700 mb-2 block">
                      Target IP / Hostname
                    </label>
                    <Input
                      placeholder="e.g., 8.8.8.8 or google.com"
                      value={targetIP}
                      onChange={(e) => setTargetIP(e.target.value)}
                      className="ip-input"
                      data-testid="target-input"
                    />
                  </div>
                </div>

                {/* Test Type Tabs */}
                <Tabs value={activeTest} onValueChange={setActiveTest}>
                  <TabsList className="grid grid-cols-4 w-full" data-testid="test-tabs">
                    <TabsTrigger value="ping" data-testid="tab-ping">
                      <Zap className="w-4 h-4 mr-1" />
                      Ping
                    </TabsTrigger>
                    <TabsTrigger value="traceroute" data-testid="tab-traceroute">
                      <Route className="w-4 h-4 mr-1" />
                      Traceroute
                    </TabsTrigger>
                    <TabsTrigger value="mtr" data-testid="tab-mtr">
                      <Activity className="w-4 h-4 mr-1" />
                      MTR
                    </TabsTrigger>
                    <TabsTrigger value="bgp" data-testid="tab-bgp">
                      <Network className="w-4 h-4 mr-1" />
                      BGP
                    </TabsTrigger>
                  </TabsList>

                  <TabsContent value="ping" className="mt-4">
                    <p className="text-sm text-slate-500 mb-4">
                      Send ICMP echo requests to test connectivity and measure
                      round-trip time.
                    </p>
                  </TabsContent>
                  <TabsContent value="traceroute" className="mt-4">
                    <p className="text-sm text-slate-500 mb-4">
                      Trace the route packets take to reach the destination.
                    </p>
                  </TabsContent>
                  <TabsContent value="mtr" className="mt-4">
                    <p className="text-sm text-slate-500 mb-4">
                      Combines ping and traceroute for comprehensive network
                      diagnostics.
                    </p>
                  </TabsContent>
                  <TabsContent value="bgp" className="mt-4">
                    <p className="text-sm text-slate-500 mb-4">
                      Look up BGP routing information for the target.
                    </p>
                  </TabsContent>
                </Tabs>

                {/* Run Button */}
                <Button
                  onClick={runNetworkTest}
                  disabled={isLoading}
                  className="w-full bg-[#0F172A] hover:bg-slate-800"
                  data-testid="run-test-btn"
                >
                  {isLoading ? (
                    <>
                      <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                      Running {activeTest.toUpperCase()}...
                    </>
                  ) : (
                    <>
                      <ChevronRight className="w-4 h-4 mr-2" />
                      Run {activeTest.toUpperCase()} Test
                    </>
                  )}
                </Button>

                {/* Results Terminal */}
                <TerminalWindow
                  title={`${activeTest.toUpperCase()} Results`}
                  content={testResult}
                  isLoading={isLoading}
                />
              </CardContent>
            </Card>

            {/* Speed Test Card */}
            <Card className="bento-card" data-testid="speed-test-panel">
              <CardHeader className="border-b border-slate-100">
                <CardTitle className="flex items-center gap-2 text-lg">
                  <Gauge className="w-5 h-5 text-emerald-600" />
                  Speed Test
                </CardTitle>
              </CardHeader>
              <CardContent className="p-6">
                <div className="flex flex-col sm:flex-row gap-6">
                  <div className="flex-1 space-y-4">
                    <p className="text-sm text-slate-500">
                      Test download/upload speeds from{" "}
                      <strong>{selectedLocationData?.name || "selected"}</strong>{" "}
                      server.
                    </p>
                    <Button
                      onClick={runSpeedTest}
                      disabled={isSpeedTesting}
                      variant="outline"
                      className="w-full"
                      data-testid="run-speed-test-btn"
                    >
                      {isSpeedTesting ? (
                        <>
                          <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                          Testing...
                        </>
                      ) : (
                        <>
                          <Zap className="w-4 h-4 mr-2" />
                          Start Speed Test
                        </>
                      )}
                    </Button>
                  </div>

                  {speedTestResult && (
                    <div className="flex-1 space-y-4" data-testid="speed-test-results">
                      <SpeedGauge
                        value={speedTestResult.download_speed}
                        max={1000}
                        label="Download"
                        type="download"
                      />
                      <SpeedGauge
                        value={speedTestResult.upload_speed}
                        max={500}
                        label="Upload"
                        type="upload"
                      />
                      <SpeedGauge
                        value={speedTestResult.latency}
                        max={100}
                        label="Latency"
                        type="latency"
                      />
                    </div>
                  )}
                </div>
              </CardContent>
            </Card>
          </div>

          {/* Sidebar */}
          <div className="space-y-6">
            {/* IP Geolocation */}
            <Card className="bento-card" data-testid="geolocation-panel">
              <CardHeader className="border-b border-slate-100">
                <CardTitle className="flex items-center gap-2 text-lg">
                  <Globe className="w-5 h-5 text-amber-600" />
                  IP Geolocation
                </CardTitle>
              </CardHeader>
              <CardContent className="p-6 space-y-4">
                <div className="flex gap-2">
                  <Input
                    placeholder="Enter IP address"
                    value={geoIP}
                    onChange={(e) => setGeoIP(e.target.value)}
                    className="ip-input flex-1"
                    data-testid="geo-ip-input"
                  />
                  <Button
                    onClick={lookupGeolocation}
                    disabled={isGeoLoading}
                    size="icon"
                    variant="outline"
                    data-testid="geo-lookup-btn"
                  >
                    {isGeoLoading ? (
                      <RefreshCw className="w-4 h-4 animate-spin" />
                    ) : (
                      <Search className="w-4 h-4" />
                    )}
                  </Button>
                </div>

                {geoResult && (
                  <>
                    <Separator />
                    <GeolocationCard data={geoResult} />
                  </>
                )}
              </CardContent>
            </Card>

            {/* Server Locations */}
            <Card className="bento-card" data-testid="locations-panel">
              <CardHeader className="border-b border-slate-100">
                <CardTitle className="flex items-center gap-2 text-lg">
                  <Server className="w-5 h-5 text-blue-600" />
                  Server Locations
                </CardTitle>
              </CardHeader>
              <CardContent className="p-4">
                <div className="space-y-2">
                  {locations.map((loc) => (
                    <button
                      key={loc.id}
                      className={`w-full p-3 rounded-lg text-left transition-all ${
                        selectedLocation === loc.id
                          ? "bg-blue-50 border border-blue-200"
                          : "hover:bg-slate-50 border border-transparent"
                      }`}
                      onClick={() => setSelectedLocation(loc.id)}
                      data-testid={`location-btn-${loc.id}`}
                    >
                      <div className="flex items-center gap-3">
                        <div
                          className={`w-2 h-2 rounded-full ${
                            selectedLocation === loc.id
                              ? "bg-blue-600"
                              : "bg-emerald-500"
                          }`}
                        />
                        <div>
                          <p className="font-medium text-sm text-slate-900">
                            {loc.name}
                          </p>
                          <p className="text-xs text-slate-500">{loc.city}</p>
                        </div>
                      </div>
                    </button>
                  ))}
                </div>
              </CardContent>
            </Card>

            {/* Recent Tests */}
            <Card className="bento-card" data-testid="history-panel">
              <CardHeader className="border-b border-slate-100">
                <CardTitle className="flex items-center gap-2 text-lg">
                  <History className="w-5 h-5 text-slate-600" />
                  Recent Tests
                </CardTitle>
              </CardHeader>
              <CardContent className="p-4">
                {testHistory.length === 0 ? (
                  <p className="text-sm text-slate-500 text-center py-4">
                    No recent tests
                  </p>
                ) : (
                  <div className="space-y-2 max-h-64 overflow-y-auto">
                    {testHistory.map((test, index) => (
                      <div
                        key={test.id || index}
                        className="p-2 rounded-lg bg-slate-50 text-xs"
                        data-testid={`history-item-${index}`}
                      >
                        <div className="flex items-center justify-between mb-1">
                          <Badge variant="secondary" className="text-xs">
                            {test.test_type?.toUpperCase()}
                          </Badge>
                          <span className="text-slate-400">
                            {test.source_location?.toUpperCase()}
                          </span>
                        </div>
                        <p className="font-mono text-slate-700 truncate">
                          {test.target}
                        </p>
                      </div>
                    ))}
                  </div>
                )}
              </CardContent>
            </Card>
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="border-t border-slate-200 mt-12" data-testid="footer">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
          <div className="flex flex-col sm:flex-row items-center justify-between gap-4">
            <div className="flex items-center gap-2">
              <Server className="w-5 h-5 text-slate-400" />
              <span className="font-medium text-slate-600">host9x.com</span>
              <span className="text-slate-400">Looking Glass</span>
            </div>
            <div className="flex items-center gap-4 text-sm text-slate-500">
              <span>Netherlands</span>
              <span>•</span>
              <span>Germany</span>
              <span>•</span>
              <span>Italy</span>
              <span>•</span>
              <span>Mumbai</span>
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
}

export default App;
