#if canImport(UIKit) && canImport(Photos)
import Foundation
@preconcurrency import Photos

@MainActor
final class PhotoKitResourceExporter {
    private let manager = PHAssetResourceManager.default()

    func export(
        _ resource: PHAssetResource,
        to destinationURL: URL,
        networkAccess: RecentPhotoImagePolicy.NetworkAccess
    ) async throws -> RecentPhotoExport {
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw RecentPhotoResourceError.destinationExists
        }
        guard FileManager.default.createFile(
            atPath: destinationURL.path,
            contents: nil
        ) else {
            throw RecentPhotoResourceError.fileSystem(
                code: CocoaError.fileWriteUnknown.rawValue,
                message: "Could not create the export file"
            )
        }

        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forWritingTo: destinationURL)
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw mapFileSystemError(error)
        }

        let typeIdentifier: String?
        if #available(iOS 26, *) {
            typeIdentifier = resource.contentType.identifier
        } else {
            typeIdentifier = resource.uniformTypeIdentifier
        }
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = networkAccess == .allowed
        let cancellation = ResourceExportCancellation()
        let manager = manager

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let state = ResourceExportState(
                    fileHandle: fileHandle,
                    destinationURL: destinationURL,
                    typeIdentifier: typeIdentifier,
                    originalFilename: resource.originalFilename,
                    continuation: continuation
                )
                if let requestID = cancellation.install(state) {
                    manager.cancelDataRequest(requestID)
                }
                let requestID = manager.requestData(
                    for: resource,
                    options: options
                ) { data in
                    if let requestID = state.append(data) {
                        manager.cancelDataRequest(requestID)
                    }
                } completionHandler: { error in
                    state.complete(photoLibraryError: error)
                }
                if state.install(requestID: requestID) {
                    manager.cancelDataRequest(requestID)
                }
            }
        } onCancel: {
            if let requestID = cancellation.cancel() {
                manager.cancelDataRequest(requestID)
            }
        }
    }
}

private final class ResourceExportState: @unchecked Sendable {
    private let lock = NSLock()
    private let fileHandle: FileHandle
    private let destinationURL: URL
    private let typeIdentifier: String?
    private let originalFilename: String?
    private var continuation: CheckedContinuation<RecentPhotoExport, Error>?
    private var requestID = PHInvalidAssetResourceDataRequestID
    private var byteCount: Int64 = 0
    private var writeError: RecentPhotoResourceError?
    private var isCancelled = false
    private var isComplete = false

    init(
        fileHandle: FileHandle,
        destinationURL: URL,
        typeIdentifier: String?,
        originalFilename: String?,
        continuation: CheckedContinuation<RecentPhotoExport, Error>
    ) {
        self.fileHandle = fileHandle
        self.destinationURL = destinationURL
        self.typeIdentifier = typeIdentifier
        self.originalFilename = originalFilename
        self.continuation = continuation
    }

    func install(requestID: PHAssetResourceDataRequestID) -> Bool {
        lock.lock()
        self.requestID = requestID
        let shouldCancel = isCancelled || writeError != nil
        lock.unlock()
        return shouldCancel
    }

    func append(_ data: Data) -> PHAssetResourceDataRequestID? {
        lock.lock()
        defer { lock.unlock() }
        guard !isComplete, writeError == nil, !isCancelled else {
            return nil
        }
        do {
            try fileHandle.write(contentsOf: data)
            byteCount += Int64(data.count)
            return nil
        } catch {
            writeError = mapFileSystemError(error)
            return requestID == PHInvalidAssetResourceDataRequestID
                ? nil
                : requestID
        }
    }

    func cancel() -> PHAssetResourceDataRequestID? {
        lock.lock()
        defer { lock.unlock() }
        guard !isComplete else { return nil }
        isCancelled = true
        return requestID == PHInvalidAssetResourceDataRequestID
            ? nil
            : requestID
    }

    func complete(photoLibraryError: Error?) {
        lock.lock()
        guard !isComplete, let continuation else {
            lock.unlock()
            return
        }
        isComplete = true
        self.continuation = nil
        let wasCancelled = isCancelled
        let writeError = writeError
        let byteCount = byteCount
        lock.unlock()

        let closeError: RecentPhotoResourceError?
        do {
            try fileHandle.close()
            closeError = nil
        } catch {
            closeError = mapFileSystemError(error)
        }

        let result: Result<RecentPhotoExport, Error>
        if wasCancelled {
            result = .failure(RecentPhotoResourceError.cancelled)
        } else if let writeError {
            result = .failure(writeError)
        } else if let closeError {
            result = .failure(closeError)
        } else if let photoLibraryError {
            result = .failure(mapPhotoResourceError(photoLibraryError))
        } else {
            result = .success(
                RecentPhotoExport(
                    url: destinationURL,
                    typeIdentifier: typeIdentifier,
                    originalFilename: originalFilename,
                    byteCount: byteCount
                )
            )
        }

        if case .failure = result {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        continuation.resume(with: result)
    }
}

private final class ResourceExportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var state: ResourceExportState?
    private var isCancelled = false

    func install(
        _ state: ResourceExportState
    ) -> PHAssetResourceDataRequestID? {
        lock.lock()
        self.state = state
        let shouldCancel = isCancelled
        lock.unlock()
        return shouldCancel ? state.cancel() : nil
    }

    func cancel() -> PHAssetResourceDataRequestID? {
        lock.lock()
        isCancelled = true
        let state = state
        lock.unlock()
        return state?.cancel()
    }
}

func mapPhotoResourceError(
    _ sourceError: Error
) -> RecentPhotoResourceError {
    let error = sourceError as NSError
    if error.domain == PHPhotosErrorDomain {
        if error.code == PHPhotosError.userCancelled.rawValue {
            return .cancelled
        }
        if error.code == PHPhotosError.networkAccessRequired.rawValue {
            return .networkAccessRequired
        }
    }
    return .photoLibrary(code: error.code, message: error.localizedDescription)
}

private func mapFileSystemError(_ sourceError: Error) -> RecentPhotoResourceError {
    let error = sourceError as NSError
    return .fileSystem(code: error.code, message: error.localizedDescription)
}
#endif
