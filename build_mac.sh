#!/bin/bash
# ============================================================
#  Health Sprout -- Mac Build Script
#  Run this once to create a standalone app you can share.
# ============================================================

set -e  # Stop on any error

echo ""
echo " ============================================"
echo "  Sprout Advisor -- Mac Build Script"
echo " ============================================"
echo ""

# ── Step 1: Check Python is available ──────────────────────────────────────
if ! command -v python3 &>/dev/null; then
    echo "[ERROR] Python3 not found."
    echo ""
    echo "Please install Python from https://python.org/downloads"
    echo "Or via Homebrew: brew install python"
    echo ""
    exit 1
fi

echo "[1/4] Python3 found: $(python3 --version)"

# ── Step 2: Install required packages ──────────────────────────────────────
echo "[2/4] Installing packages (this may take a minute)..."
pip3 install pyinstaller google-genai requests --quiet
echo "      Done."

# ── Step 3: Build the binary ────────────────────────────────────────────────
echo "[3/4] Building HealthSprout binary..."
echo "      (This takes 1-3 minutes the first time)"
echo ""

pyinstaller \
    --onefile \
    --name "HealthSprout" \
    --clean \
    health_sprout_app.py

echo ""

# ── Step 4: Copy binary to current folder ──────────────────────────────────
echo "[4/4] Copying HealthSprout here..."
cp dist/HealthSprout .
chmod +x HealthSprout

echo ""
echo " ============================================"
echo "  SUCCESS!  HealthSprout is ready."
echo " ============================================"
echo ""
echo "  HOW TO RUN:"
echo "  -----------"
echo "  Set your API key once in your shell profile:"
echo "    echo 'export GEMINI_API_KEY=\"your_key_here\"' >> ~/.zshrc"
echo "    source ~/.zshrc"
echo "    Then run: ./HealthSprout"
echo ""
echo "  Or run with key inline:"
echo "    GEMINI_API_KEY=your_key_here ./HealthSprout"
echo ""
echo "  Get your FREE API key at: https://aistudio.google.com/apikey"
echo ""
echo "  NOTE: On first run, Mac may say 'unverified developer'."
echo "  To allow it: System Settings → Privacy & Security → 'Open Anyway'"
echo "  Or right-click the file → Open → Open."
echo ""

# ── Clean up build artifacts ────────────────────────────────────────────────
echo "Cleaning up build files..."
rm -rf dist build HealthSprout.spec __pycache__

echo "Done!"
