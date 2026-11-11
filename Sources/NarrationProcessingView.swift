import SwiftUI

struct NarrationProcessingView: View {
    @Bindable var model: NarrationStudioModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(model.samplingRoom ? "Sampling…" : "Sample Room Noise (3 s)") { model.sampleRoomNoise() }.disabled(model.locked)
                Text(model.roomToneURL == nil ? "Stay silent while sampling, then record with the same mic and gain." : "Room-noise sample ready")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            NarrationCleanupControls(model: model)
            Divider()
            HStack {
                Picker("Audio Unit", selection: Binding(get: { model.effects.selectedID }, set: { model.effects.selectedID = $0 })) {
                    ForEach(model.effects.choices) { Text($0.name).tag($0.id) }
                }.frame(maxWidth: 460).disabled(model.locked)
                Button("Refresh") { model.effects.refresh() }.disabled(model.locked)
                Button("Add Effect") {
                    model.stop()
                    Task { await model.effects.add(); if model.edit != nil { model.save() } }
                }.disabled(model.locked || model.edit == nil || model.effects.selectedID.isEmpty)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.effects.plugins) { plugin in
                        HStack {
                            Text(plugin.name).lineLimit(1)
                            Spacer()
                            Toggle("Bypass", isOn: Binding(get: { model.effects.plugins.first(where: { $0.id == plugin.id })?.bypass ?? false }, set: { bypass in
                                model.stop()
                                if let index = model.effects.plugins.firstIndex(where: { $0.id == plugin.id }) { model.effects.plugins[index].bypass = bypass; model.save() }
                            }))
                            Button("Controls…") { model.effects.showEditor(plugin.id) }
                            Button("Remove") { model.stop(); model.effects.remove(plugin.id); model.save() }
                        }.disabled(model.locked)
                    }
                }
            }.frame(height: model.effects.plugins.isEmpty ? 0 : min(100, CGFloat(model.effects.plugins.count * 52)))
            if !model.effects.message.isEmpty { Text(model.effects.message).font(.caption).textSelection(.enabled) }
            Text("Effects run in order on playback/export. Save after adjusting plugin controls. AU effects only; VST3 is planned after 1.0. Compare cleanup against the original for speech artifacts.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 8)
    }
}
