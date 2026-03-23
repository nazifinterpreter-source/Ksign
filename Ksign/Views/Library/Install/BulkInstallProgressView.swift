//
//  BulkInstallProgressView.swift
//  Ksign
//
//  Created by Nagata Asami on 27/1/26.
//

import SwiftUI
import NimbleViews
import IDeviceSwift

struct BulkInstallProgressView: View {
    var app: AppInfoPresentable
    @StateObject var viewModel = InstallerStatusViewModel()
    
    @AppStorage("Feather.installationMethod") private var _installationMethod: Int = 0
    @AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0
    @StateObject var installer: ServerInstaller
    @State private var _isWebviewPresenting = false
    
    init(app: AppInfoPresentable) {
        self.app = app
        let viewModel = InstallerStatusViewModel()
        self._viewModel = StateObject(wrappedValue: viewModel)
        self._installer = StateObject(wrappedValue: try! ServerInstaller(app: app, viewModel: viewModel))
    }
    
    var body: some View {
        VStack {
            InstallProgressView(app: app, viewModel: viewModel)
        }
        .sheet(isPresented: $_isWebviewPresenting) {
            SafariRepresentableView(url: installer.pageEndpoint).ignoresSafeArea()
        }
        .onReceive(viewModel.$status) { newStatus in
            if case .ready = newStatus {
                if _serverMethod == 0 {
                    UIApplication.shared.open(URL(string: installer.iTunesLink)!)
                } else if _serverMethod == 1 {
                    _isWebviewPresenting = true
                }
            }
            
            if case .sendingPayload = newStatus, _serverMethod == 1 {
                _isWebviewPresenting = false
            }
            
            if case .completed = newStatus {
                BackgroundAudioManager.shared.stop()
            }
        }
        .onAppear(perform: _install)
        .onAppear {
            BackgroundAudioManager.shared.start()
        }
        .onDisappear {
            BackgroundAudioManager.shared.stop()
        }
    }
    
    private func _install() {
        Task.detached {
            do {
                let handler = await ArchiveHandler(app: app, viewModel: viewModel)
                try await handler.move()
                
                let packageUrl = try await handler.archive()
                
                if await _installationMethod == 0 {
                    await MainActor.run {
                        installer.packageUrl = packageUrl
                        viewModel.status = .ready
                    }
                } else if await _installationMethod == 1 {
                    let proxy = await InstallationProxy(viewModel: viewModel)
                    try await proxy.install(at: packageUrl, suspend: app.identifier == Bundle.main.bundleIdentifier!)
                }
                
            } catch {
                await MainActor.run {
                    HeartbeatManager.shared.start(true)
                }
            }
        }
    }
}
