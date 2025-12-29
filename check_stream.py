import requests
import socket
import json
import argparse
import re
import time
from requests.adapters import HTTPAdapter
from urllib3.poolmanager import PoolManager
# ==========================================
# 核心配置
# ==========================================
UA_BROWSER = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
DISNEY_AUTH = "Bearer ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84"
# ==========================================
# 网络适配器
# ==========================================
class SourceAddressAdapter(HTTPAdapter):
    def __init__(self, source_address, **kwargs):
        self.source_address = source_address
        super(SourceAddressAdapter, self).__init__(**kwargs)
    def init_poolmanager(self, connections, maxsize, block=False):
        self.poolmanager = PoolManager(
            num_pools=connections, maxsize=maxsize,
            block=block, source_address=(self.source_address, 0))
def get_session(source_ip):
    session = requests.Session()
    session.headers.update({'User-Agent': UA_BROWSER})
    if source_ip:
        adapter = SourceAddressAdapter(source_ip)
        session.mount('http://', adapter)
        session.mount('https://', adapter)
    return session
# ==========================================
# 1. Netflix (双重保险版)
# ==========================================
def check_netflix(session):
    try:
        # A. 状态检测 (复刻 ip.sh: 检测两部剧)
        url_orig = "https://www.netflix.com/title/81280792"
        url_norm = "https://www.netflix.com/title/70143836"
        
        r_orig = session.get(url_orig, timeout=6)
        r_norm = session.get(url_norm, timeout=6)
        
        is_orig_ok = r_orig.status_code == 200 and "Oh no!" not in r_orig.text
        is_norm_ok = r_norm.status_code == 200 and "Oh no!" not in r_norm.text
        
        status = "No"
        if is_orig_ok and is_norm_ok:
            status = "Yes"
        elif is_orig_ok and not is_norm_ok:
            status = "Originals Only"
        else:
            return "No"
        # B. 地区获取 (双重保险)
        region = ""
        
        # 方法1: 尝试从页面源码提取 (ip.sh 逻辑)
        # 匹配 "id":"SG","countryName" 或 "currentCountry":{"id":"SG"
        for html in [r_orig.text, r_norm.text]:
            match = re.search(r'"id":"([A-Z]{2})","countryName"', html)
            if not match:
                match = re.search(r'"currentCountry":{"id":"([A-Z]{2})"', html)
            
            if match:
                region = match.group(1)
                break
        
        # 方法2: 如果正则失败，使用 302 跳转检测 (最稳的方法)
        if not region:
            try:
                r_home = session.get("https://www.netflix.com/", timeout=5, allow_redirects=False)
                if r_home.status_code in [301, 302]:
                    loc = r_home.headers.get('Location', '')
                    # 匹配 /sg-en/ 或 /sg/
                    m_loc = re.search(r'/([a-z]{2})(-[a-z]{2})?/', loc)
                    if m_loc: region = m_loc.group(1).upper()
                else:
                    # 没跳转通常是 US
                    region = "US"
            except: pass
        if region:
            return f"{status} (Region: {region})"
        return status
    except: return "N/A"
# ==========================================
# 2. YouTube (1:1 复刻 ip.sh)
# ==========================================
def check_youtube(session):
    try:
        cookies = {'YSC': 'BiCUU3-5Gdk', 'CONSENT': 'YES+cb.20220301-11-p0.en+FX+700', 'GPS': '1', 'VISITOR_INFO1_LIVE': '4VwPMkB7W5A', 'PREF': 'tz=Asia.Shanghai'}
        headers = {'Accept-Language': 'en'}
        r = session.get("https://www.youtube.com/premium", cookies=cookies, headers=headers, timeout=6)
        
        if "www.google.cn" in r.text: return "No (Region: CN)"
        if "Premium is not available in your country" in r.text: return "No Premium"
            
        region = "US"
        match = re.search(r'"contentRegion":"([A-Z]{2})"', r.text)
        if match: region = match.group(1)
        elif re.search(r'"countryCode":"([A-Z]{2})"', r.text):
            region = re.search(r'"countryCode":"([A-Z]{2})"', r.text).group(1)
        if "ad-free" in r.text or "Premium" in r.text:
            return f"Yes (Region: {region})"
        return f"Yes (Region: {region})"
    except: return "N/A"
# ==========================================
# 3. Disney+ (1:1 复刻 ip.sh Graphql)
# ==========================================
def check_disney(session):
    try:
        data_dev = {"deviceFamily": "browser", "applicationRuntime": "chrome", "deviceProfile": "windows", "attributes": {}}
        headers_dev = {"authorization": DISNEY_AUTH, "content-type": "application/json; charset=UTF-8", "Origin": "https://www.disneyplus.com", "Referer": "https://www.disneyplus.com/"}
        r1 = session.post("https://disney.api.edge.bamgrid.com/devices", json=data_dev, headers=headers_dev, timeout=6)
        if r1.status_code != 200: return "No"
        assertion = r1.json().get('assertion')
        
        data_tok = f"grant_type=urn:ietf:params:oauth:grant-type:token-exchange&latitude=0&longitude=0&platform=browser&subject_token={assertion}&subject_token_type=urn:bamtech:params:oauth:token-type:device"
        headers_tok = {"authorization": DISNEY_AUTH, "content-type": "application/x-www-form-urlencoded"}
        r2 = session.post("https://disney.api.edge.bamgrid.com/token", data=data_tok, headers=headers_tok, timeout=6)
        if "forbidden-location" in r2.text or "403 ERROR" in r2.text: return "No"
        
        access_token = r2.json().get('access_token')
        
        gql_query = {"query": "query { extensions { sdk { session { inSupportedLocation location { countryCode } } } } }"}
        headers_gql = {"authorization": f"Bearer {access_token}", "content-type": "application/json"}
        r3 = session.post("https://disney.api.edge.bamgrid.com/graph/v1/device/graphql", json=gql_query, headers=headers_gql, timeout=6)
        
        try:
            data = r3.json()
            session_info = data['extensions']['sdk']['session']
            region = session_info['location']['countryCode']
            in_supported = session_info['inSupportedLocation']
            
            if region == "JP": return "Yes (Region: JP)"
            if region and in_supported is False: return f"Pending (Region: {region})"
            elif region and in_supported is True: return f"Yes (Region: {region})"
            else: return "No"
        except: return "No"
    except: return "No"
# ==========================================
# 4. TikTok (1:1 复刻 ip.sh)
# ==========================================
def check_tiktok(session):
    try:
        r = session.get("https://www.tiktok.com/", timeout=6)
        match = re.search(r'"region":"([A-Z]{2})"', r.text)
        if match: return f"Yes (Region: {match.group(1)})"
            
        headers = {"Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8", "Accept-Encoding": "gzip", "Accept-Language": "en"}
        r2 = session.get("https://www.tiktok.com", headers=headers, timeout=6)
        match2 = re.search(r'"region":"([A-Z]{2})"', r2.text)
        if match2: return f"Yes (Region: {match2.group(1)})"
            
        if r.status_code == 200: return "Yes"
        return "No"
    except: return "No"
# ==========================================
# 5. Spotify (1:1 复刻 ip.sh)
# ==========================================
def check_spotify(session):
    try:
        url = "https://spclient.wg.spotify.com/signup/public/v1/account"
        data = {
            "birth_day": "11", "birth_month": "11", "birth_year": "2000",
            "collect_personal_info": "undefined", "creation_flow": "",
            "creation_point": "https://www.spotify.com/hk-en/",
            "displayname": "Gay Lord", "gender": "male", "iagree": "1",
            "key": "a1e486e2729f46d6bb368d6b2bcda326", "platform": "www",
            "referrer": "", "send-email": "0", "thirdpartyemail": "0",
            "identifier_token": "AgE6YTvEzkReHNfJpO114514"
        }
        headers = {"Accept-Language": "en", "Content-Type": "application/x-www-form-urlencoded"}
        r = session.post(url, data=data, headers=headers, timeout=6)
        
        resp = r.json()
        status = resp.get("status")
        launched = resp.get("is_country_launched")
        country = resp.get("country")
        
        if status == 311 and launched:
            return f"Yes (Region: {country})" if country else "Yes"
        return "No"
    except: return "N/A"
# ==========================================
# 6. Gemini
# ==========================================
def check_gemini(session):
    try:
        r = session.get("https://gemini.google.com/", timeout=5, allow_redirects=False)
        if r.status_code in [200, 302]:
            if "unsupported" in r.headers.get('Location', ''): return "No"
            return "Yes"
        return "No"
    except: return "N/A"
# ==========================================
# 辅助: 获取本机 IP
# ==========================================
def get_local_ip():
    v4, v6 = None, None
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        v4 = s.getsockname()[0]
        s.close()
    except: pass
    try:
        s = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
        s.connect(("2001:4860:4860::8888", 80))
        v6 = s.getsockname()[0]
        s.close()
    except: pass
    return v4, v6
# ==========================================
# 主程序
# ==========================================
if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', help='Output JSON file path')
    args = parser.parse_args()
    ipv4_local, ipv6_local = get_local_ip()
    results = {"v4": {}, "v6": {}}
    if ipv4_local:
        print(f"--- Checking via IPv4 ({ipv4_local}) ---")
        s = get_session(ipv4_local)
        results["v4"]["netflix"] = check_netflix(s)
        results["v4"]["youtube"] = check_youtube(s)
        results["v4"]["disney"] = check_disney(s)
        results["v4"]["tiktok"] = check_tiktok(s)
        results["v4"]["spotify"] = check_spotify(s)
        results["v4"]["gemini"] = check_gemini(s)
        print(json.dumps(results["v4"], indent=2))
    if ipv6_local:
        print(f"\n--- Checking via IPv6 ({ipv6_local}) ---")
        s = get_session(ipv6_local)
        results["v6"]["netflix"] = check_netflix(s)
        results["v6"]["youtube"] = check_youtube(s)
        results["v6"]["disney"] = check_disney(s)
        results["v6"]["tiktok"] = check_tiktok(s)
        results["v6"]["spotify"] = check_spotify(s)
        results["v6"]["gemini"] = check_gemini(s)
        print(json.dumps(results["v6"], indent=2))
    if args.out:
        with open(args.out, 'w') as f:
            json.dump(results, f)
