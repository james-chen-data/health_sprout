# 🌿 Health Sprout — Personal Health Advisor

A personal health advisor powered by Google Gemini (free) with two modules:

- 🌱 **Sprout & Microgreens Advisor** — grow the best sprouts for your health goals
- 💪 **Body Recomposition Coach** — personalized workout plans with Fitbit integration

---

## 📱 Flutter Mobile App (`health_sprout_mobile/`)

A Flutter app that syncs health data from **Health Connect (Android)** or **HealthKit (iOS)**, stores it in SQLite, and uses **Gemini AI** for personalised coaching.

### Features
- Syncs steps, sleep stages, resting HR, HRV, SpO2, weight, body fat, active calories, breathing rate
- AI advisors (Body Recomposition, Recovery, Nutrition) using your real health history
- 7/30/90-day trend charts with stats for every metric
- Unit preferences — lbs/kg and in/cm
- Smart source filtering — prefers wearable (Fitbit) data over phone sensor / Google Fit
- Debug view (🐛 icon) to inspect which apps are writing each record

### Quick Start (Android)

**Prerequisites:** Flutter SDK 3.3+, Android device with Health Connect installed

```bash
git clone https://github.com/james-chen-data/health_sprout.git
cd health_sprout/health_sprout_mobile
flutter pub get
flutter run
```

1. Tap **⚙️ Settings** → enter your Gemini API key (free at [aistudio.google.com](https://aistudio.google.com/))
2. Tap **Sync Health Connect Data** and grant permissions
3. Data syncs up to 6 months of history

**For best accuracy with Fitbit:** In the Health Connect app → Data sources and priority → set **Fitbit** as source #1 for Steps, Sleep, and Activity.

### Porting to iOS (HealthKit)

The `health` package supports both platforms with the same Dart API. Here's what needs attention:

**1. Info.plist — add usage descriptions** (required or Apple will reject the app)
```xml
<key>NSHealthShareUsageDescription</key>
<string>Health Sprout reads your health data to provide personalised coaching.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>Health Sprout does not write health data.</string>
```

**2. Xcode — enable HealthKit capability**
- Open `ios/Runner.xcworkspace` in Xcode
- Runner target → Signing & Capabilities → **+ Capability → HealthKit**

**3. Re-enable WORKOUT type** (disabled on Android due to a SecurityException bug on Pixel + Android 16)

In `health_service.dart`, add `HealthDataType.WORKOUT` to the `_types` list.

**4. Update source filtering** for Apple Watch users

In `health_service.dart`, update `_isFitbit()` → rename to `_isPreferredWearable()` and add:
```dart
name.contains('apple watch') || id.contains('com.apple.health')
```

**5. No AndroidManifest needed** — iOS permissions are handled entirely at runtime via `requestAuthorization()`.

### Project Structure
```
health_sprout_mobile/lib/
├── main.dart
├── ai/gemini_service.dart       # Gemini 2.5 Flash API
├── db/database.dart             # SQLite schema & queries
├── health/health_service.dart   # Health Connect / HealthKit sync
├── models/
│   ├── health_metric.dart       # Metric type constants & labels
│   └── unit_prefs.dart          # Unit conversion (kg↔lbs, cm↔in)
└── screens/
    ├── home_screen.dart         # Dashboard
    ├── metrics_screen.dart      # Trend charts
    ├── chat_screen.dart         # AI coach chat
    └── settings_screen.dart     # API key & preferences
```

### Known Limitations

| Issue | Detail |
|---|---|
| Resting HR differs from Fitbit app | Fitbit uses a proprietary algorithm; Health Connect provides the raw measured value |
| Sleep duration slightly lower than Fitbit app | Fitbit's internal "Time Asleep" includes data not fully exposed via Health Connect |
| Step sync lag (~100 steps) | Fitbit syncs to Health Connect periodically, not in real-time |
| WORKOUT disabled on Android | SecurityException on Pixel + Android 16 despite permissions granted; works fine on iOS |
| HEART_RATE excluded | Per-second data over 6 months causes OutOfMemoryError on both platforms; use resting HR + HRV instead |

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
