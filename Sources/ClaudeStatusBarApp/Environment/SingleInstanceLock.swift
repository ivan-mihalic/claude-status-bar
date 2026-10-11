import Foundation
import Darwin

public enum SingleInstanceLockError: Error, Equatable {
    case alreadyRunning
    case unavailable
}

/// Drží zámek po celý život procesu. Soubor se nemaže: odstranění zamčeného
/// souboru by umožnilo další kopii vytvořit jiný inode a obejít ochranu.
public final class SingleInstanceLock {
    private let descriptor: Int32

    public init(fileURL: URL) throws {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch { throw SingleInstanceLockError.unavailable }
        let fd = Darwin.open(fileURL.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw SingleInstanceLockError.unavailable }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            Darwin.close(fd)
            throw code == EWOULDBLOCK ? SingleInstanceLockError.alreadyRunning : .unavailable
        }
        descriptor = fd
    }

    deinit { Darwin.close(descriptor) }

    public static func defaultURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cz.mihalic.claude-status-bar", isDirectory: true)
            .appendingPathComponent("instance.lock")
    }
}
