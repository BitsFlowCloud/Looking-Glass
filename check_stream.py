#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import requests
import re
import socket
import json
import sys
import argparse
import urllib3.util.connection as urllib3_cn

# ==========================================
# 全局控制变量
# ==========================================
CURRENT_PROTOCOL = socket.AF_INET 

def allowed_gai_family():
    return CURRENT_PROTOCOL

urllib3_cn.allowed_gai_family = allowed_gai_family

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
    'Accept-Language': 'en-US,en;q=0.9',
}

COOKIES_YT = {
    'CONSENT': 'YES+cb.20210328-17-p0.en+FX+416',
    'SOCS': 'CAESEwgDEgk0ODE3Nzk3MjQaAmVuIAEaBgiA_LyaBg'
}

TIMEOUT = 6 

def get_request(url, allow_redirects=True, use_cookies=False):
    try:
        cks = COOKIES_YT if use_cookies else {}
        with requests.Session() as s:
            return s.get(url, headers=HEADERS, cookies=cks, timeout=TIMEOUT, allow_redirects=allow_redirects)
    except Exception:
        class MockResponse:
            text = ""
            status_code = 0
            url = url
            history = []
        return MockResponse()

def get_ip_info():
    # 方案 A: ip-api.com
    try:
        data = requests.get("http://ip-api.com/json/", timeout=5).json()
        country = data.get('countryCode')
        isp = data.get('isp')
        query = data.get('query')
        if country:
            return f"[{country}] {isp} ({query})", country
    except:
        pass

    # 方案 B: ipify
    try:
        ip = requests.get("https://api64.ipify.org?format=json", timeout=5).json().get('ip')
        if ip:
            return f"[Unknown] {ip}", "Unknown"
    except:
        pass

    return "Network Error (Connect Failed)", "Unknown"

# --- 流媒体检测逻辑 ---

def check_youtube(current_region):
    region = "Unknown"
    r_main = get_request("https://www.youtube.com/", use_cookies=True)
    if r_main.status_code == 200:
        match = re.search(r'"countryCode":"([A-Z]{2})"', r_main.text)
        if match:
            region = match.group(1)
        else:
            match2 = re.search(r'"gl":"([A-Z]{2})"', r_main.text)
            if match2: region = match2.group(1)
    
    premium_status = "No"
    r_prem = get_request("https://www.youtube.com/premium", use_cookies=True)
    if r_prem.status_code == 200:
        text = r_prem.text.lower()
        if "premium" in text and ("try free" in text or "get youtube premium" in text or "saved" in text):
            premium_status = "Yes"
        elif region in ['US', 'DE', 'JP', 'HK', 'SG', 'TW', 'GB', 'FR', 'AU', 'CA', 'IN', 'AR', 'TR', 'UA', 'PH', 'VN']:
            premium_status = "Yes (Likely)"
            
    if region == "Unknown" and r_main.status_code == 0:
        return "Network Error"

    return f"Region: {region} | Premium: {premium_status}"

def check_netflix(current_region):
    id_non = "70143836" 
    id_org = "80018499" 
    
    def extract_region_logic(url):
        match = re.search(r'netflix\.com/([a-z]{2}(-[a-z]{2})?)/', url)
        if match:
            url_region = match.group(1).split('-')[0].upper()
            if url_region == "GB" and current_region == "DE": return "DE"
            return url_region
        if current_region != "Unknown": return current_region
        return "US"

    r1 = get_request(f"https://www.netflix.com/title/{id_non}", use_cookies=False)
    if r1.status_code == 200 and "/login" not in r1.url and "Netflix" in r1.text:
        return f"Yes (Region: {extract_region_logic(r1.url)})"

    r2 = get_request(f"https://www.netflix.com/title/{id_org}", use_cookies=False)
    if r2.status_code == 200 and "/login" not in r2.url and "Netflix" in r2.text:
        return f"Yes (Originals Only) Region: {extract_region_logic(r2.url)}"

    if r1.status_code == 403: return "No (IP Blocked)"
    return "No"

def check_disney(current_region):
    r = get_request("https://www.disneyplus.com/")
    if r.status_code == 0: return "Network Error"
    if r.status_code == 200 and "preview" not in r.url and "unavailable" not in r.url:
        region = "Global"
        match = re.search(r'disneyplus\.com/([a-z]{2}-[a-z]{2})/', r.url)
        if match:
            region = match.group(1).split('-')[1].upper()
        elif current_region != "Unknown":
            region = current_region
        return f"Yes (Region: {region})"
    return "No"

# === 修改点：TikTok 实际检测 ===
def check_tiktok():
    try:
        r = get_request("https://www.tiktok.com/")
        if r.status_code == 200:
            return "Yes"
        elif r.status_code == 403:
            return "No"
        else:
            return "No"
    except:
        return "Network Error"

def check_spotify():
    try:
        r = get_request("https://www.spotify.com/")
        if r.status_code == 200: return "Yes"
        if r.status_code == 403: return "No"
    except: pass
    try:
        r = requests.get("https://spclient.wg.spotify.com/signup/public/v1/account/validate/password", headers=HEADERS, timeout=5)
        if r.status_code == 200: return "Yes"
        if r.status_code == 403: return "No"
    except: pass
    return "No (Network Error)"

def check_gemini():
    r = get_request("https://gemini.google.com", allow_redirects=True, use_cookies=True)
    if r.status_code == 0: return "Network Error"
    if r.status_code == 200 and ("Google" in r.text or "Sign in" in r.text): return "Yes"
    if r.history and "accounts.google.com" in r.history[0].headers.get('Location', ''): return "Yes"
    return f"No ({r.status_code})"

def run_suite(protocol, proto_name):
    global CURRENT_PROTOCOL
    CURRENT_PROTOCOL = protocol 
    
    print(f"--- Checking via {proto_name} ---")
    
    ip_str, region_code = get_ip_info()
    print(f"IP Info: {ip_str}")
    
    if "Network Error" in ip_str and proto_name == "IPv6":
        print("Warning: IP API failed, but forcing continue for IPv6...")
        region_code = "Unknown" 
    elif "Network Error" in ip_str:
        print("Skipping tests due to network error.")
        return {
            'netflix': 'Network Error', 'youtube': 'Network Error', 'disney': 'Network Error',
            'tiktok': 'Network Error', 'spotify': 'Network Error', 'gemini': 'Network Error'
        }

    results_raw = {
        'netflix': check_netflix(region_code),
        'youtube': check_youtube(region_code),
        'disney': check_disney(region_code),
        'tiktok': check_tiktok(),
        'spotify': check_spotify(),
        'gemini': check_gemini()
    }
    
    for k, v in results_raw.items():
        print(f"{k.capitalize()}: {v}")
    
    # 必须返回原始文本，否则 PHP 前端无法显示详细信息
    return results_raw

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=str, help="Output JSON result to file")
    args = parser.parse_args()

    final_data = {}
    final_data['v4'] = run_suite(socket.AF_INET, "IPv4")
    print("\n")
    final_data['v6'] = run_suite(socket.AF_INET6, "IPv6")

    if args.out:
        try:
            with open(args.out, 'w') as f:
                json.dump(final_data, f)
            import os
            try: os.chmod(args.out, 0o644)
            except: pass
            print(f"\nSaved result to {args.out}")
        except Exception as e:
            print(f"Error writing file: {e}")

if __name__ == "__main__":
    main()
