# 🌿 Health Sprout — Personal Health Advisor

A personal health advisor powered by Google Gemini (free) with two modules:

- 🌱 **Sprout & Microgreens Advisor** — grow the best sprouts for your health goals
- 💪 **Body Recomposition Coach** — personalized workout plans with Fitbit integration

---

## Modules

### 🌱 Sprout & Microgreens Advisor
1. Understands your health goals (immunity, digestion, heart health, anti-inflammatory, and more)
2. Recommends the top 3 best-fit varieties for your goals, skill level, and budget
3. Finds seeds & equipment — cheapest and fastest vendor options
4. Provides complete day-by-day growing instructions from soak to harvest

### 💪 Body Recomposition Coach
1. Sets your goal — trim belly fat, build leg strength, improve endurance, and more
2. Collects your demographics — age, gender, height, weight, activity level, injuries
3. Builds your lifestyle profile — diet type, meal habits, sleep schedule
4. Optionally connects to **Fitbit** — pulls your actual steps, heart rate, sleep, and weight data
5. Delivers a personalized weekly workout plan with exercises, sets/reps, RPE targets, and nutrition tips

**Fitbit integration** uses OAuth 2.0 PKCE (the secure standard). Your Fitbit token is saved locally so you only authorize once. Future wearable support planned: Apple Watch, Samsung Watch, Garmin.

---

## Files

```
health_sprout/
├── 🌿 health_sprout_app.py         ← Main combined app (both modules)
├── 🌱 sprout_advisor.py            ← Sprout advisor standalone script
├── 📦 sprout-advisor.skill         ← Installable Claude skill package
├── 🌐 eval_review.html             ← Benchmark evaluation results
├── 🪟 build_windows.bat            ← Builds HealthSprout.exe on Windows
├── 🍎 build_mac.sh                 ← Builds HealthSprout binary on Mac
├── 🚀 run_HealthSprout.bat         ← Windows launcher (edit to add API key)
├── 📄 README.md                    ← This file
└── skill/
    ├── SKILL.md
    └── references/
        ├── health_benefits_guide.md
        └── growing_instructions.md
```

---

## Quick Start (Python)

```bash
# Install dependencies
pip install google-generativeai requests

# Run
python health_sprout_app.py
```

Get a free Gemini API key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey) — no credit card needed.

---

## Compiled App (No Python Required)

Build a standalone executable that anyone can run without installing Python.

### Windows
```
Double-click build_windows.bat
```
Produces `HealthSprout.exe`. Then:
1. Open `run_HealthSprout.bat` in Notepad
2. Replace `PASTE_YOUR_KEY_HERE` with your Gemini API key
3. Double-click `run_HealthSprout.bat` to launch anytime

### Mac
```bash
chmod +x build_mac.sh && ./build_mac.sh
```
Produces `HealthSprout` binary. Then:
```bash
export GEMINI_API_KEY="your_key_here"
./HealthSprout
```

> **First-run warnings are normal:**
> Windows SmartScreen → "More info" → "Run anyway"
> Mac Gatekeeper → System Settings → Privacy & Security → "Open Anyway"

---

## Fitbit Setup (for Body Recomposition Coach)

The app walks you through this, but here's a preview:

1. Go to [dev.fitbit.com/apps/new](https://dev.fitbit.com/apps/new) — free account
2. Create a **Personal** app with redirect URI: `http://localhost:8080/callback`
3. Copy your **Client ID** — paste it when the app asks
4. A browser window opens for you to authorize — click Allow
5. Done. Your token is saved; you won't need to re-authorize unless it expires.

Data pulled: daily steps (7-day), resting heart rate, sleep duration & efficiency (30-day), weight trend (30-day), user profile.

---

## Benchmark Results (Sprout Advisor)

Evaluated across 3 scenarios (anti-inflammatory, vegan energy, heart health):

| Metric | With Skill | Without Skill |
|--------|-----------|---------------|
| Pass Rate | **100%** | 72% |
| Avg Time | ~108s | ~49s |

---

## Sprout Varieties Covered

Broccoli · Radish · Sunflower · Pea Shoots · Mung Bean · Kale · Alfalfa · Red Cabbage · Buckwheat · Beet · Arugula · Amaranth · Cilantro · Wheatgrass · Fennel · Flaxseed

## Health Goals Covered

Immune Support · Gut Health · Energy & Vitality · Heart Health · Anti-Inflammatory · Detox & Liver · Weight Management · Bone Health · Cancer Prevention · General Nutrition

## Fitness Goals Covered

Fat Loss · Muscle Building · Cardiovascular Endurance · Post-Surgery Rehab · General Tone & Flexibility · Sport-Specific Strength
