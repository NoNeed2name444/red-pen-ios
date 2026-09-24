import SwiftUI

/// Every sheet and alert the library can raise.
///
/// Kept apart from the list itself because there are six of them and they made
/// the body twice as long as the thing it describes. They are attached by
/// wrapping rather than by a ViewModifier: a modifier struct cannot reach the
/// view's own @State, and quietly losing one of these is the kind of mistake
/// that shows up as a button that does nothing.
extension LibraryView {

    @ViewBuilder
    func attachingSheets<V: View>(to view: V) -> some View {
        view
            .sheet(item: $naming) { which in
                NameSheet(title: which == .folder ? "New folder" : "Combined set",
                          prompt: which == .folder ? "Folder name" : "Name the combined set",
                          initial: which == .folder
                              ? ""
                              : (selectedSets.first.map { "\($0.name) \u{2014} combined" } ?? ""),
                          confirm: which == .folder ? "Create folder" : "Create combined set") { name in
                    if which == .folder { store.group(selected, into: name) }
                    else { store.combine(selectedSets.map(\.id), name: name) }
                    withAnimation(.snappy) { selecting = false; selected = [] }
                }
            }
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
            .alert("Couldn't export", isPresented: Binding(
                get: { exportFailedSetName != nil },
                set: { if !$0 { exportFailedSetName = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Something went wrong building the file for \(exportFailedSetName ?? "this set").")
            }
    }
}
