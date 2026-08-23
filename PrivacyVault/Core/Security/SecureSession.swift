import Foundation

/// Active session state representation.
public enum SessionState: Sendable {
    case locked
    case active(vaultType: VaultType, sessionStart: Date)
}

/// Abstract contract for managing authenticated session lifecycle, auto-lock countdowns, and key cleanup.
public protocol SecureSessionProtocol: AnyObject, Sendable {
    var state: SessionState { get }
    var isAuthenticated: Bool { get }
    var activeVaultType: VaultType? { get }
    var activeMasterKey: SymmetricKeyMaterial? { get }
    var lastActivityDate: Date? { get }
    
    /// Starts a secure session upon successful authentication.
    func startSession(for vault: VaultType, masterKey: SymmetricKeyMaterial)
    
    /// Registers user interaction to refresh session activity timer.
    func touchActivity()
    
    /// Evaluates auto-lock condition given timeout setting.
    func checkAutoLock(timeout: AutoLockTimeout) -> Bool
    
    /// Explicitly locks the vault session and wipes key material from memory.
    func lock()
}

/// Concrete session lifecycle manager.
public final class SecureSession: SecureSessionProtocol, @unchecked Sendable {
    private let lockQueue = DispatchQueue(label: "com.privacyvault.securesession", attributes: .concurrent)
    
    private var _state: SessionState = .locked
    private var _activeMasterKey: SymmetricKeyMaterial?
    private var _lastActivityDate: Date?
    
    public init() {}
    
    public var state: SessionState {
        lockQueue.sync { _state }
    }
    
    public var isAuthenticated: Bool {
        lockQueue.sync {
            if case .active = _state { return true }
            return false
        }
    }
    
    public var activeVaultType: VaultType? {
        lockQueue.sync {
            if case let .active(vaultType, _) = _state { return vaultType }
            return nil
        }
    }
    
    public var activeMasterKey: SymmetricKeyMaterial? {
        lockQueue.sync { _activeMasterKey }
    }
    
    public var lastActivityDate: Date? {
        lockQueue.sync { _lastActivityDate }
    }
    
    public func startSession(for vault: VaultType, masterKey: SymmetricKeyMaterial) {
        lockQueue.async(flags: .barrier) {
            let now = Date()
            self._state = .active(vaultType: vault, sessionStart: now)
            self._activeMasterKey = masterKey
            self._lastActivityDate = now
        }
    }
    
    public func touchActivity() {
        lockQueue.async(flags: .barrier) {
            if case .active = self._state {
                self._lastActivityDate = Date()
            }
        }
    }
    
    public func checkAutoLock(timeout: AutoLockTimeout) -> Bool {
        guard timeout != .never else { return false }
        
        return lockQueue.sync {
            guard case .active = _state, let lastActivity = _lastActivityDate else {
                return false
            }
            
            let elapsed = Date().timeIntervalSince(lastActivity)
            if elapsed >= Double(timeout.rawValue) {
                return true
            }
            return false
        }
    }
    
    public func lock() {
        lockQueue.async(flags: .barrier) {
            self._state = .locked
            self._activeMasterKey = nil
            self._lastActivityDate = nil
        }
    }
}
