import SwiftUI

struct ContentView: View {
    @StateObject private var manager = AudioEngineManager()
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar (Left Controls)
            VStack(alignment: .leading, spacing: 20) {
                Text("Pluck")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .padding(.bottom, 10)
                
                // Mic Permission Warning
                if manager.micPermissionDenied {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Microphone Access Required", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(.body, design: .default).weight(.semibold))
                            .foregroundColor(.orange)
                        Button("Open Privacy Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption2)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(6)
                }

                // Engine Switcher
                Button(action: {
                    if manager.isRunning {
                        manager.stopEngine()
                    } else {
                        manager.startEngine()
                    }
                }) {
                    HStack {
                        Image(systemName: manager.isRunning ? "stop.fill" : "play.fill")
                        Text(manager.isRunning ? "Stop Engine" : "Start Engine")
                            .font(.system(.body, design: .default).weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(manager.isRunning ? Color.red.opacity(0.8) : Color.green.opacity(0.8))
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(.space, modifiers: [.control])
                .accessibilityLabel(manager.isRunning ? "Stop Audio Engine" : "Start Audio Engine")
                .accessibilityHint("Press Ctrl+Space to toggle audio engine")
                
                Text(manager.statusMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                
                Divider()
                
                // Device Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("AUDIO ROUTING")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                    
                    // Input Device
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Input Device")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Picker("", selection: $manager.selectedInputDevice) {
                            Text("None").tag(nil as AudioDevice?)
                            ForEach(manager.availableDevices.filter { $0.inputChannels > 0 }, id: \.self) { dev in
                                Text(dev.name).tag(dev as AudioDevice?)
                            }
                        }
                        .labelsHidden()
                    }
                    
                    // Input Channel
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Input Channel")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Picker("", selection: $manager.selectedInputChannel) {
                            if let channels = manager.selectedInputDevice?.inputChannels {
                                ForEach(0..<channels, id: \.self) { ch in
                                    Text("Channel \(ch + 1)").tag(ch)
                                }
                            } else {
                                Text("No channels").tag(0)
                            }
                        }
                        .labelsHidden()
                    }
                    
                    // Output Device
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Output Device")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Picker("", selection: $manager.selectedOutputDevice) {
                            Text("None").tag(nil as AudioDevice?)
                            ForEach(manager.availableDevices.filter { $0.outputChannels > 0 }, id: \.self) { dev in
                                Text(dev.name).tag(dev as AudioDevice?)
                            }
                        }
                        .labelsHidden()
                    }
                }
                
                Divider()
                
                // Settings (Buffer / Latency)
                VStack(alignment: .leading, spacing: 12) {
                    Text("PERFORMANCE")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Buffer Size (Latency)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Picker("", selection: $manager.selectedBufferSize) {
                            ForEach(AudioEngineManager.availableBufferSizes, id: \.self) { size in
                                Text("\(size) Samples").tag(size)
                            }
                        }
                        .labelsHidden()
                    }
                    
                    Toggle("Bypass Plugin", isOn: $manager.isBypassed)
                        .toggleStyle(CheckboxToggleStyle())
                        .font(.body)
                }
                
                Divider()
                
                // VU Meters
                VStack(alignment: .leading, spacing: 12) {
                    Text("AUDIO LEVELS")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.secondary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Input")
                                .font(.caption2)
                            Spacer()
                            Text(String(format: "%.1f dB", 20 * log10(max(0.0001, manager.inputLevel))))
                                .font(.system(.caption2, design: .monospaced))
                        }
                        ProgressView(value: min(1.0, manager.inputLevel * 5.0))
                            .tint(.green)
                            .accessibilityLabel("Input Audio Level")
                            .accessibilityValue(String(format: "%.1f dB", 20 * log10(max(0.0001, manager.inputLevel))))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Output")
                                .font(.caption2)
                            Spacer()
                            Text(String(format: "%.1f dB", 20 * log10(max(0.0001, manager.outputLevel))))
                                .font(.system(.caption2, design: .monospaced))
                        }
                        ProgressView(value: min(1.0, manager.outputLevel * 5.0))
                            .tint(.blue)
                            .accessibilityLabel("Output Audio Level")
                            .accessibilityValue(String(format: "%.1f dB", 20 * log10(max(0.0001, manager.outputLevel))))
                    }
                }
                
                Spacer()
                
                // Panic / Mute button
                Button(action: {
                    manager.stopEngine()
                }) {
                    Text("PANIC (MUTE ALL)")
                        .font(.caption.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                .keyboardShortcut(".", modifiers: [.command])
                .accessibilityLabel("Panic: Immediately Stop Engine and Mute All Audio")
            }
            .frame(width: 250)
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))
            
            // Divider
            Rectangle()
                .fill(Color(NSColor.separatorColor))
                .frame(width: 1)
                .edgesIgnoringSafeArea(.all)
            
            // Main Window (Plugin Editor GUI)
            VStack(spacing: 0) {
                if !manager.isHelixAvailable {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text("Helix Native Not Found")
                            .font(.title.weight(.bold))
                        Text("Pluck requires the Line 6 Helix Native Audio Unit plugin to function. Please install the plugin and restart the app.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let unit = manager.helixUnit {
                    AUViewRepresentable(audioUnit: unit)
                        .id(ObjectIdentifier(unit))
                } else if manager.statusMessage.contains("failed") || manager.statusMessage.contains("Failed") || manager.statusMessage.contains("Error") {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.red)
                        Text("Audio Configuration Error")
                            .font(.headline)
                        Text(manager.statusMessage)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding(.bottom, 10)
                        Text(manager.statusMessage.isEmpty ? "Loading Audio Unit..." : manager.statusMessage)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.underPageBackgroundColor))
        }
        .frame(minWidth: 900, idealWidth: 1100, maxWidth: .infinity, minHeight: 500, idealHeight: 700, maxHeight: .infinity)
        .onAppear {
            manager.activate()
        }
    }
}
