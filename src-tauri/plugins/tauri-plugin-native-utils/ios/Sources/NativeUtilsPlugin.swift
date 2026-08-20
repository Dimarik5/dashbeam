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

    @objc public func selectDownloadFolder(_ invoke: Invoke) throws {
        DispatchQueue.main.async {
            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.folder],
                asCopy: false
            )

            let delegate = DocumentPickerDelegate { urls in
                guard let url = urls.first else {
                    invoke.resolve(nil)
                    return
                }

                invoke.resolve([
                    "uri": url.absoluteString,
                    "path": url.path
                ])
            }

            self.manager.addDelegate(delegate)

            picker.delegate = delegate
            picker.allowsMultipleSelection = false

            self.manager.viewController?.present(
                picker,
                animated: true
            )
        }
    }

    @objc public func selectSendDocument(_ invoke: Invoke) throws {
        let args = try invoke.parseArgs(SelectItemArgs.self)

        DispatchQueue.main.async {
            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.item],
                asCopy: true
            )

            let delegate = DocumentPickerDelegate { urls in
                guard let url = urls.first else {
                    invoke.resolve(false)
                    return
                }

                self.copySelectedFiles(
                    urls: [url],
                    channel: args.channel
                )

                invoke.resolve(true)
            }

            self.manager.addDelegate(delegate)

            picker.delegate = delegate
            picker.allowsMultipleSelection = true

            self.manager.viewController?.present(
                picker,
                animated: true
            )
        }
    }

    @objc public func selectSendFolder(_ invoke: Invoke) throws {
        let args = try invoke.parseArgs(SelectItemArgs.self)

        DispatchQueue.main.async {
            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.folder],
                asCopy: true
            )

            let delegate = DocumentPickerDelegate { urls in
                guard let url = urls.first else {
                    invoke.resolve(false)
                    return
                }

                self.copySelectedFiles(
                    urls: [url],
                    channel: args.channel
                )

                invoke.resolve(true)
            }

            self.manager.addDelegate(delegate)

            picker.delegate = delegate
            picker.allowsMultipleSelection = false

            self.manager.viewController?.present(
                picker,
                animated: true
            )
        }
    }

    @objc public func consumeShareIntent(_ invoke: Invoke) throws {
        // Share extensions / incoming documents are not wired yet.
        invoke.resolve(false)
    }

    @objc public func cancelJob(_ invoke: Invoke) throws {
        // No cancellable copy jobs yet.
        invoke.resolve()
    }

    @objc public func exportToTree(_ invoke: Invoke) throws {
        // iOS does not expose Android's SAF tree URI.
        invoke.reject("export_to_tree is not supported on iOS")
    }

    @objc public func openDownloadFolder(_ invoke: Invoke) throws {
        // iOS has no equivalent of opening an arbitrary filesystem directory.
        invoke.reject("open_download_folder is not supported on iOS")
    }

    @objc public func getWindowInsets(_ invoke: Invoke) throws {
        DispatchQueue.main.async {
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
            .appendingPathComponent("file_cache", isDirectory: true)
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
