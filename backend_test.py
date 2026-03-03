import requests
import sys
import json
from datetime import datetime

class LookingGlassAPITester:
    def __init__(self, base_url="https://host9x-explorer.preview.emergentagent.com"):
        self.base_url = base_url
        self.api_url = f"{base_url}/api"
        self.tests_run = 0
        self.tests_passed = 0
        self.failed_tests = []

    def run_test(self, name, method, endpoint, expected_status, data=None, timeout=30):
        """Run a single API test"""
        url = f"{self.api_url}/{endpoint}"
        headers = {'Content-Type': 'application/json'}

        self.tests_run += 1
        print(f"\n🔍 Testing {name}...")
        print(f"   URL: {url}")
        
        try:
            if method == 'GET':
                response = requests.get(url, headers=headers, timeout=timeout)
            elif method == 'POST':
                response = requests.post(url, json=data, headers=headers, timeout=timeout)

            success = response.status_code == expected_status
            if success:
                self.tests_passed += 1
                print(f"✅ Passed - Status: {response.status_code}")
                try:
                    response_data = response.json()
                    print(f"   Response keys: {list(response_data.keys()) if isinstance(response_data, dict) else 'Non-dict response'}")
                    return True, response_data
                except:
                    return True, response.text
            else:
                print(f"❌ Failed - Expected {expected_status}, got {response.status_code}")
                print(f"   Response: {response.text[:200]}...")
                self.failed_tests.append({
                    "test": name,
                    "expected": expected_status,
                    "actual": response.status_code,
                    "response": response.text[:200]
                })
                return False, {}

        except requests.exceptions.Timeout:
            print(f"❌ Failed - Request timeout after {timeout}s")
            self.failed_tests.append({"test": name, "error": "Timeout"})
            return False, {}
        except Exception as e:
            print(f"❌ Failed - Error: {str(e)}")
            self.failed_tests.append({"test": name, "error": str(e)})
            return False, {}

    def test_root_endpoint(self):
        """Test API root endpoint"""
        return self.run_test("API Root", "GET", "", 200)

    def test_locations(self):
        """Test locations endpoint"""
        success, response = self.run_test("Get Locations", "GET", "locations", 200)
        if success and isinstance(response, dict):
            locations = response.get('locations', [])
            print(f"   Found {len(locations)} locations")
            expected_locations = ['nl', 'de', 'it', 'in']
            found_ids = [loc.get('id') for loc in locations]
            if all(loc_id in found_ids for loc_id in expected_locations):
                print(f"   ✅ All expected locations found: {found_ids}")
            else:
                print(f"   ⚠️  Missing locations. Expected: {expected_locations}, Found: {found_ids}")
        return success, response

    def test_ping(self):
        """Test ping endpoint"""
        return self.run_test(
            "Ping Test",
            "POST",
            "network/ping",
            200,
            data={"target": "8.8.8.8", "source_location": "nl"}
        )

    def test_traceroute(self):
        """Test traceroute endpoint"""
        return self.run_test(
            "Traceroute Test",
            "POST",
            "network/traceroute",
            200,
            data={"target": "google.com", "source_location": "de"}
        )

    def test_mtr(self):
        """Test MTR endpoint"""
        return self.run_test(
            "MTR Test",
            "POST",
            "network/mtr",
            200,
            data={"target": "cloudflare.com", "source_location": "it"}
        )

    def test_bgp(self):
        """Test BGP endpoint"""
        return self.run_test(
            "BGP Test",
            "POST",
            "network/bgp",
            200,
            data={"target": "1.1.1.1", "source_location": "in"}
        )

    def test_speed_test(self):
        """Test speed test endpoint"""
        return self.run_test(
            "Speed Test",
            "POST",
            "speed-test",
            200,
            data={"location": "nl"},
            timeout=10
        )

    def test_geolocation(self):
        """Test geolocation endpoint"""
        return self.run_test(
            "Geolocation Test",
            "GET",
            "geolocation/8.8.8.8",
            200,
            timeout=15
        )

    def test_invalid_geolocation(self):
        """Test geolocation with invalid IP"""
        return self.run_test(
            "Invalid Geolocation Test",
            "GET",
            "geolocation/invalid-ip",
            400,
            timeout=15
        )

    def test_history(self):
        """Test test history endpoint"""
        return self.run_test("Test History", "GET", "test-history", 200)

    def test_invalid_location(self):
        """Test with invalid location"""
        return self.run_test(
            "Invalid Location Test",
            "POST",
            "network/ping",
            400,
            data={"target": "8.8.8.8", "source_location": "invalid"}
        )

def main():
    print("🚀 Starting Looking Glass API Tests")
    print("=" * 50)
    
    tester = LookingGlassAPITester()
    
    # Test basic endpoints
    tester.test_root_endpoint()
    tester.test_locations()
    
    # Test network diagnostic tools
    tester.test_ping()
    tester.test_traceroute()
    tester.test_mtr()
    tester.test_bgp()
    
    # Test additional features
    tester.test_speed_test()
    tester.test_geolocation()
    tester.test_history()
    
    # Test error handling
    tester.test_invalid_geolocation()
    tester.test_invalid_location()
    
    # Print results
    print("\n" + "=" * 50)
    print("📊 TEST RESULTS")
    print("=" * 50)
    print(f"Tests passed: {tester.tests_passed}/{tester.tests_run}")
    print(f"Success rate: {(tester.tests_passed/tester.tests_run)*100:.1f}%")
    
    if tester.failed_tests:
        print(f"\n❌ Failed Tests ({len(tester.failed_tests)}):")
        for i, test in enumerate(tester.failed_tests, 1):
            print(f"{i}. {test['test']}")
            if 'expected' in test:
                print(f"   Expected: {test['expected']}, Got: {test['actual']}")
            if 'error' in test:
                print(f"   Error: {test['error']}")
            if 'response' in test:
                print(f"   Response: {test['response']}")
    else:
        print("\n✅ All tests passed!")
    
    return 0 if tester.tests_passed == tester.tests_run else 1

if __name__ == "__main__":
    sys.exit(main())