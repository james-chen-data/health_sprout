#!/usr/bin/env python3
"""
Health Sprout — Diagnostic Tool
Run this to check what's working and what isn't.
"""
import sys

print("\n" + "="*50)
print("  Health Sprout Diagnostics")
print("="*50 + "\n")

# ── Check 1: google-genai package ─────────────────
print("1. Checking google-genai package...")
try:
    from google import genai
    from google.genai import types as genai_types
    print("   ✅ google-genai is installed correctly\n")
except ImportError:
    print("   ❌ google-genai is NOT installed")
    print("   Fix: pip install google-genai\n")
    sys.exit(1)

# ── Check 2: Old package warning ──────────────────
print("2. Checking for old deprecated package...")
try:
    import importlib.util
    if importlib.util.find_spec("google.generativeai") is not None:
        print("   ⚠️  google-generativeai (old package) is still installed")
        print("   Fix: pip uninstall google-generativeai -y\n")
    else:
        print("   ✅ Old package not present\n")
except Exception:
    print("   ✅ Old package not present\n")

# ── Check 3: API Key ───────────────────────────────
print("3. Enter your Gemini API key to test it:")
print("   (Get a NEW key at https://aistudio.google.com/apikey)\n")
api_key = input("   API Key: ").strip()

if not api_key:
    print("   ❌ No key entered. Exiting.\n")
    sys.exit(1)

# ── Check 4: Test API call ─────────────────────────
print("\n4. Testing API connection with gemini-1.5-flash...")
try:
    client = genai.Client(api_key=api_key)
    response = client.models.generate_content(
        model="gemini-1.5-flash",
        contents="Say exactly: CONNECTED"
    )
    print(f"   ✅ API works! Response: {response.text.strip()}\n")
    print("="*50)
    print("  All checks passed! You're good to go.")
    print("  Run: python health_sprout_app.py")
    print("="*50 + "\n")
except Exception as e:
    err = str(e)
    print(f"   ❌ API call failed:\n   {err}\n")
    if "API_KEY_INVALID" in err or "invalid" in err.lower():
        print("   → Your API key is invalid or from the wrong place.")
        print("   → Get a key from: https://aistudio.google.com/apikey")
        print("   → NOT from Google Cloud Console — that's a different key.\n")
    elif "quota" in err.lower() or "429" in err:
        print("   → Quota exceeded on this key.")
        print("   → Create a BRAND NEW key at: https://aistudio.google.com/apikey")
        print("   → Each new key starts with a fresh quota.\n")
    elif "PERMISSION_DENIED" in err:
        print("   → The Gemini API is not enabled for this key's project.")
        print("   → Use a key from AI Studio, not Google Cloud Console.\n")
    else:
        print("   → Unexpected error. Copy the full message above and share it.\n")

input("Press Enter to close...")
