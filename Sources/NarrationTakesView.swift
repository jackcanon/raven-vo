import SwiftUI

struct NarrationTakesView: View {
    @Bindable var model: NarrationStudioModel
    @State private var expanded = false
    @State private var rename: NarrationTake?
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                expanded.toggle()
                if !expanded, model.auditioningTake != nil { model.stop() }
            } label: {
                HStack {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    Text("Script Takes (\(model.takes.count))")
                    if let current = model.currentTake {
                        Text("Editing \(current.name)").foregroundStyle(.secondary)
                    }
                }
            }
            if expanded {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.takes) { take in
                            HStack {
                                Button(model.auditioningTake == take.id ? "Stop" : "Listen", systemImage: model.auditioningTake == take.id ? "stop.fill" : "play.fill") {
                                    model.audition(take)
                                }.accessibilityLabel("\(model.auditioningTake == take.id ? "Stop" : "Listen to") \(take.name)")
                                Text(take.name).lineLimit(2)
                                Text(String(format: "%.1f s", take.duration)).foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    model.toggleFavorite(take.id)
                                } label: {
                                    Image(systemName: model.favoriteTake == take.id ? "star.fill" : "star")
                                        .foregroundStyle(model.favoriteTake == take.id ? RavenBrand.headphoneAmber : .secondary)
                                }.accessibilityLabel(model.favoriteTake == take.id ? "Remove favorite \(take.name)" : "Favorite \(take.name)")
                                Button("Rename") { name = take.name; rename = take }
                                Button("Edit") { model.editTake(take) }.disabled(model.currentTake?.id == take.id)
                            }
                        }
                    }
                }.frame(height: min(210, CGFloat(model.takes.count) * 52))
                Text("Listen plays the original recording from the beginning.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(RavenTouchButtonStyle())
        .disabled(model.locked)
        .sheet(item: $rename) { take in
            VStack(alignment: .leading) {
                TextField("Take name", text: $name)
                HStack {
                    Button("Cancel") { rename = nil }
                    Button("Save Name") { model.renameTake(take.id, to: name); rename = nil }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }.padding(20).frame(width: 340)
        }
    }
}
