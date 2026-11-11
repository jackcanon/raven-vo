import Foundation
@main struct CleanupControlHistoryChecks {
    @MainActor static func main() {
        let model = NarrationStudioModel()
        let original = model.cleanupSettings
        model.cleanupEditingChanged(true)
        model.cleanupSettings.strength = 3
        model.cleanupSettings.strength = 4
        model.cleanupSettings.strength = 5
        model.cleanupEditingChanged(false)
        precondition(model.cleanupControlUndo.count == 1)
        model.undoCleanupControl()
        precondition(model.cleanupSettings == original && model.cleanupControlRedo.count == 1)
        model.redoCleanupControl()
        precondition(model.cleanupSettings.strength == 5)
        model.monitorGainDB = 3
        model.undoCleanupControl()
        precondition(model.monitorGainDB == 0 && model.cleanupSettings.strength == 5)
        model.undoCleanupControl()
        precondition(model.cleanupSettings == original)
        model.cleanupSettings = .referenceB
        precondition(model.cleanupControlRedo.isEmpty)
        model.cleanupEditingChanged(true); model.cleanupEditingChanged(false)
        precondition(model.cleanupControlUndo.count == 1)
        for i in 0..<120 { model.cleanupSettings.strength = Double(i % 7) }
        precondition(model.cleanupControlUndo.count <= 100)
        print("PASS: grouped knob changes, control undo/redo, monitor volume undo, redo invalidation, no-op gestures and bounded history")
    }
}
