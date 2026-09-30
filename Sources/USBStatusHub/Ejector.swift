import Foundation
import DiskArbitration

/// Safely ejects USB storage: unmounts all volumes on the whole disk, then ejects it.
enum Ejector {
    private static let queue = DispatchQueue(label: "com.anguskongyeung.usbstatushub.eject")
    private static let session: DASession? = {
        let session = DASessionCreate(kCFAllocatorDefault)
        if let session { DASessionSetDispatchQueue(session, queue) }
        return session
    }()

    private final class Context {
        let completion: (String?) -> Void
        init(_ completion: @escaping (String?) -> Void) { self.completion = completion }
    }

    /// Calls completion on the main queue with nil on success or an error message.
    static func eject(bsdName: String, completion: @escaping (String?) -> Void) {
        let done: (String?) -> Void = { message in
            DispatchQueue.main.async { completion(message) }
        }
        guard let session,
              let disk = DADiskCreateFromBSDName(kCFAllocatorDefault, session, bsdName) else {
            done("Could not access disk \(bsdName).")
            return
        }

        let context = Unmanaged.passRetained(Context(done)).toOpaque()
        DADiskUnmount(disk, DADiskUnmountOptions(kDADiskUnmountOptionWhole), { disk, dissenter, context in
            if let dissenter, DADissenterGetStatus(dissenter) != 0 {
                let ctx = Unmanaged<Context>.fromOpaque(context!).takeRetainedValue()
                let status = DADissenterGetStatusString(dissenter) as String?
                ctx.completion(status ?? "Unmount failed — a file on the disk may be in use.")
                return
            }
            DADiskEject(disk, DADiskEjectOptions(kDADiskEjectOptionDefault), { _, dissenter, context in
                let ctx = Unmanaged<Context>.fromOpaque(context!).takeRetainedValue()
                if let dissenter, DADissenterGetStatus(dissenter) != 0 {
                    let status = DADissenterGetStatusString(dissenter) as String?
                    ctx.completion(status ?? "Eject failed.")
                } else {
                    ctx.completion(nil)
                }
            }, context)
        }, context)
    }
}
