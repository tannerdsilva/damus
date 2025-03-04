//
//  RelayPool.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation
import Network

struct SubscriptionId: Identifiable, CustomStringConvertible {
    let id: String

    var description: String {
        id
    }
}

struct RelayId: Identifiable, CustomStringConvertible {
    let id: String

    var description: String {
        id
    }
}

struct RelayHandler {
    let sub_id: String
    let callback: (String, NostrConnectionEvent) -> ()
}

struct QueuedRequest {
    let req: NostrRequest
    let relay: String
}

struct NostrRequestId: Equatable, Hashable {
    let relay: String?
    let sub_id: String
}

class RelayPool {
    var relays: [Relay] = []
    var handlers: [RelayHandler] = []
    var request_queue: [QueuedRequest] = []
    var seen: Set<String> = Set()
    var counts: [String: UInt64] = [:]
    
    private let network_monitor = NWPathMonitor()
    private let network_monitor_queue = DispatchQueue(label: "io.damus.network_monitor")
    private var last_network_status: NWPath.Status = .unsatisfied

    init() {
        network_monitor.pathUpdateHandler = { [weak self] path in
            if (path.status == .satisfied || path.status == .requiresConnection) && self?.last_network_status != path.status {
                DispatchQueue.main.async {
                    self?.connect_to_disconnected()
                }
            }
            
            self?.last_network_status = path.status
        }
        network_monitor.start(queue: network_monitor_queue)
    }
    
    var descriptors: [RelayDescriptor] {
        relays.map { $0.descriptor }
    }
    
    var num_connecting: Int {
        return relays.reduce(0) { n, r in n + (r.connection.isConnecting ? 1 : 0) }
    }
    
    var num_connected: Int {
        return relays.reduce(0) { n, r in n + (r.connection.isConnected ? 1 : 0) }
    }

    func remove_handler(sub_id: String) {
        self.handlers = handlers.filter { $0.sub_id != sub_id }
        print("removing \(sub_id) handler, current: \(handlers.count)")
    }

    func register_handler(sub_id: String, handler: @escaping (String, NostrConnectionEvent) -> ()) {
        for handler in handlers {
            // don't add duplicate handlers
            if handler.sub_id == sub_id {
                return
            }
        }
        self.handlers.append(RelayHandler(sub_id: sub_id, callback: handler))
        print("registering \(sub_id) handler, current: \(self.handlers.count)")
    }
    
    func remove_relay(_ relay_id: String) {
        var i: Int = 0
        
        self.disconnect(to: [relay_id])
        
        for relay in relays {
            if relay.id == relay_id {
                relays.remove(at: i)
                break
            }
            
            i += 1
        }
    }
    
    func add_relay(_ url: RelayURL, info: RelayInfo) throws {
        let relay_id = get_relay_id(url)
        if get_relay(relay_id) != nil {
            throw RelayError.RelayAlreadyExists
        }
        let conn = RelayConnection(url: url) { event in
            self.handle_event(relay_id: relay_id, event: event)
        }
        let descriptor = RelayDescriptor(url: url, info: info)
        let relay = Relay(descriptor: descriptor, connection: conn)
        self.relays.append(relay)
    }
    
    /// This is used to retry dead connections
    func connect_to_disconnected() {
        for relay in relays {
            let c = relay.connection
            
            let is_connecting = c.isConnecting
            
            if is_connecting && (Date.now.timeIntervalSince1970 - c.last_connection_attempt) > 5 {
                print("stale connection detected (\(relay.descriptor.url.url.absoluteString)). retrying...")
                relay.connection.reconnect()
            } else if relay.is_broken || is_connecting || c.isConnected {
                continue
            } else {
                relay.connection.reconnect()
            }
            
        }
    }
    
    func reconnect(to: [String]? = nil) {
        let relays = to.map{ get_relays($0) } ?? self.relays
        for relay in relays {
            // don't try to reconnect to broken relays
            relay.connection.reconnect()
        }
    }
    
    func mark_broken(_ relay_id: String) {
        for relay in relays {
            relay.mark_broken()
        }
    }

    func connect(to: [String]? = nil) {
        let relays = to.map{ get_relays($0) } ?? self.relays
        for relay in relays {
            relay.connection.connect()
        }
    }

    func disconnect(to: [String]? = nil) {
        let relays = to.map{ get_relays($0) } ?? self.relays
        for relay in relays {
            relay.connection.disconnect()
        }
    }
    
    func unsubscribe(sub_id: String, to: [String]? = nil) {
        if to == nil {
            self.remove_handler(sub_id: sub_id)
        }
        self.send(.unsubscribe(sub_id), to: to)
    }
    
    func subscribe(sub_id: String, filters: [NostrFilter], handler: @escaping (String, NostrConnectionEvent) -> (), to: [String]? = nil) {
        register_handler(sub_id: sub_id, handler: handler)
        send(.subscribe(.init(filters: filters, sub_id: sub_id)), to: to)
    }
    
    func subscribe_to(sub_id: String, filters: [NostrFilter], to: [String]?, handler: @escaping (String, NostrConnectionEvent) -> ()) {
        register_handler(sub_id: sub_id, handler: handler)
        send(.subscribe(.init(filters: filters, sub_id: sub_id)), to: to)
    }
    
    func count_queued(relay: String) -> Int {
        var c = 0
        for request in request_queue {
            if request.relay == relay {
                c += 1
            }
        }
        
        return c
    }
    
    func queue_req(r: NostrRequest, relay: String) {
        let count = count_queued(relay: relay)
        guard count <= 10 else {
            print("can't queue, too many queued events for \(relay)")
            return
        }
        
        print("queueing request: \(r) for \(relay)")
        request_queue.append(QueuedRequest(req: r, relay: relay))
    }
    
    func send(_ req: NostrRequest, to: [String]? = nil) {
        let relays = to.map{ get_relays($0) } ?? self.relays

        for relay in relays {
            guard relay.connection.isConnected else {
                queue_req(r: req, relay: relay.id)
                continue
            }
            
            relay.connection.send(req)
        }
    }
    
    func get_relays(_ ids: [String]) -> [Relay] {
        relays.filter { ids.contains($0.id) }
    }
    
    func get_relay(_ id: String) -> Relay? {
        relays.first(where: { $0.id == id })
    }
    
    func run_queue(_ relay_id: String) {
        self.request_queue = request_queue.reduce(into: Array<QueuedRequest>()) { (q, req) in
            guard req.relay == relay_id else {
                q.append(req)
                return
            }
            
            print("running queueing request: \(req.req) for \(relay_id)")
            self.send(req.req, to: [relay_id])
        }
    }
    
    func record_seen(relay_id: String, event: NostrConnectionEvent) {
        if case .nostr_event(let ev) = event {
            if case .event(_, let nev) = ev {
                let k = relay_id + nev.id
                if !seen.contains(k) {
                    seen.insert(k)
                    if counts[relay_id] == nil {
                        counts[relay_id] = 1
                    } else {
                        counts[relay_id] = (counts[relay_id] ?? 0) + 1
                    }
                }
            }
        }
    }
    
    func handle_event(relay_id: String, event: NostrConnectionEvent) {
        record_seen(relay_id: relay_id, event: event)
        
        // run req queue when we reconnect
        if case .ws_event(let ws) = event {
            if case .connected = ws {
                run_queue(relay_id)
            }
        }
        
        for handler in handlers {
            handler.callback(relay_id, event)
        }
    }
}

func add_rw_relay(_ pool: RelayPool, _ url: String) {
    guard let url = RelayURL(url) else {
        return
    }
    try? pool.add_relay(url, info: RelayInfo.rw)
}


