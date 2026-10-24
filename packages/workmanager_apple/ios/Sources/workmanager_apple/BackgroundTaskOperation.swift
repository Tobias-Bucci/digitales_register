//
//  BackgroundTaskOperation.swift
//  workmanager
//
//  Created by Sebastian Roth on 10/06/2021.
//

import Foundation

#if os(iOS)
import Flutter
#elseif os(macOS)
import FlutterMacOS
#else
#error("Unsupported platform.")
#endif

class BackgroundTaskOperation: Operation, @unchecked Sendable {

    private let identifier: String
    private let flutterPluginRegistrantCallback: FlutterPluginRegistrantCallback?
    private let inputData: [String: Any]?
    private let backgroundMode: BackgroundMode
    private let semaphore = DispatchSemaphore(value: 0)
    private var worker: BackgroundWorker?
    private let resultLock = NSLock()
    private var successful = false
    var completedSuccessfully: Bool {
        resultLock.lock()
        defer { resultLock.unlock() }
        return successful && !isCancelled
    }

    init(_ identifier: String,
         inputData: [String: Any]?,
         flutterPluginRegistrantCallback: FlutterPluginRegistrantCallback?,
         backgroundMode: BackgroundMode) {
        self.identifier = identifier
        self.inputData = inputData
        self.flutterPluginRegistrantCallback = flutterPluginRegistrantCallback
        self.backgroundMode = backgroundMode
    }

    override func main() {
        DispatchQueue.main.async {
            guard !self.isCancelled else { self.semaphore.signal(); return }
            let worker = BackgroundWorker(mode: self.backgroundMode,
                                          inputData: self.inputData,
                                          flutterPluginRegistrantCallback: self.flutterPluginRegistrantCallback)
            self.worker = worker
            worker.performBackgroundRequest { result in
                self.resultLock.lock()
                self.successful = result != .failed
                self.resultLock.unlock()
                self.worker = nil
                self.semaphore.signal()
            }
        }

        semaphore.wait()
    }

    override func cancel() {
        super.cancel()
        // Expiration must unblock Operation.main even if Dart never replies.
        DispatchQueue.main.async {
            self.worker?.cancelRequest?()
            self.worker = nil
            self.semaphore.signal()
        }
    }
}
