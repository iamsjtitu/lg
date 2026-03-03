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
  Clock,
  ChevronRight,
  Network,
  Route,
  Gauge,
  History,
  FileText,
  Cpu,
  Wifi,
  Download,
  Upload,
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
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";

const BACKEND_URL = process.env.REACT_APP_BACKEND_URL;
const API = `${BACKEND_URL}/api`;

// Terminal Window Component
const TerminalWindow = ({ title, content, isLoading }) => (
  <div className="terminal-window" data-testid="terminal-window">
    <div className="terminal-header">
      <div className="terminal-dot bg-red-500" />
      <div className="terminal-dot bg-yellow-500" />
      <div className="terminal-dot bg-green-500" />
      <span className="ml-3 text-sm text-slate-400">{title}</span>
      <Badge variant="outline" className="ml-auto text-xs text-green-400 border-green-400/30">
        REAL OUTPUT
      </Badge>
    </div>
    <div className="terminal-content min-h-[200px] max-h-[500px] overflow-y-auto">
      {isLoading ? (
        <div className="flex items-center gap-2 text-green-400">
          <RefreshCw className="w-4 h-4 animate-spin" />
          <span>Executing command...</span>
        </div>
      ) : content ? (
        <pre className="text-green-400 whitespace-pre-wrap">{content}</pre>
      ) : (
        <span className="text-slate-500">
          $ Results will appear here after running a test...
        </span>
      )}
    </div>
  </div>
);

// Speed Gauge Component
const SpeedGauge = ({ value, max, label, type, isReal }) => {
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
        <span className="text-sm text-slate-600 flex items-center gap-1">
          {label}
          {isReal && <Badge variant="outline" className="text-[10px] px-1 py-0">REAL</Badge>}
        </span>
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
  
  // DNS lookup state
  const [dnsDomain, setDnsDomain] = useState("");
  const [dnsRecordType, setDnsRecordType] = useState("A");
  
  // Whois state
  const [whoisDomain, setWhoisDomain] = useState("");
  
  // iperf3 state
  const [iperfServers, setIperfServers] = useState([]);
  const [selectedIperfServer, setSelectedIperfServer] = useState("");
  const [iperfMode, setIperfMode] = useState("download");
  const [isIperfTesting, setIsIperfTesting] = useState(false);

  useEffect(() => {
    fetchTestHistory();
    fetchIperfServers();
  }, []);

  const fetchIperfServers = async () => {
    try {
      const response = await axios.get(`${API}/iperf-servers`);
      setIperfServers(response.data.servers);
      if (response.data.servers.length > 0) {
        setSelectedIperfServer(response.data.servers[0].host);
      }
    } catch (error) {
      console.error("Failed to fetch iperf servers");
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
        source_location: "demo",
      });
      setTestResult(response.data.result);
      toast.success(`${activeTest.toUpperCase()} completed (Real Output)`);
      fetchTestHistory();
    } catch (error) {
      toast.error(`Test failed: ${error.response?.data?.detail || error.message}`);
      setTestResult(`Error: ${error.response?.data?.detail || error.message}`);
    } finally {
      setIsLoading(false);
    }
  };

  const runDNSLookup = async () => {
    if (!dnsDomain.trim()) {
      toast.error("Please enter a domain");
      return;
    }

    setIsLoading(true);
    setTestResult("");
    setActiveTest("dns");

    try {
      const response = await axios.post(`${API}/network/dns`, {
        domain: dnsDomain,
        record_type: dnsRecordType,
      });
      setTestResult(response.data.result);
      toast.success("DNS lookup completed (Real Output)");
      fetchTestHistory();
    } catch (error) {
      toast.error(`DNS lookup failed: ${error.response?.data?.detail || error.message}`);
      setTestResult(`Error: ${error.response?.data?.detail || error.message}`);
    } finally {
      setIsLoading(false);
    }
  };

  const runWhoisLookup = async () => {
    if (!whoisDomain.trim()) {
      toast.error("Please enter a domain");
      return;
    }

    setIsLoading(true);
    setTestResult("");
    setActiveTest("whois");

    try {
      const response = await axios.post(`${API}/network/whois`, {
        domain: whoisDomain,
      });
      setTestResult(response.data.result);
      toast.success("WHOIS lookup completed (Real Output)");
      fetchTestHistory();
    } catch (error) {
      toast.error(`WHOIS lookup failed: ${error.response?.data?.detail || error.message}`);
      setTestResult(`Error: ${error.response?.data?.detail || error.message}`);
    } finally {
      setIsLoading(false);
    }
  };

  const runIperfTest = async () => {
    if (!selectedIperfServer) {
      toast.error("Please select an iperf3 server");
      return;
    }

    setIsIperfTesting(true);
    setTestResult("");
    setActiveTest("iperf");

    const server = iperfServers.find(s => s.host === selectedIperfServer);
    
    try {
      const response = await axios.post(`${API}/network/iperf`, {
        server: selectedIperfServer,
        port: server?.port || 5201,
        duration: 5,
        reverse: iperfMode === "download",
      });
      setTestResult(response.data.result);
      toast.success(`iperf3 ${iperfMode} test completed`);
      fetchTestHistory();
    } catch (error) {
      toast.error(`iperf3 test failed: ${error.response?.data?.detail || error.message}`);
      setTestResult(`Error: ${error.response?.data?.detail || error.message}`);
    } finally {
      setIsIperfTesting(false);
    }
  };

  const runSpeedTest = async () => {
    setIsSpeedTesting(true);
    setSpeedTestResult(null);

    try {
      const response = await axios.post(`${API}/speed-test`);
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

  const getTestIcon = (testType) => {
    const icons = {
      ping: <Zap className="w-3 h-3" />,
      traceroute: <Route className="w-3 h-3" />,
      mtr: <Activity className="w-3 h-3" />,
      bgp: <Network className="w-3 h-3" />,
      dns: <Globe className="w-3 h-3" />,
      whois: <FileText className="w-3 h-3" />,
      iperf: <Wifi className="w-3 h-3" />,
      "iperf3-download": <Download className="w-3 h-3" />,
      "iperf3-upload": <Upload className="w-3 h-3" />,
    };
    return icons[testType] || <Terminal className="w-3 h-3" />;
  };

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
            <div className="flex items-center gap-3">
              <Badge className="bg-emerald-500 text-white gap-1">
                <Cpu className="w-3 h-3" />
                Real Commands
              </Badge>
              <Badge variant="outline" className="hidden sm:flex gap-1">
                <Activity className="w-3 h-3 text-emerald-500" />
                Operational
              </Badge>
            </div>
          </div>
        </div>
      </header>

      {/* Hero Section */}
      <section className="hero-section relative py-8" data-testid="hero-section">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 relative z-10">
          <div className="text-center mb-6">
            <h2 className="text-3xl sm:text-4xl lg:text-5xl font-black text-slate-900 mb-3">
              Network Diagnostic Tools
            </h2>
            <p className="text-slate-600 max-w-2xl mx-auto">
              Execute <strong>real network commands</strong> from our server.
              Ping, Traceroute, MTR, DNS, WHOIS, BGP lookups and more.
            </p>
          </div>
        </div>
      </section>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <div className="grid lg:grid-cols-3 gap-6">
          {/* Network Tests Panel */}
          <div className="lg:col-span-2 space-y-6">
            <Card className="bento-card" data-testid="network-tests-panel">
              <CardHeader className="border-b border-slate-100">
                <CardTitle className="flex items-center gap-2 text-lg">
                  <Terminal className="w-5 h-5 text-blue-600" />
                  Network Tests
                  <Badge variant="outline" className="ml-2 text-xs">Real Execution</Badge>
                </CardTitle>
              </CardHeader>
              <CardContent className="p-6 space-y-6">
                {/* Test Type Tabs */}
                <Tabs value={activeTest} onValueChange={setActiveTest}>
                  <TabsList className="grid grid-cols-7 w-full" data-testid="test-tabs">
                    <TabsTrigger value="ping" data-testid="tab-ping">
                      <Zap className="w-4 h-4 sm:mr-1" />
                      <span className="hidden sm:inline">Ping</span>
                    </TabsTrigger>
                    <TabsTrigger value="traceroute" data-testid="tab-traceroute">
                      <Route className="w-4 h-4 sm:mr-1" />
                      <span className="hidden sm:inline">Trace</span>
                    </TabsTrigger>
                    <TabsTrigger value="mtr" data-testid="tab-mtr">
                      <Activity className="w-4 h-4 sm:mr-1" />
                      <span className="hidden sm:inline">MTR</span>
                    </TabsTrigger>
                    <TabsTrigger value="bgp" data-testid="tab-bgp">
                      <Network className="w-4 h-4 sm:mr-1" />
                      <span className="hidden sm:inline">BGP</span>
                    </TabsTrigger>
                    <TabsTrigger value="dns" data-testid="tab-dns">
                      <Globe className="w-4 h-4 sm:mr-1" />
                      <span className="hidden sm:inline">DNS</span>
                    </TabsTrigger>
                    <TabsTrigger value="whois" data-testid="tab-whois">
                      <FileText className="w-4 h-4 sm:mr-1" />
                      <span className="hidden sm:inline">WHOIS</span>
                    </TabsTrigger>
                    <TabsTrigger value="iperf" data-testid="tab-iperf">
                      <Wifi className="w-4 h-4 sm:mr-1" />
                      <span className="hidden sm:inline">iPerf3</span>
                    </TabsTrigger>
                  </TabsList>

                  {/* Ping/Traceroute/MTR/BGP */}
                  <TabsContent value="ping" className="mt-4 space-y-4">
                    <p className="text-sm text-slate-500">
                      Send ICMP echo requests to test connectivity and measure round-trip time.
                    </p>
                    <Input
                      placeholder="e.g., 8.8.8.8 or google.com"
                      value={targetIP}
                      onChange={(e) => setTargetIP(e.target.value)}
                      className="ip-input"
                      data-testid="target-input"
                    />
                    <Button
                      onClick={runNetworkTest}
                      disabled={isLoading}
                      className="w-full bg-[#0F172A] hover:bg-slate-800"
                      data-testid="run-test-btn"
                    >
                      {isLoading ? (
                        <>
                          <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                          Running PING...
                        </>
                      ) : (
                        <>
                          <ChevronRight className="w-4 h-4 mr-2" />
                          Run PING
                        </>
                      )}
                    </Button>
                  </TabsContent>

                  <TabsContent value="traceroute" className="mt-4 space-y-4">
                    <p className="text-sm text-slate-500">
                      Trace the route packets take to reach the destination.
                    </p>
                    <Input
                      placeholder="e.g., 8.8.8.8 or google.com"
                      value={targetIP}
                      onChange={(e) => setTargetIP(e.target.value)}
                      className="ip-input"
                      data-testid="target-input-trace"
                    />
                    <Button
                      onClick={runNetworkTest}
                      disabled={isLoading}
                      className="w-full bg-[#0F172A] hover:bg-slate-800"
                      data-testid="run-trace-btn"
                    >
                      {isLoading ? (
                        <>
                          <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                          Running TRACEROUTE...
                        </>
                      ) : (
                        <>
                          <ChevronRight className="w-4 h-4 mr-2" />
                          Run TRACEROUTE
                        </>
                      )}
                    </Button>
                  </TabsContent>

                  <TabsContent value="mtr" className="mt-4 space-y-4">
                    <p className="text-sm text-slate-500">
                      Combines ping and traceroute for comprehensive network diagnostics.
                    </p>
                    <Input
                      placeholder="e.g., 8.8.8.8 or google.com"
                      value={targetIP}
                      onChange={(e) => setTargetIP(e.target.value)}
                      className="ip-input"
                      data-testid="target-input-mtr"
                    />
                    <Button
                      onClick={runNetworkTest}
                      disabled={isLoading}
                      className="w-full bg-[#0F172A] hover:bg-slate-800"
                      data-testid="run-mtr-btn"
                    >
                      {isLoading ? (
                        <>
                          <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                          Running MTR...
                        </>
                      ) : (
                        <>
                          <ChevronRight className="w-4 h-4 mr-2" />
                          Run MTR
                        </>
                      )}
                    </Button>
                  </TabsContent>

                  <TabsContent value="bgp" className="mt-4 space-y-4">
                    <p className="text-sm text-slate-500">
                      Look up BGP routing information using BGPView API.
                    </p>
                    <Input
                      placeholder="e.g., 8.8.8.8"
                      value={targetIP}
                      onChange={(e) => setTargetIP(e.target.value)}
                      className="ip-input"
                      data-testid="target-input-bgp"
                    />
                    <Button
                      onClick={runNetworkTest}
                      disabled={isLoading}
                      className="w-full bg-[#0F172A] hover:bg-slate-800"
                      data-testid="run-bgp-btn"
                    >
                      {isLoading ? (
                        <>
                          <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                          Looking up BGP...
                        </>
                      ) : (
                        <>
                          <ChevronRight className="w-4 h-4 mr-2" />
                          BGP Lookup
                        </>
                      )}
                    </Button>
                  </TabsContent>

                  {/* DNS Lookup */}
                  <TabsContent value="dns" className="mt-4 space-y-4">
                    <p className="text-sm text-slate-500">
                      Query DNS records for any domain.
                    </p>
                    <div className="grid sm:grid-cols-3 gap-3">
                      <Input
                        placeholder="e.g., google.com"
                        value={dnsDomain}
                        onChange={(e) => setDnsDomain(e.target.value)}
                        className="ip-input sm:col-span-2"
                        data-testid="dns-domain-input"
                      />
                      <Select value={dnsRecordType} onValueChange={setDnsRecordType}>
                        <SelectTrigger data-testid="dns-type-select">
                          <SelectValue placeholder="Record Type" />
                        </SelectTrigger>
                        <SelectContent>
                          {["A", "AAAA", "MX", "NS", "TXT", "CNAME", "SOA"].map((type) => (
                            <SelectItem key={type} value={type}>{type}</SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                    <Button
                      onClick={runDNSLookup}
                      disabled={isLoading}
                      className="w-full bg-[#0F172A] hover:bg-slate-800"
                      data-testid="run-dns-btn"
                    >
                      {isLoading && activeTest === "dns" ? (
                        <>
                          <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                          Looking up DNS...
                        </>
                      ) : (
                        <>
                          <ChevronRight className="w-4 h-4 mr-2" />
                          DNS Lookup
                        </>
                      )}
                    </Button>
                  </TabsContent>

                  {/* WHOIS Lookup */}
                  <TabsContent value="whois" className="mt-4 space-y-4">
                    <p className="text-sm text-slate-500">
                      Get domain registration and ownership information.
                    </p>
                    <Input
                      placeholder="e.g., google.com"
                      value={whoisDomain}
                      onChange={(e) => setWhoisDomain(e.target.value)}
                      className="ip-input"
                      data-testid="whois-domain-input"
                    />
                    <Button
                      onClick={runWhoisLookup}
                      disabled={isLoading}
                      className="w-full bg-[#0F172A] hover:bg-slate-800"
                      data-testid="run-whois-btn"
                    >
                      {isLoading && activeTest === "whois" ? (
                        <>
                          <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                          Looking up WHOIS...
                        </>
                      ) : (
                        <>
                          <ChevronRight className="w-4 h-4 mr-2" />
                          WHOIS Lookup
                        </>
                      )}
                    </Button>
                  </TabsContent>

                  {/* iperf3 Bandwidth Test */}
                  <TabsContent value="iperf" className="mt-4 space-y-4">
                    <p className="text-sm text-slate-500">
                      Real bandwidth test using iperf3 to public servers.
                    </p>
                    <div className="grid sm:grid-cols-2 gap-3">
                      <Select value={selectedIperfServer} onValueChange={setSelectedIperfServer}>
                        <SelectTrigger data-testid="iperf-server-select">
                          <SelectValue placeholder="Select iperf3 server" />
                        </SelectTrigger>
                        <SelectContent>
                          {iperfServers.map((server) => (
                            <SelectItem key={server.host} value={server.host}>
                              {server.name}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                      <Select value={iperfMode} onValueChange={setIperfMode}>
                        <SelectTrigger data-testid="iperf-mode-select">
                          <SelectValue placeholder="Test Mode" />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="download">
                            <div className="flex items-center gap-2">
                              <Download className="w-4 h-4" />
                              Download Test
                            </div>
                          </SelectItem>
                          <SelectItem value="upload">
                            <div className="flex items-center gap-2">
                              <Upload className="w-4 h-4" />
                              Upload Test
                            </div>
                          </SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                    <Button
                      onClick={runIperfTest}
                      disabled={isIperfTesting}
                      className="w-full bg-emerald-600 hover:bg-emerald-700"
                      data-testid="run-iperf-btn"
                    >
                      {isIperfTesting ? (
                        <>
                          <RefreshCw className="w-4 h-4 mr-2 animate-spin" />
                          Running iperf3 {iperfMode}...
                        </>
                      ) : (
                        <>
                          <Wifi className="w-4 h-4 mr-2" />
                          Run iperf3 {iperfMode.charAt(0).toUpperCase() + iperfMode.slice(1)} Test
                        </>
                      )}
                    </Button>
                    <div className="text-xs text-slate-400 bg-slate-50 p-2 rounded">
                      Test duration: 5 seconds • Results in Mbits/sec
                    </div>
                  </TabsContent>
                </Tabs>

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
                      Test connection speeds. Latency is measured with real ping to 8.8.8.8.
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
                        isReal={false}
                      />
                      <SpeedGauge
                        value={speedTestResult.upload_speed}
                        max={500}
                        label="Upload"
                        type="upload"
                        isReal={false}
                      />
                      <SpeedGauge
                        value={speedTestResult.latency}
                        max={100}
                        label="Latency"
                        type="latency"
                        isReal={true}
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

            {/* Server Info */}
            <Card className="bento-card" data-testid="server-info-panel">
              <CardHeader className="border-b border-slate-100">
                <CardTitle className="flex items-center gap-2 text-lg">
                  <Server className="w-5 h-5 text-blue-600" />
                  Server Info
                </CardTitle>
              </CardHeader>
              <CardContent className="p-4">
                <div className="space-y-3">
                  <div className="flex items-center justify-between p-3 rounded-lg bg-slate-50">
                    <span className="text-sm text-slate-600">Location</span>
                    <Badge variant="outline">Demo Server</Badge>
                  </div>
                  <div className="flex items-center justify-between p-3 rounded-lg bg-slate-50">
                    <span className="text-sm text-slate-600">Commands</span>
                    <Badge className="bg-emerald-500">Real Execution</Badge>
                  </div>
                  <div className="flex items-center justify-between p-3 rounded-lg bg-slate-50">
                    <span className="text-sm text-slate-600">Tools</span>
                    <span className="text-xs text-slate-500">ping, traceroute, mtr, dig, whois, iperf3</span>
                  </div>
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
                          <Badge variant="secondary" className="text-xs flex items-center gap-1">
                            {getTestIcon(test.test_type)}
                            {test.test_type?.toUpperCase()}
                          </Badge>
                          <Clock className="w-3 h-3 text-slate-400" />
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
            <div className="flex items-center gap-2 text-sm text-slate-500">
              <Badge variant="outline" className="text-xs">Ping</Badge>
              <Badge variant="outline" className="text-xs">Traceroute</Badge>
              <Badge variant="outline" className="text-xs">MTR</Badge>
              <Badge variant="outline" className="text-xs">DNS</Badge>
              <Badge variant="outline" className="text-xs">WHOIS</Badge>
              <Badge variant="outline" className="text-xs">BGP</Badge>
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
}

export default App;
