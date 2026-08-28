#!/usr/bin/env -S swift -parse-as-library

import CryptoKit
import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private enum CLIError: LocalizedError {
    case usage(String)
    case malformedResponse(String)
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .usage(let message), .malformedResponse(let message):
            return message
        case .requestFailed(let status, let message):
            return "App Store Connect returned HTTP \(status): \(message)"
        }
    }
}

private struct Configuration {
    let keyID: String
    let issuerID: String
    let keyPath: String
    let appID: String
    let buildNumber: String
    let groupName: String
    let apply: Bool

    static let help = """
    Usage:
      swift scripts/testflight-group.swift \\
        --key-id <KEY_ID> \\
        --issuer-id <ISSUER_UUID> \\
      --key-path <AuthKey_KEY_ID.p8> [--build-number <BUILD>] [--apply]

    Defaults:
      --app-id 6803853891
      --build-number from Apps/project.yml
      --group "Personal Testing"

    Without --apply, the command authenticates and reports whether the build is
    already assigned. With --apply, it adds the selected build to the exact
    internal group and verifies the relationship. The private key and JWT are
    never printed.
    """

    private static func currentBuildNumber() -> String? {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = repository.appending(path: "Apps/project.yml")
        guard let contents = try? String(contentsOf: project, encoding: .utf8) else {
            return nil
        }
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let prefix = "CURRENT_PROJECT_VERSION:"
            guard trimmed.hasPrefix(prefix) else { continue }
            return trimmed.dropFirst(prefix.count)
                .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
        }
        return nil
    }

    static func parse(_ arguments: [String]) throws -> Configuration {
        if arguments.contains("--help") || arguments.contains("-h") {
            print(help)
            Foundation.exit(EXIT_SUCCESS)
        }

        var values: [String: String] = [:]
        var apply = false
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--apply" {
                apply = true
                index += 1
                continue
            }

            guard argument.hasPrefix("--"), index + 1 < arguments.count else {
                throw CLIError.usage("Unknown or incomplete argument: \(argument)\n\n\(help)")
            }
            values[argument] = arguments[index + 1]
            index += 2
        }

        let allowed = Set([
            "--key-id", "--issuer-id", "--key-path", "--app-id",
            "--build-number", "--group",
        ])
        let unknown = Set(values.keys).subtracting(allowed)
        guard unknown.isEmpty else {
            throw CLIError.usage("Unknown option: \(unknown.sorted().joined(separator: ", "))\n\n\(help)")
        }

        guard let keyID = values["--key-id"], !keyID.isEmpty,
              let issuerID = values["--issuer-id"], !issuerID.isEmpty,
              let keyPath = values["--key-path"], !keyPath.isEmpty
        else {
            throw CLIError.usage("--key-id, --issuer-id, and --key-path are required.\n\n\(help)")
        }

        guard FileManager.default.fileExists(atPath: keyPath) else {
            throw CLIError.usage("Private key not found at the supplied path.")
        }

        guard let buildNumber = values["--build-number"] ?? currentBuildNumber(),
              !buildNumber.isEmpty
        else {
            throw CLIError.usage("--build-number is required when Apps/project.yml cannot be read.\n\n\(help)")
        }

        return Configuration(
            keyID: keyID,
            issuerID: issuerID,
            keyPath: keyPath,
            appID: values["--app-id"] ?? "6803853891",
            buildNumber: buildNumber,
            groupName: values["--group"] ?? "Personal Testing",
            apply: apply
        )
    }
}

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func makeToken(configuration: Configuration) throws -> String {
    let now = Int(Date().timeIntervalSince1970)
    let header = try JSONSerialization.data(withJSONObject: [
        "alg": "ES256",
        "kid": configuration.keyID,
        "typ": "JWT",
    ], options: [.sortedKeys])
    let payload = try JSONSerialization.data(withJSONObject: [
        "aud": "appstoreconnect-v1",
        "exp": now + 1_200,
        "iat": now,
        "iss": configuration.issuerID,
    ], options: [.sortedKeys])
    let unsignedToken = "\(base64URL(header)).\(base64URL(payload))"

    let pem = try String(contentsOfFile: configuration.keyPath, encoding: .utf8)
    let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
    let signature = try key.signature(for: Data(unsignedToken.utf8))
    return "\(unsignedToken).\(base64URL(signature.rawRepresentation))"
}

private struct AppStoreConnectClient {
    let token: String
    private let baseURL = URL(string: "https://api.appstoreconnect.apple.com/v1/")!

    func get(_ path: String, query: [URLQueryItem] = []) async throws -> [String: Any] {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw CLIError.malformedResponse("Could not construct App Store Connect URL.")
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else {
            throw CLIError.malformedResponse("Could not construct App Store Connect URL.")
        }
        let data = try await request(url: url, method: "GET", body: nil)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CLIError.malformedResponse("App Store Connect returned malformed JSON.")
        }
        return object
    }

    func post(_ path: String, body: [String: Any]) async throws {
        let url = baseURL.appendingPathComponent(path)
        let data = try JSONSerialization.data(withJSONObject: body)
        _ = try await request(url: url, method: "POST", body: data)
    }

    private func request(url: URL, method: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CLIError.malformedResponse("App Store Connect returned no HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["errors"] as? [[String: Any]] }?
                .compactMap { $0["detail"] as? String }
                .joined(separator: "; ")
            throw CLIError.requestFailed(http.statusCode, message ?? "Unknown API error")
        }
        return data
    }
}

private func resources(in response: [String: Any]) throws -> [[String: Any]] {
    guard let data = response["data"] as? [[String: Any]] else {
        throw CLIError.malformedResponse("App Store Connect response has no resource data.")
    }
    return data
}

private func exactResource(
    _ candidates: [[String: Any]],
    description: String
) throws -> [String: Any] {
    guard candidates.count == 1 else {
        throw CLIError.malformedResponse(
            "Expected exactly one \(description), found \(candidates.count). No change was made."
        )
    }
    return candidates[0]
}

private func resourceID(_ resource: [String: Any], description: String) throws -> String {
    guard let id = resource["id"] as? String, !id.isEmpty else {
        throw CLIError.malformedResponse("The \(description) has no resource ID.")
    }
    return id
}

private func run() async throws {
    let configuration = try Configuration.parse(Array(CommandLine.arguments.dropFirst()))
    let client = AppStoreConnectClient(token: try makeToken(configuration: configuration))

    let buildsResponse = try await client.get("builds", query: [
        URLQueryItem(name: "filter[app]", value: configuration.appID),
        URLQueryItem(name: "filter[version]", value: configuration.buildNumber),
        URLQueryItem(name: "limit", value: "10"),
    ])
    let build = try exactResource(
        resources(in: buildsResponse),
        description: "Anchor build \(configuration.buildNumber)"
    )
    let buildID = try resourceID(build, description: "build")
    let buildAttributes = build["attributes"] as? [String: Any] ?? [:]
    let processingState = buildAttributes["processingState"] as? String ?? "unknown"
    let expired = buildAttributes["expired"] as? Bool ?? false

    guard processingState == "VALID", !expired else {
        throw CLIError.malformedResponse(
            "Build \(configuration.buildNumber) is not assignable (state=\(processingState), expired=\(expired))."
        )
    }

    let groupsResponse = try await client.get("apps/\(configuration.appID)/betaGroups", query: [
        URLQueryItem(name: "limit", value: "200"),
    ])
    let matchingGroups = try resources(in: groupsResponse).filter { resource in
        let attributes = resource["attributes"] as? [String: Any]
        return attributes?["name"] as? String == configuration.groupName
    }
    let group = try exactResource(matchingGroups, description: "beta group named \(configuration.groupName)")
    let groupID = try resourceID(group, description: "beta group")
    let groupAttributes = group["attributes"] as? [String: Any] ?? [:]
    let isInternal = groupAttributes["isInternalGroup"] as? Bool ?? false

    guard isInternal else {
        throw CLIError.malformedResponse(
            "The exact group named \(configuration.groupName) is not internal. No change was made."
        )
    }

    func assignmentExists() async throws -> Bool {
        let relationships = try await client.get(
            "betaGroups/\(groupID)/relationships/builds",
            query: [URLQueryItem(name: "limit", value: "200")]
        )
        return try resources(in: relationships).contains { resource in
            resource["id"] as? String == buildID
        }
    }

    print("Anchor build \(configuration.buildNumber): VALID, resource \(buildID)")
    print("Beta group: \(configuration.groupName), internal, resource \(groupID)")

    if try await assignmentExists() {
        print("Assignment: already present")
        return
    }

    guard configuration.apply else {
        print("Assignment: missing (read-only check; re-run with --apply to add it)")
        return
    }

    try await client.post("betaGroups/\(groupID)/relationships/builds", body: [
        "data": [["id": buildID, "type": "builds"]],
    ])

    guard try await assignmentExists() else {
        throw CLIError.malformedResponse("App Store Connect accepted the request but did not expose the relationship.")
    }
    print("Assignment: added and verified")
}

private let completion = DispatchSemaphore(value: 0)
private var outcome: Result<Void, Error>?

Task {
    do {
        try await run()
        outcome = .success(())
    } catch {
        outcome = .failure(error)
    }
    completion.signal()
}

completion.wait()

switch outcome {
case .success:
    Foundation.exit(EXIT_SUCCESS)
case .failure(let error):
    FileHandle.standardError.write(Data("Error: \(error.localizedDescription)\n".utf8))
    Foundation.exit(EXIT_FAILURE)
case .none:
    FileHandle.standardError.write(Data("Error: command finished without a result.\n".utf8))
    Foundation.exit(EXIT_FAILURE)
}
