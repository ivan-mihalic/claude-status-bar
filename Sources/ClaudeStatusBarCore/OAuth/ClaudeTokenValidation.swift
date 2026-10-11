import Foundation

public enum ClaudeTokenValidationError: Error, Equatable, LocalizedError {
    case expiredOrInvalid
    case usageRefused
    case temporarilyUnavailable
    case rateLimited
    case credentialsChanged

    public var errorDescription: String? {
        switch self {
        case .expiredOrInvalid:
            return "Claude rejected this access token. Supply a current OAuth access token; your existing credentials have been kept."
        case .usageRefused:
            return "Claude refused usage access (HTTP 403). This token cannot be used to read usage. Tokens from claude setup-token only allow model requests; a longer lifetime does not add usage permission."
        case .temporarilyUnavailable:
            return "Usage access could not be verified. Try again later; your existing credentials have been kept."
        case .credentialsChanged:
            return "Credentials changed while verifying. The newer credentials have been kept; verify again to replace them."
        case .rateLimited:
            return "Claude is limiting usage requests. Wait before verifying again; your existing credentials have been kept."
        }
    }
}

public struct ClaudeTokenValidation: Sendable {
    private let usage: any UsageFetching
    private let clock: any Clock

    public init(usage: any UsageFetching, clock: any Clock) {
        self.usage = usage; self.clock = clock
    }

    public func verify(_ bundle: TokenBundle) async throws -> UsageSnapshot {
        do {
            let snapshot = try await usage.fetch(tokens: bundle, now: clock.now())
            try Task.checkCancellation()
            return snapshot
        } catch is CancellationError {
            throw CancellationError()
        } catch UsageAPIError.unauthorized {
            throw ClaudeTokenValidationError.expiredOrInvalid
        } catch UsageAPIError.forbidden {
            throw ClaudeTokenValidationError.usageRefused
        } catch UsageAPIError.rateLimited {
            throw ClaudeTokenValidationError.rateLimited
        } catch {
            if Task.isCancelled { throw CancellationError() }
            // Nezobrazujeme tělo odpovědi ani libovolný popis chyby s možnými tajnými údaji.
            throw ClaudeTokenValidationError.temporarilyUnavailable
        }
    }
}
