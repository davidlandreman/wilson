import SwiftUI

/// Debug visualization for audio analysis — Phase 1 milestone view.
struct AudioDebugView: View {
    @Environment(\.appState) private var appState

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Audio Analysis Debug")
                    .font(.title2.bold())

                let state = appState.audioAnalysisService.musicalState

                HStack(alignment: .top, spacing: 16) {
                    VStack(spacing: 16) {
                        beatSection(state)
                        energySection(state)
                        spectralFeaturesSection(state)
                        keySection(state)
                    }
                    .frame(minWidth: 300)

                    VStack(spacing: 16) {
                        spectrumSection(state)
                        waveformSection(state)
                        bandsSection(state)
                        chromagramSection(state)
                    }
                    .frame(minWidth: 400)
                }

                Spacer()
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Beat & Tempo

    private func beatSection(_ state: MusicalState) -> some View {
        GroupBox("Beat") {
            VStack(spacing: 8) {
                HStack {
                    Text("BPM")
                        .fontWeight(.medium)
                    Spacer()
                    Text(state.bpm > 0 ? String(format: "%.1f", state.bpm) : "—")
                        .font(.title.monospacedDigit().bold())
                }

                HStack {
                    Text("Confidence")
                    Spacer()
                    ProgressView(value: state.bpmConfidence)
                        .frame(width: 120)
                    Text(String(format: "%.0f%%", state.bpmConfidence * 100))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                // Beat phase indicator — circle that pulses with beats
                ZStack {
                    Circle()
                        .fill(state.isBeat ? Color.orange : Color.orange.opacity(0.15))
                        .frame(width: 40, height: 40)
                        .scaleEffect(state.isBeat ? 1.3 : 0.8 + 0.2 * state.beatPhase)
                        .animation(.easeOut(duration: 0.08), value: state.isBeat)
                        .animation(.linear(duration: 0.02), value: state.beatPhase)

                    if state.isDownbeat {
                        Circle()
                            .stroke(Color.red, lineWidth: 3)
                            .frame(width: 50, height: 50)
                    }
                }
                .frame(height: 56)

                HStack {
                    Text("Bar position")
                    Spacer()
                    Text(String(format: "%.2f", state.beatPosition))
                        .monospacedDigit()
                }

                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Int(state.beatPosition) == i ? Color.orange : Color.orange.opacity(0.2))
                            .frame(height: 8)
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: - Energy & Dynamics

    private func energySection(_ state: MusicalState) -> some View {
        GroupBox("Dynamics") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Energy").fontWeight(.medium)
                    ProgressView(value: min(state.energy * 3, 1.0))
                        .frame(width: 140)
                    Text(String(format: "%.3f", state.energy))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Peak").fontWeight(.medium)
                    ProgressView(value: min(state.peakLevel, 1.0))
                        .frame(width: 140)
                    Text(String(format: "%.3f", state.peakLevel))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Crest").fontWeight(.medium)
                    ProgressView(value: state.crestFactor)
                        .frame(width: 140)
                    Text(String(format: "%.2f", state.crestFactor))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Onset").fontWeight(.medium)
                    Circle()
                        .fill(state.isOnset ? Color.yellow : Color.yellow.opacity(0.15))
                        .frame(width: 14, height: 14)
                    Text(String(format: "%.2f", state.onsetStrength))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Silent").fontWeight(.medium)
                    Image(systemName: state.isSilent ? "speaker.slash" : "speaker.wave.2")
                        .foregroundStyle(state.isSilent ? .secondary : .primary)
                    Text("")
                }
            }
            .padding(8)
        }
    }

    // MARK: - Spectral Features

    private func spectralFeaturesSection(_ state: MusicalState) -> some View {
        GroupBox("Spectral") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Centroid").fontWeight(.medium)
                    Text(String(format: "%.0f Hz", state.spectralCentroid))
                        .monospacedDigit()
                }
                GridRow {
                    Text("Flatness").fontWeight(.medium)
                    ProgressView(value: state.spectralFlatness)
                        .frame(width: 100)
                    Text(state.spectralFlatness < 0.3 ? "Tonal" : state.spectralFlatness < 0.7 ? "Mixed" : "Noise")
                        .foregroundStyle(.secondary)
                }
                GridRow {
                    Text("Dominant").fontWeight(.medium)
                    Text(String(format: "%.0f Hz", state.dominantFrequency))
                        .monospacedDigit()
                }
            }
            .padding(8)
        }
    }

    // MARK: - Key Detection

    private func keySection(_ state: MusicalState) -> some View {
        GroupBox("Key") {
            HStack {
                Text(state.detectedKey.displayName)
                    .font(.title3.bold())
                Spacer()
                if state.keyConfidence > 0 {
                    Text(String(format: "%.0f%%", state.keyConfidence * 100))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    // MARK: - Spectrum Visualizer

    private func spectrumSection(_ state: MusicalState) -> some View {
        GroupBox("Spectrum") {
            Canvas { context, size in
                guard !state.magnitudeSpectrum.isEmpty else { return }
                let bins = state.magnitudeSpectrum
                let count = bins.count

                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height))

                for i in 0..<count {
                    // Log-frequency X axis
                    let logX = log2(Double(max(i, 1))) / log2(Double(count))
                    let x = logX * size.width
                    // Linear magnitude Y axis (scaled for visibility)
                    let mag = min(Double(bins[i]) * 8, 1.0)
                    let y = size.height * (1.0 - mag)
                    path.addLine(to: CGPoint(x: x, y: y))
                }

                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()

                context.fill(path, with: .linearGradient(
                    Gradient(colors: [.cyan.opacity(0.7), .blue.opacity(0.4)]),
                    startPoint: .init(x: 0, y: 0),
                    endPoint: .init(x: 0, y: size.height)
                ))
            }
            .frame(height: 120)
            .background(Color.black.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    // MARK: - Waveform Oscilloscope

    private func waveformSection(_ state: MusicalState) -> some View {
        GroupBox("Waveform") {
            Canvas { context, size in
                guard !state.waveformBuffer.isEmpty else { return }
                let samples = state.waveformBuffer
                let count = samples.count

                var path = Path()
                let midY = size.height / 2

                for i in 0..<count {
                    let x = Double(i) / Double(count) * size.width
                    let y = midY - Double(samples[i]) * midY
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }

                context.stroke(path, with: .color(.green), lineWidth: 1)
            }
            .frame(height: 80)
            .background(Color.black.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    // MARK: - Band Energies

    private func bandsSection(_ state: MusicalState) -> some View {
        GroupBox("Frequency Bands") {
            let sp = state.spectralProfile
            VStack(alignment: .leading, spacing: 4) {
                bandBar(label: "Sub-Bass", value: sp.subBass)
                bandBar(label: "Bass", value: sp.bass)
                bandBar(label: "Mids", value: sp.mids)
                bandBar(label: "Highs", value: sp.highs)
                bandBar(label: "Presence", value: sp.presence)
            }
            .padding(8)
        }
    }

    private func bandBar(label: String, value: Double) -> some View {
        HStack {
            Text(label)
                .frame(width: 80, alignment: .trailing)
                .fontWeight(.medium)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.cyan.opacity(0.7))
                    .frame(width: geo.size.width * min(value * 5, 1.0))
            }
            .frame(height: 16)
            Text(String(format: "%.3f", value))
                .frame(width: 50, alignment: .trailing)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Chromagram

    private func chromagramSection(_ state: MusicalState) -> some View {
        GroupBox("Chromagram") {
            HStack(spacing: 3) {
                let notes = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
                ForEach(0..<12, id: \.self) { i in
                    VStack(spacing: 2) {
                        GeometryReader { geo in
                            let val = i < state.chromagram.count ? state.chromagram[i] : 0
                            VStack {
                                Spacer()
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.purple.opacity(0.5 + val * 0.5))
                                    .frame(height: geo.size.height * min(val, 1.0))
                            }
                        }
                        .frame(height: 60)
                        Text(notes[i])
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(8)
        }
    }
}

#Preview {
    AudioDebugView()
        .environment(\.appState, AppState())
}
