import SwiftUI
import DockfoldCore

struct ContentView: View {
    @ObservedObject var model: ManagerModel

    var body: some View {
        NavigationSplitView {
            FolderSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 300)
        } detail: {
            Group {
                if let id = model.selection, let folder = model.binding(for: id) {
                    FolderEditorView(folder: folder, model: model)
                        .id(id)
                } else {
                    EmptyFolderState(model: model)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { ApplyBar(model: model) }
        }
    }
}

struct FolderSidebar: View {
    @ObservedObject var model: ManagerModel

    var body: some View {
        List(selection: $model.selection) {
            Section("Dossiers") {
                ForEach(model.folders) { folder in
                    Label {
                        Text(folder.displayName)
                    } icon: {
                        Image(nsImage: model.preview(for: folder, size: 22))
                            .resizable()
                            .frame(width: 22, height: 22)
                    }
                    .tag(folder.id)
                    .contextMenu {
                        Button("Supprimer le dossier", role: .destructive) { model.deleteFolder(folder.id) }
                    }
                }
            }
        }
        .onDeleteCommand {
            if let id = model.selection { model.deleteFolder(id) }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { model.addFolder() } label: { Label("Nouveau dossier", systemImage: "plus") }
                    .help("Nouveau dossier")
                Button {
                    if let id = model.selection { model.deleteFolder(id) }
                } label: { Label("Supprimer le dossier", systemImage: "trash") }
                    .help("Supprimer le dossier (ses apps reviennent dans le Dock)")
                    .disabled(model.selection == nil)
            }
        }
    }
}

struct EmptyFolderState: View {
    @ObservedObject var model: ManagerModel

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.3x3.square")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.secondary)
            Text("Range ton Dock dans des dossiers")
                .font(.title2.weight(.semibold))
            Text("Crée un dossier, mets-y des apps, puis applique : elles quittent le Dock et se retrouvent ensemble derrière une seule icône.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
            Button("Créer un dossier") { model.addFolder() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ApplyBar: View {
    @ObservedObject var model: ManagerModel

    var body: some View {
        HStack(spacing: 12) {
            if model.phase == .applying {
                ProgressView().controlSize(.small)
            } else if case .failed = model.phase {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else if !model.isDirty && !model.folders.isEmpty {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            Text(model.statusText)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button("Restaurer le Dock d'origine…") { model.restoreDock() }
                .disabled(!model.hasBackup || model.phase == .applying)
                .help("Remet le Dock exactement comme avant la première modification par Dockfold")
            Button("Appliquer au Dock") { Task { await model.apply() } }
                .buttonStyle(.borderedProminent)
                .disabled(!model.isDirty || model.phase == .applying)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
