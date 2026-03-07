#!/usr/bin/env python3
"""
🌿 Health Sprout — Personal Health Advisor
Powered by Google Gemini (free tier)

Modules:
  1. 🌱 Sprout & Microgreens Growing Advisor
  2. 💪 Body Recomposition Coach  (with Fitbit integration)

SETUP:
  1. Get a FREE Gemini API key: https://aistudio.google.com/apikey
  2. Install packages:  pip install google-genai requests
  3. Run:              python health_sprout_app.py

For Fitbit integration (optional):
  1. Go to https://dev.fitbit.com/apps/new and register a free "Personal" app
  2. Set OAuth 2.0 Application Type: "Personal"
  3. Set Redirect URI: http://localhost:8080/callback
  4. Copy your Client ID — the script will ask for it
"""

import os
import sys
import json
import webbrowser
import threading
import secrets
import hashlib
import base64
import urllib.parse
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

# ── Package checks ─────────────────────────────────────────────────────────────
try:
    from google import genai
    from google.genai import types as genai_types
except ImportError:
    print("\n❌ Missing package. Please run:\n\n   pip install google-genai requests\n")
    sys.exit(1)

try:
    import requests as req
    REQUESTS_AVAILABLE = True
except ImportError:
    REQUESTS_AVAILABLE = False

# ── Config (stores Fitbit tokens between sessions) ─────────────────────────────
CONFIG_PATH = Path.home() / ".health_sprout_config.json"

def load_config():
    if CONFIG_PATH.exists():
        try:
            with open(CONFIG_PATH) as f:
                return json.load(f)
        except Exception:
            pass
    return {}

def save_config(config):
    try:
        with open(CONFIG_PATH, "w") as f:
            json.dump(config, f, indent=2)
    except Exception:
        pass


# ══════════════════════════════════════════════════════════════════════════════
#  FITBIT INTEGRATION
# ══════════════════════════════════════════════════════════════════════════════

FITBIT_AUTH_URL   = "https://www.fitbit.com/oauth2/authorize"
FITBIT_TOKEN_URL  = "https://api.fitbit.com/oauth2/token"
FITBIT_API_BASE   = "https://api.fitbit.com"
FITBIT_REDIRECT   = "http://localhost:8080/callback"
FITBIT_SCOPES     = "activity heartrate sleep weight profile"


class _OAuthCallbackHandler(BaseHTTPRequestHandler):
    """Minimal HTTP handler that captures the Fitbit OAuth callback."""
    auth_code  = None
    auth_error = None

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        params = urllib.parse.parse_qs(parsed.query)
        _OAuthCallbackHandler.auth_code  = params.get("code",  [None])[0]
        _OAuthCallbackHandler.auth_error = params.get("error", [None])[0]

        self.send_response(200)
        self.send_header("Content-type", "text/html; charset=utf-8")
        self.end_headers()
        if _OAuthCallbackHandler.auth_code:
            body = b"""<html><body style="font-family:sans-serif;padding:40px;text-align:center">
            <h2 style="color:#2e7d32">&#x2705; Fitbit Connected!</h2>
            <p>You can close this window and return to the terminal.</p>
            </body></html>"""
        else:
            body = b"""<html><body style="font-family:sans-serif;padding:40px;text-align:center">
            <h2 style="color:#c62828">&#x274C; Authorization Failed</h2>
            <p>Please return to the terminal for details.</p>
            </body></html>"""
        self.wfile.write(body)

    def log_message(self, *args):
        pass  # suppress console noise


def fitbit_authorize(client_id: str) -> dict | None:
    """
    Run the Fitbit OAuth 2.0 PKCE flow.
    Returns a token dict {access_token, refresh_token, user_id, ...} or None.
    """
    if not REQUESTS_AVAILABLE:
        print("\n⚠️  The 'requests' package is required for Fitbit. Run: pip install requests\n")
        return None

    # Generate PKCE pair
    code_verifier  = secrets.token_urlsafe(64)
    code_challenge = base64.urlsafe_b64encode(
        hashlib.sha256(code_verifier.encode()).digest()
    ).rstrip(b"=").decode()

    # Build authorization URL
    auth_params = {
        "client_id":             client_id,
        "response_type":         "code",
        "code_challenge":        code_challenge,
        "code_challenge_method": "S256",
        "redirect_uri":          FITBIT_REDIRECT,
        "scope":                 FITBIT_SCOPES,
    }
    auth_url = FITBIT_AUTH_URL + "?" + urllib.parse.urlencode(auth_params)

    # Reset handler state
    _OAuthCallbackHandler.auth_code  = None
    _OAuthCallbackHandler.auth_error = None

    # Start one-shot local server on port 8080
    try:
        server = HTTPServer(("localhost", 8080), _OAuthCallbackHandler)
    except OSError:
        print("\n⚠️  Port 8080 is busy. Close any other app using it and try again.\n")
        return None

    server_thread = threading.Thread(target=server.handle_request)
    server_thread.daemon = True
    server_thread.start()

    print("\n🌐 Opening Fitbit authorization in your browser...")
    print("   Authorize the app, then come back here.\n")
    print(f"   (If browser doesn't open, paste this URL manually:\n   {auth_url})\n")
    webbrowser.open(auth_url)

    server_thread.join(timeout=180)   # Wait up to 3 minutes

    if _OAuthCallbackHandler.auth_error:
        print(f"\n❌ Fitbit authorization error: {_OAuthCallbackHandler.auth_error}\n")
        return None

    code = _OAuthCallbackHandler.auth_code
    if not code:
        print("\n❌ No authorization code received. Did you complete the authorization?\n")
        return None

    # Exchange code for tokens
    try:
        resp = req.post(FITBIT_TOKEN_URL, data={
            "client_id":     client_id,
            "grant_type":    "authorization_code",
            "redirect_uri":  FITBIT_REDIRECT,
            "code":          code,
            "code_verifier": code_verifier,
        }, timeout=15)

        if resp.status_code == 200:
            token = resp.json()
            token["client_id"] = client_id
            return token
        else:
            print(f"\n❌ Token exchange failed ({resp.status_code}): {resp.text}\n")
            return None
    except Exception as e:
        print(f"\n❌ Token exchange error: {e}\n")
        return None


def fitbit_refresh(token: dict) -> dict | None:
    """Refresh an expired Fitbit access token."""
    try:
        resp = req.post(FITBIT_TOKEN_URL, data={
            "grant_type":    "refresh_token",
            "refresh_token": token["refresh_token"],
            "client_id":     token.get("client_id", ""),
        }, timeout=15)
        if resp.status_code == 200:
            new_token = resp.json()
            new_token["client_id"] = token.get("client_id", "")
            return new_token
    except Exception:
        pass
    return None


def fitbit_get(endpoint: str, access_token: str) -> dict | None:
    """Make a single Fitbit API GET request."""
    try:
        resp = req.get(
            FITBIT_API_BASE + endpoint,
            headers={"Authorization": f"Bearer {access_token}"},
            timeout=15,
        )
        if resp.status_code == 200:
            return resp.json()
        if resp.status_code == 401:
            return {"_expired": True}
    except Exception:
        pass
    return None


def fetch_fitbit_summary(token: dict) -> dict:
    """
    Fetch a health summary from Fitbit.
    Handles token refresh automatically.
    Returns a dict with keys: profile, steps_7d, sleep_30d, weight_30d, heart_today.
    """
    access = token["access_token"]
    data   = {}

    endpoints = {
        "profile":     "/1/user/-/profile.json",
        "steps_7d":    "/1/user/-/activities/steps/date/today/7d.json",
        "sleep_30d":   "/1/user/-/sleep/date/today/1M.json",
        "weight_30d":  "/1/user/-/body/weight/date/today/1M.json",
        "heart_today": "/1/user/-/activities/heart/date/today/1d.json",
    }

    for key, ep in endpoints.items():
        result = fitbit_get(ep, access)
        if isinstance(result, dict) and result.get("_expired"):
            # Try to refresh once
            new_token = fitbit_refresh(token)
            if new_token:
                token.update(new_token)
                access = token["access_token"]
                result = fitbit_get(ep, access)
        if result and not result.get("_expired"):
            data[key] = result

    return data


def summarise_fitbit(data: dict) -> str:
    """Convert raw Fitbit JSON into a concise text block for the LLM."""
    lines = ["=== FITBIT HEALTH DATA ==="]

    # Profile
    profile = data.get("profile", {}).get("user", {})
    if profile:
        lines.append(f"Age: {profile.get('age', 'N/A')}  |  "
                     f"Gender: {profile.get('gender', 'N/A')}  |  "
                     f"Height: {profile.get('height', 'N/A')} cm  |  "
                     f"Weight: {profile.get('weight', 'N/A')} kg")
        lines.append(f"Member since: {profile.get('memberSince', 'N/A')}")

    # Steps (last 7 days)
    steps_raw = data.get("steps_7d", {}).get("activities-steps", [])
    if steps_raw:
        avg_steps = sum(int(d.get("value", 0)) for d in steps_raw) // max(len(steps_raw), 1)
        lines.append(f"\n7-Day Avg Daily Steps: {avg_steps:,}")
        lines.append("Daily breakdown: " + ", ".join(
            f"{d['dateTime']}: {int(d['value']):,}" for d in steps_raw
        ))

    # Resting heart rate
    heart = data.get("heart_today", {}).get("activities-heart", [])
    if heart:
        rhr = heart[-1].get("value", {}).get("restingHeartRate", "N/A")
        lines.append(f"\nResting Heart Rate (today): {rhr} bpm")

    # Sleep (last 30 days — summarise averages)
    sleep_logs = data.get("sleep_30d", {}).get("sleep", [])
    if sleep_logs:
        recent = sleep_logs[-7:]  # last 7 nights
        avg_duration = sum(s.get("duration", 0) for s in recent) // max(len(recent), 1)
        avg_efficiency = sum(s.get("efficiency", 0) for s in recent) // max(len(recent), 1)
        avg_hrs = avg_duration / 3_600_000
        lines.append(f"\n7-Night Avg Sleep: {avg_hrs:.1f} hrs/night  |  Efficiency: {avg_efficiency}%")

    # Weight trend (last 30 days)
    weight_logs = data.get("weight_30d", {}).get("body-weight", [])
    if weight_logs:
        latest = float(weight_logs[-1]["value"])
        oldest = float(weight_logs[0]["value"])
        trend  = latest - oldest
        lines.append(f"\nWeight (latest): {latest} kg  |  30-day change: {trend:+.1f} kg")

    lines.append("=========================")
    return "\n".join(lines)


# ══════════════════════════════════════════════════════════════════════════════
#  SYSTEM PROMPTS
# ══════════════════════════════════════════════════════════════════════════════

SPROUT_SYSTEM_PROMPT = """
You are a knowledgeable, friendly Sprouts & Microgreens Growing Advisor. You help
users grow the best sprouts and microgreens for their personal health goals. Walk
them through a natural conversation that ends with a complete, personalized growing
plan — from seed selection all the way to harvest.

Work through these four stages in order:

STAGE 1 — UNDERSTAND HEALTH GOALS
Ask warmly about their health goals. Examples: immune support, gut health, energy,
heart health, anti-inflammatory, detox, weight management, bone health, cancer
prevention, general nutrition.
Also ask: specific condition or general wellness? Dietary restrictions/allergies?
Beginner or experienced? Budget? Simple jar sprouting or open to soil-based trays?
If they mention medical context (post-surgery, medications), ask if they're on blood
thinners like warfarin — some microgreens are high in Vitamin K and can interact.

STAGE 2 — RECOMMEND TOP 3 VARIETIES
Pick the 3 best-matched varieties. For each:
🌱 #N: [Name]
Why it's perfect for you: [1-2 personalized sentences]
Key nutrients: [list]
Difficulty: ⭐ Easy / ⭐⭐ Moderate / ⭐⭐⭐ Intermediate
Time to harvest: X–X days  |  Form: Sprout / Microgreen / Both
After all 3, explain tradeoffs. Then ask: "Ready to find where to buy and walk through setup?"

STAGE 3 — SEEDS & EQUIPMENT
Vendors: True Leaf Market (trueleafmarket.com), Organo Republic (organorepublic.com),
Sow Right Seeds (sowrightseeds.com). Provide Cheapest and Fastest option per variety.
Equipment: Minimal ~$15-30 (mason jar, spray bottle, container, soil near a sunny window).
Starter kit ~$50-80 (Bootstrap Farmer trays, coco coir, LED grow light). Amazon fastest.

STAGE 4 — STEP-BY-STEP GROWING INSTRUCTIONS
For each variety: full day-by-day timeline, seeding density, daily care, harvest cues,
storage, troubleshooting (mold, leggy growth, slow germination).

VARIETY REFERENCE BY HEALTH GOAL:
Immune: Broccoli (sulforaphane, Vit C/E), Kale (Vit A/C/K), Sunflower (Vit E, zinc), Alfalfa
Gut: Fenugreek (enzymes), Radish (bile), Pea Shoots (fiber), Mung Bean (prebiotic)
Energy: Sunflower (complete amino acids, B vits), Pea Shoots (protein), Buckwheat (rutin)
Heart: Broccoli (arterial inflammation), Beet (nitrates→nitric oxide), Buckwheat (rutin, capillaries), Sunflower (Vit E)
Anti-inflammatory: Broccoli Sprouts (10-100x sulforaphane vs mature), Red Cabbage (anthocyanins), Arugula (quercetin)
Detox: Broccoli Sprout (Phase 2 liver detox), Cilantro (heavy-metal chelation), Sunflower (chlorophyll)
Weight: Pea Shoots (high fiber/protein/low cal), Kale (low cal), Mung Bean (protein, low fat)
Bone: Kale (Vit K1/K2, Ca, Mg), Arugula (Vit K), Alfalfa (Vit K, silicon)
Cancer: Broccoli Sprout (sulforaphane), Red Cabbage (anthocyanins 6x mature), Kale (glucosinolates)

DIFFICULTY & HARVEST TIMES:
Radish: ⭐ Easiest | 5-7 days | Pea Shoots: ⭐ Easiest | 8-12 days
Mung Bean: ⭐ Easiest | 3-5 days (jar) | Sunflower: ⭐⭐ Easy | 10-14 days
Broccoli: ⭐⭐ Easy | 3-4 days sprout / 8-12 days micro | Alfalfa: ⭐⭐ Easy | 5-6 days
Kale: ⭐⭐ Easy | 8-12 days | Buckwheat: ⭐⭐ Easy | 8-12 days
Beet: ⭐⭐ Moderate | 10-14 days | Arugula: ⭐⭐ Moderate | 7-10 days

JAR SPROUTING (broccoli, alfalfa, mung bean):
Day 0 eve: Rinse 2 tbsp seeds, soak 8-12 hrs. Day 1: drain, invert jar 45° in bowl.
Rinse & drain every 12 hrs for 3-4 days. Harvest at ½–1 inch tails.
Refrigerate in loose-lid jar, use within 5-7 days.

TRAY MICROGREENS (universal):
Day 0: Soak seeds, fill tray with 1-1.5" moist soil, spread seeds, mist.
Day 1-4 BLACKOUT: Cover with tray/dome. Day 4-5: Uncover, move to light, bottom-water.
Day 5-8 GREENING: Water from below daily. Day 8-14 HARVEST: cut above soil line.
Rinse, pat dry, store airtight with paper towel in fridge, 5-7 days.

STYLE: Warm, encouraging. Pause between stages. If overwhelmed, suggest starting with ONE variety.
Food safety: sprouts have slightly higher bacteria risk — use filtered water, rinse 2x/day, clean equipment.
"""


BODY_RECOMPOSITION_SYSTEM_PROMPT = """
You are an expert personal fitness coach and body recomposition specialist.
Your approach is science-based, highly personalized, encouraging, realistic,
and safety-first. Always recommend consulting a doctor before starting a new
exercise program, especially for anyone with a medical history.

Work through these stages in order:

STAGE 1 — GOAL SETTING
Ask what body recomposition goal they want to work toward. Examples:
- Trim belly / tummy fat
- Build leg strength
- Improve upper body muscle
- Lose weight overall
- Improve cardiovascular endurance
- General tone and flexibility
- Post-surgery gentle rehabilitation
Keep it conversational. If they say something vague like "get fit", ask what
that looks like to them in 3 months.

STAGE 2 — DEMOGRAPHICS
Collect: age, gender, height, weight, current activity level
(sedentary / lightly active / moderately active / very active).
Also ask: any injuries, physical limitations, or medical conditions?
(e.g., post-CABG, bad knees, back pain — this shapes exercise selection significantly)
Calculate BMI and estimated TDEE silently — use them to personalize without lecturing.

STAGE 3 — LIFESTYLE PROFILE
Food profile:
- Diet type (omnivore, vegetarian, vegan, keto, Mediterranean, etc.)
- Meals per day / do they track calories?
- Protein supplements? Food allergies?
Sleep profile:
- Hours per night on average?
- Consistent schedule? Feel rested?
(Sleep is critical for recovery — affects how many training days per week are appropriate)

STAGE 4 — FITBIT DATA (if provided)
If a FITBIT HEALTH DATA block is provided in the conversation, use it to:
- Reference their actual step count, active minutes, and resting heart rate
- Acknowledge their sleep patterns and adjust recovery day recommendations
- Note their weight trend over the past month
- Use resting heart rate as a cardiovascular fitness indicator
Cite specific numbers naturally: "Based on your Fitbit data, you're averaging X steps
per day and your resting heart rate of Y bpm suggests [good/moderate/needs work]
cardiovascular fitness..."
If no Fitbit data: skip this section.

STAGE 5 — PERSONALIZED WEEKLY WORKOUT PLAN
Generate a 7-day plan appropriate for their goal, experience level, available time,
and any physical limitations. Format EXACTLY like this:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📅 YOUR PERSONALIZED WEEKLY WORKOUT PLAN
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🏋️ MONDAY — [Muscle Group / Session Type]
─────────────────────────────────────
Warm-up (5-10 min): [specific activities]

1. [Exercise Name]
   • Sets × Reps: 3 × 12  |  Rest: 60 sec
   • 💡 Tip: [key form cue]

2. [Exercise Name]
   [same format]

Cool-down (5-10 min): [specific stretches]
⏱ Duration: ~45 min  |  🎯 RPE Target: 7/10

[Repeat for each day — mark rest/recovery days clearly]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

After the plan, add:
📊 NUTRITION GUIDANCE (2-3 specific tips based on their food profile & goal)
😴 RECOVERY TIPS (sleep & rest guidance)
📈 PROGRESSION NOTES (when and how to increase intensity)

PERSONALIZATION RULES:
- Fat loss: compound movements + cardio + caloric deficit awareness.
  3-4 sessions/week is optimal for beginners; don't prescribe 6 days.
- Muscle building: progressive overload, protein target (1.6-2.2g/kg), sleep priority.
- Post-CABG or medical history: START VERY GENTLE. Walking, light stretching,
  breathing exercises. Always recommend cardiologist clearance before any resistance work.
- Beginners: 3-day full body > complicated 6-day split.
- No gym? Design bodyweight-only or minimal equipment plan.
- Ask about equipment availability before finalizing the plan.

STYLE: Warm, encouraging, realistic. Celebrate effort over perfection.
After delivering the plan, ask: "Would you like me to adjust anything —
fewer days, different equipment, or any exercises to swap out?"
"""


# ══════════════════════════════════════════════════════════════════════════════
#  CHAT HELPERS
# ══════════════════════════════════════════════════════════════════════════════

def get_api_key() -> str:
    key = os.environ.get("GEMINI_API_KEY", "").strip()
    if not key:
        print("\nPaste your Gemini API key below.")
        print("(Get one free at: https://aistudio.google.com/apikey)\n")
        key = input("API Key: ").strip()
    if not key:
        print("No API key provided. Exiting.")
        sys.exit(1)
    return key


def run_chat(system_prompt: str, opening_instruction: str, label: str):
    """Generic multi-turn chat loop with a given system prompt."""
    api_key = get_api_key()
    client = genai.Client(api_key=api_key)

    chat = client.chats.create(
        model="gemini-1.5-flash",               # Free tier: 15 RPM, 1,500 req/day
        config=genai_types.GenerateContentConfig(
            system_instruction=system_prompt,
        ),
    )

    print(f"\nType your message and press Enter. Type 'quit' to go back to the menu.\n")
    print("─" * 62)

    try:
        intro = chat.send_message(opening_instruction)
        print(f"\n{label}:\n{intro.text}\n")
    except Exception as e:
        print(f"\n❌ Could not connect to Gemini API: {e}")
        print("Check your API key and internet connection.\n")
        return

    while True:
        print("─" * 62)
        try:
            user_input = input("You: ").strip()
        except (KeyboardInterrupt, EOFError):
            break
        if not user_input:
            continue
        if user_input.lower() in ("quit", "exit", "q", "back", "menu"):
            print("\nReturning to main menu...\n")
            break
        try:
            response = chat.send_message(user_input)
            print(f"\n{label}:\n{response.text}\n")
        except Exception as e:
            print(f"\n⚠️  Error: {e}\nTry again.\n")


# ══════════════════════════════════════════════════════════════════════════════
#  MODULE 2 — BODY RECOMPOSITION WITH FITBIT
# ══════════════════════════════════════════════════════════════════════════════

def run_body_recomposition():
    print("\n" + "═" * 62)
    print("  💪  Body Recomposition Coach")
    print("═" * 62)

    api_key = get_api_key()

    # ── Fitbit setup ──────────────────────────────────────────────────────────
    fitbit_summary = ""
    config = load_config()

    print("\n🏃 Do you want to connect your Fitbit for personalized insights?")
    print("   (Your activity, heart rate, sleep & weight data will be used)")
    print("   [y] Yes   [n] No, skip\n")
    use_fitbit = input("Choice: ").strip().lower()

    if use_fitbit == "y":
        if not REQUESTS_AVAILABLE:
            print("\n⚠️  Install 'requests' to use Fitbit: pip install requests\n")
        else:
            # Check for saved token
            saved_token = config.get("fitbit_token")
            fitbit_data  = None

            if saved_token:
                print("\n✅ Found saved Fitbit connection. Fetching your data...")
                fitbit_data = fetch_fitbit_summary(saved_token)
                config["fitbit_token"] = saved_token   # save refreshed token
                save_config(config)

            if not fitbit_data:
                # Need fresh authorization
                print("\n📋 FITBIT SETUP")
                print("─" * 40)
                print("You need a free Fitbit Developer app (takes 2 min):")
                print("  1. Go to https://dev.fitbit.com/apps/new")
                print("  2. Fill in any app name (e.g. 'My Health App')")
                print("  3. Set 'OAuth 2.0 Application Type' = Personal")
                print("  4. Set 'Redirect URI' = http://localhost:8080/callback")
                print("  5. Click Save — then copy your Client ID\n")
                client_id = input("Paste your Fitbit Client ID (or press Enter to skip): ").strip()

                if client_id:
                    token = fitbit_authorize(client_id)
                    if token:
                        print("\n✅ Fitbit connected! Fetching your health data...")
                        fitbit_data = fetch_fitbit_summary(token)
                        config["fitbit_token"] = token
                        save_config(config)
                        print("✅ Data fetched. Your Fitbit connection is saved for next time.\n")
                    else:
                        print("\n⚠️  Fitbit connection failed. Continuing without it.\n")

            if fitbit_data:
                fitbit_summary = "\n\n" + summarise_fitbit(fitbit_data)
                print("✅ Fitbit data ready — I'll incorporate it into your plan.\n")

    # ── Build system prompt (inject Fitbit data if available) ─────────────────
    full_system = BODY_RECOMPOSITION_SYSTEM_PROMPT
    if fitbit_summary:
        full_system += f"\n\nFITBIT DATA FOR THIS SESSION:\n{fitbit_summary}"

    # ── Start conversation ────────────────────────────────────────────────────
    client = genai.Client(api_key=api_key)
    chat = client.chats.create(
        model="gemini-1.5-flash",               # Free tier: 15 RPM, 1,500 req/day
        config=genai_types.GenerateContentConfig(
            system_instruction=full_system,
        ),
    )

    opening = (
        "Greet the user warmly. If Fitbit data is available in your context, "
        "briefly acknowledge it (e.g. 'I can already see some of your health data '). "
        "Then ask what body recomposition goal they want to work toward, "
        "giving a few examples to spark ideas."
    )

    print("\nType your message and press Enter. Type 'quit' to go back to the menu.\n")
    print("─" * 62)

    try:
        intro = chat.send_message(opening)
        print(f"\n💪 Coach:\n{intro.text}\n")
    except Exception as e:
        print(f"\n❌ Could not connect to Gemini API: {e}\n")
        return

    while True:
        print("─" * 62)
        try:
            user_input = input("You: ").strip()
        except (KeyboardInterrupt, EOFError):
            break
        if not user_input:
            continue
        if user_input.lower() in ("quit", "exit", "q", "back", "menu"):
            print("\nReturning to main menu...\n")
            break
        try:
            response = chat.send_message(user_input)
            print(f"\n💪 Coach:\n{response.text}\n")
        except Exception as e:
            print(f"\n⚠️  Error: {e}\nTry again.\n")


# ══════════════════════════════════════════════════════════════════════════════
#  MAIN MENU
# ══════════════════════════════════════════════════════════════════════════════

def main():
    while True:
        print("\n" + "═" * 62)
        print("  🌿  HEALTH SPROUT — Personal Health Advisor")
        print("      Powered by Google Gemini (free)")
        print("═" * 62)
        print()
        print("  1. 🌱  Sprout & Microgreens Advisor")
        print("         Find the best sprouts for your health goals")
        print()
        print("  2. 💪  Body Recomposition Coach")
        print("         Personalized workout plan  +  Fitbit integration")
        print()
        print("  3. 🚪  Exit")
        print()

        choice = input("  Choose (1 / 2 / 3): ").strip()

        if choice == "1":
            print("\n" + "═" * 62)
            print("  🌱  Sprout & Microgreens Advisor")
            print("═" * 62)
            run_chat(
                system_prompt=SPROUT_SYSTEM_PROMPT,
                opening_instruction=(
                    "Introduce yourself warmly as a Sprouts & Microgreens Growing Advisor. "
                    "Ask the user what health outcomes they're hoping to support by growing "
                    "their own sprouts or microgreens, giving a few examples."
                ),
                label="🌱 Advisor",
            )

        elif choice == "2":
            run_body_recomposition()

        elif choice in ("3", "q", "quit", "exit"):
            print("\n  Goodbye! Stay healthy. 🌿\n")
            break

        else:
            print("\n  Please enter 1, 2, or 3.\n")


if __name__ == "__main__":
    main()
