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
print("   (Get a key at https://aistudio.google.com/apikey)\n")
api_key = input("   API Key: ").strip()

if not api_key:
    print("   ❌ No key entered. Exiting.\n")
    sys.exit(1)

client = genai.Client(api_key=api_key)

# ── Check 4: List available models ────────────────
print("\n4. Listing models available for your API key...")
available = []
try:
    for m in client.models.list():
        name = getattr(m, "name", str(m))
        # Only show generateContent-capable Gemini models
        supported = getattr(m, "supported_actions", None) or \
                    getattr(m, "supported_generation_methods", [])
        if "generateContent" in str(supported) and "gemini" in name.lower():
            available.append(name)
            print(f"   ✅ {name}")
    if not available:
        print("   ⚠️  No generateContent-capable models found — key may be restricted.")
except Exception as e:
    print(f"   ⚠️  Could not list models: {e}")

# ── Check 5: Try candidate models ─────────────────
CANDIDATES = [
    "gemini-2.0-flash-lite",
    "gemini-2.0-flash",
    "gemini-2.5-flash",
    "gemini-1.5-flash",
]

print("\n5. Testing candidate models (first success wins)...")
working_model = None
for model in CANDIDATES:
    try:
        response = client.models.generate_content(
            model=model,
            contents="Say exactly: CONNECTED"
        )
        txt = response.text.strip() if response.text else ""
        print(f"   ✅ {model} → {txt}")
        working_model = model
        break
    except Exception as e:
        short = str(e).split("\n")[0][:80]
        print(f"   ❌ {model} → {short}")

print("\n" + "="*50)
if working_model:
    print(f"  ✅ Working model: {working_model}")
    print(f"\n  ACTION: Update health_sprout_app.py and sprout_advisor.py")
    print(f"  Change both lines that say:")
    print(f'      model="gemini-1.5-flash"')
    print(f"  to:")
    print(f'      model="{working_model}"')
    print(f"\n  Then run: python health_sprout_app.py")
else:
    print("  ❌ No working model found.")
    print("\n  POSSIBLE FIXES:")
    print("  a) Get a fresh API key at: https://aistudio.google.com/apikey")
    print("     (use your Google account, it's free)")
    print("  b) Make sure you're NOT using a Google Cloud Console key")
    print("     — only AI Studio keys (aistudio.google.com) work for free tier")
print("="*50 + "\n")

input("Press Enter to close...")
