# 🌱 Sprout Advisor — Claude Skill

A Claude skill that acts as a personalized **Sprouts & Microgreens Growing Advisor**. It guides users from health goals all the way to harvest with tailored recommendations, vendor sourcing, and step-by-step growing instructions.

## What It Does

1. **Understands your health goals** — immunity, digestion, energy, heart health, anti-inflammatory, detox, weight management, and more
2. **Recommends the top 3 best-fit varieties** — matched to your specific goals, skill level, and budget
3. **Finds seeds & equipment** — searches for the cheapest and fastest vendor options in real time
4. **Provides complete growing instructions** — day-by-day timelines from soak to harvest, with storage and troubleshooting tips

## Files

```
health_sprout/
├── sprout-advisor.skill          # Installable Claude skill package
├── eval_review.html              # Benchmark evaluation review (open in browser)
├── README.md                     # This file
└── skill/
    ├── SKILL.md                  # Main skill instructions and workflow
    └── references/
        ├── health_benefits_guide.md   # Variety → health goal mapping table
        └── growing_instructions.md    # Detailed growing specs per variety
```

## How to Install

Double-click `sprout-advisor.skill` to install into your Claude desktop app, or manually copy the `skill/` folder into your Claude skills directory.

## Benchmark Results

Evaluated across 3 test scenarios (anti-inflammatory beginner, vegan energy, heart health elderly):

| Metric | With Skill | Without Skill |
|--------|-----------|---------------|
| Pass Rate | **100%** | 72% |
| Time | ~108s | ~49s |

The skill trades some speed for significantly better completeness — day-by-day timelines, personalized vendor search, and acknowledgment of existing equipment are the key differentiators.

## Varieties Covered

Broccoli, Radish, Sunflower, Pea Shoots, Mung Bean, Kale, Alfalfa, Red Cabbage, Buckwheat, Beet, Arugula, Amaranth, Cilantro, Wheatgrass, Fennel, Flaxseed, and more.

## Health Goals Covered

Immune Support · Gut Health · Energy & Vitality · Heart Health · Anti-Inflammatory · Detox & Liver · Weight Management · Bone Health · Cancer Prevention · General Nutrition
