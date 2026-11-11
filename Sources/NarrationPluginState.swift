import Foundation
import AudioToolbox

struct NarrationPluginState: Codable, Equatable, Sendable, Identifiable {
    var id = UUID()
    var name: String
    var type: UInt32
    var subtype: UInt32
    var manufacturer: UInt32
    var state: Data?
    var bypass = false
    var description: AudioComponentDescription {
        .init(componentType: type, componentSubType: subtype, componentManufacturer: manufacturer, componentFlags: 0, componentFlagsMask: 0)
    }
}
