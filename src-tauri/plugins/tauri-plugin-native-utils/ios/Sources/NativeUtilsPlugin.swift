import Tauri
import UIKit
import UniformTypeIdentifiers

struct SelectItemArgs: Decodable {
    let channel: Channel
}

struct CancelJobArgs: Decodable {
    let channelId: Int64
}

struct ExportToTreeArgs: Decodable {
    let treeUri: String
    let sourceDir: String
}

struct OpenDownloadFolderArgs: Decodable {
    let treeUri: String
}

final class NativeUtilsPlugin: Plugin {

    private var documentPickerDelegates: [ObjectIdentifier: DocumentPickerDelegate] = [:]

    private func retainDelegate(
        _ delegate: DocumentPickerDelegate,
        for picker: UIDocumentPickerViewController
    ) {
        documentPickerDelegates[ObjectIdentifier(picker)] = delegate
    }

    private func releaseDelegate(
        for picker: UIDocumentPickerViewController
    ) {
        documentPickerDelegates.removeValue(
            forKey: ObjectIdentifier(picker)
        )
    }

    @objc(select_download_folder:)
    public func selectDownloadFolder(_ invoke: Invoke) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.folder],
                asCopy: false
            )

            let delegate = DocumentPickerDelegate { [weak self, weak picker] urls in
                guard let self else { return }

                guard let url = urls.first else {
                    invoke.resolve([:])
                    if let picker { self.releaseDelegate(for: picker) }
                    return
                }

                let isScoped = url.startAccessingSecurityScopedResource()

                var isDir: ObjCBool = true
                if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                }

                invoke.resolve([
                    "uri": url.absoluteString,
                    "path": url.path
                ])

                if let picker { self.releaseDelegate(for: picker) }
            }

            self.retainDelegate(delegate, for: picker)
            picker.delegate = delegate
            picker.allowsMultipleSelection = false

            self.manager.viewController?.present(picker, animated: true)
        }
    }

    @objc(select_send_document:)
    public func selectSendDocument(_ invoke: Invoke) {
        do {
            let args = try invoke.parseArgs(SelectItemArgs.self)

            Task { @MainActor [weak self] in
                guard let self else { return }

                let picker = UIDocumentPickerViewController(
                    forOpeningContentTypes: [.item],
                    asCopy: true
                )

                let delegate = DocumentPickerDelegate { [weak self, weak picker] urls in
                    guard let self else { return }

                    guard let url = urls.first else {
                        invoke.resolve(false)

                        if let picker {
                            self.releaseDelegate(for: picker)
                        }

                        return
                    }

                    self.copySelectedFiles(
                        urls: [url],
                        channel: args.channel
                    )

                    invoke.resolve(true)

                    if let picker {
                        self.releaseDelegate(for: picker)
                    }
                }

                self.retainDelegate(delegate, for: picker)

                picker.delegate = delegate
                picker.allowsMultipleSelection = true

                self.manager.viewController?.present(
                    picker,
                    animated: true
                )
            }
        } catch {
            invoke.reject(error.localizedDescription)
        }
    }

    @objc(select_send_folder:)
    public func selectSendFolder(_ invoke: Invoke) {
        do {
            let args = try invoke.parseArgs(SelectItemArgs.self)

            Task { @MainActor [weak self] in
                guard let self else { return }

                let picker = UIDocumentPickerViewController(
                    forOpeningContentTypes: [.folder],
                    asCopy: true
                )

                let delegate = DocumentPickerDelegate { [weak self, weak picker] urls in
                    guard let self else { return }

                    guard let url = urls.first else {
                        invoke.resolve(false)

                        if let picker {
                            self.releaseDelegate(for: picker)
                        }

                        return
                    }

                    self.copySelectedFiles(
                        urls: [url],
                        channel: args.channel
                    )

                    invoke.resolve(true)

                    if let picker {
                        self.releaseDelegate(for: picker)
                    }
                }

                self.retainDelegate(delegate, for: picker)

                picker.delegate = delegate
                picker.allowsMultipleSelection = false

                self.manager.viewController?.present(
                    picker,
                    animated: true
                )
            }
        } catch {
            invoke.reject(error.localizedDescription)
        }
    }

    @objc(consume_share_intent:)
    public func consumeShareIntent(_ invoke: Invoke) {
        invoke.resolve(false)
    }

    @objc(cancel_job:)
    public func cancelJob(_ invoke: Invoke) {
        invoke.resolve()
    }

    @objc(export_to_tree:)
    public func exportToTree(_ invoke: Invoke) {
        invoke.reject("export_to_tree is not supported on iOS")
    }

    @objc(open_download_folder:)
    public func openDownloadFolder(_ invoke: Invoke) {
        invoke.reject("open_download_folder is not supported on iOS")
    }

    @objc(get_window_insets:)
    public func getWindowInsets(_ invoke: Invoke) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            guard let window = self.manager.viewController?.view.window else {
                invoke.resolve([
                    "top": 0.0,
                    "right": 0.0,
                    "bottom": 0.0,
                    "left": 0.0
                ])
                return
            }

            let insets = window.safeAreaInsets
            let scale = window.screen.scale

            invoke.resolve([
                "top": Double(insets.top / scale),
                "right": Double(insets.right / scale),
                "bottom": Double(insets.bottom / scale),
                "left": Double(insets.left / scale)
            ])
        }
    }

    private func copySelectedFiles(
        urls: [URL],
        channel: Channel
    ) {
        let fileManager = FileManager.default

        let cacheDirectory = fileManager.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        )[0]

        let destination = cacheDirectory
            .appendingPathComponent(
                "file_cache",
                isDirectory: true
            )
            .appendingPathComponent(
                String(Int(Date().timeIntervalSince1970 * 1000)),
                isDirectory: true
            )

        do {
            try fileManager.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )

            var paths: [String] = []

            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()

                defer {
                    if didAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let name = url.lastPathComponent
                let target = destination.appendingPathComponent(name)

                try fileManager.copyItem(
                    at: url,
                    to: target
                )

                paths.append(target.path)
            }

            if paths.count == 1 {
                channel.send([
                    "copiedBytes": "0",
                    "totalBytes": "0",
                    "cachedPath": paths[0],
                    "completed": true,
                    "progress": 1.0
                ])
            } else {
                channel.send([
                    "copiedBytes": "0",
                    "totalBytes": "0",
                    "cachedPaths": paths,
                    "completed": true,
                    "progress": 1.0
                ])
            }

        } catch {
            channel.send([
                "error": error.localizedDescription,
                "progress": -1.0,
                "copiedBytes": "0",
                "totalBytes": "0"
            ])
        }
    }
}

final class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {

    private let completion: ([URL]) -> Void

    init(completion: @escaping ([URL]) -> Void) {
        self.completion = completion
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        completion(urls)
    }

    func documentPickerWasCancelled(
        _ controller: UIDocumentPickerViewController
    ) {
        completion([])
    }
}

@_cdecl("init_plugin_native_utils")
func initPlugin() -> Plugin {
    NativeUtilsPlugin()
}
