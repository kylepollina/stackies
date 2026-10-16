import SwiftUI

/// Stackies ▸ Settings… (⌘,). Each control reads and writes the same `UserDefaults` key the
/// pomodoro code reads, so changes apply from the next session on.
struct SettingsView: View {
    @AppStorage("focusMinutes") private var focusMinutes = 25.0
    @AppStorage("breakMinutes") private var breakMinutes = 5.0
    @AppStorage("warnHours") private var warnHours = 2.0
    @AppStorage(PomodoroSound.Event.focusDone.key) private var focusSound = PomodoroSound.Event.focusDone.defaultSound
    @AppStorage(PomodoroSound.Event.breakDone.key) private var breakSound = PomodoroSound.Event.breakDone.defaultSound

    var body: some View {
        Form {
            Section {
                stepper("Focus", value: $focusMinutes, in: 5...120, step: 5) { "\(Int($0)) min" }
                stepper("Break", value: $breakMinutes, in: 1...30, step: 1) { "\(Int($0)) min" }
                stepper("Flag a task after", value: $warnHours, in: 0.5...8, step: 0.5) {
                    "\($0.formatted()) h"
                }
            } header: {
                Text("Pomodoro")
            } footer: {
                Text("A task's ⏱ total turns orange, with a one-time alert, once it passes the flag time.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("Sounds") {
                soundPicker("End of focus", selection: $focusSound)
                soundPicker("End of break", selection: $breakSound)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }

    private func stepper(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
                         format: @escaping (Double) -> String) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text(format(value.wrappedValue)).monospacedDigit()
                Stepper(title, value: value, in: range, step: step).labelsHidden()
            }
        }
    }

    /// A menu of every sound plus a button to hear the chosen one; picking a sound also plays it.
    private func soundPicker(_ title: String, selection: Binding<String>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Picker(title, selection: selection) {
                    ForEach(PomodoroSound.chimes, id: \.self) { Text($0) }
                    Divider()
                    ForEach(PomodoroSound.system, id: \.self) { Text($0) }
                    Divider()
                    Text(PomodoroSound.none).tag(PomodoroSound.none)
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: selection.wrappedValue) { _, name in PomodoroSound.play(name) }

                Button {
                    PomodoroSound.play(selection.wrappedValue)
                } label: {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderless)
                .help("Play")
                .disabled(selection.wrappedValue == PomodoroSound.none)
            }
        }
    }
}
