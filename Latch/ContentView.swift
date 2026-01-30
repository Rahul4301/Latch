//
//  ContentView.swift
//  Latch
//
//  Created by Rahul Suthar on 1/29/26.
//

import SwiftUI
import AppKit

struct ContentView: View {

    @State private var workspacePath: String? = WorkspaceManager.shared.getWorkspaceRoot()?.path

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button("Select Workspace") {
                    openWorkspacePanel()
                }
                if let path = workspacePath {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
            }
            .padding(8)

            if workspacePath != nil {
                ChatView()
            } else {
                VStack(spacing: 8) {
                    Text("Select a workspace to start")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    private func openWorkspacePanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Select Workspace"
        panel.prompt = "Select"
        panel.begin { response in
            if response == .OK, let url = panel.url, WorkspaceManager.shared.setWorkspaceRoot(url) {
                workspacePath = url.path
            }
        }
    }
}

#Preview {
    ContentView()
}
