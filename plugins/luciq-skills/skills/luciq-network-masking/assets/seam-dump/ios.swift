//
//  LuciqSeamDump.swift  —  SEAM-DUMP CAPTURE (iOS) for luciq-network-masking.
//
//  Captures at the exact Luciq obfuscation seam your real scrubPII handler will
//  mask — no Frida, no proxy, no cert, no pinning. It only READS; every handler
//  returns the data UNCHANGED. Add temporarily, walk the paths, pull the file,
//  then DELETE this file and its call site.
//
//  API verified against LuciqSDK LCQNetworkLogger.h (setRequest/ResponseObfuscationHandler).
//
//  1. Add this file to the target.
//  2. Call `LuciqSeamDump.installIfRequested()` right after `Luciq.start(...)`.
//  3. Build + run with the launch argument `-seamDump` (Xcode scheme ▸ Arguments,
//     or `xcrun simctl launch booted <bundle-id> -seamDump`).
//  4. Walk every critical path.
//  5. Pull the capture:
//       xcrun simctl get_app_container booted <bundle-id> data
//       -> <container>/Documents/luciq-seam-capture.jsonl
//  6. Feed it to the skill's classify.py, then DELETE this file + the call.
//
//  Output is the flow shape classify.py consumes: request and response are
//  written as separate JSON lines (classify treats each independently).
//
//  KNOWN LIMITATIONS (expect empty bodies in these cases — not a bug in this file):
//   • Request bodies: URLSession moves the body off the NSURLRequest, so
//     `request.httpBody` is usually nil at this seam. Draining httpBodyStream does
//     not recover it either — the request handed to the handler carries no body.
//     Request-body capture on iOS is therefore unreliable; rely on response bodies.
//   • Response bodies from a custom-delegate session (e.g. a URLSessionDelegate that
//     handles auth challenges / cert pinning) or a self-signed / local HTTP backend:
//     Luciq re-issues internally to collect the body and that re-issue can't complete,
//     so respBody is empty even though respHeaders are present. Test against a real
//     HTTPS endpoint (or a system-trusted cert) to confirm response-body capture.

import Foundation
import LuciqSDK

enum LuciqSeamDump {

    private static let queue = DispatchQueue(label: "luciq.seamdump")
    private static let fileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("luciq-seam-capture.jsonl")
    }()

    /// No-op unless the app is launched with `-seamDump`.
    static func installIfRequested() {
        guard CommandLine.arguments.contains("-seamDump") else { return }
        try? FileManager.default.removeItem(at: fileURL)
        NSLog("[luciq-seam-dump] capturing to \(fileURL.path)")

        NetworkLogger.setRequestObfuscationHandler { request in
            append([
                "method": request.httpMethod ?? "GET",
                "url": request.url?.absoluteString ?? "",
                "host": request.url?.host ?? "",
                "reqHeaders": request.allHTTPHeaderFields ?? [:],
                "reqBody": request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? "",
            ])
            return request  // UNCHANGED — capture only
        }

        NetworkLogger.setResponseObfuscationHandler { responseData, response, returnBlock in
            var headers: [String: String] = [:]
            for (k, v) in ((response as? HTTPURLResponse)?.allHeaderFields ?? [:]) {
                headers["\(k)".lowercased()] = "\(v)"
            }
            append([
                "url": response.url?.absoluteString ?? "",
                "host": response.url?.host ?? "",
                "respHeaders": headers,
                "respBody": responseData.flatMap { String(data: $0, encoding: .utf8) } ?? "",
            ])
            returnBlock(responseData, response)  // UNCHANGED — capture only
        }
    }

    private static func append(_ obj: [String: Any]) {
        queue.async {
            guard let data = try? JSONSerialization.data(withJSONObject: obj),
                  let line = String(data: data, encoding: .utf8) else { return }
            let bytes = (line + "\n").data(using: .utf8)!
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile(); handle.write(bytes); try? handle.close()
            } else {
                try? bytes.write(to: fileURL)
            }
        }
    }
}
