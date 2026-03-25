# Sandstorm Telemetry Analysis

**Date:** 2026-03-25
**Song:** Darude - Sandstorm (136 BPM, E Minor, 3:50)
**Recording:** 225 seconds, 224 samples at 1s intervals

## Song Structure Reference

| Section | Song Time | Recording Time | Description |
|---|---|---|---|
| Intro | 0:00-0:25 | t=4-29 | Synth pad strings, sparse drums, atmospheric |
| Build 1 | 0:25-0:42 | t=29-46 | Filter sweep rising, iconic riff emerges |
| **First Drop** | 0:42-1:27 | t=46-91 | Full kick+synth riff, peak energy section |
| Breakdown | 1:27-2:00 | t=91-124 | Energy pulls back, arpeggio, atmospheric |
| Build 2 | 2:00-2:30 | t=124-154 | Rising filter sweep, tension to second drop |
| **Second Drop** | 2:30-3:00 | t=154-184 | Main riff returns, additional synth layers |
| Extended/Outro | 3:00-3:50 | t=184-225 | Sustained energy, additional elements, fade |

## Per-Section Telemetry Summary

### Intro (t=4-29, 25 samples)
- Energy: avg=0.035, max=0.109
- Peak: avg=0.053, max=0.161
- Intensity: avg=0.089, max=0.161
- Excitement: avg=0.359, max=0.453
- Brightness: avg=0.846, max=0.989
- Composite: avg=0.329, max=0.407
- Scenarios: low(4), declining(2), medium(15), building(4)
- BPM: 136-200 (unstable, locking to wrong subdivision)

### Build 1 (t=29-46, 17 samples)
- Energy: avg=0.105, max=0.157
- Peak: avg=0.162, max=0.188
- Intensity: avg=0.170, max=0.197
- Excitement: avg=0.400, max=0.447
- Brightness: avg=0.904, max=0.997
- Composite: avg=0.387, max=0.425
- Scenarios: medium(17) — 100%
- BPM: 136-181 (still unstable)

### First Drop (t=46-91, 45 samples) — SHOULD BE HIGH/PEAK
- Energy: avg=0.111, max=0.178
- Peak: avg=0.167, max=0.193
- Intensity: avg=0.174, max=0.199
- Excitement: avg=0.319, max=0.328
- Brightness: avg=0.863, max=0.970
- Composite: avg=0.354, max=0.390
- **Scenarios: medium(45) — 100% medium, never high**
- BPM: 136 (locked correctly)

### Breakdown (t=91-124, 33 samples) — should be low/declining
- Energy: avg=0.048, max=0.159
- Intensity: avg=0.114, max=0.190
- Composite: avg=0.334, max=0.384
- Scenarios: medium(24), building(7), low(2)

### Build 2 (t=124-154, 29 samples)
- Energy: avg=0.078, max=0.140
- Intensity: avg=0.132, max=0.204
- Composite: avg=0.345, max=0.429
- Scenarios: medium(20), building(4), low(5)

### Second Drop (t=154-184, 30 samples) — SHOULD BE HIGH/PEAK
- Energy: avg=0.123, max=0.172
- Peak: avg=0.170, max=0.193
- Intensity: avg=0.180, max=0.197
- Excitement: avg=0.356, max=0.450
- Brightness: avg=0.865, max=0.939
- Composite: avg=0.368, max=0.416
- **Scenarios: medium(30) — 100% medium, never high**
- BPM: 136-182 (some instability)

### Extended/Outro (t=184-225, 41 samples) — should be high
- Energy: avg=0.125, max=0.177
- Intensity: avg=0.181, max=0.211
- Composite: avg=0.369, max=0.396
- **Scenarios: medium(41) — 100% medium**

## Key Findings

### 1. Both drops stuck at "medium" — never reach "high"
The first drop (45 samples) and second drop (30 samples) are 100% "medium" scenario. For the most iconic EDM drop in history, the system never once classifies it as high energy.

### 2. Raw energy levels compressed into 0-0.2
Even at peak moments, RMS energy maxes at 0.19. Peak-hold reaches 0.21. Intensity never exceeds 0.20. The system was designed for a 0-1 scale but the entire dynamic range of Sandstorm maps to 0-0.2.

### 3. Composite score maxes at 0.39 — needs 0.55 for "high"
During the first drop: `0.174*0.35 + 0.319*0.30 + 0.863*0.20 + 0.166*0.15 = 0.354`. The high threshold at 0.55 is unreachable at these energy levels.

### 4. Brightness is strongest signal but underweighted
Brightness correctly identifies drops (0.86-0.97) vs breakdown (0.83). But at 20% weight it only contributes ~0.17 to the composite.

### 5. Breakdown barely distinguishable from drops
Breakdown composite: 0.334 vs First Drop composite: 0.354. Only 0.02 difference. Everything is jammed in the 0.30-0.40 range.

### 6. BPM detection unreliable in sparse sections
Jumps between 136 (correct) and 181.5 (136 * 4/3). Inflates excitement during quiet sections where BPM should contribute less.

### 7. Excitement paradoxically higher during intro than drop
Intro excitement: 0.359, First Drop excitement: 0.319. False 199 BPM during intro inflates the BPM contribution while the drop's correct 136 BPM gives a lower score.

## Root Cause

The energy from system audio capture (ScreenCaptureKit) is compressed into a tiny dynamic range (0-0.2 RMS). All thresholds, weights, and composite scoring were designed assuming energy values would approach 1.0. The result: the entire song maps to "medium" and the system cannot distinguish a breakdown from the biggest drop in EDM.

## Recommendation

Adaptive energy normalization: track the running max energy and normalize against it rather than assuming absolute 0-1 scale. This spreads the actual observed range across 0-1, making drops clearly distinguishable from breakdowns regardless of system volume.
