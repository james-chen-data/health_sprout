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
  4. Copy your Client ID AND Client Secret — the script will ask for both
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


def fitbit_authorize(client_id: str, client_secret: str) -> dict | None:
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
    # Fitbit requires Basic auth: base64(client_id:client_secret)
    basic_auth = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    try:
        resp = req.post(FITBIT_TOKEN_URL,
            headers={
                "Authorization":  f"Basic {basic_auth}",
                "Content-Type":   "application/x-www-form-urlencoded",
            },
            data={
                "client_id":     client_id,
                "grant_type":    "authorization_code",
                "redirect_uri":  FITBIT_REDIRECT,
                "code":          code,
                "code_verifier": code_verifier,
            }, timeout=15)

        if resp.status_code == 200:
            token = resp.json()
            token["client_id"]     = client_id
            token["client_secret"] = client_secret
            return token
        else:
            print(f"\n❌ Token exchange failed ({resp.status_code}): {resp.text}\n")
            return None
    except Exception as e:
        print(f"\n❌ Token exchange error: {e}\n")
        return None


def fitbit_refresh(token: dict) -> dict | None:
    """Refresh an expired Fitbit access token."""
    client_id     = token.get("client_id", "")
    client_secret = token.get("client_secret", "")
    basic_auth    = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    try:
        resp = req.post(FITBIT_TOKEN_URL,
            headers={
                "Authorization": f"Basic {basic_auth}",
                "Content-Type":  "application/x-www-form-urlencoded",
            },
            data={
                "grant_type":    "refresh_token",
                "refresh_token": token["refresh_token"],
                "client_id":     client_id,
            }, timeout=15)
        if resp.status_code == 200:
            new_token = resp.json()
            new_token["client_id"]     = client_id
            new_token["client_secret"] = client_secret
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
    Fetch comprehensive health history from Fitbit.
    Handles token refresh automatically.
    Pulls 6 months of: steps, resting HR, weight, body fat, sleep, HRV, SpO2.
    """
    access = token["access_token"]
    data   = {}

    endpoints = {
        # Profile
        "profile":          "/1/user/-/profile.json",
        # Activity — 6 months of daily steps
        "steps_6m":         "/1/user/-/activities/steps/date/today/6m.json",
        # Resting heart rate — 6 months of daily values
        "heart_6m":         "/1/user/-/activities/heart/date/today/6m.json",
        # Weight — 6 months
        "weight_6m":        "/1/user/-/body/weight/date/today/6m.json",
        # Body fat % — 6 months
        "bodyfat_6m":       "/1/user/-/body/fat/date/today/6m.json",
        # BMI — 6 months
        "bmi_6m":           "/1/user/-/body/bmi/date/today/6m.json",
        # Sleep — last 30 nights (API limit per call)
        "sleep_30d":        "/1/user/-/sleep/date/today/1M.json",
        # SpO2 (blood oxygen) — 30 days; requires compatible device
        "spo2_30d":         "/1/user/-/spo2/date/today/1M.json",
        # HRV — 30 days; requires Fitbit Premium or compatible device
        "hrv_30d":          "/1/user/-/hrv/date/today/30d.json",
        # Breathing rate during sleep — 30 days
        "breathingrate_30d":"/1/user/-/br/date/today/30d.json",
    }

    print("   Fetching data", end="", flush=True)
    for key, ep in endpoints.items():
        result = fitbit_get(ep, access)
        if isinstance(result, dict) and result.get("_expired"):
            new_token = fitbit_refresh(token)
            if new_token:
                token.update(new_token)
                access = token["access_token"]
                result = fitbit_get(ep, access)
        if result and not result.get("_expired"):
            data[key] = result
        print(".", end="", flush=True)
    print(" done\n")

    return data


def summarise_fitbit(data: dict) -> str:
    """Convert rich Fitbit history into a structured text block for the LLM."""
    lines = ["=== FITBIT HEALTH HISTORY ==="]

    # ── Profile ───────────────────────────────────────────────────────────────
    profile = data.get("profile", {}).get("user", {})
    if profile:
        lines.append(
            f"Profile — Age: {profile.get('age','N/A')} | "
            f"Gender: {profile.get('gender','N/A')} | "
            f"Height: {profile.get('height','N/A')} cm | "
            f"Current weight: {profile.get('weight','N/A')} kg"
        )

    # ── Weight trend ──────────────────────────────────────────────────────────
    weight_logs = data.get("weight_6m", {}).get("body-weight", [])
    if weight_logs:
        vals = [(d["dateTime"], float(d["value"])) for d in weight_logs if d.get("value")]
        if vals:
            oldest_date, oldest_val = vals[0]
            latest_date, latest_val = vals[-1]
            change = latest_val - oldest_val
            lines.append(
                f"\nWeight — Latest: {latest_val} kg ({latest_date}) | "
                f"6-month change: {change:+.1f} kg (from {oldest_val} kg on {oldest_date})"
            )
            # Monthly averages
            from collections import defaultdict
            monthly: dict = defaultdict(list)
            for dt, v in vals:
                monthly[dt[:7]].append(v)
            monthly_avgs = {m: sum(vs)/len(vs) for m, vs in sorted(monthly.items())}
            lines.append("Monthly avg weight (kg): " + " | ".join(
                f"{m}: {v:.1f}" for m, v in monthly_avgs.items()
            ))

    # ── Body fat % ────────────────────────────────────────────────────────────
    fat_logs = data.get("bodyfat_6m", {}).get("body-fat", [])
    if fat_logs:
        fat_vals = [(d["dateTime"], float(d["value"])) for d in fat_logs if d.get("value")]
        if fat_vals:
            latest_fat_date, latest_fat = fat_vals[-1]
            oldest_fat = fat_vals[0][1]
            lines.append(
                f"Body Fat % — Latest: {latest_fat:.1f}% ({latest_fat_date}) | "
                f"6-month change: {latest_fat - oldest_fat:+.1f}%"
            )

    # ── BMI ───────────────────────────────────────────────────────────────────
    bmi_logs = data.get("bmi_6m", {}).get("body-bmi", [])
    if bmi_logs:
        latest_bmi = float(bmi_logs[-1]["value"])
        lines.append(f"BMI (latest): {latest_bmi:.1f}")

    # ── Resting heart rate trend ───────────────────────────────────────────────
    heart_logs = data.get("heart_6m", {}).get("activities-heart", [])
    if heart_logs:
        rhr_vals = [
            (d["dateTime"], d["value"].get("restingHeartRate"))
            for d in heart_logs
            if isinstance(d.get("value"), dict) and d["value"].get("restingHeartRate")
        ]
        if rhr_vals:
            latest_rhr_date, latest_rhr = rhr_vals[-1]
            oldest_rhr = rhr_vals[0][1]
            avg_rhr = sum(v for _, v in rhr_vals) // len(rhr_vals)
            lines.append(
                f"\nResting HR — Latest: {latest_rhr} bpm ({latest_rhr_date}) | "
                f"6-month avg: {avg_rhr} bpm | "
                f"6-month change: {latest_rhr - oldest_rhr:+d} bpm"
            )
            # Monthly averages
            from collections import defaultdict
            monthly_rhr: dict = defaultdict(list)
            for dt, v in rhr_vals:
                monthly_rhr[dt[:7]].append(v)
            lines.append("Monthly avg resting HR (bpm): " + " | ".join(
                f"{m}: {sum(vs)//len(vs)}" for m, vs in sorted(monthly_rhr.items())
            ))

    # ── HRV ───────────────────────────────────────────────────────────────────
    hrv_data = data.get("hrv_30d", {}).get("hrv", [])
    if hrv_data:
        hrv_vals = []
        for entry in hrv_data:
            for m in entry.get("minutes", []):
                rmssd = m.get("value", {}).get("rmssd")
                if rmssd:
                    hrv_vals.append((entry.get("dateTime", ""), float(rmssd)))
        if hrv_vals:
            avg_hrv = sum(v for _, v in hrv_vals) / len(hrv_vals)
            latest_hrv = hrv_vals[-1][1]
            lines.append(f"HRV (RMSSD) — Latest: {latest_hrv:.1f} ms | 30-day avg: {avg_hrv:.1f} ms")

    # ── SpO2 ──────────────────────────────────────────────────────────────────
    spo2_data = data.get("spo2_30d", {})
    spo2_list = spo2_data if isinstance(spo2_data, list) else spo2_data.get("dateRangeList", [])
    if spo2_list:
        spo2_vals = [
            float(d.get("value", {}).get("avg", 0) or d.get("avg", 0))
            for d in spo2_list
            if (d.get("value", {}).get("avg") or d.get("avg"))
        ]
        if spo2_vals:
            avg_spo2 = sum(spo2_vals) / len(spo2_vals)
            lines.append(f"SpO2 (blood oxygen) — 30-day avg: {avg_spo2:.1f}%")

    # ── Sleep ─────────────────────────────────────────────────────────────────
    sleep_logs = data.get("sleep_30d", {}).get("sleep", [])
    if sleep_logs:
        main_sleep = [s for s in sleep_logs if s.get("isMainSleep")]
        if main_sleep:
            avg_duration   = sum(s.get("duration", 0) for s in main_sleep) / len(main_sleep)
            avg_efficiency = sum(s.get("efficiency", 0) for s in main_sleep) / len(main_sleep)
            avg_hrs        = avg_duration / 3_600_000

            # Sleep stages breakdown (if available)
            deep_mins = rem_mins = light_mins = 0
            stage_count = 0
            for s in main_sleep:
                stages = s.get("levels", {}).get("summary", {})
                if stages:
                    deep_mins  += stages.get("deep",  {}).get("minutes", 0)
                    rem_mins   += stages.get("rem",   {}).get("minutes", 0)
                    light_mins += stages.get("light", {}).get("minutes", 0)
                    stage_count += 1

            lines.append(
                f"\nSleep (last {len(main_sleep)} nights) — "
                f"Avg: {avg_hrs:.1f} hrs | Efficiency: {avg_efficiency:.0f}%"
            )
            if stage_count:
                n = stage_count
                lines.append(
                    f"Avg sleep stages/night — Deep: {deep_mins//n} min | "
                    f"REM: {rem_mins//n} min | Light: {light_mins//n} min"
                )

            # Sleep HR during rest (from heartRateData if available)
            sleep_hr_vals = []
            for s in main_sleep[-7:]:
                hr_data = s.get("heartRateData", {})
                avg_hr = hr_data.get("averageHeartRate") or \
                         s.get("averageHeartRate")
                if avg_hr:
                    sleep_hr_vals.append(float(avg_hr))
            if sleep_hr_vals:
                avg_sleep_hr = sum(sleep_hr_vals) / len(sleep_hr_vals)
                lines.append(f"Avg sleeping HR (last 7 nights): {avg_sleep_hr:.0f} bpm")

    # ── Breathing rate ────────────────────────────────────────────────────────
    br_data = data.get("breathingrate_30d", {}).get("br", [])
    if br_data:
        br_vals = [
            float(d.get("value", {}).get("breathingRate", 0))
            for d in br_data
            if d.get("value", {}).get("breathingRate")
        ]
        if br_vals:
            avg_br = sum(br_vals) / len(br_vals)
            lines.append(f"Avg breathing rate during sleep (30d): {avg_br:.1f} breaths/min")

    # ── Steps ─────────────────────────────────────────────────────────────────
    steps_raw = data.get("steps_6m", {}).get("activities-steps", [])
    if steps_raw:
        active_days = [d for d in steps_raw if int(d.get("value", 0)) > 500]
        if active_days:
            avg_steps = sum(int(d["value"]) for d in active_days) // len(active_days)
            recent_7  = steps_raw[-7:]
            avg_recent = sum(int(d["value"]) for d in recent_7) // len(recent_7)
            lines.append(
                f"\nSteps — 7-day avg: {avg_recent:,} | "
                f"6-month avg (active days): {avg_steps:,}"
            )

    lines.append("\n=== END FITBIT DATA ===")
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


def run_chat(system_prompt: str, opening_instruction: str, label: str, api_key: str):
    """Generic multi-turn chat loop with a given system prompt."""
    client = genai.Client(api_key=api_key)

    chat = client.chats.create(
        model="gemini-2.5-flash",               # Free tier: 500 RPD, 10 RPM
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

def run_body_recomposition(api_key: str):
    print("\n" + "═" * 62)
    print("  💪  Body Recomposition Coach")
    print("═" * 62)

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
                print("  5. Click Save — then copy your Client ID and Client Secret\n")
                client_id     = input("Paste your Fitbit Client ID (or press Enter to skip): ").strip()
                client_secret = input("Paste your Fitbit Client Secret: ").strip() if client_id else ""

                if client_id and client_secret:
                    token = fitbit_authorize(client_id, client_secret)
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
        model="gemini-2.5-flash",               # Free tier: 500 RPD, 10 RPM
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
    # Ask for API key once at startup — reused for all modules
    api_key = get_api_key()

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
                api_key=api_key,
            )

        elif choice == "2":
            run_body_recomposition(api_key)

        elif choice in ("3", "q", "quit", "exit"):
            print("\n  Goodbye! Stay healthy. 🌿\n")
            break

        else:
            print("\n  Please enter 1, 2, or 3.\n")


if __name__ == "__main__":
    main()
