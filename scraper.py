import sys
import requests
import json

def scrape(url, output_file):
    print(f"Scraping {url}...")
    # Add ArcGIS query parameters to get all features
    query_url = f"{url}/query"
    params = {
        'where': '1=1',
        'outFields': '*',
        'f': 'json',
        'resultOffset': 0,
        'resultRecordCount': 1000
    }
    
    all_features = []
    
    while True:
        response = requests.get(query_url, params=params, timeout=30)
        if response.status_code != 200:
            print(f"Error: Status code {response.status_code}")
            sys.exit(1)
            
        data = response.json()
        features = data.get('features', [])
        all_features.extend(features)
        
        print(f"  Downloaded {len(all_features)} features...")
        
        if data.get('exceededTransferLimit') or len(features) == params['resultRecordCount']:
            params['resultOffset'] += params['resultRecordCount']
        else:
            break
            
    # Reconstruct a complete ESRI JSON object
    if all_features:
        data['features'] = all_features
        with open(output_file, 'w') as f:
            json.dump(data, f)
        print(f"Saved {len(all_features)} features to {output_file}")
    else:
        print("No features found.")
        sys.exit(1)

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: python3 scraper.py <URL> <OUTPUT_FILE>")
        sys.exit(1)
    scrape(sys.argv[1], sys.argv[2])
