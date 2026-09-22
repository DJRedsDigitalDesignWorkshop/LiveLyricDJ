import Foundation
import Network
import CryptoKit

@MainActor
protocol SeratoServerDelegate: AnyObject {
    func seratoConnectionStateChanged(connected: Bool)
    func seratoDeck(deck: Int, title: String)
    func seratoDeck(deck: Int, artist: String)
    func seratoDeck(deck: Int, filepath: String)
    func seratoDeck(deck: Int, valid: Bool)
    func seratoDeck(deck: Int, positionSeconds: Double, playRate: Float, bpm: Float)
}

/// Serato DJ Pro Remote protocol server.
///
/// Serato is the TCP *client*: it browses for our Bonjour advert
/// (`_SeratoIOSRemote._tcp`), connects to us (typically two parallel
/// connections — heartbeat + control), and streams state outward once we
/// complete the MD5 challenge-response handshake. See `serato-connect`'s
/// protocol docs for the full wire spec.
final class SeratoServer {
    weak var delegate: SeratoServerDelegate?

    private let peerName = "LiveLyricDJ"
    private let peerUUID = UUID().uuidString
    private let secret = Data(hex: "d25db261a4411bc1f3788f57723b8977c541a4b619b94a9a8b45c46f8511c2f8")!
    private let sentinel = Data([
        0x4c, 0xaa, 0xc2, 0xae, 0x35, 0xb1, 0xc4, 0x76,
        0xdb, 0x5a, 0x64, 0x44, 0x03, 0xbd, 0x41, 0x70,
    ])
    private let subscribeTopics = [
        "/Register/Status/Deck/Playhead",
        "/Register/Status/Deck/Song/Title",
        "/Register/Status/Deck/Song/Artist",
        "/Register/Status/Deck/Song/Filepath",
        "/Register/Status/Deck/Song/Valid",
    ]

    private let queue = DispatchQueue(label: "serato.server", qos: .userInitiated)
    private var listener: NWListener?
    private var sessions: [ObjectIdentifier: Session] = [:]
    private(set) var isConnected = false

    private final class Session {
        let connection: NWConnection
        var buffer = Data()
        var didSubscribe = false
        var didPair = false

        init(connection: NWConnection) {
            self.connection = connection
        }
    }

    func start() {
        do {
            let listener = try NWListener(using: .tcp)
            let hostname = Host.current().name ?? "Mac"
            listener.service = NWListener.Service(
                name: "\(peerName) @ \(hostname)",
                type: "_SeratoIOSRemote._tcp",
                domain: "local."
            )
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    print("[SeratoServer] listener failed: \(error)")
                }
            }
            self.listener = listener
            listener.start(queue: queue)
            print("[SeratoServer] publishing _SeratoIOSRemote._tcp as \(peerName) @ \(hostname)")
        } catch {
            print("[SeratoServer] failed to start: \(error)")
        }
    }

    // MARK: - Connections

    private func handleConnection(_ connection: NWConnection) {
        let session = Session(connection: connection)
        sessions[ObjectIdentifier(session)] = session
        connection.start(queue: queue)
        receiveLoop(session)
    }

    private func receiveLoop(_ session: Session) {
        session.connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self, let live = self.sessions[ObjectIdentifier(session)] else { return }
            if let data, !data.isEmpty {
                self.process(data, session: live)
            }
            if isComplete || error != nil {
                self.connectionClosed(live)
                return
            }
            self.receiveLoop(live)
        }
    }

    private func process(_ data: Data, session: Session) {
        session.buffer.append(data)
        while !session.buffer.isEmpty {
            guard let range = session.buffer.range(of: sentinel) else {
                if session.buffer.count > (1 << 20) {
                    print("[SeratoServer] frame too large, dropping connection")
                    connectionClosed(session)
                }
                return
            }
            let payload = session.buffer.subdata(in: 0..<range.lowerBound)
            session.buffer.removeSubrange(0..<range.upperBound)
            guard !payload.isEmpty else { continue }
            do {
                for message in try OSC.decodePacket(payload) {
                    handle(message, session: session)
                }
            } catch {
                print("[SeratoServer] decode error: \(error)")
            }
        }
    }

    // MARK: - Handshake / dispatch

    private func handle(_ msg: OSCMessage, session: Session) {
        switch msg.address {
        case "/Ping":
            send(OSCMessage.message("/Ping"), session: session)
        case "/StreamMgmt/Authorize/Request":
            guard case .b(let nonce)? = msg.args.first(where: {
                if case .b = $0 { return true }
                return false
            }) else {
                print("[SeratoServer] Authorize/Request without nonce blob")
                return
            }
            var input = nonce
            input.append(secret)
            let digest = Data(Insecure.MD5.hash(data: input))
            send(
                OSCMessage.message(
                    "/StreamMgmt/Authorize/Response",
                    .s(peerName),
                    .s(peerUUID),
                    .b(digest)
                ),
                session: session
            )
            print("[SeratoServer] authorize response sent (nonce \(nonce.count) bytes)")
        case "/StreamMgmt/Pairing/Pair":
            if !session.didPair {
                session.didPair = true
                send(
                    OSCMessage.message(
                        "/StreamMgmt/Pairing/Pair",
                        .s(peerName),
                        .s(peerUUID),
                        .i(1)
                    ),
                    session: session
                )
                subscribe(session)
                setConnected(true)
            }
        case "/StreamMgmt/Pairing/StatusChanged":
            subscribe(session)
        case "/StreamMgmt/Pairing/UnPair":
            connectionClosed(session)
        case let address where address.hasPrefix("/Status/"):
            routeStatus(msg)
        default:
            break
        }
    }

    private func subscribe(_ session: Session) {
        guard !session.didSubscribe else { return }
        session.didSubscribe = true
        for topic in subscribeTopics {
            send(OSCMessage.message(topic), session: session)
        }
        print("[SeratoServer] subscribed to \(subscribeTopics.count) topics")
    }

    private func send(_ msg: OSCMessage, session: Session) {
        var frame = OSC.encode(msg)
        frame.append(sentinel)
        session.connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func connectionClosed(_ session: Session) {
        guard sessions.removeValue(forKey: ObjectIdentifier(session)) != nil else { return }
        session.connection.cancel()
        if sessions.isEmpty {
            setConnected(false)
        }
    }

    private func setConnected(_ connected: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.isConnected != connected else { return }
            self.isConnected = connected
            self.delegate?.seratoConnectionStateChanged(connected: connected)
        }
    }

    // MARK: - Status routing

    private func routeStatus(_ msg: OSCMessage) {
        let args = msg.args

        func deckIndex() -> Int? {
            guard case .i(let v)? = args.first else { return nil }
            return Int(v)
        }
        func stringArg(_ idx: Int) -> String? {
            guard idx < args.count, case .s(let s) = args[idx] else { return nil }
            return s
        }
        func floatArg(_ idx: Int) -> Float? {
            guard idx < args.count, case .f(let f) = args[idx] else { return nil }
            return f
        }

        guard let deck = deckIndex() else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            switch msg.address {
            case "/Status/Deck/Song/Title":
                if let s = stringArg(1) { self.delegate?.seratoDeck(deck: deck, title: s) }
            case "/Status/Deck/Song/Artist":
                if let s = stringArg(1) { self.delegate?.seratoDeck(deck: deck, artist: s) }
            case "/Status/Deck/Song/Filepath":
                if let s = stringArg(1) { self.delegate?.seratoDeck(deck: deck, filepath: s) }
            case "/Status/Deck/Song/Valid":
                if let v = floatArg(1) { self.delegate?.seratoDeck(deck: deck, valid: v >= 0.5) }
            case "/Status/Deck/Playhead":
                if let p = floatArg(1), let r = floatArg(2), let b = floatArg(3) {
                    self.delegate?.seratoDeck(
                        deck: deck,
                        positionSeconds: Double(p),
                        playRate: r,
                        bpm: b
                    )
                }
            default:
                break
            }
        }
    }
}

private extension Data {
    init?(hex: String) {
        var bytes = [UInt8]()
        var s = hex.filter { !$0.isWhitespace }
        while s.count >= 2 {
            guard let b = UInt8(s.prefix(2), radix: 16) else { return nil }
            bytes.append(b)
            s.removeFirst(2)
        }
        self.init(bytes)
    }
}
