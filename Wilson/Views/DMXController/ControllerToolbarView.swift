import SwiftUI

/// Top toolbar for the DMX controller: activate toggle, grand master, blackout, crossfade.
struct ControllerToolbarView: View {
    @Environment(\.appState) private var appState
    @Binding var isActive: Bool
    @Binding var grandMaster: Double
    @Binding var isBlackout: Bool
    @Binding var crossfadeDuration: Double

    var body: some View {
        HStack(spacing: 16) {
            // Activate toggle
            Button {
                toggleActivation()
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isActive ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 10, height: 10)
                    Text(isActive ? "Active" : "Activate")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isActive ? Color.green.opacity(0.15) : Color.secondary.opacity(0.1))
                )
            }
            .buttonStyle(.plain)

            Divider()
                .frame(height: 24)

            // Grand Master
            HStack(spacing: 8) {
                Text("GM")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Slider(value: $grandMaster, in: 0...1)
                    .frame(width: 150)
                    .onChange(of: grandMaster) {
                        pushAllIfActive()
                    }
                Text("\(Int(grandMaster * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }

            Divider()
                .frame(height: 24)

            // Blackout
            Button {
                isBlackout.toggle()
                pushAllIfActive()
            } label: {
                Text("BLACKOUT")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isBlackout ? .white : .red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isBlackout ? Color.red : Color.red.opacity(0.15))
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            // Crossfade duration
            HStack(spacing: 6) {
                Text("Xfade")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Picker("", selection: $crossfadeDuration) {
                    Text("0s").tag(0.0)
                    Text("1s").tag(1.0)
                    Text("2s").tag(2.0)
                    Text("3s").tag(3.0)
                    Text("5s").tag(5.0)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.3))
    }

    private func toggleActivation() {
        if isActive {
            appState.dmxController.deactivate(engine: appState.decisionEngine)
        } else {
            appState.dmxController.activate(
                fixtures: appState.fixtureManager.fixtures,
                currentStates: appState.decisionEngine.fixtureStates
            )
        }
        appState.updateManualRefreshTimer()
    }

    private func pushAllIfActive() {
        guard isActive else { return }
        appState.dmxController.pushAllOverrides(engine: appState.decisionEngine)
    }
}
