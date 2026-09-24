import SwiftUI

/// Every sheet, alert and question the library can raise.
///
/// Kept apart from the list itself because there are eight of them and they made
/// the body twice as long as the thing it describes. They are attached by
/// wrapping rather than by a ViewModifier: a modifier struct cannot reach the
/// view's own @State, and quietly losing one of these is the kind of mistake
/// that shows up as a button that does nothing.
extension LibraryView {

    @ViewBuilder
    func attachingSheets<V: View>(to view: V) -> some View {
        view
            .sheet(item: $naming) { which in namingSheet(which) }
            .sheet(item: $renaming) { set in
                NameSheet(title: "Rename set", prompt: "Set name",
                          initial: set.name, confirm: "Rename") { name in
                    store.rename(set.id, to: name)
                }
            }
            .sheet(item: $renamingFolder) { folder in
                NameSheet(title: "Rename folder", prompt: "Folder name",
                          initial: folder.name, confirm: "Rename") { name in
                    store.renameFolder(folder.id, to: name)
                }
            }
            .sheet(item: $editing) { set in
                CardsEditorView(set: set)
            }
            .sheet(item: $reading) { opening in
                SourcePreviewView(source: opening.source,
                                  set: store.library.first { $0.sources.contains(opening.source) },
                                  openAt: opening.page)
            }
            .sheet(item: $newSetKind) { kind in NewSetView(kind: kind) }
            .sheet(item: $addingKind) { kind in NewSetView(kind: kind, startingAt: .material) }
            .turnIntoPicker(for: $turning)
            .sheet(item: $reasoningFor) { set in
                NavigationStack {
                    ReasoningSetView(set: set)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { reasoningFor = nil } }
                        }
                }
            }
            .sheet(isPresented: Binding(get: { exportURL != nil },
                                        set: { if !$0 { exportURL = nil } })) {
                if let exportURL { ShareSheet(items: [exportURL]) }
            }
            // "Ask before deleting a set": every delete comes through here
            .confirmationDialog(deleteTitle, isPresented: deleteAsked, titleVisibility: .visible,
                                presenting: pendingDelete) { ids in
                Button("Delete", role: .destructive) { performDelete(ids) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This can\u{2019}t be undone.")
            }
            .alert("Couldn't export", isPresented: Binding(
                get: { exportFailedSetName != nil },
                set: { if !$0 { exportFailedSetName = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Something went wrong building the file for \(exportFailedSetName ?? "this set").")
            }
    }

    /// The naming sheet for a new folder or a combined set.
    func namingSheet(_ which: NamingSheet) -> some View {
        let folder: Bool = which == .folder
        let title: String = folder ? "New folder" : "Combined set"
        let prompt: String = folder ? "Folder name" : "Name the combined set"
        let firstName: String? = selectedSets.first?.name
        let combined: String = firstName.map { "\($0) \u{2014} combined" } ?? ""
        let initial: String = folder ? "" : combined
        let confirm: String = folder ? "Create folder" : "Create combined set"
        return NameSheet(title: title, prompt: prompt, initial: initial, confirm: confirm) { name in
            if folder { store.group(selected, into: name) }
            else { store.combine(selectedSets.map(\.id), name: name) }
            withAnimation(.snappy) { selecting = false; selected = [] }
        }
    }

    /// "Delete 1 set?" or "Delete 3 sets?".
    var deleteTitle: String {
        let count: Int = pendingDelete?.count ?? 0
        let plural: String = count == 1 ? "" : "s"
        return "Delete \(count) set\(plural)?"
    }

    var deleteAsked: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }
}
