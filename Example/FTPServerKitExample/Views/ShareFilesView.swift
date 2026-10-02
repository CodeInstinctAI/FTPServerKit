//
//  ShareFilesView.swift
//  FTPServerKitExample
//
//  Created by Marc Janga on 13/10/2025.
//

import SwiftUI
import UniformTypeIdentifiers

/// Main view for sharing files via the local server
struct ShareFilesView: View {
    @EnvironmentObject private var serverManager: ServerManager
    @State private var showingFilePicker = false
    @State private var showingError = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Server Status Section
                serverStatusSection
                
                Divider()
                
                // Files List
                if serverManager.sharedFiles.isEmpty {
                    emptyStateView
                } else {
                    filesListView
                }
            }
            .navigationTitle("Share Files")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingFilePicker = true
                    } label: {
                        Label("Add Files", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingFilePicker) {
                DocumentPicker { urls in
                    for url in urls {
                        serverManager.addFile(from: url)
                    }
                }
            }
            .alert("Error", isPresented: $showingError, presenting: serverManager.errorMessage) { _ in
                Button("OK") {
                    serverManager.errorMessage = nil
                }
            } message: { message in
                Text(message)
            }
            .onChange(of: serverManager.errorMessage) { _, newValue in
                showingError = newValue != nil
            }
        }
    }
    
    // MARK: - Server Status Section

    private var serverStatusSection: some View {
        VStack(spacing: 16) {
            // Server Toggle
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FTP Server")
                        .font(.headline)
                    Text(serverManager.isRunning ? "Running" : serverManager.isStarting ? "Starting…" : "Stopped")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { serverManager.isRunning || serverManager.isStarting },
                    set: { isOn in
                        if isOn {
                            serverManager.startServer()
                        } else {
                            serverManager.stopServer()
                        }
                    }
                ))
                .labelsHidden()
                .disabled(serverManager.sharedFiles.isEmpty)
            }

            // Connection Information Display
            if let connectionInfo = serverManager.getConnectionInfo() {
                connectionInfoView(for: connectionInfo)
            }

            // Info Message
            if !serverManager.isRunning && !serverManager.sharedFiles.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Start the FTP server to share files")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    // MARK: - Connection Info View

    private func connectionInfoView(for info: ServerConnectionInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Server URL
            VStack(alignment: .leading, spacing: 8) {
                Text("Server Address")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(info.url)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.blue)
                        .textSelection(.enabled)

                    Spacer()

                    Button {
                        UIPasteboard.general.string = info.url
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.body)
                    }
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }

            // FTP Credentials (if applicable)
            if let credentials = info.credentials {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Credentials")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        HStack {
                            Text("Username:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(credentials.username)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                            Spacer()
                        }

                        HStack {
                            Text("Password:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(credentials.password)
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }

            // Protocol Description
            Text("FTP client access")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Files Shared")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Tap the + button to add files you want to share")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                showingFilePicker = true
            } label: {
                Label("Add Files", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Files List
    
    private var filesListView: some View {
        List {
            ForEach(serverManager.sharedFiles) { file in
                FileRowView(file: file)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    serverManager.removeFile(serverManager.sharedFiles[index])
                }
            }
        }
        .listStyle(.plain)
    }
}

// MARK: - File Row View

struct FileRowView: View {
    let file: SharedFile
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.iconName)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(file.name)
                    .font(.body)
                    .lineLimit(2)
                
                HStack(spacing: 8) {
                    Text(file.formattedSize)
                    Text("•")
                    Text(file.type)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Document Picker

struct DocumentPicker: UIViewControllerRepresentable {
    let onPick: ([URL]) -> Void
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: ([URL]) -> Void
        
        init(onPick: @escaping ([URL]) -> Void) {
            self.onPick = onPick
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }
    }
}

#Preview {
    ShareFilesView()
        .environmentObject(ServerManager())
}

