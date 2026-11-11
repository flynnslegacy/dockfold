import SwiftUI
import NidoCore

struct FolderEditorView: View {
    @Binding var folder: DockFolder
    @ObservedObject var model: ManagerModel
    @State private var dropTargeted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                appsSection
                DockAppsSection(model: model, folderID: folder.id)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            Image(nsImage: model.preview(for: folder, size: 72))
                .resizable()
                .frame(width: 72, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Nom du dossier", text: $folder.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .semibold))
                Text(countText).foregroundStyle(.secondary)
            }
        }
    }

    private var countText: String {
        switch folder.apps.count {
        case 0: return "Aucune app pour l'instant"
        case 1: return "1 app"
        case 2...9: return "\(folder.apps.count) apps"
        default: return "\(folder.apps.count) apps, les 9 premières sont visibles sur l'icône"
        }
    }

    private var appsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dans ce dossier").font(.headline)
            Group {
                if folder.apps.isEmpty {
                    Text("Glisse des apps ici depuis le Finder, ou choisis-les dans ton Dock juste en dessous.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 70)
                        .background(RoundedRectangle(cornerRadius: 8).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5])).foregroundStyle(.tertiary))
                } else {
                    List {
                        ForEach(folder.apps) { app in
                            FolderAppRow(app: app) { model.remove(app, from: folder.id) }
                        }
                        .onMove { folder.apps.move(fromOffsets: $0, toOffset: $1) }
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
                    .frame(height: min(CGFloat(folder.apps.count) * 34 + 10, 320))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 2).opacity(dropTargeted ? 1 : 0))
            .dropDestination(for: URL.self) { urls, _ in
                model.addURLs(urls, to: folder.id)
                return true
            } isTargeted: { dropTargeted = $0 }

            HStack(spacing: 10) {
                Button("Ajouter des apps…") { model.pickApps(for: folder.id) }
                Text("Fais glisser une ligne pour changer l'ordre des apps dans la bulle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FolderAppRow: View {
    let app: FolderApp
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 24, height: 24)
            Text(app.name)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Retirer du dossier (l'app revient dans le Dock)")
        }
        .padding(.vertical, 2)
    }
}

struct DockAppsSection: View {
    @ObservedObject var model: ManagerModel
    let folderID: DockFolder.ID

    private let columns = [GridItem(.adaptive(minimum: 86), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Apps de ton Dock").font(.headline)
                Spacer()
                Button { model.refreshDockApps() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("Relire le Dock")
            }
            Text("Clique sur une app pour la mettre dans ce dossier, ou pour l'en retirer.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.dockApps.isEmpty {
                Text("Aucune app épinglée dans le Dock.").foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(model.dockApps) { app in
                        DockAppTile(app: app, membership: model.membership(of: app, in: folderID)) {
                            model.toggle(app, in: folderID)
                        }
                    }
                }
            }
        }
    }
}

struct DockAppTile: View {
    let app: FolderApp
    let membership: Membership
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                        .resizable()
                        .frame(width: 44, height: 44)
                    if membership == .here {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .font(.system(size: 15))
                            .offset(x: 5, y: -3)
                    }
                }
                Text(app.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(otherFolderName ?? " ")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 6)
            .frame(width: 86)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 10).fill(membership == .here ? Color.accentColor.opacity(0.15) : .clear))
        }
        .buttonStyle(.plain)
        .opacity(otherFolderName == nil ? 1 : 0.5)
        .help(helpText)
    }

    private var otherFolderName: String? {
        if case .other(let name) = membership { return name }
        return nil
    }

    private var helpText: String {
        switch membership {
        case .none: return "Ajouter \(app.name) à ce dossier"
        case .here: return "Retirer \(app.name) de ce dossier"
        case .other(let name): return "\(app.name) est déjà dans « \(name) » ; clique pour l'ajouter aussi ici"
        }
    }
}
