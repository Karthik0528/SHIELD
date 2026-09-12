import Foundation

/// State management model for gallery multi-selection mode.
public final class PhotoSelectionMode: ObservableObject, Sendable {
    @Published public var isSelectionMode: Bool = false
    @Published public var selectedIDs: Set<UUID> = []
    
    public init() {}
    
    @MainActor
    public func toggleSelectionMode() {
        isSelectionMode.toggle()
        if !isSelectionMode {
            selectedIDs.removeAll()
        }
    }
    
    @MainActor
    public func toggleSelect(id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
    
    @MainActor
    public func clearSelection() {
        selectedIDs.removeAll()
        isSelectionMode = false
    }
}
